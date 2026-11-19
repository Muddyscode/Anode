-- Tenancy and row-level security: a user sees only their own organisation's data
-- (Stage 2 definition of done), and roles limit what they can do (section 9).
begin;
\ir _helpers.psql
select no_plan();

select tests.setup_people();
select tests.save('a', tests.make_fixture('alice'));
select tests.save('b', tests.make_fixture('bruno'));
select tests.save('a_open', tests.make_fixture('alice'));
select tests.save_id('a_finding', tests.ai_finding(tests.get('a'), 'S2'));
select tests.save_id('b_finding', tests.ai_finding(tests.get('b'), 'S2'));
select tests.make_ready(tests.get('a'), 'alice');
select tests.save_id('a_report', tests.make_report(tests.get('a'), 'alice'));
select public.sign_report(tests.id('a_report'), tests.uid('alice'),
  tests.pdf_path(tests.get('a'), tests.id('a_report')), repeat('d', 64), 'screening-v1');
select tests.save_id('a_draft_report', gen_random_uuid());
insert into public.report (id, org_id, title, created_by)
values (tests.id('a_draft_report'), tests.org_of('alice'), 'Draft', tests.uid('alice'));
insert into storage.objects (bucket_id, name) values
  ('inspection-photos', tests.fx('a', 'org') || '/' || tests.fx('a', 'inspection') || '/x.jpg'),
  ('inspection-photos', tests.fx('b', 'org') || '/' || tests.fx('b', 'inspection') || '/y.jpg');

-- Sign-up (A2) --------------------------------------------------------------------

select results_eq(
  $$ select p.display_name, m.role::text, o.name
       from public.profile p
       join public.membership m on m.user_id = p.id
       join public.organisation o on o.id = m.org_id
      where p.id = tests.uid('bruno') $$,
  $$ values ('Bruno', 'admin', 'Bruno''s organisation') $$,
  'sign-up creates a profile, a personal organisation and an admin membership');

-- Isolation between organisations ------------------------------------------------

select tests.authenticate_as('bruno');

select is((select count(*)::int from public.organisation where id = tests.org_of('alice')), 0,
  'bruno cannot see alice''s organisation');
select is((select count(*)::int from public.asset where org_id = tests.org_of('alice')), 0,
  'bruno cannot see alice''s assets');
select is((select count(*)::int from public.inspection_point where org_id = tests.org_of('alice')), 0,
  'bruno cannot see alice''s points');
select is((select count(*)::int from public.inspection where org_id = tests.org_of('alice')), 0,
  'bruno cannot see alice''s inspections');
select is((select count(*)::int from public.photo where org_id = tests.org_of('alice')), 0,
  'bruno cannot see alice''s photos');
select is((select count(*)::int from public.measurement where org_id = tests.org_of('alice')), 0,
  'bruno cannot see alice''s measurements');
select is((select count(*)::int from public.finding where org_id = tests.org_of('alice')), 0,
  'bruno cannot see alice''s findings');
select is((select count(*)::int from public.finding_review where org_id = tests.org_of('alice')), 0,
  'bruno cannot see alice''s reviews');
select is((select count(*)::int from public.report where org_id = tests.org_of('alice')), 0,
  'bruno cannot see alice''s reports, even signed ones');
select is((select count(*)::int from public.audit_event where org_id = tests.org_of('alice')), 0,
  'bruno cannot see alice''s audit log');
select is((select count(*)::int from public.membership where org_id = tests.org_of('alice')), 0,
  'bruno cannot see alice''s memberships');
select is((select count(*)::int from public.profile where id = tests.uid('alice')), 0,
  'bruno cannot see alice''s profile');
select is((select count(*)::int from storage.objects where name like tests.org_of('alice') || '/%'), 0,
  'bruno cannot see alice''s stored files');
select is((select count(*)::int from public.asset), 1, 'bruno sees his own asset');
select is((select count(*)::int from public.finding), 1, 'bruno sees his own finding');

select throws_like(
  $$ insert into public.asset (org_id, name, asset_type, material, coating_status, environment,
       is_insulated, is_pressure_containing, failure_could_injure)
     values (tests.org_of('alice'), 'Intruder', 'pipe', 'carbon_steel', 'coated', 'indoor', false, false, false) $$,
  '%row-level security%', 'bruno cannot create assets in alice''s organisation');
select is_empty(
  $$ update public.asset set name = 'Hijacked' where org_id = tests.org_of('alice') returning id $$,
  'bruno cannot edit alice''s assets');
select throws_like(
  $$ insert into storage.objects (bucket_id, name)
     values ('inspection-photos', tests.fx('a_open', 'org') || '/' || tests.fx('a_open', 'inspection') || '/z.jpg') $$,
  '%row-level security%', 'bruno cannot upload into alice''s inspection folder');
select throws_like(
  $$ insert into public.membership (org_id, user_id, role) values (tests.org_of('alice'), tests.uid('bruno'), 'admin') $$,
  '%row-level security%', 'bruno cannot add himself to alice''s organisation');
reset role;

-- Within an organisation: admin, inspector, viewer --------------------------------

