-- Findings: grades (R2), severity and confidence (R3, R4, D1, D3, D4), escalation
-- (R5, D2), mechanisms (R7), recommendations (R8), review and feedback (R9).
begin;
\ir _helpers.psql
select no_plan();

select tests.setup_people();
select tests.save('a', tests.make_fixture('alice'));

create function tests.ai_sql(p_rules text, p_severity text, p_confidence text, p_reason text default null,
  p_grade int default 2, p_fixture text default 'a') returns text
language sql immutable as $$
  select format(
    'insert into public.finding (org_id, inspection_id, photo_id, measurement_id, origin, defect_type, standard_id,
       grade_value, rules_severity, severity, confidence, severity_raised_reason, grading_rules_version)
     values (tests.fx(%1$L, ''org''), tests.fx(%1$L, ''inspection''), tests.fx(%1$L, ''photo''), tests.fx(%1$L, ''measurement''),
       ''ai'', ''rusting'', tests.standard_id(), %2$s, %3$L, %4$L, %5$L, %6$L, ''r1'')',
    p_fixture, p_grade, p_rules, p_severity, p_confidence, p_reason)
$$;

-- R2, R4, D1, D4: severity and confidence ----------------------------------------------

select lives_ok(tests.ai_sql('S1', 'S2', 'low', 'Low confidence.'), 'D1: low confidence lifts S1 to S2');
select lives_ok(tests.ai_sql('S2', 'S3', 'low', 'Low confidence.'), 'D1: low confidence lifts S2 to S3');
select lives_ok(tests.ai_sql('S3', 'S4', 'low', 'Low confidence.'), 'D1: low confidence lifts S3 to S4');
select lives_ok(tests.ai_sql('S4', 'S4', 'low'), 'D1: S4 is the cap');
select throws_like(tests.ai_sql('S1', 'S1', 'low'), '%finding_low_confidence_raises_severity%',
  'R4: an AI finding with low confidence is never S1');
select throws_like(tests.ai_sql('S2', 'S2', 'low'), '%finding_low_confidence_raises_severity%',
  'D1: low confidence raises every level, not just S1');
select throws_like(tests.ai_sql('S1', 'S3', 'low', 'Too far.'), '%finding_low_confidence_raises_severity%',
  'D1: the raise is exactly one step');
select lives_ok(tests.ai_sql('S1', 'S1', 'medium'), 'D4: medium confidence does not block S1');
select lives_ok(tests.ai_sql('S1', 'S1', 'high'), 'high confidence keeps S1');
select throws_like(tests.ai_sql('S2', 'S3', 'high', 'Felt like it.'), '%finding_low_confidence_raises_severity%',
  'high confidence keeps the rules severity');
select throws_like(tests.ai_sql('S1', 'S2', 'low'), '%finding_raise_has_reason%', 'R4: a raise says why');
select throws_like(tests.ai_sql('S1', 'S1', 'high', null, 6), '%outside ISO 4628-3%', 'C13: Ri is 0 to 5');
select throws_like(tests.ai_sql('S1', 'S1', 'high', null, -1), '%outside ISO 4628-3%', 'C13: Ri is not negative');
select throws_like(
  $$ insert into public.finding (org_id, inspection_id, photo_id, origin, defect_type, standard_id,
       grade_value, rules_severity, severity, confidence, grading_rules_version)
     values (tests.fx('a', 'org'), tests.fx('a', 'inspection'), tests.fx('a', 'photo'), 'ai', 'rusting',
       tests.standard_id(), 1, 'S1', 'S1', 'high', 'r1') $$,
  '%finding_ai_provenance%', 'C12: an AI finding comes from a measurement');
select is((select count(*)::int from public.finding where status <> 'draft' and origin = 'ai'
              and org_id = tests.org_of('alice')), 0,
  'AI findings start as draft (R9)');

-- R5, D2: escalations the database adds ------------------------------------------------

select is(
  (select array_agg(e.reason::text) from public.finding_escalation e join public.finding f on f.id = e.finding_id
    where f.severity = 'S4'),
  array['severity_s4', 'severity_s4'], 'C16a: every S4 finding is escalated');

