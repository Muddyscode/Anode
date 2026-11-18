-- Anode Phase 1 schema, part 3: global reference data (read-only to users).
-- Domain model E4 to E8, C2, C8. The recommendation library and the context
-- questions are drafted in Stage 5 (D5); this migration creates their tables only.

create table public.standard (
  id uuid primary key default gen_random_uuid(),
  code text not null check (private.nonblank(code)),
  edition text not null check (private.nonblank(edition)),
  title text not null check (private.nonblank(title)),
  grade_scale public.grade_scale not null,
  grade_min smallint not null,
  grade_max smallint not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (code, edition),
  check (grade_min <= grade_max)
);

create table public.severity_level (
  code public.severity primary key,
  name text not null check (private.nonblank(name)),
  action text not null check (private.nonblank(action)),
  requires_escalation boolean not null
);

create table public.mechanism (
  code text primary key check (code ~ '^[a-z][a-z0-9_]*$'),
  name text not null check (private.nonblank(name)),
  possibility_only boolean not null default false,
  escalation_reason public.escalation_reason,
  is_active boolean not null default true
);

-- Each wording change is a new version; old versions are kept so old reports
-- reprint identically (A15). At most one active version per code.
create table public.recommendation (
  code text not null check (code ~ '^[a-z][a-z0-9_]*$'),
  version integer not null check (version >= 1),
  text text not null check (private.nonblank(text)),
  min_severity public.severity,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  primary key (code, version)
);
create unique index recommendation_one_active_version on public.recommendation (code) where is_active;

create table public.context_question (
  key text primary key check (key ~ '^[a-z][a-z0-9_]*$'),
  prompt text not null check (private.nonblank(prompt)),
  answer_type public.answer_type not null,
  options jsonb,
  sort_order integer not null default 0,
  is_active boolean not null default true,
  -- C8: single-choice questions list their options; others have none.
  check (
    (answer_type = 'single_choice'
      and options is not null
      and jsonb_typeof(options) = 'array'
      and jsonb_array_length(options) > 0)
    or (answer_type <> 'single_choice' and options is null)
  )
);

-- Seeded reference rows ------------------------------------------------------------

insert into public.standard (code, edition, title, grade_scale, grade_min, grade_max) values
  ('ISO 4628-3', '2016',
   'Paints and varnishes. Evaluation of degradation of coatings. Part 3: Assessment of degree of rusting',
   'iso_4628_3_ri', 0, 5);

-- Business rule R3 wording.
insert into public.severity_level (code, name, action, requires_escalation) values
  ('S1', 'Cosmetic', 'Monitor at the normal interval.', false),
  ('S2', 'Developing', 'Plan maintenance; re-inspect sooner.', false),
  ('S3', 'Significant', 'Schedule repair; measure thickness (UT) before the next interval.', false),
  ('S4', 'Critical', 'Stop and escalate to a qualified inspector now.', true);

-- PRD "Mechanisms the Copilot names (first release)".
insert into public.mechanism (code, name, possibility_only, escalation_reason) values
  ('uniform', 'Uniform corrosion', false, null),
  ('pitting', 'Pitting corrosion', false, null),
  ('galvanic', 'Galvanic corrosion', false, null),
  ('crevice', 'Crevice corrosion', false, null),
  ('cui', 'Corrosion under insulation (CUI)', false, 'suspected_cui'),
  ('coating_breakdown_underfilm', 'Coating breakdown with underfilm rust', false, null),
  ('mic', 'Microbiologically influenced corrosion (possible)', true, null);
