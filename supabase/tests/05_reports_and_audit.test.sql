-- Reports: signing (R9, C25 to C30), void and reissue (D7, C33, C34), and the
-- append-only audit log (D8, C35, C36).
begin;
\ir _helpers.psql
select no_plan();

select tests.setup_people();
select tests.save('a', tests.make_fixture('alice', p_injury => true));
select tests.save_id('f1', tests.ai_finding(tests.get('a'), 'S2'));
select tests.save_id('r1', tests.make_report(tests.get('a'), 'ivan'));

create function tests.sign_sql(p_report text, p_signer text, p_fixture text default 'a') returns text
language sql immutable as $$
  select format(
    'select public.sign_report(tests.id(%1$L), tests.uid(%2$L), tests.pdf_path(tests.get(%3$L), tests.id(%1$L)), repeat(''9'', 64), ''screening-v1'')',
    p_report, p_signer, p_fixture)
$$;

-- C25 to C28: what signing requires --------------------------------------------------

select is((select status::text from public.inspection where id = tests.fx('a', 'inspection')), 'draft',
  'an inspection with a draft finding is draft');
select throws_like(tests.sign_sql('r1', 'ivan'), '%accepted, edited or rejected%',
  'R9: a report cannot be signed while a finding is still draft');

insert into public.finding_review (org_id, finding_id, decision, reviewed_by)
values (tests.fx('a', 'org'), tests.id('f1'), 'accept', tests.uid('ivan'));
select is((select status::text from public.inspection where id = tests.fx('a', 'inspection')), 'ready_for_signoff',
  'C25: every finding decided, so ready for sign-off');
select throws_like(tests.sign_sql('r1', 'ivan'), '%escalation must be acknowledged%',
  'R5: an unacknowledged escalation blocks signing (A34)');

update public.finding_escalation set acknowledged_by = tests.uid('ivan'), acknowledged_at = now(),
  acknowledgement_note = 'Area cordoned off.' where finding_id = tests.id('f1');
select throws_like(tests.sign_sql('r1', 'vera'), '%inspector or admin%', 'viewers cannot sign');
select throws_like(tests.sign_sql('r1', 'bruno'), '%must be a member%', 'outsiders cannot sign');
select throws_like(
  $$ select public.sign_report(tests.id('r1'), tests.uid('ivan'), tests.fx('a', 'org') || '/missing.pdf',
       repeat('9', 64), 'screening-v1') $$,
  '%has not been stored%', 'the PDF must be stored before signing');
select throws_like(
  $$ update public.report set status = 'signed' where id = tests.id('r1') $$,
  '%only through sign_report%', 'C28: status cannot be set to signed directly');

select tests.authenticate_as('ivan');
select throws_like(tests.sign_sql('r1', 'ivan'), '%permission denied%',
  'C28: users cannot call sign_report; the server does');
reset role;

select tests.save_id('empty', gen_random_uuid());
insert into public.report (id, org_id, title) values (tests.id('empty'), tests.fx('a', 'org'), 'Empty');
insert into storage.objects (bucket_id, name) values ('reports', tests.pdf_path(tests.get('a'), tests.id('empty')));
select throws_like(tests.sign_sql('empty', 'ivan'), '%at least one inspection%', 'C27: a report covers something');

-- Sign ---------------------------------------------------------------------------------

set local role service_role;
select lives_ok(tests.sign_sql('r1', 'ivan'), 'the server signs on behalf of a verified inspector');
reset role;
select results_eq(
  $$ select status::text, signed_by, signer_name, disclaimer_version from public.report where id = tests.id('r1') $$,
  $$ values ('signed', tests.uid('ivan'), 'Ivan', 'screening-v1') $$,
  'the signed report records who signed and the disclaimer version (C26, C31)');
select is((select status::text from public.inspection where id = tests.fx('a', 'inspection')), 'reported',
  'signing reports the inspection');
select results_eq(
  $$ select action::text, actor_id, actor_kind::text from public.audit_event
      where entity_id = tests.id('r1') $$,
  $$ values ('report_signed', tests.uid('ivan'), 'user') $$,
  'D8: signing is audited');

-- C30: everything signed is locked --------------------------------------------------------

select throws_like($$ update public.report set title = 'Changed' where id = tests.id('r1') $$,
  '%signed report cannot be changed%', 'C30: a signed report is never edited');
select throws_like($$ delete from public.report where id = tests.id('r1') $$,
  '%never deleted%', 'C30: a signed report is never deleted');
