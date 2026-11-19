-- Anode Phase 1 schema, part 6: findings, escalations, mechanisms, recommendations, reviews.
-- Domain model E15 to E20; constraints C11 to C25 (R1 to R9, D1 to D4, D7).

create table public.finding (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  inspection_id uuid not null,
  photo_id uuid not null,
  measurement_id uuid,
  origin public.finding_origin not null,
  supersedes_finding_id uuid,
  revision_reason text check (revision_reason is null or private.nonblank(revision_reason)),
  defect_type public.defect_type not null,
  standard_id uuid not null references public.standard (id) on delete restrict,
  grade_value smallint not null,
  rules_severity public.severity not null,
  severity public.severity not null,
  confidence public.confidence not null,
  severity_raised_reason text check (severity_raised_reason is null or private.nonblank(severity_raised_reason)),
  possible_staining boolean not null default false,
  summary text check (summary is null or private.nonblank(summary)),
  status public.finding_status not null default 'draft',
  grading_rules_version text check (grading_rules_version is null or private.nonblank(grading_rules_version)),
  explain_model text check (explain_model is null or private.nonblank(explain_model)),
  created_by uuid references public.profile (id) on delete restrict default auth.uid(),
  created_at timestamptz not null default now(),
  unique (org_id, id),
  unique (org_id, inspection_id, id),
  foreign key (org_id, inspection_id) references public.inspection (org_id, id) on delete restrict,
  -- C11: the photo belongs to the same inspection.
  foreign key (org_id, inspection_id, photo_id) references public.photo (org_id, inspection_id, id) on delete restrict,
  -- C12: the measurement belongs to the finding's photo.
  foreign key (org_id, photo_id, measurement_id) references public.measurement (org_id, photo_id, id) on delete restrict,
  -- C21: a superseded finding is in the same inspection.
  foreign key (org_id, inspection_id, supersedes_finding_id)
    references public.finding (org_id, inspection_id, id) on delete restrict,
  check (supersedes_finding_id is null or supersedes_finding_id <> id),
  -- C12
  constraint finding_ai_provenance check (origin <> 'ai' or (
    measurement_id is not null and grading_rules_version is not null and created_by is null
    and supersedes_finding_id is null and revision_reason is null)),
  -- C20
  constraint finding_inspector_author check (origin <> 'inspector' or created_by is not null),
  -- C15 and D1, D4: AI findings with low confidence go up exactly one step, capped at S4.
  -- Medium and high confidence keep the rules severity. So low confidence never gives S1.
  constraint finding_low_confidence_raises_severity check (origin <> 'ai' or severity = case
    when confidence = 'low' then private.severity_step_up(rules_severity)
    else rules_severity
  end),
  -- C15b and D3: an inspector's finding is their own judgement, with no rule adjustment.
  constraint finding_inspector_severity_is_own check (origin <> 'inspector' or severity = rules_severity),
  -- C15: a raise always says why.
  constraint finding_raise_has_reason check ((severity > rules_severity) = (severity_raised_reason is not null))
);
create index finding_inspection_status_idx on public.finding (inspection_id, status);
create index finding_severity_idx on public.finding (org_id, severity) where status in ('draft', 'accepted');
create unique index finding_superseded_once on public.finding (supersedes_finding_id)
  where supersedes_finding_id is not null;
create index finding_photo_idx on public.finding (photo_id);
create index finding_measurement_idx on public.finding (measurement_id);
create index finding_standard_idx on public.finding (standard_id);
create index finding_created_by_idx on public.finding (created_by);

-- Inspection status is derived from its findings (section 7, C25):
-- ready_for_signoff when it has findings and none is draft, otherwise draft.
-- A reported inspection is left alone unless p_force (used by void_report).
create function private.refresh_inspection_status(p_inspection uuid, p_force boolean default false)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  v_prev text;
  v_status public.inspection_status;
