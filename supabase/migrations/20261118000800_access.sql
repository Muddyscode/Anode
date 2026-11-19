-- Anode Phase 1 schema, part 8: privileges, row-level security and storage.
-- Domain model section 9. Every policy first checks organisation membership, so
-- a user never sees another organisation's rows.
--
-- Privileges are granted explicitly, column by column where it matters, rather
-- than relying on Supabase's default grants. Row-level security then decides
-- which rows. Triggers enforce the remaining rules for every role.

-- Start from nothing ------------------------------------------------------------

revoke all on all tables in schema public from anon, authenticated, service_role;
revoke all on all sequences in schema public from anon, authenticated, service_role;
revoke execute on function public.sign_report(uuid, uuid, text, text, text) from public, anon, authenticated;
revoke execute on function public.void_report(uuid, uuid, text) from public, anon, authenticated;

-- The server (service role) reads and writes everything, subject to triggers.
-- The audit log is the exception: nobody writes it except the triggers (C36).
grant select, insert, update, delete on all tables in schema public to service_role;
revoke insert, update, delete, truncate on public.audit_event from service_role;

grant execute on function public.sign_report(uuid, uuid, text, text, text) to service_role;
grant execute on function public.void_report(uuid, uuid, text) to service_role;

-- Reference data (C2): readable, never writable by users ----------------------

grant select on public.standard, public.severity_level, public.mechanism,
  public.recommendation, public.context_question to authenticated;

alter table public.standard enable row level security;
alter table public.severity_level enable row level security;
alter table public.mechanism enable row level security;
alter table public.recommendation enable row level security;
alter table public.context_question enable row level security;

create policy "reference is readable" on public.standard for select to authenticated using (true);
create policy "reference is readable" on public.severity_level for select to authenticated using (true);
create policy "reference is readable" on public.mechanism for select to authenticated using (true);
create policy "reference is readable" on public.recommendation for select to authenticated using (true);
create policy "reference is readable" on public.context_question for select to authenticated using (true);

-- Tenancy ---------------------------------------------------------------------------

alter table public.organisation enable row level security;
alter table public.profile enable row level security;
alter table public.membership enable row level security;

grant select on public.organisation to authenticated;
grant update (name) on public.organisation to authenticated;
create policy "members read their organisation" on public.organisation
  for select to authenticated using ((select private.is_member(id)));
create policy "admins rename their organisation" on public.organisation
  for update to authenticated using ((select private.is_admin(id))) with check ((select private.is_admin(id)));

grant select on public.profile to authenticated;
grant update (display_name, qualification) on public.profile to authenticated;
create policy "people read their own and co-members' profiles" on public.profile
  for select to authenticated using (
    id = (select auth.uid())
    or exists (
      select 1 from public.membership mine
        join public.membership theirs on theirs.org_id = mine.org_id
       where mine.user_id = (select auth.uid()) and theirs.user_id = profile.id
    )
  );
create policy "people edit their own profile" on public.profile
  for update to authenticated using (id = (select auth.uid())) with check (id = (select auth.uid()));

grant select, insert, delete on public.membership to authenticated;
grant update (role) on public.membership to authenticated;
create policy "members read their organisation's memberships" on public.membership
  for select to authenticated using ((select private.is_member(org_id)));
create policy "admins add members" on public.membership
  for insert to authenticated with check ((select private.is_admin(org_id)));
create policy "admins change roles" on public.membership
  for update to authenticated using ((select private.is_admin(org_id))) with check ((select private.is_admin(org_id)));
create policy "admins remove members" on public.membership
  for delete to authenticated using ((select private.is_admin(org_id)));

-- Asset register ----------------------------------------------------------------

alter table public.asset enable row level security;
alter table public.inspection_point enable row level security;

grant select on public.asset, public.inspection_point to authenticated;
grant insert (id, org_id, name, asset_type, material, coating_status, coating_description, environment,
  is_insulated, is_pressure_containing, failure_could_injure, location_text, latitude, longitude)
  on public.asset to authenticated;
grant update (name, asset_type, material, coating_status, coating_description, environment,
  is_insulated, is_pressure_containing, failure_could_injure, location_text, latitude, longitude, archived_at)
  on public.asset to authenticated;
grant insert (id, org_id, asset_id, label, description) on public.inspection_point to authenticated;
grant update (label, description, archived_at) on public.inspection_point to authenticated;

create policy "members read assets" on public.asset
  for select to authenticated using ((select private.is_member(org_id)));
create policy "writers add assets" on public.asset
  for insert to authenticated
  with check ((select private.can_write(org_id)) and created_by = (select auth.uid()));
create policy "writers edit and archive assets" on public.asset
  for update to authenticated
  using ((select private.can_write(org_id))) with check ((select private.can_write(org_id)));

create policy "members read points" on public.inspection_point
  for select to authenticated using ((select private.is_member(org_id)));
create policy "writers add points" on public.inspection_point
  for insert to authenticated
  with check ((select private.can_write(org_id)) and created_by = (select auth.uid()));
