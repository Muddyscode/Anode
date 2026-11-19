-- Anode Phase 1 schema, part 7: reports, signing, voiding and reissue.
-- Domain model E21, E22; constraints C25 to C30, C33, C34 (R9, D7).

create table public.report (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organisation (id) on delete restrict,
  title text not null check (private.nonblank(title) and char_length(title) <= 120),
  status public.report_status not null default 'draft',
  created_by uuid references public.profile (id) on delete restrict default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  signed_by uuid references public.profile (id) on delete restrict,
  signed_at timestamptz,
  signer_name text,
  signer_qualification text,
  disclaimer_version text check (disclaimer_version is null or private.nonblank(disclaimer_version)),
  pdf_path text,
  pdf_sha256 text check (pdf_sha256 is null or pdf_sha256 ~ '^[0-9a-f]{64}$'),
  replaces_report_id uuid,
  voided_by uuid references public.profile (id) on delete restrict,
  voided_at timestamptz,
  void_reason text check (void_reason is null or private.nonblank(void_reason)),
  unique (org_id, id),
  foreign key (org_id, replaces_report_id) references public.report (org_id, id) on delete restrict,
  check (replaces_report_id is null or replaces_report_id <> id),
  check (pdf_path is null or pdf_path = org_id || '/' || id || '.pdf'),
  -- C26: signed and void reports carry the full signature.
  check (status = 'draft' or (
    signed_by is not null and signed_at is not null and private.nonblank(signer_name)
    and disclaimer_version is not null and pdf_path is not null and pdf_sha256 is not null)),
  check (status <> 'draft' or (
    signed_by is null and signed_at is null and signer_name is null and signer_qualification is null
    and disclaimer_version is null and pdf_path is null and pdf_sha256 is null)),
  -- C33: void reports carry who, when and why; others carry none of it.
  check ((status = 'void') = (voided_by is not null)
         and (status = 'void') = (voided_at is not null)
         and (status = 'void') = (void_reason is not null))
);
create index report_list_idx on public.report (org_id, status, created_at desc);
-- C34: a voided report has at most one replacement.
create unique index report_replaced_once on public.report (replaces_report_id) where replaces_report_id is not null;
create index report_created_by_idx on public.report (created_by);
create index report_signed_by_idx on public.report (signed_by);
create index report_voided_by_idx on public.report (voided_by);
create trigger report_updated_at before update on public.report
  for each row execute function private.set_updated_at();

-- C34: a replacement points at a void report.
create function private.assert_replaces_void(p_replaces uuid) returns void
language plpgsql stable
set search_path = ''
as $$
begin
  if p_replaces is not null
     and not exists (select 1 from public.report r where r.id = p_replaces and r.status = 'void') then
    raise exception 'a report can only replace a voided report' using errcode = 'check_violation';
  end if;
end
$$;

-- C28, C30, C33: signing and voiding happen only inside sign_report and
-- void_report; a signed report changes only by being voided; void is final.
create function private.report_guard() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if new.status <> 'draft' then
      raise exception 'a new report starts as draft' using errcode = 'check_violation';
    end if;
    if new.created_by is not null then
      perform private.assert_member(new.org_id, new.created_by, true, 'the report author');
    end if;
    perform private.assert_replaces_void(new.replaces_report_id);
    return new;
  end if;

  if tg_op = 'DELETE' then
    if old.status <> 'draft' then
      raise exception 'a signed or voided report is never deleted' using errcode = 'check_violation';
    end if;
    return old;
  end if;

  if new.org_id <> old.org_id then
    raise exception 'a report cannot move to another organisation' using errcode = 'check_violation';
  end if;

  if old.status = 'draft' then
    if new.status <> 'draft' and not private.is_internal() then
      raise exception 'reports are signed only through sign_report' using errcode = 'check_violation';
    end if;
    if new.replaces_report_id is distinct from old.replaces_report_id then
      perform private.assert_replaces_void(new.replaces_report_id);
    end if;
    return new;
  end if;

  if old.status = 'signed' and new.status = 'void' and private.is_internal()
     and (to_jsonb(new) - array['status', 'voided_by', 'voided_at', 'void_reason', 'updated_at'])
       = (to_jsonb(old) - array['status', 'voided_by', 'voided_at', 'void_reason', 'updated_at']) then
    return new;
  end if;

  raise exception 'a % report cannot be changed', old.status using errcode = 'check_violation';
end
$$;
create trigger report_guard before insert or update or delete on public.report
  for each row execute function private.report_guard();

create table public.report_inspection (
  report_id uuid not null,
  inspection_id uuid not null,
  org_id uuid not null,
  primary key (report_id, inspection_id),
  foreign key (org_id, report_id) references public.report (org_id, id) on delete restrict,
  foreign key (org_id, inspection_id) references public.inspection (org_id, id) on delete restrict
);
create index report_inspection_inspection_idx on public.report_inspection (inspection_id);

-- C29, C30: contents change only while the report is a draft, and an inspection
-- is in at most one report that is not void.
-- SECURITY DEFINER: it locks the inspection row to serialise concurrent reports.
create function private.report_inspection_guard() returns trigger
language plpgsql security definer
set search_path = ''
as $$
declare
  v_report_status public.report_status;