select tests.save('injury', tests.make_fixture('alice', p_injury => true));
select tests.save_id('f_injury', tests.ai_finding(tests.get('injury'), 'S1'));
select is(
  (select array_agg(reason::text) from public.finding_escalation where finding_id = tests.id('f_injury')),
  array['injury_risk'], 'D2: an S1 finding on an injury-risk asset is escalated');

select tests.save('insulated', tests.make_fixture('alice', p_insulated => true));
select tests.save_id('f_insulated', tests.ai_finding(tests.get('insulated'), 'S2'));
select is(
  (select array_agg(reason::text) from public.finding_escalation where finding_id = tests.id('f_insulated')),
  array['suspected_cui'], 'R5: findings on insulated assets escalate for suspected CUI');

select tests.save('pressure', tests.make_fixture('alice', p_pressure => true));
select tests.save_id('f_pressure_rust', tests.ai_finding(tests.get('pressure'), 'S2'));
select is((select count(*)::int from public.finding_escalation where finding_id = tests.id('f_pressure_rust')), 0,
  'rusting alone on pressure equipment does not trigger the pitting escalation');
select tests.save_id('f_pressure_pit', tests.ai_finding(tests.get('pressure'), 'S2', 'high', 'pitting'));
select is(
  (select array_agg(reason::text) from public.finding_escalation where finding_id = tests.id('f_pressure_pit')),
  array['pressure_pitting_or_wall_loss'], 'R5: pitting on pressure equipment escalates');

select tests.save_id('f_crack', tests.ai_finding(tests.get('a'), 'S2', 'high', 'suspected_cracking'));
select is(
  (select array_agg(reason::text) from public.finding_escalation where finding_id = tests.id('f_crack')),
  array['suspected_cracking'], 'R5: suspected cracking escalates');

select tests.save_id('f_plain', tests.ai_finding(tests.get('a'), 'S2'));
select is((select count(*)::int from public.finding_escalation where finding_id = tests.id('f_plain')), 0,
  'an S2 rust finding on an ordinary asset has no escalation');

-- R7 / C17, C18: mechanisms ---------------------------------------------------------------

select lives_ok(
  $$ insert into public.mechanism_hypothesis (org_id, finding_id, rank, mechanism_code, visual_evidence)
     values (tests.fx('a', 'org'), tests.id('f_plain'), 1, 'cui', 'Rust weeping from under the cladding.') $$,
  'a ranked mechanism with visual evidence');
select is(
  (select array_agg(reason::text) from public.finding_escalation where finding_id = tests.id('f_plain')),
  array['suspected_cui'], 'C16b: CUI as a ranked mechanism escalates');
select throws_like(
  $$ insert into public.mechanism_hypothesis (org_id, finding_id, rank, mechanism_code, visual_evidence)
     values (tests.fx('a', 'org'), tests.id('f_plain'), 2, 'cui', 'Again.') $$,
  '%duplicate key%', 'each mechanism appears once per finding');
select throws_like(
  $$ insert into public.mechanism_hypothesis (org_id, finding_id, rank, mechanism_code, visual_evidence)
     values (tests.fx('a', 'org'), tests.id('f_plain'), 4, 'pitting', 'Pits.') $$,
  '%violates check constraint%', 'R7: at most three mechanisms');
select throws_like(
  $$ insert into public.mechanism_hypothesis (org_id, finding_id, rank, mechanism_code, visual_evidence)
     values (tests.fx('a', 'org'), tests.id('f_plain'), 2, 'pitting', '   ') $$,
  '%violates check constraint%', 'R7: each mechanism has visual evidence');
select throws_like(
  $$ insert into public.mechanism_hypothesis (org_id, finding_id, rank, mechanism_code, visual_evidence)
     values (tests.fx('a', 'org'), tests.id('f_crack'), 1, 'mic', 'Black slime.') $$,
  '%only as a possibility%', 'C17: MIC is never ranked first');
select lives_ok(
  $$ insert into public.mechanism_hypothesis (org_id, finding_id, rank, mechanism_code, visual_evidence)
     values (tests.fx('a', 'org'), tests.id('f_plain'), 2, 'mic', 'Dark deposits near the base.') $$,
  'MIC can be listed as a lower-ranked possibility');