begin
  select case
    when exists (select 1 from public.finding f where f.inspection_id = p_inspection)
     and not exists (select 1 from public.finding f where f.inspection_id = p_inspection and f.status = 'draft')
    then 'ready_for_signoff'::public.inspection_status
    else 'draft'::public.inspection_status
  end into v_status;

  v_prev := private.enter_internal();
  update public.inspection i
     set status = v_status
   where i.id = p_inspection
     and i.status is distinct from v_status
     and (p_force or i.status <> 'reported');
  perform private.restore_internal(v_prev);
end
$$;

-- Adds an escalation unless the finding already has one for that reason.
create function private.add_escalation(
  p_finding public.finding,
  p_reason public.escalation_reason,
  p_source public.escalation_source,
  p_detail text
) returns void
language plpgsql security definer
set search_path = ''
as $$
begin
  insert into public.finding_escalation (org_id, finding_id, reason, source, detail)
  values (p_finding.org_id, p_finding.id, p_reason, p_source, p_detail)
  on conflict (finding_id, reason) do nothing;
end
$$;

-- SECURITY DEFINER: it locks the superseded row, which needs UPDATE rights users do not have.
create function private.finding_before_insert() returns trigger
language plpgsql security definer
set search_path = ''
as $$
declare
  s public.standard;
  target public.finding;
begin
  -- Status is never chosen by the writer (section 7).
  new.status := case new.origin when 'ai' then 'draft'::public.finding_status else 'accepted'::public.finding_status end;

  perform private.assert_photo_gradeable(new.photo_id);

  -- C13: the grade fits an active standard's scale.
  select * into s from public.standard where id = new.standard_id;
  if not s.is_active then
    raise exception 'standard % % is not active', s.code, s.edition using errcode = 'check_violation';
  end if;
  if new.grade_value not between s.grade_min and s.grade_max then
    raise exception 'grade % is outside % (% to %)', new.grade_value, s.code, s.grade_min, s.grade_max
      using errcode = 'check_violation';
  end if;

  if new.origin = 'inspector' then
    perform private.assert_member(new.org_id, new.created_by, true, 'the inspector');
  end if;

  -- C21 and C21a: what an inspector finding may supersede.
  if new.supersedes_finding_id is not null then
    select * into target from public.finding where id = new.supersedes_finding_id for update;
    if target.origin = 'ai' and target.status = 'draft' then
      null; -- an edit at review; the review records the reason (C22)
    elsif target.status = 'accepted' and exists (
      select 1 from public.report_inspection ri
        join public.report r on r.id = ri.report_id
       where ri.inspection_id = new.inspection_id and r.status = 'void'
    ) then
      if new.revision_reason is null then
        raise exception 'revising a finding after a void needs a reason' using errcode = 'check_violation';
      end if;
    else
      raise exception 'only a draft AI finding, or an accepted finding after its report was voided, can be superseded'
        using errcode = 'check_violation';
    end if;
  end if;
  return new;
end
$$;
create trigger finding_before_insert before insert on public.finding
  for each row execute function private.finding_before_insert();
create trigger finding_open before insert or update or delete on public.finding
  for each row execute function private.guard_inspection_open();

-- R5 / C16a / C16b / D2: escalations that follow from the finding and its asset
-- are added by the database itself, so no writer can forget them.
create function private.finding_after_insert() returns trigger
language plpgsql security definer
set search_path = ''
as $$
declare
  a public.asset;
  v_prev text;
