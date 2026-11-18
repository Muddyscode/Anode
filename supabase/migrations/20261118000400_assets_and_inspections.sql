-- Anode Phase 1 schema, part 4: asset register, inspections, photos, measurements.
-- Domain model E9 to E14; constraints C1, C3 to C11a, C30 (inspection lock).

-- Asset register ---------------------------------------------------------------

create table public.asset (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organisation (id) on delete restrict,
  name text not null check (private.nonblank(name) and char_length(name) <= 120),
  asset_type public.asset_type not null,
  material public.material not null,
  coating_status public.coating_status not null,
  coating_description text check (coating_description is null or private.nonblank(coating_description)),
  environment public.environment not null,
  -- R5 flags: no defaults, so they must be answered (A10).
  is_insulated boolean not null,
  is_pressure_containing boolean not null,
  failure_could_injure boolean not null,
  location_text text check (location_text is null or private.nonblank(location_text)),
  latitude numeric(9, 6),
  longitude numeric(9, 6),
  archived_at timestamptz,
  created_by uuid references public.profile (id) on delete restrict default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (org_id, id),
  -- C6
  check ((latitude is null) = (longitude is null)),
  check (latitude is null or latitude between -90 and 90),
  check (longitude is null or longitude between -180 and 180)
);
create index asset_org_list_idx on public.asset (org_id, created_at desc) where archived_at is null;
create index asset_created_by_idx on public.asset (created_by);
create trigger asset_updated_at before update on public.asset
  for each row execute function private.set_updated_at();

create table public.inspection_point (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  asset_id uuid not null,
  label text not null check (private.nonblank(label) and char_length(label) <= 120),
  description text check (description is null or private.nonblank(description)),
  archived_at timestamptz,
  created_by uuid references public.profile (id) on delete restrict default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (org_id, id),
  foreign key (org_id, asset_id) references public.asset (org_id, id) on delete restrict
);
-- C5
create unique index inspection_point_label_unique on public.inspection_point (asset_id, lower(label));
create index inspection_point_org_idx on public.inspection_point (org_id);
create index inspection_point_created_by_idx on public.inspection_point (created_by);
create trigger inspection_point_updated_at before update on public.inspection_point
  for each row execute function private.set_updated_at();

-- Inspections -----------------------------------------------------------------

create table public.inspection (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  point_id uuid not null,
  inspector_id uuid not null references public.profile (id) on delete restrict default auth.uid(),
  inspected_at timestamptz not null default now(),
  status public.inspection_status not null default 'draft',
  notes text check (notes is null or private.nonblank(notes)),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (org_id, id),
  foreign key (org_id, point_id) references public.inspection_point (org_id, id) on delete restrict
);
create index inspection_point_history_idx on public.inspection (point_id, inspected_at desc);
create index inspection_queue_idx on public.inspection (org_id, status, inspected_at desc);
create index inspection_inspector_idx on public.inspection (inspector_id);
create trigger inspection_updated_at before update on public.inspection
  for each row execute function private.set_updated_at();

-- C3 and C7 on insert and on change of the checked columns.
create function private.inspection_checks() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' or new.inspector_id is distinct from old.inspector_id then
    perform private.assert_member(new.org_id, new.inspector_id, false, 'the inspector');
  end if;
  if (tg_op = 'INSERT' or new.inspected_at is distinct from old.inspected_at)
     and new.inspected_at > now() + interval '5 minutes' then
    raise exception 'inspected_at cannot be in the future' using errcode = 'check_violation';
  end if;
  if tg_op = 'INSERT' and new.status <> 'draft' then
    raise exception 'a new inspection starts as draft' using errcode = 'check_violation';
  end if;
  return new;
end
$$;
create trigger inspection_checks before insert or update on public.inspection
  for each row execute function private.inspection_checks();

-- Status is derived by Anode's own functions (section 7), and a reported
-- inspection is locked (C30).
create function private.inspection_guard() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    if old.status = 'reported' then
      raise exception 'a reported inspection cannot be deleted' using errcode = 'check_violation';
    end if;
    return old;
  end if;
  if new.org_id <> old.org_id or new.point_id <> old.point_id then
    raise exception 'an inspection cannot move to another point or organisation' using errcode = 'check_violation';
  end if;
  if not private.is_internal() then
    if new.status <> old.status then
      raise exception 'inspection status is set by Anode, not directly' using errcode = 'check_violation';
    end if;
    if old.status = 'reported' then
      raise exception 'this inspection is in a signed report and is locked' using errcode = 'check_violation';
    end if;
  end if;
  return new;
end
$$;
create trigger inspection_guard before update or delete on public.inspection
  for each row execute function private.inspection_guard();

