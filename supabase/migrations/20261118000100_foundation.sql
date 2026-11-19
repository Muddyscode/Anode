-- Anode Phase 1 schema, part 1: schemas, enumerations and shared helpers.
-- Source of truth: docs/domain-model.md (sections 2 and 5).

-- Helper functions live in a schema the API does not expose.
create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to authenticated, service_role;
-- Nothing in private is callable unless granted explicitly.
alter default privileges in schema private revoke execute on functions from public;

-- Enumerations (domain model section 5) ----------------------------------------

create type public.member_role as enum ('admin', 'inspector', 'viewer');
create type public.grade_scale as enum ('iso_4628_3_ri');
create type public.severity as enum ('S1', 'S2', 'S3', 'S4');
create type public.confidence as enum ('low', 'medium', 'high');
create type public.answer_type as enum ('boolean', 'single_choice', 'number', 'text');
create type public.asset_type as enum ('pipe', 'tank', 'beam', 'hull_plate', 'bolt', 'structure', 'other');
create type public.material as enum (
  'carbon_steel', 'low_alloy_steel', 'stainless_steel', 'galvanised_steel', 'cast_iron', 'other', 'unknown'
);
create type public.coating_status as enum ('coated', 'uncoated', 'unknown');
create type public.environment as enum (
  'atmospheric_rural', 'atmospheric_urban', 'atmospheric_industrial', 'atmospheric_marine',
  'immersed', 'buried', 'indoor', 'other'
);
create type public.inspection_status as enum ('draft', 'ready_for_signoff', 'reported');
create type public.gradeability as enum ('pending', 'gradeable', 'rejected');
create type public.photo_rejection_reason as enum (
  'out_of_focus', 'uneven_lighting', 'glare', 'no_scale_reference', 'surface_not_visible'
);
create type public.scale_reference as enum ('anode_scale_card', 'ruler', 'tape_measure', 'none');
create type public.finding_origin as enum ('ai', 'inspector');
create type public.defect_type as enum ('rusting', 'pitting', 'suspected_cracking', 'coating_breakdown', 'other');
create type public.finding_status as enum ('draft', 'accepted', 'rejected', 'superseded');
create type public.escalation_reason as enum (
  'severity_s4', 'pressure_pitting_or_wall_loss', 'suspected_cracking', 'suspected_cui', 'injury_risk'
);
create type public.escalation_source as enum ('grading_rules', 'explain_step', 'inspector');
create type public.review_decision as enum ('accept', 'edit', 'reject');
create type public.report_status as enum ('draft', 'signed', 'void');
create type public.audit_actor_kind as enum ('user', 'server');
create type public.audit_action as enum (
  'report_signed', 'report_voided', 'escalation_acknowledged',
  'finding_accepted', 'finding_edited', 'finding_rejected', 'finding_revised'
);

-- Shared helpers -----------------------------------------------------------------

-- True when a text value has visible content (C4 and the "non-empty" rules).
create function private.nonblank(value text) returns boolean
language sql immutable parallel safe
set search_path = ''
as $$ select value is not null and char_length(btrim(value)) > 0 $$;

-- Keeps updated_at current on mutable tables (section 2).
create function private.set_updated_at() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end
$$;

-- Parses a uuid without raising, for storage paths supplied by clients.
create function private.try_uuid(value text) returns uuid
language plpgsql immutable
set search_path = ''
as $$
begin
  return value::uuid;
exception when invalid_text_representation then
  return null;
end
$$;

-- Internal state changes (inspection status, finding status) are made only by
-- Anode's own trigger functions. They mark the transaction so guard triggers can
-- tell an internal change from a direct UPDATE.
-- enter_internal() returns the previous value so callers can nest:
--   v_prev := private.enter_internal(); ...; perform private.restore_internal(v_prev);
create function private.enter_internal() returns text
language plpgsql
set search_path = ''
as $$
declare
  v_prev text := coalesce(current_setting('anode.internal', true), 'off');
begin
  perform set_config('anode.internal', 'on', true);
  return v_prev;
end
$$;

create function private.restore_internal(p_prev text) returns void
language sql
set search_path = ''
as $$ select set_config('anode.internal', coalesce(p_prev, 'off'), true) $$;

create function private.is_internal() returns boolean
language sql stable
set search_path = ''
as $$ select coalesce(current_setting('anode.internal', true), 'off') = 'on' $$;

-- Severity one step higher, capped at S4 (D1).
create function private.severity_step_up(value public.severity) returns public.severity
language sql immutable parallel safe
set search_path = ''
as $$
  select case value
    when 'S1' then 'S2'::public.severity
    when 'S2' then 'S3'::public.severity
    else 'S4'::public.severity
  end
$$;

revoke all on all functions in schema private from public;
grant execute on function private.nonblank(text), private.try_uuid(text) to authenticated, service_role;