select throws_like($$ delete from public.report_inspection where report_id = tests.id('r1') $$,
  '%contents cannot change%', 'a signed report''s contents are fixed');
select throws_like($$ update public.inspection set notes = 'late note' where id = tests.fx('a', 'inspection') $$,
  '%locked%', 'C30: a reported inspection is locked');
select throws_like(
  $$ insert into public.photo (org_id, inspection_id, storage_path, content_sha256, mime_type, width_px, height_px, uploaded_by)
     values (tests.fx('a', 'org'), tests.fx('a', 'inspection'), 'p', repeat('1', 64), 'image/jpeg', 1, 1, tests.uid('ivan')) $$,
  '%locked%', 'C30: no new photos on a reported inspection');
select throws_like(
  $$ insert into public.finding_escalation (org_id, finding_id, reason, source)
     values (tests.fx('a', 'org'), tests.id('f1'), 'suspected_cracking', 'inspector') $$,
  '%locked%', 'C30: no new escalations on a reported inspection');
select throws_like(
  $$ insert into public.finding (org_id, inspection_id, photo_id, origin, defect_type, standard_id,
       grade_value, rules_severity, severity, confidence, created_by)
     values (tests.fx('a', 'org'), tests.fx('a', 'inspection'), tests.fx('a', 'photo'), 'inspector', 'rusting',
       tests.standard_id(), 1, 'S1', 'S1', 'high', tests.uid('ivan')) $$,
  '%locked%', 'C30: no new findings on a reported inspection');

select tests.save_id('r_dup', gen_random_uuid());
insert into public.report (id, org_id, title) values (tests.id('r_dup'), tests.fx('a', 'org'), 'Duplicate');
select throws_like(
  $$ insert into public.report_inspection (report_id, inspection_id, org_id)
     values (tests.id('r_dup'), tests.fx('a', 'inspection'), tests.fx('a', 'org')) $$,
  '%already in a signed report%', 'C29: an inspection is in one live report');

-- D7 / C33: void ----------------------------------------------------------------------------

select throws_like($$ select public.void_report(tests.id('r1'), tests.uid('ivan'), '  ') $$,
  '%needs a reason%', 'voiding needs a reason');
select throws_like($$ select public.void_report(tests.id('r1'), tests.uid('vera'), 'Wrong point') $$,
  '%inspector or admin%', 'viewers cannot void');
select throws_like($$ select public.void_report(tests.id('r_dup'), tests.uid('ivan'), 'Nope') $$,
  '%only a signed report%', 'only a signed report can be voided');
select throws_like(
  $$ update public.report set status = 'void', voided_by = tests.uid('ivan'), voided_at = now(), void_reason = 'x'
      where id = tests.id('r1') $$,
  '%signed report cannot be changed%', 'C33: status cannot be set to void directly');

set local role service_role;
select lives_ok(
  $$ select public.void_report(tests.id('r1'), tests.uid('alice'), 'Wrong grade: pits missed on first review.') $$,
  'the server voids a signed report with a reason');
reset role;
select results_eq(
  $$ select status::text, voided_by, void_reason, pdf_sha256 from public.report where id = tests.id('r1') $$,
  $$ values ('void', tests.uid('alice'), 'Wrong grade: pits missed on first review.', repeat('9', 64)) $$,
  'the voided report keeps its signature and PDF hash; only the void columns are added');
select is((select status::text from public.inspection where id = tests.fx('a', 'inspection')), 'ready_for_signoff',
  'A38: voiding releases the inspection for correction');
select throws_like($$ select public.void_report(tests.id('r1'), tests.uid('alice'), 'Again') $$,
  '%only a signed report%', 'void is final');
select throws_like($$ update public.report set title = 'Changed' where id = tests.id('r1') $$,
  '%void report cannot be changed%', 'a void report is never edited');
select throws_like($$ delete from public.report where id = tests.id('r1') $$,
  '%never deleted%', 'a void report is never deleted');

-- C21a: correcting a finding after the void ---------------------------------------------------

select throws_like(
  $$ insert into public.finding (org_id, inspection_id, photo_id, origin, supersedes_finding_id, defect_type, standard_id,
       grade_value, rules_severity, severity, confidence, created_by)
     values (tests.fx('a', 'org'), tests.fx('a', 'inspection'), tests.fx('a', 'photo'), 'inspector', tests.id('f1'),
       'pitting', tests.standard_id(), 3, 'S3', 'S3', 'high', tests.uid('ivan')) $$,
  '%needs a reason%', 'C21a: a revision after a void needs a reason');