select lives_ok(
  $$ insert into public.mechanism_hypothesis (org_id, finding_id, rank, mechanism_code, visual_evidence)
     values (tests.fx('pressure', 'org'), tests.id('f_pressure_rust'), 1, 'pitting', 'Scattered pits.') $$,
  'pitting ranked on a pressure asset');
select is(
  (select array_agg(reason::text) from public.finding_escalation where finding_id = tests.id('f_pressure_rust')),
  array['pressure_pitting_or_wall_loss'], 'C16b: ranked pitting on pressure equipment escalates (A28)');

insert into public.context_question (key, prompt, answer_type) values ('t_wet', 'Wet?', 'boolean');
select tests.save_id('ans_a', gen_random_uuid());
select tests.save_id('ans_other', gen_random_uuid());
insert into public.context_answer (id, org_id, inspection_id, question_key, value) values
  (tests.id('ans_a'), tests.fx('a', 'org'), tests.fx('a', 'inspection'), 't_wet', 'true'),
  (tests.id('ans_other'), tests.fx('injury', 'org'), tests.fx('injury', 'inspection'), 't_wet', 'false');
select lives_ok(
  $$ insert into public.hypothesis_evidence (hypothesis_id, context_answer_id, org_id)
     select h.id, tests.id('ans_a'), h.org_id from public.mechanism_hypothesis h
      where h.finding_id = tests.id('f_plain') and h.rank = 1 $$,
  'R7: a mechanism cites a context answer from its inspection');
select throws_like(
  $$ insert into public.hypothesis_evidence (hypothesis_id, context_answer_id, org_id)
     select h.id, tests.id('ans_other'), h.org_id from public.mechanism_hypothesis h
      where h.finding_id = tests.id('f_plain') and h.rank = 2 $$,
  '%same inspection%', 'C18: evidence comes from the same inspection');

-- R8 / C24: recommendations -----------------------------------------------------------------

insert into public.recommendation (code, version, text, min_severity, is_active) values
  ('t_monitor', 1, 'Old wording.', null, false),
  ('t_monitor', 2, 'Monitor.', null, true),
  ('t_ut', 1, 'UT grid.', 'S3', true);
select throws_like(
  $$ insert into public.finding_recommendation (finding_id, recommendation_code, recommendation_version, sort_order, org_id)
     values (tests.id('f_plain'), 't_free_text', 1, 1, tests.fx('a', 'org')) $$,
  '%foreign key%', 'R8: recommendations come only from the library');
select throws_like(
  $$ insert into public.finding_recommendation (finding_id, recommendation_code, recommendation_version, sort_order, org_id)
     values (tests.id('f_plain'), 't_monitor', 1, 1, tests.fx('a', 'org')) $$,
  '%not the current library entry%', 'C24: only the current version');
select lives_ok(
  $$ insert into public.finding_recommendation (finding_id, recommendation_code, recommendation_version, sort_order, org_id)
     values (tests.id('f_plain'), 't_monitor', 2, 1, tests.fx('a', 'org')) $$,
  'the current version is accepted');
select throws_like(
  $$ insert into public.finding_recommendation (finding_id, recommendation_code, recommendation_version, sort_order, org_id)
     values (tests.id('f_plain'), 't_ut', 1, 2, tests.fx('a', 'org')) $$,
  '%applies from S3%', 'a recommendation is not offered below its severity floor');
select throws_like(
  $$ insert into public.recommendation (code, version, text) values ('t_monitor', 3, 'Second active.') $$,
  '%recommendation_one_active_version%', 'one active version per recommendation');

-- C19: findings are immutable ---------------------------------------------------------------

select throws_like(
  $$ update public.finding set severity = 'S1' where id = tests.id('f_plain') $$,
  '%cannot be edited%', 'C19: a finding''s grade cannot be changed, even by the database owner');
select throws_like(
  $$ update public.finding set status = 'accepted' where id = tests.id('f_plain') $$,
  '%only through a review%', 'finding status changes only through a review');
select throws_like(
  $$ delete from public.finding where id = tests.id('f_plain') $$,
  '%kept, not deleted%', 'findings are never deleted');
select throws_like(
  $$ delete from public.mechanism_hypothesis where finding_id = tests.id('f_plain') $$,
  '%cannot be changed%', 'hypotheses are immutable');

-- R5 / C16: escalations are append-only and acknowledged once -------------------------------

