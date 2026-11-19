-- Photos, the gradeable-photo check (R1, C9 to C11, D6) and measurements (R6, C19).
begin;
\ir _helpers.psql
select no_plan();

select tests.setup_people();
select tests.save('a', tests.make_fixture('alice'));

-- A second inspection with no photo yet, for the photo tests.
select tests.save_id('insp', gen_random_uuid());
insert into public.inspection (id, org_id, point_id, inspector_id)
values (tests.id('insp'), tests.org_of('alice'), tests.fx('a', 'point'), tests.uid('alice'));

create function tests.photo_sql(p_id text, p_extra_cols text, p_extra_vals text) returns text
language sql immutable as $$
  select format(
    'insert into public.photo (id, org_id, inspection_id, storage_path, content_sha256, mime_type, width_px, height_px, uploaded_by%s)
     values (%L, tests.org_of(''alice''), tests.id(''insp''), tests.org_of(''alice'') || ''/'' || tests.id(''insp'') || ''/'' || %L || ''.jpg'',
             repeat(''e'', 64), ''image/jpeg'', 100, 100, tests.uid(''alice'')%s)',
    p_extra_cols, p_id, p_id, p_extra_vals)
$$;

-- R1 / C9, C9a, C10 -----------------------------------------------------------------

select lives_ok(tests.photo_sql('10000000-0000-4000-8000-000000000001', '', ''),
  'a photo starts pending');
select is((select gradeability::text from public.photo where id = '10000000-0000-4000-8000-000000000001'), 'pending',
  'gradeability defaults to pending');

select throws_like(
  tests.photo_sql('10000000-0000-4000-8000-000000000002', ', gradeability, scale_reference, mm_per_px, checked_at',
    ', ''gradeable'', ''none'', 0.1, now()'),
  '%violates check constraint%', 'R1: no scale reference, no grade');
select throws_like(
  tests.photo_sql('10000000-0000-4000-8000-000000000003', ', gradeability, scale_reference, checked_at',
    ', ''gradeable'', ''ruler'', now()'),
  '%violates check constraint%', 'R1: a gradeable photo has a measured scale (mm per pixel)');
select throws_like(
  tests.photo_sql('10000000-0000-4000-8000-000000000004', ', gradeability, checked_at', ', ''rejected'', now()'),
  '%violates check constraint%', 'C10: a rejected photo says why');
select throws_like(
  tests.photo_sql('10000000-0000-4000-8000-000000000005', ', gradeability, rejection_reasons, scale_reference, checked_at',
    ', ''rejected'', ''{out_of_focus}'', ''none'', now()'),
  '%violates check constraint%', 'C10: a checked photo with no scale reference lists no_scale_reference');
select lives_ok(
  tests.photo_sql('10000000-0000-4000-8000-000000000006', ', gradeability, rejection_reasons, scale_reference, checked_at',
    ', ''rejected'', ''{out_of_focus,no_scale_reference}'', ''none'', now()'),
  'a blurry, unscaled photo is rejected with reasons');
select throws_like(
  tests.photo_sql('10000000-0000-4000-8000-000000000007', ', gradeability, scale_reference, mm_per_px, colour_corrected, checked_at',
    ', ''gradeable'', ''ruler'', 0.1, true, now()'),
  '%violates check constraint%', 'C9a: colour correction needs the Anode scale card');
select lives_ok(
  tests.photo_sql('10000000-0000-4000-8000-000000000008', ', gradeability, scale_reference, mm_per_px, colour_corrected, checked_at',
    ', ''gradeable'', ''anode_scale_card'', 0.1, true, now()'),
  'D6: a scale-card photo can be gradeable and colour corrected');
select throws_like(
  tests.photo_sql('10000000-0000-4000-8000-000000000009', ', gradeability, scale_reference, mm_per_px, checked_at',
    ', ''gradeable'', ''tape_measure'', 0.1, now()'),
  '%photo_one_gradeable%', 'C10a: one gradeable photo per inspection');
select throws_like($$ select 'coin'::public.scale_reference $$, '%invalid input value%',
  'D6: coins are not an accepted scale reference');

select throws_like(
  $$ insert into public.photo (org_id, inspection_id, storage_path, content_sha256, mime_type, width_px, height_px, uploaded_by)
     values (tests.org_of('alice'), tests.id('insp'), 'somewhere/else.jpg', repeat('e', 64), 'image/jpeg', 1, 1, tests.uid('alice')) $$,
  '%violates check constraint%', 'the storage path must be {org}/{inspection}/{photo}.{ext}');