select tests.save_id('f1_rev', gen_random_uuid());
select lives_ok(
  $$ insert into public.finding (id, org_id, inspection_id, photo_id, origin, supersedes_finding_id, revision_reason,
       defect_type, standard_id, grade_value, rules_severity, severity, confidence, created_by)
     values (tests.id('f1_rev'), tests.fx('a', 'org'), tests.fx('a', 'inspection'), tests.fx('a', 'photo'), 'inspector',
       tests.id('f1'), 'Pitting confirmed with a pit gauge.', 'pitting', tests.standard_id(), 3, 'S3', 'S3', 'high',
       tests.uid('ivan')) $$,
  'an inspector revises an accepted finding after the void');
select is((select status::text from public.finding where id = tests.id('f1')), 'superseded',
  'the earlier finding is superseded, not edited');
select results_eq(
  $$ select action::text, actor_id, details ->> 'reason' from public.audit_event where action = 'finding_revised'
      and org_id = tests.org_of('alice') $$,
  $$ values ('finding_revised', tests.uid('ivan'), 'Pitting confirmed with a pit gauge.') $$,
  'D8: the revision is audited');
select is((select count(*)::int from public.finding_escalation where finding_id = tests.id('f1_rev') and reason = 'injury_risk'),
  1, 'D2: the revision on an injury-risk asset is escalated again');

-- C34: reissue --------------------------------------------------------------------------------

select throws_like(
  $$ insert into public.report (org_id, title, replaces_report_id)
     values (tests.fx('a', 'org'), 'Bad link', tests.id('r_dup')) $$,
  '%only replace a voided report%', 'C34: a replacement points at a void report');
select tests.save_id('r2', tests.make_report(tests.get('a'), 'ivan', tests.id('r1')));
select throws_like(
  $$ insert into public.report (org_id, title, replaces_report_id) values (tests.fx('a', 'org'), 'Second', tests.id('r1')) $$,
  '%report_replaced_once%', 'C34: a voided report has one replacement');
select throws_like(tests.sign_sql('r2', 'ivan'), '%escalation must be acknowledged%',
  'the revision''s new escalation must be acknowledged before re-signing');
update public.finding_escalation set acknowledged_by = tests.uid('ivan'), acknowledged_at = now(),
  acknowledgement_note = 'Still cordoned off.' where finding_id = tests.id('f1_rev');
select lives_ok(tests.sign_sql('r2', 'ivan'), 'the replacement report is signed');
select results_eq(
  $$ select r.status::text, r.replaces_report_id, o.status::text from public.report r
       join public.report o on o.id = r.replaces_report_id where r.id = tests.id('r2') $$,
  $$ values ('signed', tests.id('r1'), 'void') $$,
  'D7: the new report links to the voided one, which stays void');

-- D8 / C36: the audit log is append-only -----------------------------------------------------

select throws_like($$ update public.audit_event set details = '{}' where org_id = tests.org_of('alice') $$,
  '%cannot be changed%', 'C36: audit events cannot be edited, even by the database owner');
select throws_like($$ delete from public.audit_event where org_id = tests.org_of('alice') $$,
  '%cannot be changed%', 'C36: audit events cannot be deleted, even by the database owner');
select throws_like($$ truncate public.audit_event $$, '%cannot be truncated%', 'C36: the audit log cannot be truncated');

set local role service_role;
select throws_like(
  $$ insert into public.audit_event (org_id, actor_kind, action, entity_type, entity_id)
     values (tests.org_of('alice'), 'server', 'report_signed', 'report', gen_random_uuid()) $$,
  '%permission denied%', 'C36: not even the server writes audit events directly');
reset role;

select tests.authenticate_as('ivan');
select throws_like(
  $$ insert into public.audit_event (org_id, actor_kind, action, entity_type, entity_id)
     values (tests.org_of('alice'), 'server', 'report_signed', 'report', gen_random_uuid()) $$,
  '%permission denied%', 'users cannot write audit events');
reset role;

select set_eq(
  $$ select action::text from public.audit_event where org_id = tests.org_of('alice') $$,
  array['finding_accepted', 'escalation_acknowledged', 'report_signed', 'report_voided', 'finding_revised'],
  'D8: signing, voiding, acknowledgements, reviews and revisions are all on record');

select * from finish();
rollback;