select throws_like(
  $$ delete from public.finding_escalation where finding_id = tests.id('f_injury') $$,
  '%cannot be removed%', 'C16: escalations cannot be removed');
select throws_like(
  $$ update public.finding_escalation set reason = 'severity_s4' where finding_id = tests.id('f_injury') $$,
  '%can only be acknowledged%', 'an escalation''s reason cannot change');
select throws_like(
  $$ update public.finding_escalation set acknowledged_by = tests.uid('alice'), acknowledged_at = now()
      where finding_id = tests.id('f_injury') $$,
  '%violates check constraint%', 'C16: acknowledgement needs a note');
select throws_like(
  $$ update public.finding_escalation set acknowledged_by = tests.uid('vera'), acknowledged_at = now(),
       acknowledgement_note = 'ok' where finding_id = tests.id('f_injury') $$,
  '%inspector or admin%', 'C3: viewers cannot acknowledge escalations');

select tests.authenticate_as('ivan');
select lives_ok(
  $$ update public.finding_escalation set acknowledged_by = tests.uid('ivan'), acknowledged_at = now(),
       acknowledgement_note = 'Barrier placed; inspector informed.' where finding_id = tests.id('f_injury') $$,
  'an inspector acknowledges an escalation');
select throws_like(
  $$ update public.finding_escalation set acknowledged_by = tests.uid('ivan'), acknowledged_at = now(),
       acknowledgement_note = 'Again' where finding_id = tests.id('f_injury') $$,
  '%already acknowledged%', 'an escalation is acknowledged once');
select lives_ok(
  $$ insert into public.finding_escalation (org_id, finding_id, reason, source, detail)
     values (tests.fx('a', 'org'), tests.id('f_plain'), 'suspected_cracking', 'inspector', 'Hairline crack at weld toe.') $$,
  'C16c: an inspector can raise an escalation');
select throws_like(
  $$ insert into public.finding_escalation (org_id, finding_id, reason, source)
     values (tests.fx('a', 'org'), tests.id('f_plain'), 'injury_risk', 'grading_rules') $$,
  '%row-level security%', 'people cannot pose as the grading rules');
reset role;

select results_eq(
  $$ select action::text, actor_id, details ->> 'reason' from public.audit_event
      where entity_type = 'finding_escalation' and org_id = tests.org_of('alice') $$,
  $$ values ('escalation_acknowledged', tests.uid('ivan'), 'injury_risk') $$,
  'D8: acknowledgements are audited');

-- R9: review --------------------------------------------------------------------------------

select tests.authenticate_as('ivan');
select throws_like(
  $$ insert into public.finding (org_id, inspection_id, photo_id, measurement_id, origin, defect_type, standard_id,
       grade_value, rules_severity, severity, confidence, grading_rules_version)
     values (tests.fx('a', 'org'), tests.fx('a', 'inspection'), tests.fx('a', 'photo'), tests.fx('a', 'measurement'),
       'ai', 'rusting', tests.standard_id(), 1, 'S1', 'S1', 'high', 'fake') $$,
  '%permission denied%', 'people cannot write AI findings');

-- Accept.
select lives_ok(
  $$ insert into public.finding_review (org_id, finding_id, decision)
     values (tests.fx('injury', 'org'), tests.id('f_injury'), 'accept') $$,
  'an inspector accepts an AI finding');
select is((select status::text from public.finding where id = tests.id('f_injury')), 'accepted', 'accepted');
select is((select status::text from public.inspection where id = tests.fx('injury', 'inspection')), 'ready_for_signoff',
  'C25: an inspection with every finding decided is ready for sign-off');
select throws_like(
  $$ insert into public.finding_review (org_id, finding_id, decision)
     values (tests.fx('injury', 'org'), tests.id('f_injury'), 'reject') $$,
  '%only a draft AI finding%', 'a finding is reviewed once');

-- Reject.
select throws_like(
  $$ insert into public.finding_review (org_id, finding_id, decision)
     values (tests.fx('insulated', 'org'), tests.id('f_insulated'), 'reject') $$,
  '%violates check constraint%', 'a rejection needs a reason (A18)');