create policy "writers edit and archive points" on public.inspection_point
  for update to authenticated
  using ((select private.can_write(org_id))) with check ((select private.can_write(org_id)));

-- Inspections, answers, photos, measurements ------------------------------------

alter table public.inspection enable row level security;
alter table public.context_answer enable row level security;
alter table public.photo enable row level security;
alter table public.measurement enable row level security;

grant select on public.inspection, public.context_answer, public.photo, public.measurement to authenticated;
grant insert (id, org_id, point_id, inspector_id, inspected_at, notes) on public.inspection to authenticated;
grant update (inspector_id, inspected_at, notes) on public.inspection to authenticated;
grant insert (id, org_id, inspection_id, question_key, value) on public.context_answer to authenticated;
grant update (value) on public.context_answer to authenticated;
-- A8: the gradeability check result is written by the server, not the client.
grant insert (id, org_id, inspection_id, storage_path, content_sha256, mime_type, width_px, height_px, captured_at)
  on public.photo to authenticated;

create policy "members read inspections" on public.inspection
  for select to authenticated using ((select private.is_member(org_id)));
create policy "writers start inspections" on public.inspection
  for insert to authenticated with check ((select private.can_write(org_id)));
create policy "writers edit open inspections" on public.inspection
  for update to authenticated
  using ((select private.can_write(org_id)) and status <> 'reported')
  with check ((select private.can_write(org_id)));

create policy "members read answers" on public.context_answer
  for select to authenticated using ((select private.is_member(org_id)));
create policy "writers answer on open inspections" on public.context_answer
  for insert to authenticated
  with check ((select private.can_write(org_id)) and (select private.inspection_open(inspection_id)));
create policy "writers change answers on open inspections" on public.context_answer
  for update to authenticated
  using ((select private.can_write(org_id)) and (select private.inspection_open(inspection_id)))
  with check ((select private.can_write(org_id)));

create policy "members read photos" on public.photo
  for select to authenticated using ((select private.is_member(org_id)));
create policy "writers add photos to open inspections" on public.photo
  for insert to authenticated
  with check (
    (select private.can_write(org_id))
    and uploaded_by = (select auth.uid())
    and (select private.inspection_open(inspection_id))
  );

create policy "members read measurements" on public.measurement
  for select to authenticated using ((select private.is_member(org_id)));

-- Findings -------------------------------------------------------------------------

alter table public.finding enable row level security;
alter table public.finding_escalation enable row level security;
alter table public.mechanism_hypothesis enable row level security;
alter table public.hypothesis_evidence enable row level security;
alter table public.finding_recommendation enable row level security;
alter table public.finding_review enable row level security;

grant select on public.finding, public.finding_escalation, public.mechanism_hypothesis,
  public.hypothesis_evidence, public.finding_recommendation, public.finding_review to authenticated;

-- Inspectors write their own findings only (C20); AI findings come from the server.
grant insert (id, org_id, inspection_id, photo_id, measurement_id, origin, supersedes_finding_id, revision_reason,
  defect_type, standard_id, grade_value, rules_severity, severity, confidence, possible_staining, summary)
  on public.finding to authenticated;
create policy "members read findings" on public.finding
  for select to authenticated using ((select private.is_member(org_id)));
create policy "writers add their own findings" on public.finding
  for insert to authenticated
  with check (
    origin = 'inspector'
    and created_by = (select auth.uid())
    and (select private.can_write(org_id))
    and (select private.inspection_open(inspection_id))
  );

-- C16c: people may raise escalations; acknowledging is the only update.
grant insert (id, org_id, finding_id, reason, source, detail) on public.finding_escalation to authenticated;
grant update (acknowledged_by, acknowledged_at, acknowledgement_note) on public.finding_escalation to authenticated;
create policy "members read escalations" on public.finding_escalation
  for select to authenticated using ((select private.is_member(org_id)));
create policy "writers raise escalations" on public.finding_escalation
  for insert to authenticated
  with check (source = 'inspector' and (select private.can_write(org_id)));
create policy "writers acknowledge escalations" on public.finding_escalation
  for update to authenticated
  using ((select private.can_write(org_id)))
  with check ((select private.can_write(org_id)) and acknowledged_by = (select auth.uid()));

-- Children of a finding: people add them only to findings they wrote.
create function private.is_own_inspector_finding(p_finding uuid) returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.finding f
     where f.id = p_finding and f.origin = 'inspector' and f.created_by = (select auth.uid())
  )
$$;
grant execute on function private.is_own_inspector_finding(uuid) to authenticated;

grant insert (id, org_id, finding_id, rank, mechanism_code, visual_evidence) on public.mechanism_hypothesis to authenticated;
create policy "members read hypotheses" on public.mechanism_hypothesis
  for select to authenticated using ((select private.is_member(org_id)));
create policy "writers rank mechanisms on their own findings" on public.mechanism_hypothesis
  for insert to authenticated
  with check ((select private.can_write(org_id)) and (select private.is_own_inspector_finding(finding_id)));

