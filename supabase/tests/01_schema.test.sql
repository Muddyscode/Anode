-- Schema shape: tables, RLS everywhere, reference data, enums, key indexes, privileges.
begin;
\ir _helpers.psql
select no_plan();

select tables_are('public', array[
  'organisation', 'profile', 'membership',
  'standard', 'severity_level', 'mechanism', 'recommendation', 'context_question',
  'asset', 'inspection_point', 'inspection', 'context_answer', 'photo', 'measurement',
  'finding', 'finding_escalation', 'mechanism_hypothesis', 'hypothesis_evidence',
  'finding_recommendation', 'finding_review', 'report', 'report_inspection', 'audit_event'
], 'every domain-model entity (E1 to E23) has a table, and nothing else');

select is(
  (select count(*)::int from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity),
  0, 'row-level security is enabled on every public table');

select is(
  (select count(*)::int from information_schema.table_privileges
    where table_schema = 'public' and grantee = 'anon'),
  0, 'anon has no privileges on any public table');

select is(
  (select count(*)::int from information_schema.columns
    where table_schema = 'public'
      and (column_name ~ 'depth|thickness|wall_loss|remaining_life')),
  0, 'R6: no depth, thickness, wall-loss or remaining-life columns');

-- Enumerations that carry decisions.
select enum_has_labels('public', 'scale_reference', array['anode_scale_card', 'ruler', 'tape_measure', 'none'],
  'D6: scale card, ruler or tape measure; no coins');
select enum_has_labels('public', 'severity', array['S1', 'S2', 'S3', 'S4'], 'R3: S1 to S4');
select enum_has_labels('public', 'confidence', array['low', 'medium', 'high'], 'R2: three confidence levels');
select enum_has_labels('public', 'report_status', array['draft', 'signed', 'void'], 'D7: reports can be voided');
select enum_has_labels('public', 'grade_scale', array['iso_4628_3_ri'], 'D9: Phase 1 grades on ISO 4628-3 only');
select enum_has_labels('public', 'audit_action', array['report_signed', 'report_voided', 'escalation_acknowledged',
  'finding_accepted', 'finding_edited', 'finding_rejected', 'finding_revised'], 'D8: audited actions');

-- Reference data.
select results_eq(
  $$ select code, edition, grade_min::int, grade_max::int from public.standard $$,
  $$ values ('ISO 4628-3', '2016', 0, 5) $$,
  'one standard: ISO 4628-3:2016, Ri 0 to 5');
select results_eq(
  $$ select code::text, requires_escalation from public.severity_level order by code $$,
  $$ values ('S1', false), ('S2', false), ('S3', false), ('S4', true) $$,
  'four severity levels; only S4 requires escalation');
select set_eq(
  $$ select code from public.mechanism $$,
  array['uniform', 'pitting', 'galvanic', 'crevice', 'cui', 'coating_breakdown_underfilm', 'mic'],
  'the first-release mechanisms');
select ok((select possibility_only from public.mechanism where code = 'mic'), 'MIC is possibility-only');
select is((select escalation_reason::text from public.mechanism where code = 'cui'), 'suspected_cui',
  'CUI as a mechanism escalates');

-- Key indexes behind constraints.
select has_index('public', 'photo', 'photo_one_gradeable', 'C10a index exists');
select has_index('public', 'finding', 'finding_superseded_once', 'C21 index exists');
select has_index('public', 'report', 'report_replaced_once', 'C34 index exists');
select has_index('public', 'membership', 'membership_user_id_idx', 'RLS membership lookup index exists');
select has_index('public', 'inspection', 'inspection_point_history_idx', 'R10 point history index exists');
select has_index('public', 'audit_event', 'audit_event_timeline_idx', 'audit timeline index exists');

-- Every foreign key has an index leading with one of its columns. For the
-- composite tenancy keys (org_id, x), the index must lead with the selective x.
select is(
  (select count(*)::int
     from pg_constraint c
     join pg_namespace n on n.oid = c.connamespace
    where n.nspname = 'public' and c.contype = 'f'
      and not exists (
        select 1 from pg_index i
          join pg_attribute a on a.attrelid = i.indrelid and a.attnum = i.indkey[0]
         where i.indrelid = c.conrelid
           and i.indkey[0] = any (c.conkey)
           and (a.attname <> 'org_id' or cardinality(c.conkey) = 1)
      )),
  0, 'every foreign key is indexed');

-- Signing and voiding are server-only (C28, C33).
select ok(not has_function_privilege('authenticated', 'public.sign_report(uuid, uuid, text, text, text)', 'execute'),
  'authenticated users cannot call sign_report');
select ok(not has_function_privilege('anon', 'public.void_report(uuid, uuid, text)', 'execute'),
  'anon cannot call void_report');
select ok(has_function_privilege('service_role', 'public.sign_report(uuid, uuid, text, text, text)', 'execute'),
  'the server can call sign_report');

-- Storage buckets are private.
select results_eq(
  $$ select id, public from storage.buckets where id in ('inspection-photos', 'reports') order by id $$,
  $$ values ('inspection-photos', false), ('reports', false) $$,
  'both storage buckets are private');

select * from finish();
rollback;
