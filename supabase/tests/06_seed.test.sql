-- The development seed loads and is internally consistent (Stage 2 definition of done).
begin;
select no_plan();

select is((select count(*)::int from public.organisation where is_demo), 1, 'one demo organisation');
select results_eq(
  $$ select p.display_name, m.role::text from public.membership m
       join public.profile p on p.id = m.user_id
       join public.organisation o on o.id = m.org_id
      where o.is_demo order by p.display_name $$,
  $$ values ('Demo Admin', 'admin'), ('Demo Inspector', 'inspector'), ('Demo Viewer', 'viewer') $$,
  'the demo organisation has an admin, an inspector and a viewer');
select results_eq(
  $$ select r.status::text, r.signer_name, i.status::text
       from public.report r
       join public.report_inspection ri on ri.report_id = r.id
       join public.inspection i on i.id = ri.inspection_id
       join public.organisation o on o.id = r.org_id
      where o.is_demo $$,
  $$ values ('signed', 'Demo Inspector', 'reported') $$,
  'the demo has a signed report over a reported inspection');
select results_eq(
  $$ select f.rules_severity::text, f.severity::text, f.confidence::text, f.status::text
       from public.finding f join public.organisation o on o.id = f.org_id where o.is_demo $$,
  $$ values ('S2', 'S3', 'low', 'accepted') $$,
  'the demo finding shows a low-confidence raise (D1)');
select results_eq(
  $$ select e.reason::text, e.acknowledged_at is not null
       from public.finding_escalation e join public.organisation o on o.id = e.org_id where o.is_demo $$,
  $$ values ('injury_risk', true) $$,
  'the demo injury-risk escalation is acknowledged (D2)');
select set_eq(
  $$ select a.action::text from public.audit_event a join public.organisation o on o.id = a.org_id where o.is_demo $$,
  array['escalation_acknowledged', 'finding_accepted', 'report_signed'],
  'the demo audit log has the acknowledgement, the review and the signing');
select is((select count(*)::int from public.inspection i join public.organisation o on o.id = i.org_id
            where o.name = 'Other Fabrication Ltd'), 1,
  'a second organisation exists for isolation checks');
select ok((select bool_and(code like 'dev\_%') from public.recommendation),
  'seeded recommendations are clearly marked dev fixtures (D5)');

select * from finish();
rollback;
