-- Phase 1 recommendation library and context questions: FIRST DRAFT for Michael to correct (D5).
-- Wording changes later are new versions of a recommendation (A15), never edits of a used one.

-- Recommendation library (R8). min_severity: the lowest severity it is offered at (C24).
insert into public.recommendation (code, version, text, min_severity) values
  ('monitor_normal_interval', 1, 'Monitor this point at the normal inspection interval.', null),
  ('reinspect_sooner', 1, 'Re-inspect this point sooner than the normal interval.', 'S2'),
  ('spot_repair_coating', 1, 'Spot-repair the coating: clean the rusted area to bare metal, prime and recoat.', 'S2'),
  ('plan_coating_maintenance', 1, 'Plan coating maintenance for this area: surface preparation and a full recoat.', 'S2'),
  ('ut_thickness_grid', 1, 'Measure wall thickness with an ultrasonic (UT) grid at this point before the next interval.', 'S3'),
  ('pit_depth_measurement', 1, 'Measure the deepest pits with a pit gauge or depth micrometer.', 'S3'),
  ('crack_ndt', 1, 'Check for cracking with dye-penetrant or magnetic-particle testing.', null),
  ('remove_insulation_inspect', 1, 'Remove the insulation at this point and inspect the steel underneath.', null),
  ('check_dissimilar_metal_contact', 1, 'Check for contact with a different metal and isolate the joint.', null),
  ('seal_crevice', 1, 'Clean and seal the joint or crevice so water cannot collect in it.', null),
  ('improve_drainage', 1, 'Remove standing water and improve drainage at this point.', null),
  ('sample_deposits', 1, 'Sample the deposits for microbiological testing before cleaning them off.', null),
  ('confirm_not_staining', 1, 'Confirm whether the discolouration is rust or staining (wipe and scrape test) before acting.', null),
  ('refer_qualified_inspector', 1, 'Stop and refer this finding to a qualified inspector now.', 'S4');

-- Context questions asked at capture time; answers are cited as evidence for mechanisms (R7).
insert into public.context_question (key, prompt, answer_type, options, sort_order) values
  ('exposure', 'How exposed is the surface?', 'single_choice',
   '["Sheltered or indoors", "Open to weather", "Splash or spray zone", "Immersed or buried"]', 10),
  ('coating_condition', 'What does the coating look like around the rust?', 'single_choice',
   '["Intact", "Blistered", "Cracked or flaking", "Missing"]', 20),
  ('standing_water', 'Is there standing water or ponding on or next to the surface?', 'boolean', null, 30),
  ('crevice_present', 'Is the rust at a joint, lap, flange, or under a gasket, washer or bolt head?', 'boolean', null, 40),
  ('dissimilar_metal_contact', 'Is the steel touching a different metal (fittings, bolts, supports, copper or stainless parts)?', 'boolean', null, 50),
  ('deposits_present', 'Are there slimy, black or nodular deposits on the surface?', 'boolean', null, 60),
  ('possible_staining_source', 'Could the marks be staining from something above (run-off, chemicals, bird droppings)?', 'boolean', null, 70),
  ('years_since_coating', 'About how many years since this surface was last coated? Skip if unknown.', 'number', null, 80);
