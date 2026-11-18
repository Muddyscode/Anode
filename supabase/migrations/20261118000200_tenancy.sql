-- Anode Phase 1 schema, part 2: organisations, people and memberships.
-- Domain model E1 to E3, section 9 (roles), A1 to A3.

create table public.organisation (
  id uuid primary key default gen_random_uuid(),
  name text not null check (private.nonblank(name) and char_length(name) <= 120),
  is_demo boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger organisation_updated_at before update on public.organisation
  for each row execute function private.set_updated_at();

create table public.profile (
  id uuid primary key references auth.users (id) on delete restrict,
  display_name text not null check (private.nonblank(display_name) and char_length(display_name) <= 120),
  qualification text check (qualification is null or (private.nonblank(qualification) and char_length(qualification) <= 200)),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger profile_updated_at before update on public.profile
  for each row execute function private.set_updated_at();

create table public.membership (
  org_id uuid not null references public.organisation (id) on delete restrict,
  user_id uuid not null references public.profile (id) on delete restrict,
  role public.member_role not null,
  created_at timestamptz not null default now(),
  primary key (org_id, user_id)
);
create index membership_user_id_idx on public.membership (user_id);

-- Membership helpers used by row-level security --------------------------------
-- SECURITY DEFINER so that policies can read membership without recursing into
-- membership's own policies.

create function private.is_member(p_org uuid) returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.membership m
    where m.org_id = p_org and m.user_id = (select auth.uid())
  )
$$;

create function private.has_role(p_org uuid, p_roles public.member_role[]) returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.membership m
    where m.org_id = p_org and m.user_id = (select auth.uid()) and m.role = any (p_roles)
  )
$$;

-- Admins and inspectors can write; viewers only read (section 9).
create function private.can_write(p_org uuid) returns boolean
language sql stable
set search_path = ''
as $$ select private.has_role(p_org, array['admin', 'inspector']::public.member_role[]) $$;

create function private.is_admin(p_org uuid) returns boolean
language sql stable
set search_path = ''
as $$ select private.has_role(p_org, array['admin']::public.member_role[]) $$;

-- The role a given person holds in a given organisation, or null (C3).
create function private.role_of(p_org uuid, p_user uuid) returns public.member_role
language sql stable security definer
set search_path = ''
as $$ select m.role from public.membership m where m.org_id = p_org and m.user_id = p_user $$;

-- C3: raises unless p_user is a member of p_org, optionally with a writing role.
create function private.assert_member(p_org uuid, p_user uuid, p_need_write boolean, p_what text)
returns void
language plpgsql stable
set search_path = ''
as $$
declare
  v_role public.member_role := private.role_of(p_org, p_user);
begin
  if v_role is null then
    raise exception '% must be a member of the organisation', p_what using errcode = 'check_violation';
  end if;
  if p_need_write and v_role not in ('admin', 'inspector') then
    raise exception '% must be an inspector or admin of the organisation', p_what using errcode = 'check_violation';
  end if;
end
$$;

grant execute on function
  private.is_member(uuid),
  private.has_role(uuid, public.member_role[]),
  private.can_write(uuid),
  private.is_admin(uuid)
to authenticated, service_role;

-- Every organisation keeps at least one admin (section 9: "not the last admin").
create function private.keep_one_admin() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.role = 'admin'
     and (tg_op = 'DELETE' or new.role <> 'admin')
     and not exists (
       select 1 from public.membership m
       where m.org_id = old.org_id and m.role = 'admin' and m.user_id <> old.user_id
     )
  then
    raise exception 'an organisation must keep at least one admin' using errcode = 'check_violation';
  end if;
  return coalesce(new, old);
end
$$;
create trigger membership_keep_one_admin before update or delete on public.membership
  for each row execute function private.keep_one_admin();

-- Membership keys never change; remove and re-add instead.
create function private.membership_keys_fixed() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.org_id <> old.org_id or new.user_id <> old.user_id then
    raise exception 'membership organisation and user cannot change' using errcode = 'check_violation';
  end if;
  return new;
end
$$;
create trigger membership_keys_fixed before update on public.membership
  for each row execute function private.membership_keys_fixed();

-- Sign-up: profile, personal organisation and admin membership (A2) -----------

create function private.handle_new_user() returns trigger
language plpgsql security definer
set search_path = ''
as $$
declare
  v_name text := coalesce(
    nullif(btrim(new.raw_user_meta_data ->> 'display_name'), ''),
    nullif(split_part(coalesce(new.email, ''), '@', 1), ''),
    'Inspector'
  );
  v_org_name text := coalesce(
    nullif(btrim(new.raw_user_meta_data ->> 'organisation_name'), ''),
    left(v_name, 104) || '''s organisation'
  );
  v_org uuid;
begin
  insert into public.profile (id, display_name) values (new.id, left(v_name, 120));
  insert into public.organisation (name) values (left(v_org_name, 120)) returning id into v_org;
  insert into public.membership (org_id, user_id, role) values (v_org, new.id, 'admin');
  return new;
end
$$;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function private.handle_new_user();