begin
  select a2.* into a
    from public.inspection i
    join public.inspection_point p on p.id = i.point_id
    join public.asset a2 on a2.id = p.asset_id
   where i.id = new.inspection_id;

  if new.severity = 'S4' then
    perform private.add_escalation(new, 'severity_s4', 'grading_rules', 'Severity S4: stop and escalate now.');
  end if;
  if a.failure_could_injure then
    perform private.add_escalation(new, 'injury_risk', 'grading_rules', 'Failure of this asset could injure people.');
  end if;
  if a.is_insulated then
    perform private.add_escalation(new, 'suspected_cui', 'grading_rules', 'Insulated asset: corrosion under insulation suspected.');
  end if;
  if a.is_pressure_containing and new.defect_type = 'pitting' then
    perform private.add_escalation(new, 'pressure_pitting_or_wall_loss', 'grading_rules',
      'Pitting on pressure-containing equipment.');
  end if;
  if new.defect_type = 'suspected_cracking' then
    perform private.add_escalation(new, 'suspected_cracking', 'grading_rules', 'Cracking suspected.');
  end if;

  -- C21a: a revision after a void retires the finding it replaces.
  if new.supersedes_finding_id is not null and exists (
    select 1 from public.finding f where f.id = new.supersedes_finding_id and f.status = 'accepted'
  ) then
    v_prev := private.enter_internal();
    update public.finding set status = 'superseded' where id = new.supersedes_finding_id;
    perform private.restore_internal(v_prev);
    perform private.audit(new.org_id, 'finding_revised', 'finding', new.supersedes_finding_id,
      jsonb_build_object('revised_finding_id', new.id, 'reason', new.revision_reason,
                         'new_severity', new.severity, 'new_grade_value', new.grade_value),
      new.created_by);
  end if;

  perform private.refresh_inspection_status(new.inspection_id);
  return new;
end
$$;
create trigger finding_after_insert after insert on public.finding
  for each row execute function private.finding_after_insert();

-- C19: findings are never edited or deleted. Only status moves, only through
-- Anode's own functions, and only along the section 7 lifecycle.
create function private.finding_guard() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'findings are kept, not deleted' using errcode = 'check_violation';
  end if;
  if (to_jsonb(new) - 'status') <> (to_jsonb(old) - 'status') then
    raise exception 'a finding cannot be edited; an inspector edit creates a new finding (rule 9)'
      using errcode = 'check_violation';
  end if;
  if new.status <> old.status then
    if not private.is_internal() then
      raise exception 'finding status changes only through a review' using errcode = 'check_violation';
    end if;
    if not ((old.status = 'draft' and new.status in ('accepted', 'rejected', 'superseded'))
            or (old.status = 'accepted' and new.status = 'superseded')) then
      raise exception 'a finding cannot move from % to %', old.status, new.status using errcode = 'check_violation';
    end if;
  end if;
  return new;
end
$$;
create trigger finding_guard before update or delete on public.finding
  for each row execute function private.finding_guard();

-- C19 helper: child rows of a finding can be added only while the finding is
-- still open: an AI finding in draft, or an accepted inspector finding.
create function private.assert_finding_open_for_children(p_finding uuid) returns public.finding
language plpgsql stable
set search_path = ''
as $$
declare
  f public.finding;
begin
  select * into f from public.finding where id = p_finding;
  if not ((f.origin = 'ai' and f.status = 'draft') or (f.origin = 'inspector' and f.status = 'accepted')) then
    raise exception 'this finding is closed to changes' using errcode = 'check_violation';
  end if;
  return f;
end
$$;

-- Escalations (R5) ------------------------------------------------------------

create table public.finding_escalation (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  finding_id uuid not null,
  reason public.escalation_reason not null,
  source public.escalation_source not null,
  detail text check (detail is null or private.nonblank(detail)),
  acknowledged_by uuid references public.profile (id) on delete restrict,
  acknowledged_at timestamptz,
  acknowledgement_note text check (acknowledgement_note is null or private.nonblank(acknowledgement_note)),
  created_at timestamptz not null default now(),
  unique (org_id, id),
  unique (finding_id, reason),
  foreign key (org_id, finding_id) references public.finding (org_id, id) on delete restrict,
  -- C16: acknowledged completely or not at all.
  check ((acknowledged_by is null) = (acknowledged_at is null)
         and (acknowledged_at is null) = (acknowledgement_note is null))
);
create index finding_escalation_open_idx on public.finding_escalation (org_id) where acknowledged_at is null;
create index finding_escalation_ack_by_idx on public.finding_escalation (acknowledged_by);
create trigger finding_escalation_open before insert or update or delete on public.finding_escalation
  for each row execute function private.guard_inspection_open();