-- C30: rows under a reported inspection cannot be inserted, changed or deleted.
-- Shared by every table that hangs off an inspection.
create function private.guard_inspection_open() returns trigger
language plpgsql
set search_path = ''
as $$
declare
  r jsonb := to_jsonb(coalesce(new, old));
  v_inspection uuid;
begin
  v_inspection := case tg_table_name
    when 'photo' then (r ->> 'inspection_id')::uuid
    when 'context_answer' then (r ->> 'inspection_id')::uuid
    when 'finding' then (r ->> 'inspection_id')::uuid
    when 'measurement' then
      (select p.inspection_id from public.photo p where p.id = (r ->> 'photo_id')::uuid)
    when 'hypothesis_evidence' then
      (select f.inspection_id from public.mechanism_hypothesis h
         join public.finding f on f.id = h.finding_id
        where h.id = (r ->> 'hypothesis_id')::uuid)
    else
      (select f.inspection_id from public.finding f where f.id = (r ->> 'finding_id')::uuid)
  end;
  if exists (select 1 from public.inspection i where i.id = v_inspection and i.status = 'reported') then
    raise exception 'this inspection is in a signed report and is locked' using errcode = 'check_violation';
  end if;
  return coalesce(new, old);
end
$$;

-- True while an inspection can still be changed (it is not in a signed report).
create function private.inspection_open(p_inspection uuid) returns boolean
language sql stable security definer
set search_path = ''
as $$ select exists (select 1 from public.inspection i where i.id = p_inspection and i.status <> 'reported') $$;
grant execute on function private.inspection_open(uuid) to authenticated, service_role;

-- Context answers ---------------------------------------------------------------

create table public.context_answer (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  inspection_id uuid not null,
  question_key text not null references public.context_question (key) on delete restrict,
  value jsonb not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (org_id, id),
  unique (inspection_id, question_key),
  foreign key (org_id, inspection_id) references public.inspection (org_id, id) on delete restrict
);
create index context_answer_question_idx on public.context_answer (question_key);
create trigger context_answer_updated_at before update on public.context_answer
  for each row execute function private.set_updated_at();
create trigger context_answer_open before insert or update or delete on public.context_answer
  for each row execute function private.guard_inspection_open();

-- C8: the value matches the question's answer type.
create function private.context_answer_checks() returns trigger
language plpgsql
set search_path = ''
as $$
declare
  q public.context_question;
  v_ok boolean;
