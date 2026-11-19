# Database

Stage 2 of the Phase 1 build: the approved [domain model](domain-model.md) as Supabase migrations,
with row-level security, seed data and pgTAP tests.

## Layout

| Path | What it holds |
|---|---|
| `supabase/migrations/` | Schema, in order. Each file names the domain-model sections it implements |
| `supabase/seed.sql` | Development and demo data. Never run against production |
| `supabase/tests/*.test.sql` | pgTAP tests: schema, tenancy and RLS, photos, findings, reports and audit, seed |
| `supabase/tests/_helpers.psql` | Test helpers, included by each test file and rolled back with it |
| `supabase/config.toml` | Supabase CLI configuration (API exposes `public` and `graphql_public` only) |
| `scripts/db-test.sh` | Runs migrations, seed and tests against a throwaway Postgres |
| `scripts/db/supabase-shim.sql` | Test-only stand-in for Supabase's `auth` and `storage` schemas and roles |

## Migrations

| File | Domain model |
|---|---|
| `…0100_foundation.sql` | Enumerations (section 5), shared helpers |
| `…0200_tenancy.sql` | E1 to E3, membership helpers, sign-up trigger (A2), last-admin rule |
| `…0300_reference_data.sql` | E4 to E8, seeded standard, severity scale and mechanisms |
| `…0400_assets_and_inspections.sql` | E9 to E14, C3 to C11a, the inspection lock (C30) |
| `…0500_audit.sql` | E23, C35, C36 |
| `…0600_findings.sql` | E15 to E20, C11 to C25 |
| `…0700_reports.sql` | E21, E22, `sign_report`, `void_report`, C25 to C34 |
| `…0800_access.sql` | Privileges, row-level security, storage buckets and policies (section 9) |

## How the rules are enforced

- **Privileges** say which columns each role may write. Clients cannot write AI output, a photo's
  gradeability result, status columns or the audit log at all.
- **Row-level security** says which rows: every policy first checks membership of the row's organisation.
- **Triggers** enforce everything else for every role, the service role and the database owner
  included: immutability, lifecycles, escalations, the inspection lock and audit events.
- **Signing and voiding** happen only in `sign_report` and `void_report`, callable by the server only.

When adding a table later, grant its privileges and enable row-level security in the same migration.
Supabase's default grants would otherwise expose it; the schema test fails if any public table lacks
row-level security, gives `anon` a privilege, or has an unindexed foreign key.

## Running the tests

With Postgres 16, pgTAP and `pg_prove` installed (`apt install postgresql-16 postgresql-16-pgtap
libtap-parser-sourcehandler-pgtap-perl`):

```sh
scripts/db-test.sh
```

The script starts a temporary cluster, loads the test-only Supabase stand-in, applies every migration
and the seed, and runs the pgTAP suite. CI runs the same script (`.github/workflows/database.yml`).

With Docker and the Supabase CLI, the real local stack works too:

```sh
supabase start
supabase db reset   # migrations + seed
supabase test db    # pgTAP tests
```

## Seed accounts

| Email | Role | Organisation |
|---|---|---|
| `demo.admin@anode.test` | admin | Anode Demo (`is_demo`) |
| `demo.inspector@anode.test` | inspector | Anode Demo |
| `demo.viewer@anode.test` | viewer | Anode Demo |
| `other.admin@anode.test` | admin | Other Fabrication Ltd |

The seed has no passwords; sign-in for the public demo is set up in Stage 10.