select tests.authenticate_as('ivan');
select is((select count(*)::int from public.asset where org_id = tests.org_of('alice')), 2,
  'ivan (inspector) sees his organisation''s assets');
select is((select count(*)::int from public.profile where id in (tests.uid('alice'), tests.uid('vera'))), 2,
  'ivan sees co-members'' profiles');
select lives_ok(
  $$ insert into public.asset (org_id, name, asset_type, material, coating_status, environment,
       is_insulated, is_pressure_containing, failure_could_injure)
     values (tests.org_of('alice'), 'New tank', 'tank', 'carbon_steel', 'coated', 'indoor', false, false, false) $$,
  'ivan can add assets');
select is((select created_by from public.asset where name = 'New tank'), tests.uid('ivan'),
  'created_by is the signed-in user');
select lives_ok(
  $$ insert into storage.objects (bucket_id, name)
     values ('inspection-photos', tests.fx('a_open', 'org') || '/' || tests.fx('a_open', 'inspection') || '/ivan.jpg') $$,
  'ivan can upload a photo to an open inspection');
select throws_like(
  $$ insert into storage.objects (bucket_id, name)
     values ('inspection-photos', tests.fx('a', 'org') || '/' || tests.fx('a', 'inspection') || '/late.jpg') $$,
  '%row-level security%', 'nobody can upload to an inspection that is in a signed report');
select throws_like(
  $$ insert into storage.objects (bucket_id, name) values ('reports', tests.fx('a', 'org') || '/fake.pdf') $$,
  '%row-level security%', 'nobody but the server writes report PDFs');
select throws_like(
  $$ insert into public.membership (org_id, user_id, role) values (tests.org_of('alice'), tests.uid('bruno'), 'viewer') $$,
  '%row-level security%', 'inspectors cannot manage members');
select ok((select count(*) from public.audit_event where org_id = tests.org_of('alice')) > 0,
  'inspectors can read the audit log');
select throws_like(
  $$ update public.organisation set is_demo = true where id = tests.org_of('alice') $$,
  '%permission denied%', 'nobody can flag an organisation as demo through the API');
reset role;

select tests.authenticate_as('vera');
select is((select count(*)::int from public.asset where org_id = tests.org_of('alice')), 3,
  'vera (viewer) can read all of her organisation''s assets');
select is((select count(*)::int from public.report where id = tests.id('a_report')), 1,
  'vera can read signed reports');
select is((select count(*)::int from public.report where id = tests.id('a_draft_report')), 0,
  'vera cannot see draft reports');
select is((select count(*)::int from public.audit_event), 0, 'viewers cannot read the audit log');
select throws_like(
  $$ insert into public.asset (org_id, name, asset_type, material, coating_status, environment,
       is_insulated, is_pressure_containing, failure_could_injure)
     values (tests.org_of('alice'), 'Viewer asset', 'pipe', 'carbon_steel', 'coated', 'indoor', false, false, false) $$,
  '%row-level security%', 'viewers cannot add assets');
select is_empty(
  $$ update public.inspection set notes = 'viewer note' where org_id = tests.org_of('alice') returning id $$,
  'viewers cannot edit inspections');
select throws_like(
  $$ insert into storage.objects (bucket_id, name)
     values ('inspection-photos', tests.fx('a_open', 'org') || '/' || tests.fx('a_open', 'inspection') || '/v.jpg') $$,
  '%row-level security%', 'viewers cannot upload photos');
select ok((select count(*) from storage.objects where name like tests.org_of('alice') || '/%') > 0,
  'viewers can read their organisation''s files');
reset role;

select tests.authenticate_as('alice');
select lives_ok(
  $$ update public.membership set role = 'admin' where org_id = tests.org_of('alice') and user_id = tests.uid('ivan') $$,
  'admins can change roles');
select lives_ok(
  $$ update public.membership set role = 'inspector' where org_id = tests.org_of('alice') and user_id = tests.uid('ivan') $$,
  'admins can change roles back');
select throws_like(
  $$ delete from public.membership where org_id = tests.org_of('alice') and user_id = tests.uid('alice') $$,
  '%at least one admin%', 'the last admin cannot leave');
select throws_like(
  $$ update public.membership set role = 'viewer' where org_id = tests.org_of('alice') and user_id = tests.uid('alice') $$,
  '%at least one admin%', 'the last admin cannot demote themselves');
select lives_ok(
  $$ update public.organisation set name = 'Alice Inspection Services' where id = tests.org_of('alice') $$,
  'admins can rename their organisation');
select throws_like(
  $$ delete from public.asset where org_id = tests.org_of('alice') $$,
  '%permission denied%', 'assets are archived, not deleted');
select is_empty(
  $$ update public.profile set display_name = 'Not Ivan' where id = tests.uid('ivan') returning id $$,
  'people cannot edit someone else''s profile');
select lives_ok(
  $$ update public.profile set qualification = 'API 570' where id = tests.uid('alice') $$,
  'people can edit their own profile');
reset role;

-- anon has no access at all.
set local role anon;
select throws_like($$ select count(*) from public.asset $$, '%permission denied%', 'anon cannot read assets');
select throws_like($$ select count(*) from public.standard $$, '%permission denied%', 'anon cannot read reference data');
reset role;

select * from finish();
rollback;
