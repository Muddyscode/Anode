#!/usr/bin/env bash
# Applies Anode's migrations and seed to a throwaway Postgres database and runs
# the pgTAP tests in supabase/tests.
#
# Usage:
#   scripts/db-test.sh                          # starts a temporary Postgres 16 cluster
#   PGHOST=... PGPORT=... PGUSER=... PGDATABASE=... scripts/db-test.sh
#                                               # uses an existing, empty database (superuser)
#
# Needs: Postgres 16 server binaries, psql, the pgTAP extension and pg_prove.
# Against a real local Supabase stack, use `supabase db reset && supabase test db` instead.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PG_BIN="${PG_BIN:-/usr/lib/postgresql/16/bin}"
TMP_DIR=""

as_pg() {
  # Postgres refuses to run as root, so drop to the postgres user when needed.
  if [ "$(id -u)" -eq 0 ]; then
    runuser -u postgres -- "$@"
  else
    "$@"
  fi
}

cleanup() {
  if [ -n "$TMP_DIR" ]; then
    as_pg "$PG_BIN/pg_ctl" -D "$TMP_DIR/data" -m immediate stop >/dev/null 2>&1 || true
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

if [ -z "${PGHOST:-}" ]; then
  TMP_DIR="$(mktemp -d)"
  chmod 755 "$TMP_DIR"
  if [ "$(id -u)" -eq 0 ]; then chown postgres "$TMP_DIR"; fi
  PORT="${PGPORT_TEST:-54329}"
  as_pg "$PG_BIN/initdb" -D "$TMP_DIR/data" -U postgres --auth=trust >/dev/null
  as_pg "$PG_BIN/pg_ctl" -D "$TMP_DIR/data" -l "$TMP_DIR/log" \
    -o "-p $PORT -k $TMP_DIR -c listen_addresses=''" -w start >/dev/null
  as_pg "$PG_BIN/createdb" -h "$TMP_DIR" -p "$PORT" -U postgres anode_test
  export PGHOST="$TMP_DIR" PGPORT="$PORT" PGUSER=postgres PGDATABASE=anode_test
fi

run_sql() {
  psql -X -q -v ON_ERROR_STOP=1 "$@"
}

echo "==> Supabase stand-in (test only)"
# Like Supabase, keep extensions out of public. Test roles call pgTAP functions.
run_sql -c "create schema if not exists extensions; create extension if not exists pgtap with schema extensions;"
run_sql -c "grant usage on schema extensions to public; grant execute on all functions in schema extensions to public;"
run_sql -f "$ROOT/scripts/db/supabase-shim.sql"

echo "==> Migrations"
for f in "$ROOT"/supabase/migrations/*.sql; do
  echo "    $(basename "$f")"
  run_sql -f "$f"
done

echo "==> Seed"
run_sql -f "$ROOT/supabase/seed.sql"

echo "==> Tests"
PGOPTIONS="-c search_path=public,extensions" pg_prove --ext .sql --failures "$ROOT"/supabase/tests/*.test.sql
