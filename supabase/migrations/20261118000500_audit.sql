-- Anode Phase 1 schema, part 5: the append-only audit log (D8).
-- Domain model E23; constraints C35 and C36.

create table public.audit_event (
  id bigint generated always as identity primary key,
  org_id uuid not null references public.organisation (id) on delete restrict,
  occurred_at timestamptz not null default now(),
  actor_id uuid references public.profile (id) on delete restrict,
  actor_kind public.audit_actor_kind not null,
  action public.audit_action not null,
  entity_type text not null check (private.nonblank(entity_type)),
  entity_id uuid not null,
  details jsonb not null default '{}' check (jsonb_typeof(details) = 'object'),
  check ((actor_kind = 'user') = (actor_id is not null))
);
create index audit_event_timeline_idx on public.audit_event (org_id, occurred_at desc);
create index audit_event_entity_idx on public.audit_event (entity_type, entity_id);
create index audit_event_actor_idx on public.audit_event (actor_id);

-- C36: append-only for every role, including the service role and the owner.
create trigger audit_event_immutable before update or delete on public.audit_event
  for each row execute function private.immutable_row();

create function private.refuse_truncate() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception '% cannot be truncated', tg_table_name using errcode = 'check_violation';
end
$$;
create trigger audit_event_no_truncate before truncate on public.audit_event
  for each statement execute function private.refuse_truncate();

-- The only way rows get in (C35). Called from Anode's trigger functions.
create function private.audit(
  p_org uuid,
  p_action public.audit_action,
  p_entity_type text,
  p_entity_id uuid,
  p_details jsonb default '{}',
  p_actor uuid default auth.uid()
) returns void
language plpgsql security definer
set search_path = ''
as $$
begin
  insert into public.audit_event (org_id, actor_id, actor_kind, action, entity_type, entity_id, details)
  values (
    p_org,
    p_actor,
    case when p_actor is null then 'server'::public.audit_actor_kind else 'user'::public.audit_actor_kind end,
    p_action,
    p_entity_type,
    p_entity_id,
    coalesce(p_details, '{}')
  );
end
$$;