grant insert (hypothesis_id, context_answer_id, org_id) on public.hypothesis_evidence to authenticated;
create policy "members read evidence" on public.hypothesis_evidence
  for select to authenticated using ((select private.is_member(org_id)));
create policy "writers cite evidence on their own findings" on public.hypothesis_evidence
  for insert to authenticated
  with check (
    (select private.can_write(org_id))
    and exists (
      select 1 from public.mechanism_hypothesis h
       where h.id = hypothesis_id and (select private.is_own_inspector_finding(h.finding_id))
    )
  );

grant insert (finding_id, recommendation_code, recommendation_version, sort_order, org_id)
  on public.finding_recommendation to authenticated;
create policy "members read recommendations" on public.finding_recommendation
  for select to authenticated using ((select private.is_member(org_id)));
create policy "writers recommend on their own findings" on public.finding_recommendation
  for insert to authenticated
  with check ((select private.can_write(org_id)) and (select private.is_own_inspector_finding(finding_id)));

grant insert (id, org_id, finding_id, decision, revised_finding_id, reason) on public.finding_review to authenticated;
create policy "members read reviews" on public.finding_review
  for select to authenticated using ((select private.is_member(org_id)));
create policy "writers review findings" on public.finding_review
  for insert to authenticated
  with check ((select private.can_write(org_id)) and reviewed_by = (select auth.uid()));

-- Reports -----------------------------------------------------------------------------

alter table public.report enable row level security;
alter table public.report_inspection enable row level security;

grant select, delete on public.report to authenticated;
grant insert (id, org_id, title, replaces_report_id) on public.report to authenticated;
grant update (title, replaces_report_id) on public.report to authenticated;
create policy "members read reports; drafts only for writers" on public.report
  for select to authenticated
  using ((select private.is_member(org_id)) and (status <> 'draft' or (select private.can_write(org_id))));
create policy "writers create reports" on public.report
  for insert to authenticated
  with check ((select private.can_write(org_id)) and created_by = (select auth.uid()));
create policy "writers edit draft reports" on public.report
  for update to authenticated
  using ((select private.can_write(org_id)) and status = 'draft')
  with check ((select private.can_write(org_id)));
create policy "writers delete draft reports" on public.report
  for delete to authenticated
  using ((select private.can_write(org_id)) and status = 'draft');

grant select, insert, delete on public.report_inspection to authenticated;
create function private.report_status_of(p_report uuid) returns public.report_status
language sql stable security definer
set search_path = ''
as $$ select r.status from public.report r where r.id = p_report $$;
grant execute on function private.report_status_of(uuid) to authenticated;

create policy "members read report contents; drafts only for writers" on public.report_inspection
  for select to authenticated
  using (
    (select private.is_member(org_id))
    and ((select private.report_status_of(report_id)) <> 'draft' or (select private.can_write(org_id)))
  );
create policy "writers fill draft reports" on public.report_inspection
  for insert to authenticated
  with check ((select private.can_write(org_id)) and (select private.report_status_of(report_id)) = 'draft');
create policy "writers empty draft reports" on public.report_inspection
  for delete to authenticated
  using ((select private.can_write(org_id)) and (select private.report_status_of(report_id)) = 'draft');

-- Audit log (C36): inspectors and admins read; nobody writes directly ----------

alter table public.audit_event enable row level security;
grant select on public.audit_event to authenticated;
create policy "inspectors and admins read the audit log" on public.audit_event
  for select to authenticated using ((select private.can_write(org_id)));

-- Storage -----------------------------------------------------------------------------
-- Private buckets. Paths start with the organisation id (section 9).

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('inspection-photos', 'inspection-photos', false, 20971520,
   array['image/jpeg', 'image/png', 'image/heic', 'image/webp']),
  ('reports', 'reports', false, 20971520, array['application/pdf'])
on conflict (id) do nothing;

-- Writable photo path: {org_id}/{inspection_id}/{file}, for an open inspection of that organisation.
create function private.can_upload_photo(p_name text) returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.inspection i
     where i.org_id = private.try_uuid((storage.foldername(p_name))[1])
       and i.id = private.try_uuid((storage.foldername(p_name))[2])
       and i.status <> 'reported'
       and array_length(storage.foldername(p_name), 1) = 2
  ) and private.can_write(private.try_uuid((storage.foldername(p_name))[1]))
$$;
grant execute on function private.can_upload_photo(text) to authenticated;

create policy "members read their organisation's photos and reports" on storage.objects
  for select to authenticated
  using (
    bucket_id in ('inspection-photos', 'reports')
    and (select private.is_member(private.try_uuid((storage.foldername(name))[1])))
  );

-- No update or delete policies: photos are never overwritten or removed, and
-- report PDFs are written only by the server (service role).
create policy "writers upload photos to open inspections" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'inspection-photos' and (select private.can_upload_photo(name)));

-- Internal helpers -----------------------------------------------------------------
-- Trigger and policy code runs as the calling role, so the API roles need EXECUTE
-- on the helpers. The private schema is not exposed by the Supabase API, so
-- these are not callable as RPCs.
grant execute on all functions in schema private to authenticated, service_role;