select lives_ok(
  $$ insert into public.finding_review (org_id, finding_id, decision, reason)
     values (tests.fx('insulated', 'org'), tests.id('f_insulated'), 'reject', 'Staining from a bird nest, not rust.') $$,
  'an inspector rejects with a reason');
select is((select status::text from public.finding where id = tests.id('f_insulated')), 'rejected', 'rejected');

-- Edit: a new inspector finding supersedes the AI one; the AI one is kept (A17).
reset role;
select tests.save_id('f_ivan', gen_random_uuid());
select tests.authenticate_as('ivan');
select lives_ok(
  $$ insert into public.finding (id, org_id, inspection_id, photo_id, origin, supersedes_finding_id, defect_type,
       standard_id, grade_value, rules_severity, severity, confidence, summary)
     values (tests.id('f_ivan'), tests.fx('pressure', 'org'), tests.fx('pressure', 'inspection'), tests.fx('pressure', 'photo'),
       'inspector', tests.id('f_pressure_rust'), 'pitting', tests.standard_id(), 3, 'S3', 'S3', 'high',
       'Pits are deeper than the model saw.') $$,
  'an inspector writes a revised finding');
select is((select status::text from public.finding where id = tests.id('f_ivan')), 'accepted',
  'inspector findings are accepted when written');
select throws_like(
  $$ insert into public.finding_review (org_id, finding_id, decision, reason)
     values (tests.fx('pressure', 'org'), tests.id('f_pressure_rust'), 'accept', null) $$,
  '%already has an inspector revision%', 'a revised finding is reviewed as an edit');
select lives_ok(
  $$ insert into public.finding_review (org_id, finding_id, decision, revised_finding_id, reason)
     values (tests.fx('pressure', 'org'), tests.id('f_pressure_rust'), 'edit', tests.id('f_ivan'), 'Pit depth underestimated.') $$,
  'the review links the AI finding to its revision');
select is((select status::text from public.finding where id = tests.id('f_pressure_rust')), 'superseded',
  'the AI finding is superseded, not overwritten');
select is((select severity::text from public.finding where id = tests.id('f_pressure_rust')), 'S2',
  'the AI''s original grade is kept as feedback (R9)');
select throws_like(
  $$ update public.finding_review set reason = 'changed' where finding_id = tests.id('f_pressure_rust') $$,
  '%permission denied%', 'reviews cannot be edited');

-- D3: an inspector may record S1 with low confidence.
select lives_ok(
  $$ insert into public.finding (org_id, inspection_id, photo_id, origin, defect_type, standard_id,
       grade_value, rules_severity, severity, confidence, summary)
     values (tests.fx('a', 'org'), tests.fx('a', 'inspection'), tests.fx('a', 'photo'), 'inspector', 'rusting',
       tests.standard_id(), 0, 'S1', 'S1', 'low', 'Light bloom only.') $$,
  'D3: rule 4 binds AI findings only; an inspector may record S1');
select throws_like(
  $$ insert into public.finding (org_id, inspection_id, photo_id, origin, defect_type, standard_id,
       grade_value, rules_severity, severity, confidence)
     values (tests.fx('a', 'org'), tests.fx('a', 'inspection'), tests.fx('a', 'photo'), 'inspector', 'rusting',
       tests.standard_id(), 1, 'S1', 'S2', 'high') $$,
  '%finding_inspector_severity_is_own%', 'an inspector''s severity is their own, with no rule adjustment');
reset role;

select set_eq(
  $$ select action::text from public.audit_event where entity_type = 'finding' and org_id = tests.org_of('alice') $$,
  array['finding_accepted', 'finding_rejected', 'finding_edited'],
  'D8: every review decision is audited (A40)');
select results_eq(
  $$ select details ->> 'ai_severity', details ->> 'revised_severity', actor_id from public.audit_event
      where action = 'finding_edited' and org_id = tests.org_of('alice') $$,
  $$ values ('S2', 'S3', tests.uid('ivan')) $$,
  'the edit audit records the AI and revised severities and who edited');

select tests.authenticate_as('vera');
select throws_like(
  $$ insert into public.finding_review (org_id, finding_id, decision) values (tests.fx('a', 'org'), tests.id('f_crack'), 'accept') $$,
  '%inspector or admin%', 'viewers cannot review findings');
reset role;

select * from finish();
rollback;