begin
  if tg_op = 'UPDATE' then
    raise exception 'report contents are added or removed, not changed' using errcode = 'check_violation';
  end if;
  select r.status into v_report_status from public.report r where r.id = coalesce(new.report_id, old.report_id);
  if v_report_status <> 'draft' then
    raise exception 'a % report''s contents cannot change', v_report_status using errcode = 'check_violation';
  end if;
  if tg_op = 'INSERT' then
    -- Serialise concurrent attempts to report the same inspection.
    perform 1 from public.inspection i where i.id = new.inspection_id for update;
    if exists (select 1 from public.inspection i where i.id = new.inspection_id and i.status = 'reported') then
      raise exception 'this inspection is already in a signed report' using errcode = 'check_violation';
    end if;
    if exists (
      select 1 from public.report_inspection ri
        join public.report r on r.id = ri.report_id
       where ri.inspection_id = new.inspection_id and ri.report_id <> new.report_id and r.status <> 'void'
    ) then
      raise exception 'this inspection is already in another report' using errcode = 'check_violation';
    end if;
    return new;
  end if;
  return old;
end
$$;
create trigger report_inspection_guard before insert or update or delete on public.report_inspection
  for each row execute function private.report_inspection_guard();

-- sign_report: called by the server after it has generated and stored the PDF.
-- Enforces C25 to C29 and writes the audit event (C35).
create function public.sign_report(
  p_report_id uuid,
  p_signer_id uuid,
  p_pdf_path text,
  p_pdf_sha256 text,
  p_disclaimer_version text
) returns public.report
language plpgsql security definer
set search_path = ''
as $$
declare
  r public.report;
  p public.profile;
  v_inspections uuid[];
  v_prev text;
begin
  select * into r from public.report where id = p_report_id for update;
  if not found then
    raise exception 'report not found' using errcode = 'no_data_found';
  end if;
  if r.status <> 'draft' then
    raise exception 'only a draft report can be signed' using errcode = 'check_violation';
  end if;
  perform private.assert_member(r.org_id, p_signer_id, true, 'the signer');

  select coalesce(array_agg(i.id order by i.id), '{}') into v_inspections
    from public.inspection i
    join public.report_inspection ri on ri.inspection_id = i.id
   where ri.report_id = p_report_id;
  perform 1 from public.inspection i where i.id = any (v_inspections) for update;

  if cardinality(v_inspections) = 0 then
    raise exception 'a report must cover at least one inspection' using errcode = 'check_violation';
  end if;
  if exists (select 1 from public.inspection i where i.id = any (v_inspections) and i.status <> 'ready_for_signoff') then
    raise exception 'every finding must be accepted, edited or rejected before signing (rule 9)'
      using errcode = 'check_violation';
  end if;
  if exists (
    select 1 from public.report_inspection ri
      join public.report o on o.id = ri.report_id
     where ri.inspection_id = any (v_inspections) and o.id <> p_report_id and o.status <> 'void'
  ) then
    raise exception 'an inspection in this report is already in another report' using errcode = 'check_violation';
  end if;
  if exists (
    select 1 from public.finding_escalation e
      join public.finding f on f.id = e.finding_id
     where f.inspection_id = any (v_inspections) and e.acknowledged_at is null
  ) then
    raise exception 'every escalation must be acknowledged by an inspector before signing (rule 5)'
      using errcode = 'check_violation';
  end if;
  if not exists (select 1 from storage.objects o where o.bucket_id = 'reports' and o.name = p_pdf_path) then
    raise exception 'the report PDF has not been stored at %', p_pdf_path using errcode = 'check_violation';
  end if;

  select * into p from public.profile where id = p_signer_id;

  v_prev := private.enter_internal();
  update public.report
     set status = 'signed',
         signed_by = p_signer_id,
         signed_at = now(),
         signer_name = p.display_name,
         signer_qualification = p.qualification,
         disclaimer_version = p_disclaimer_version,
         pdf_path = p_pdf_path,
         pdf_sha256 = p_pdf_sha256
   where id = p_report_id
  returning * into r;
  update public.inspection set status = 'reported' where id = any (v_inspections);
  perform private.restore_internal(v_prev);

  perform private.audit(r.org_id, 'report_signed', 'report', r.id,
    jsonb_strip_nulls(jsonb_build_object(
      'pdf_sha256', r.pdf_sha256,
      'disclaimer_version', r.disclaimer_version,
      'inspection_ids', to_jsonb(v_inspections),
      'replaces_report_id', r.replaces_report_id)),
    p_signer_id);
  return r;
end
$$;

-- void_report: a signed report is voided with a reason, never edited (D7, C33).
-- Its inspections are released so they can be corrected and reported again.
create function public.void_report(
  p_report_id uuid,
  p_actor_id uuid,
  p_reason text
) returns public.report
language plpgsql security definer
set search_path = ''
as $$
declare
  r public.report;
  v_inspection uuid;
  v_prev text;
begin
  select * into r from public.report where id = p_report_id for update;
  if not found then
    raise exception 'report not found' using errcode = 'no_data_found';
  end if;
  if r.status <> 'signed' then
    raise exception 'only a signed report can be voided' using errcode = 'check_violation';
  end if;
  perform private.assert_member(r.org_id, p_actor_id, true, 'the person voiding');
  if not private.nonblank(p_reason) then
    raise exception 'voiding a report needs a reason' using errcode = 'check_violation';
  end if;

  v_prev := private.enter_internal();
  update public.report
     set status = 'void', voided_by = p_actor_id, voided_at = now(), void_reason = btrim(p_reason)
   where id = p_report_id
  returning * into r;
  perform private.restore_internal(v_prev);

  for v_inspection in select ri.inspection_id from public.report_inspection ri where ri.report_id = p_report_id loop
    perform private.refresh_inspection_status(v_inspection, true);
  end loop;

  perform private.audit(r.org_id, 'report_voided', 'report', r.id,
    jsonb_build_object('reason', r.void_reason, 'pdf_sha256', r.pdf_sha256),
    p_actor_id);
  return r;
end
$$;