-- C16 and C16c: added, never removed; acknowledged once.
create function private.escalation_guard() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'escalations cannot be removed (rule 5)' using errcode = 'check_violation';
  end if;
  if tg_op = 'INSERT' then
    if new.acknowledged_at is not null then
      raise exception 'an escalation is acknowledged after it is raised' using errcode = 'check_violation';
    end if;
    return new;
  end if;
  if old.acknowledged_at is not null then
    raise exception 'this escalation is already acknowledged' using errcode = 'check_violation';
  end if;
  if new.acknowledged_at is null then
    raise exception 'an escalation can only be acknowledged' using errcode = 'check_violation';
  end if;
  if (to_jsonb(new) - array['acknowledged_by', 'acknowledged_at', 'acknowledgement_note'])
     <> (to_jsonb(old) - array['acknowledged_by', 'acknowledged_at', 'acknowledgement_note']) then
    raise exception 'only the acknowledgement of an escalation can be written' using errcode = 'check_violation';
  end if;
  perform private.assert_member(new.org_id, new.acknowledged_by, true, 'the person acknowledging');
  return new;
end
$$;
create trigger escalation_guard before insert or update or delete on public.finding_escalation
  for each row execute function private.escalation_guard();

create function private.escalation_after_ack() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  perform private.audit(new.org_id, 'escalation_acknowledged', 'finding_escalation', new.id,
    jsonb_build_object('finding_id', new.finding_id, 'reason', new.reason, 'note', new.acknowledgement_note),
    new.acknowledged_by);
  return new;
end
$$;
create trigger escalation_after_ack after update on public.finding_escalation
  for each row execute function private.escalation_after_ack();

-- Mechanism hypotheses (R7) -----------------------------------------------------

create table public.mechanism_hypothesis (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  finding_id uuid not null,
  rank smallint not null check (rank between 1 and 3),
  mechanism_code text not null references public.mechanism (code) on delete restrict,
  visual_evidence text not null check (private.nonblank(visual_evidence)),
  created_at timestamptz not null default now(),
  unique (org_id, id),
  unique (finding_id, rank),
  unique (finding_id, mechanism_code),
  foreign key (org_id, finding_id) references public.finding (org_id, id) on delete restrict
);
create index mechanism_hypothesis_mechanism_idx on public.mechanism_hypothesis (mechanism_code);
create trigger mechanism_hypothesis_open before insert or update or delete on public.mechanism_hypothesis
  for each row execute function private.guard_inspection_open();
create trigger mechanism_hypothesis_immutable before update or delete on public.mechanism_hypothesis
  for each row execute function private.immutable_row();

create function private.hypothesis_before_insert() returns trigger
language plpgsql
set search_path = ''
as $$
declare
  m public.mechanism;
begin
  perform private.assert_finding_open_for_children(new.finding_id);
  select * into m from public.mechanism where code = new.mechanism_code;
  if not m.is_active then
    raise exception 'mechanism % is not active', m.code using errcode = 'check_violation';
  end if;
  -- C17: a possibility-only mechanism (MIC) is never the leading hypothesis.
  if m.possibility_only and new.rank = 1 then
    raise exception '% can be listed only as a possibility, not ranked first', m.name using errcode = 'check_violation';
  end if;
  return new;
end
$$;
create trigger hypothesis_before_insert before insert on public.mechanism_hypothesis
  for each row execute function private.hypothesis_before_insert();

-- C16b: escalations that follow from a ranked mechanism.
create function private.hypothesis_after_insert() returns trigger
language plpgsql security definer
set search_path = ''
as $$
declare
  f public.finding;
  m public.mechanism;
  v_pressure boolean;
