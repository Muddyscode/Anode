-- Development and demo seed data. Loaded after the migrations by `supabase db reset`
-- (and by scripts/db-test.sh). Never run against production.
--
-- Recommendation and context-question rows here are DEV FIXTURES (codes start
-- with dev_). The real Phase 1 library is drafted in Stage 5 (decision D5).

-- People. Sign-up triggers create each person's profile and personal organisation.
insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data, email_confirmed_at) values
  ('00000000-0000-4000-a000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'demo.admin@anode.test', '{"display_name": "Demo Admin", "organisation_name": "Anode Demo"}', now()),
  ('00000000-0000-4000-a000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'demo.inspector@anode.test', '{"display_name": "Demo Inspector"}', now()),
  ('00000000-0000-4000-a000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'demo.viewer@anode.test', '{"display_name": "Demo Viewer"}', now()),
  ('00000000-0000-4000-a000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'other.admin@anode.test', '{"display_name": "Other Admin", "organisation_name": "Other Fabrication Ltd"}', now());

update public.profile set qualification = 'Coating inspector (demo)' where id = '00000000-0000-4000-a000-000000000002';

-- The demo organisation (A25) gets an inspector and a viewer.
update public.organisation o set is_demo = true
  from public.membership m
 where m.org_id = o.id and m.user_id = '00000000-0000-4000-a000-000000000001';

insert into public.membership (org_id, user_id, role)
select m.org_id, x.user_id, x.role
  from public.membership m
 cross join (values
   ('00000000-0000-4000-a000-000000000002'::uuid, 'inspector'::public.member_role),
   ('00000000-0000-4000-a000-000000000003'::uuid, 'viewer'::public.member_role)) as x (user_id, role)
 where m.user_id = '00000000-0000-4000-a000-000000000001' and m.role = 'admin';

-- Dev fixtures for the Stage 5 libraries.
insert into public.recommendation (code, version, text, min_severity) values
  ('dev_monitor', 1, 'DEV FIXTURE: monitor at the normal interval.', null),
  ('dev_ut_grid', 1, 'DEV FIXTURE: UT thickness grid at this point.', 'S2');

insert into public.context_question (key, prompt, answer_type, options, sort_order) values
  ('dev_standing_water', 'DEV FIXTURE: Is there standing water on or near the surface?', 'boolean', null, 1),
  ('dev_exposure', 'DEV FIXTURE: How exposed is the surface?', 'single_choice', '["sheltered", "open", "splash zone"]', 2);

-- A complete, signed inspection in the demo organisation -------------------------

do $$
declare
  v_admin uuid := '00000000-0000-4000-a000-000000000001';
  v_insp uuid := '00000000-0000-4000-a000-000000000002';
  v_org uuid;
  v_asset uuid := '00000000-0000-4000-b000-000000000001';
  v_point uuid := '00000000-0000-4000-b000-000000000002';
  v_inspection uuid := '00000000-0000-4000-b000-000000000003';
  v_photo uuid := '00000000-0000-4000-b000-000000000004';
  v_measurement uuid := '00000000-0000-4000-b000-000000000005';
  v_finding uuid := '00000000-0000-4000-b000-000000000006';
  v_hypothesis uuid := '00000000-0000-4000-b000-000000000007';
  v_report uuid := '00000000-0000-4000-b000-000000000008';
  v_answer uuid := '00000000-0000-4000-b000-000000000009';
  v_standard uuid;
begin
  select org_id into v_org from public.membership where user_id = v_admin and role = 'admin';
  select id into v_standard from public.standard where code = 'ISO 4628-3' and edition = '2016';

  insert into public.asset (id, org_id, name, asset_type, material, coating_status, coating_description,
    environment, is_insulated, is_pressure_containing, failure_could_injure, location_text, created_by)
  values (v_asset, v_org, 'Elevated water tank T2', 'tank', 'carbon_steel', 'coated',
    'Epoxy primer with polyurethane topcoat', 'atmospheric_marine', false, false, true,
    'Demo yard, north side', v_admin);

  insert into public.inspection_point (id, org_id, asset_id, label, description, created_by)
  values (v_point, v_org, v_asset, 'Shell, east face, 2 m above base', 'Below the overflow outlet', v_admin);

  insert into public.inspection (id, org_id, point_id, inspector_id, inspected_at, notes)
  values (v_inspection, v_org, v_point, v_insp, now() - interval '2 days', 'Routine visual inspection.');

  insert into public.context_answer (id, org_id, inspection_id, question_key, value)
  values (v_answer, v_org, v_inspection, 'dev_standing_water', 'true');

  insert into public.photo (id, org_id, inspection_id, storage_path, content_sha256, mime_type, width_px, height_px,
    captured_at, gradeability, scale_reference, mm_per_px, colour_corrected, checked_at, uploaded_by)
  values (v_photo, v_org, v_inspection, v_org || '/' || v_inspection || '/' || v_photo || '.jpg',
    repeat('a', 64), 'image/jpeg', 4032, 3024, now() - interval '2 days',
    'gradeable', 'anode_scale_card', 0.085, true, now() - interval '2 days', v_insp);

  insert into public.measurement (id, org_id, photo_id, model_name, model_version, percent_area_rusted, outline, model_confidence)
  values (v_measurement, v_org, v_photo, 'anode-seg', 'dev-0', 0.8,
    '{"type": "MultiPolygon", "coordinates": [[[[100, 100], [180, 100], [180, 160], [100, 160], [100, 100]]]]}', 0.42);

  -- Low confidence raises the rules severity one step (D1).
  insert into public.finding (id, org_id, inspection_id, photo_id, measurement_id, origin, defect_type, standard_id,
    grade_value, rules_severity, severity, confidence, severity_raised_reason, summary, grading_rules_version, explain_model)
  values (v_finding, v_org, v_inspection, v_photo, v_measurement, 'ai', 'rusting', v_standard,
    2, 'S2', 'S3', 'low', 'Model confidence is low, so severity was raised one step (rule 4).',
    'Scattered rust breakthrough below the overflow outlet.', 'dev-0', 'dev-fixture');

  insert into public.mechanism_hypothesis (id, org_id, finding_id, rank, mechanism_code, visual_evidence) values
    (v_hypothesis, v_org, v_finding, 1, 'coating_breakdown_underfilm', 'Blistered topcoat with rust bleeding at the edges.');
  insert into public.mechanism_hypothesis (org_id, finding_id, rank, mechanism_code, visual_evidence) values
    (v_org, v_finding, 2, 'crevice', 'Rust concentrated at the outlet flange joint.');
  insert into public.hypothesis_evidence (hypothesis_id, context_answer_id, org_id) values (v_hypothesis, v_answer, v_org);

  insert into public.finding_recommendation (finding_id, recommendation_code, recommendation_version, sort_order, org_id)
  values (v_finding, 'dev_ut_grid', 1, 1, v_org);

  -- Injury-risk asset: the database raised an injury_risk escalation (D2). Acknowledge it.
  update public.finding_escalation
     set acknowledged_by = v_insp, acknowledged_at = now(), acknowledgement_note = 'Seen; access below the tank restricted.'
   where finding_id = v_finding;

  insert into public.finding_review (org_id, finding_id, decision, reviewed_by) values (v_org, v_finding, 'accept', v_insp);

  insert into public.report (id, org_id, title, created_by) values (v_report, v_org, 'Tank T2 visual inspection', v_insp);
  insert into public.report_inspection (report_id, inspection_id, org_id) values (v_report, v_inspection, v_org);
  insert into storage.objects (bucket_id, name, metadata)
  values ('reports', v_org || '/' || v_report || '.pdf', '{"mimetype": "application/pdf"}');
  perform public.sign_report(v_report, v_insp, v_org || '/' || v_report || '.pdf', repeat('b', 64), 'screening-v1');
end
$$;

-- A draft inspection in the other organisation, for isolation checks -------------

do $$
declare
  v_admin uuid := '00000000-0000-4000-a000-000000000004';
  v_org uuid;
  v_asset uuid := '00000000-0000-4000-c000-000000000001';
  v_point uuid := '00000000-0000-4000-c000-000000000002';
begin
  select org_id into v_org from public.membership where user_id = v_admin and role = 'admin';
  insert into public.asset (id, org_id, name, asset_type, material, coating_status, environment,
    is_insulated, is_pressure_containing, failure_could_injure, created_by)
  values (v_asset, v_org, 'Workshop gantry beam', 'beam', 'carbon_steel', 'coated', 'indoor', false, false, false, v_admin);
  insert into public.inspection_point (id, org_id, asset_id, label, created_by)
  values (v_point, v_org, v_asset, 'Mid-span, underside', v_admin);
  insert into public.inspection (org_id, point_id, inspector_id) values (v_org, v_point, v_admin);
end
$$;