select throws_like(
  $$ insert into public.photo (org_id, inspection_id, storage_path, content_sha256, mime_type, width_px, height_px, uploaded_by)
     values (tests.org_of('alice'), tests.id('insp'), 'x', repeat('e', 64), 'image/jpeg', 1, 1, tests.uid('bruno')) $$,
  '%the uploader must be a member%', 'C3: the uploader must belong to the organisation');

-- C10b: decided once -----------------------------------------------------------------

select lives_ok(
  $$ update public.photo set gradeability = 'rejected', rejection_reasons = '{glare,no_scale_reference}', checked_at = now()
      where id = '10000000-0000-4000-8000-000000000001' $$,
  'the server records a pending photo''s check result');
select throws_like(
  $$ update public.photo set gradeability = 'pending', rejection_reasons = '{}', checked_at = null
      where id = '10000000-0000-4000-8000-000000000001' $$,
  '%decided once%', 'C10b: a decided photo is never re-decided; retakes are new photos');
select throws_like(
  $$ update public.photo set width_px = 5 where id = '10000000-0000-4000-8000-000000000008' $$,
  '%decided once%', 'photos are never edited');
select throws_like(
  $$ delete from public.photo where id = '10000000-0000-4000-8000-000000000006' $$,
  '%kept, not deleted%', 'A6: rejected photos are kept');

-- A8: clients cannot write the check result ------------------------------------------

select tests.authenticate_as('ivan');
select throws_like(
  $$ insert into public.photo (org_id, inspection_id, storage_path, content_sha256, mime_type, width_px, height_px, gradeability)
     values (tests.org_of('alice'), tests.id('insp'), 'x', repeat('e', 64), 'image/jpeg', 1, 1, 'gradeable') $$,
  '%permission denied%', 'A8: a client cannot mark its own photo gradeable');
select lives_ok(
  $$ insert into public.photo (id, org_id, inspection_id, storage_path, content_sha256, mime_type, width_px, height_px)
     values ('10000000-0000-4000-8000-00000000000a', tests.org_of('alice'), tests.id('insp'),
       tests.org_of('alice') || '/' || tests.id('insp') || '/10000000-0000-4000-8000-00000000000a.png',
       repeat('f', 64), 'image/png', 10, 10) $$,
  'a client uploads a pending photo with a client-made id (A4)');
select is((select uploaded_by from public.photo where id = '10000000-0000-4000-8000-00000000000a'), tests.uid('ivan'),
  'uploaded_by is the signed-in user');
select throws_like(
  $$ update public.photo set gradeability = 'rejected' where id = '10000000-0000-4000-8000-00000000000a' $$,
  '%permission denied%', 'a client cannot update photos');
select throws_like(
  $$ insert into public.measurement (org_id, photo_id, model_name, model_version, percent_area_rusted, outline, model_confidence)
     values (tests.org_of('alice'), tests.fx('a', 'photo'), 'm', '2', 1, '{"type": "MultiPolygon", "coordinates": []}', 0.5) $$,
  '%permission denied%', 'clients cannot write measurements; the server does');
reset role;

-- Measurements (C11, C19) --------------------------------------------------------------

select throws_like(
  $$ insert into public.measurement (org_id, photo_id, model_name, model_version, percent_area_rusted, outline, model_confidence)
     values (tests.org_of('alice'), '10000000-0000-4000-8000-000000000006', 'm', '1', 1,
       '{"type": "MultiPolygon", "coordinates": []}', 0.5) $$,
  '%only a gradeable photo%', 'C11: a rejected photo is never measured');
select throws_like(
  $$ insert into public.measurement (org_id, photo_id, model_name, model_version, percent_area_rusted, outline, model_confidence)
     values (tests.org_of('alice'), '10000000-0000-4000-8000-000000000008', 'm', '1', 101,
       '{"type": "MultiPolygon", "coordinates": []}', 0.5) $$,
  '%violates check constraint%', 'percent area is 0 to 100');
select throws_like(
  $$ insert into public.measurement (org_id, photo_id, model_name, model_version, percent_area_rusted, outline, model_confidence)
     values (tests.org_of('alice'), '10000000-0000-4000-8000-000000000008', 'm', '1', 1, '{"type": "Polygon"}', 0.5) $$,
  '%violates check constraint%', 'the outline is a GeoJSON MultiPolygon (A12)');