begin
  select * into f from public.finding where id = new.finding_id;
  select * into m from public.mechanism where code = new.mechanism_code;
  if m.escalation_reason is not null then
    perform private.add_escalation(f, m.escalation_reason, 'grading_rules', format('%s is a ranked mechanism.', m.name));
  end if;
  if m.code = 'pitting' then
    select a.is_pressure_containing into v_pressure
      from public.inspection i
      join public.inspection_point p on p.id = i.point_id
      join public.asset a on a.id = p.asset_id
     where i.id = f.inspection_id;
    if v_pressure then
      perform private.add_escalation(f, 'pressure_pitting_or_wall_loss', 'grading_rules',
        'Pitting is a ranked mechanism on pressure-containing equipment.');
    end if;
  end if;
  return new;
end
$$;
create trigger hypothesis_after_insert after insert on public.mechanism_hypothesis
  for each row execute function private.hypothesis_after_insert();

create table public.hypothesis_evidence (
  hypothesis_id uuid not null,
  context_answer_id uuid not null,
  org_id uuid not null,
  primary key (hypothesis_id, context_answer_id),
  foreign key (org_id, hypothesis_id) references public.mechanism_hypothesis (org_id, id) on delete restrict,
  foreign key (org_id, context_answer_id) references public.context_answer (org_id, id) on delete restrict
);
create index hypothesis_evidence_answer_idx on public.hypothesis_evidence (context_answer_id);
create trigger hypothesis_evidence_open before insert or update or delete on public.hypothesis_evidence
  for each row execute function private.guard_inspection_open();
create trigger hypothesis_evidence_immutable before update or delete on public.hypothesis_evidence
  for each row execute function private.immutable_row();

-- C18: the cited answer belongs to the same inspection as the finding.
create function private.evidence_before_insert() returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_finding uuid;
begin
  select h.finding_id into v_finding from public.mechanism_hypothesis h where h.id = new.hypothesis_id;
  perform private.assert_finding_open_for_children(v_finding);
  if not exists (
    select 1 from public.finding f
      join public.context_answer ca on ca.inspection_id = f.inspection_id
     where f.id = v_finding and ca.id = new.context_answer_id
  ) then
    raise exception 'evidence must be an answer from the same inspection' using errcode = 'check_violation';
  end if;
  return new;
end
$$;
create trigger evidence_before_insert before insert on public.hypothesis_evidence
  for each row execute function private.evidence_before_insert();

-- Recommendations (R8) ----------------------------------------------------------

create table public.finding_recommendation (
  finding_id uuid not null,
  recommendation_code text not null,
  recommendation_version integer not null,
  sort_order smallint not null check (sort_order >= 1),
  org_id uuid not null,
  primary key (finding_id, recommendation_code),
  unique (finding_id, sort_order),
  foreign key (org_id, finding_id) references public.finding (org_id, id) on delete restrict,
  foreign key (recommendation_code, recommendation_version)
    references public.recommendation (code, version) on delete restrict
);
create index finding_recommendation_code_idx on public.finding_recommendation (recommendation_code, recommendation_version);
create trigger finding_recommendation_open before insert or update or delete on public.finding_recommendation
  for each row execute function private.guard_inspection_open();
create trigger finding_recommendation_immutable before update or delete on public.finding_recommendation
  for each row execute function private.immutable_row();

-- C24: only the current version of an active library entry, and not below its severity floor.
create function private.recommendation_before_insert() returns trigger
language plpgsql
set search_path = ''
as $$
declare
  f public.finding;
  rec public.recommendation;
begin
  f := private.assert_finding_open_for_children(new.finding_id);
  select * into rec from public.recommendation
   where code = new.recommendation_code and version = new.recommendation_version;
  if not rec.is_active then
    raise exception 'recommendation % version % is not the current library entry', rec.code, rec.version
      using errcode = 'check_violation';
  end if;
  if rec.min_severity is not null and f.severity < rec.min_severity then
    raise exception 'recommendation % applies from % upwards', rec.code, rec.min_severity
      using errcode = 'check_violation';
  end if;
  return new;
end
$$;
create trigger recommendation_before_insert before insert on public.finding_recommendation
  for each row execute function private.recommendation_before_insert();