begin
  select * into q from public.context_question where key = new.question_key;
  if tg_op = 'INSERT' and not q.is_active then
    raise exception 'question % is not active', new.question_key using errcode = 'check_violation';
  end if;
  if tg_op = 'UPDATE' and (new.inspection_id <> old.inspection_id or new.question_key <> old.question_key) then
    raise exception 'an answer cannot move to another inspection or question' using errcode = 'check_violation';
  end if;
  v_ok := (case q.answer_type
    when 'boolean' then jsonb_typeof(new.value) = 'boolean'
    when 'number' then jsonb_typeof(new.value) = 'number'
    when 'text' then jsonb_typeof(new.value) = 'string' and private.nonblank(new.value #>> '{}')
    when 'single_choice' then jsonb_typeof(new.value) = 'string' and q.options @> jsonb_build_array(new.value)
  end);
  if not coalesce(v_ok, false) then
    raise exception 'answer does not match the % question %', q.answer_type, q.key using errcode = 'check_violation';
  end if;
  return new;
end
$$;
create trigger context_answer_checks before insert or update on public.context_answer
  for each row execute function private.context_answer_checks();

-- Photos (R1) ---------------------------------------------------------------------

create table public.photo (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  inspection_id uuid not null,
  storage_path text not null unique,
  content_sha256 text not null check (content_sha256 ~ '^[0-9a-f]{64}$'),
  mime_type text not null check (mime_type in ('image/jpeg', 'image/png', 'image/heic', 'image/webp')),
  width_px integer not null check (width_px > 0),
  height_px integer not null check (height_px > 0),
  captured_at timestamptz,
  gradeability public.gradeability not null default 'pending',
  rejection_reasons public.photo_rejection_reason[] not null default '{}',
  scale_reference public.scale_reference not null default 'none',
  mm_per_px numeric(10, 6) check (mm_per_px is null or mm_per_px > 0),
  colour_corrected boolean not null default false,
  checked_at timestamptz,
  uploaded_by uuid not null references public.profile (id) on delete restrict default auth.uid(),
  created_at timestamptz not null default now(),
  unique (org_id, id),
  unique (org_id, inspection_id, id),
  foreign key (org_id, inspection_id) references public.inspection (org_id, id) on delete restrict,
  -- Storage layout: {org_id}/{inspection_id}/{photo_id}.{ext}
  constraint photo_storage_path check (storage_path ~ ('^' || org_id || '/' || inspection_id || '/' || id || '\.(jpg|jpeg|png|heic|webp)$')),
  -- Pending: not yet checked.
  constraint photo_pending_unchecked check (gradeability <> 'pending' or (checked_at is null and rejection_reasons = '{}')),
  -- C9
  constraint photo_gradeable_needs_scale check (gradeability <> 'gradeable'
         or (rejection_reasons = '{}' and scale_reference <> 'none' and mm_per_px is not null and checked_at is not null)),
  -- C10
  constraint photo_rejected_needs_reason check (gradeability <> 'rejected' or (cardinality(rejection_reasons) > 0 and checked_at is not null)),
  constraint photo_unscaled_is_rejected check (not (scale_reference = 'none' and checked_at is not null)
         or 'no_scale_reference' = any (rejection_reasons)),
  -- C9a
  constraint photo_colour_needs_scale_card check (not colour_corrected or scale_reference = 'anode_scale_card')
);
create index photo_inspection_idx on public.photo (inspection_id, created_at);
create index photo_duplicate_idx on public.photo (org_id, content_sha256);
create index photo_uploaded_by_idx on public.photo (uploaded_by);
-- C10a: one gradeable photo per inspection in Phase 1.
create unique index photo_one_gradeable on public.photo (inspection_id) where gradeability = 'gradeable';
create trigger photo_open before insert or update or delete on public.photo
  for each row execute function private.guard_inspection_open();

-- C10b: a photo is never edited, except that its check result is written once.
create function private.photo_guard() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'photos are kept, not deleted' using errcode = 'check_violation';
  end if;
  if tg_op = 'INSERT' then
    perform private.assert_member(new.org_id, new.uploaded_by, true, 'the uploader');
    return new;
  end if;
  if old.gradeability <> 'pending' then
    raise exception 'a photo''s gradeability is decided once; upload a new photo to retake'
      using errcode = 'check_violation';
  end if;
  if (to_jsonb(new) - array['gradeability', 'rejection_reasons', 'scale_reference', 'mm_per_px',
                             'colour_corrected', 'checked_at'])
     <> (to_jsonb(old) - array['gradeability', 'rejection_reasons', 'scale_reference', 'mm_per_px',
                               'colour_corrected', 'checked_at']) then
    raise exception 'only the gradeability check result can be written to a photo' using errcode = 'check_violation';
  end if;
  return new;
end
$$;
create trigger photo_guard before insert or update or delete on public.photo
  for each row execute function private.photo_guard();

-- Measurements -----------------------------------------------------------------

create table public.measurement (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  photo_id uuid not null,
  model_name text not null check (private.nonblank(model_name)),
  model_version text not null check (private.nonblank(model_version)),
  percent_area_rusted numeric(6, 3) not null check (percent_area_rusted between 0 and 100),
  outline jsonb not null check (
    jsonb_typeof(outline) = 'object'
    and outline ->> 'type' = 'MultiPolygon'
    and jsonb_typeof(outline -> 'coordinates') = 'array'
  ),
  model_confidence numeric(4, 3) not null check (model_confidence between 0 and 1),
  created_at timestamptz not null default now(),
  -- R6 / C11a: deliberately no depth, wall-loss or thickness columns.
  unique (org_id, id),
  unique (org_id, photo_id, id),
  unique (photo_id, model_name, model_version),
  foreign key (org_id, photo_id) references public.photo (org_id, id) on delete restrict
);
create trigger measurement_open before insert or update or delete on public.measurement
  for each row execute function private.guard_inspection_open();

-- C11: only gradeable photos are measured or graded.
create function private.assert_photo_gradeable(p_photo uuid) returns void
language plpgsql stable
set search_path = ''
as $$
begin
  if not exists (select 1 from public.photo p where p.id = p_photo and p.gradeability = 'gradeable') then
    raise exception 'only a gradeable photo can be measured or graded (rule 1)' using errcode = 'check_violation';
  end if;
end
$$;

-- Generic guard: rows that are never changed or deleted once written (C19, C23).
create function private.immutable_row() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception '% rows cannot be changed or deleted', tg_table_name using errcode = 'check_violation';
end
$$;

create function private.measurement_checks() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  perform private.assert_photo_gradeable(new.photo_id);
  return new;
end
$$;
create trigger measurement_checks before insert on public.measurement
  for each row execute function private.measurement_checks();
create trigger measurement_immutable before update or delete on public.measurement
  for each row execute function private.immutable_row();