select throws_like(
  $$ insert into public.measurement (org_id, photo_id, model_name, model_version, percent_area_rusted, outline, model_confidence)
     values (tests.org_of('alice'), '10000000-0000-4000-8000-000000000008', 'm', '1', 1,
       '{"type": "MultiPolygon", "coordinates": []}', 1.5) $$,
  '%violates check constraint%', 'model confidence is 0 to 1');
select throws_like(
  $$ update public.measurement set percent_area_rusted = 50 where id = tests.fx('a', 'measurement') $$,
  '%cannot be changed%', 'C19: measurements are immutable, even for the database owner');
select throws_like(
  $$ delete from public.measurement where id = tests.fx('a', 'measurement') $$,
  '%cannot be changed%', 'C19: measurements are never deleted');

-- Context answers (C8) ----------------------------------------------------------------

insert into public.context_question (key, prompt, answer_type, options) values
  ('t_bool', 'Wet?', 'boolean', null),
  ('t_choice', 'Exposure?', 'single_choice', '["open", "sheltered"]');
select throws_like(
  $$ insert into public.context_question (key, prompt, answer_type, options) values ('t_bad', 'Q', 'single_choice', null) $$,
  '%violates check constraint%', 'C8: a single-choice question lists its options');
select lives_ok(
  $$ insert into public.context_answer (org_id, inspection_id, question_key, value)
     values (tests.org_of('alice'), tests.id('insp'), 't_bool', 'true') $$,
  'a boolean answer is accepted');
select throws_like(
  $$ insert into public.context_answer (org_id, inspection_id, question_key, value)
     values (tests.org_of('alice'), tests.id('insp'), 't_choice', '"underwater"') $$,
  '%does not match%', 'C8: a single-choice answer is one of the options');
select throws_like(
  $$ insert into public.context_answer (org_id, inspection_id, question_key, value)
     values (tests.org_of('alice'), tests.fx('a', 'inspection'), 't_bool', '"yes"') $$,
  '%does not match%', 'C8: a boolean answer is a boolean');

-- Inspections (C3, C7, section 7) ------------------------------------------------------

select throws_like(
  $$ insert into public.inspection (org_id, point_id, inspector_id, inspected_at)
     values (tests.org_of('alice'), tests.fx('a', 'point'), tests.uid('alice'), now() + interval '1 day') $$,
  '%future%', 'C7: inspected_at is not in the future');
select throws_like(
  $$ insert into public.inspection (org_id, point_id, inspector_id)
     values (tests.org_of('alice'), tests.fx('a', 'point'), tests.uid('bruno')) $$,
  '%must be a member%', 'C3: the inspector belongs to the organisation');
select throws_like(
  $$ update public.inspection set status = 'ready_for_signoff' where id = tests.id('insp') $$,
  '%set by Anode%', 'inspection status is derived, never set directly');
select throws_like(
  $$ insert into public.inspection_point (org_id, asset_id, label)
     values (tests.org_of('alice'), tests.fx('a', 'asset'), 'POINT 1') $$,
  '%inspection_point_label_unique%', 'C5: point labels are unique per asset, ignoring case');
select throws_like(
  $$ insert into public.inspection_point (org_id, asset_id, label)
     values (tests.org_of('bruno'), tests.fx('a', 'asset'), 'Cross-tenant point') $$,
  '%foreign key%', 'C1: a point cannot hang off another organisation''s asset');
select throws_like(
  $$ insert into public.asset (org_id, name, asset_type, material, coating_status, environment,
       is_pressure_containing, failure_could_injure)
     values (tests.org_of('alice'), 'Unanswered', 'pipe', 'carbon_steel', 'coated', 'indoor', false, false) $$,
  '%null value in column "is_insulated"%', 'A10: the escalation flags must be answered');
select throws_like(
  $$ insert into public.asset (org_id, name, asset_type, material, coating_status, environment,
       is_insulated, is_pressure_containing, failure_could_injure, latitude)
     values (tests.org_of('alice'), 'Half located', 'pipe', 'carbon_steel', 'coated', 'indoor', false, false, false, 4.8) $$,
  '%violates check constraint%', 'C6: latitude and longitude come together');

select * from finish();
rollback;