-- Reviews (R9) ---------------------------------------------------------------------

create table public.finding_review (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  finding_id uuid not null unique,
  decision public.review_decision not null,
  revised_finding_id uuid,
  reason text check (reason is null or private.nonblank(reason)),
  reviewed_by uuid not null references public.profile (id) on delete restrict default auth.uid(),
  reviewed_at timestamptz not null default now(),
  unique (org_id, id),
  foreign key (org_id, finding_id) references public.finding (org_id, id) on delete restrict,
  foreign key (org_id, revised_finding_id) references public.finding (org_id, id) on delete restrict,
  -- C22
  check ((decision = 'edit') = (revised_finding_id is not null)),
  check (decision = 'accept' or reason is not null)
);
create index finding_review_feedback_idx on public.finding_review (org_id, reviewed_at desc);
create index finding_review_revised_idx on public.finding_review (revised_finding_id);
create index finding_review_reviewer_idx on public.finding_review (reviewed_by);
create trigger finding_review_open before insert or update or delete on public.finding_review
  for each row execute function private.guard_inspection_open();
-- C23
create trigger finding_review_immutable before update or delete on public.finding_review
  for each row execute function private.immutable_row();

-- SECURITY DEFINER: it locks the reviewed finding, which needs UPDATE rights users do not have.
create function private.review_before_insert() returns trigger
language plpgsql security definer
set search_path = ''
as $$
declare
  f public.finding;
  revised public.finding;
begin
  select * into f from public.finding where id = new.finding_id for update;
  if f.origin <> 'ai' or f.status <> 'draft' then
    raise exception 'only a draft AI finding can be reviewed' using errcode = 'check_violation';
  end if;
  perform private.assert_member(new.org_id, new.reviewed_by, true, 'the reviewer');
  new.reviewed_at := now();
  if new.decision = 'edit' then
    select * into revised from public.finding where id = new.revised_finding_id;
    if revised.origin <> 'inspector' or revised.supersedes_finding_id is distinct from f.id then
      raise exception 'an edit must point at the inspector finding that supersedes this one'
        using errcode = 'check_violation';
    end if;
  elsif exists (select 1 from public.finding r where r.supersedes_finding_id = f.id) then
    raise exception 'this finding already has an inspector revision; review it as an edit'
      using errcode = 'check_violation';
  end if;
  return new;
end
$$;
create trigger review_before_insert before insert on public.finding_review
  for each row execute function private.review_before_insert();

create function private.review_after_insert() returns trigger
language plpgsql security definer
set search_path = ''
as $$
declare
  f public.finding;
  revised public.finding;
  v_prev text;
begin
  select * into f from public.finding where id = new.finding_id;
  v_prev := private.enter_internal();
  update public.finding
     set status = case new.decision
       when 'accept' then 'accepted'::public.finding_status
       when 'reject' then 'rejected'::public.finding_status
       else 'superseded'::public.finding_status
     end
   where id = new.finding_id;
  perform private.restore_internal(v_prev);

  if new.decision = 'edit' then
    select * into revised from public.finding where id = new.revised_finding_id;
  end if;

  perform private.audit(
    new.org_id,
    case new.decision
      when 'accept' then 'finding_accepted'::public.audit_action
      when 'reject' then 'finding_rejected'::public.audit_action
      else 'finding_edited'::public.audit_action
    end,
    'finding', new.finding_id,
    jsonb_strip_nulls(jsonb_build_object(
      'review_id', new.id,
      'reason', new.reason,
      'ai_grade_value', f.grade_value,
      'ai_severity', f.severity,
      'ai_confidence', f.confidence,
      'revised_finding_id', new.revised_finding_id,
      'revised_grade_value', revised.grade_value,
      'revised_severity', revised.severity
    )),
    new.reviewed_by
  );

  perform private.refresh_inspection_status(f.inspection_id);
  return new;
end
$$;
create trigger review_after_insert after insert on public.finding_review
  for each row execute function private.review_after_insert();
