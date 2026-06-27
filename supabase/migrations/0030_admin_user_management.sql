-- ============================================================================
-- 0030 — Admin-user management (owner-only) for the Settings page
-- (BUILD_PROMPT_ADMIN_PANEL_PERFECT_FINAL.md §6, §12.13; Phase 8)
--
-- Owner-only, audited RPCs to add/promote admins and enable/disable them. The
-- auth.users email lookup needs the auth schema, so this lives in a SECURITY
-- DEFINER function rather than a PostgREST call. Idempotent + additive.
-- ============================================================================

-- ── add or change an admin (owner-only) ─────────────────────────────────────
create or replace function public.admin_upsert_admin(
  p_admin_id uuid, p_admin_email text, p_target_email text, p_role text
) returns bigint
language plpgsql security definer set search_path = public as $$
declare v_uid uuid; v_email text; v_before jsonb;
begin
  perform admin_assert_owner(p_admin_id);
  if p_role not in ('owner', 'admin', 'moderator', 'support', 'content_manager') then
    raise exception 'BAD_ROLE: %', p_role using errcode = '22023';
  end if;
  select id, email into v_uid, v_email from auth.users where lower(email) = lower(p_target_email);
  if v_uid is null then
    raise exception 'AUTH_USER_NOT_FOUND: %', p_target_email using errcode = 'P0002';
  end if;
  select to_jsonb(a) into v_before
    from (select role, status from public.admin_users where user_id = v_uid) a;
  insert into public.admin_users (user_id, email, role, status, created_by)
  values (v_uid, v_email, p_role, 'active', p_admin_id)
  on conflict (user_id) do update
    set role = excluded.role, email = excluded.email, status = 'active', updated_at = now();
  return admin_log_audit(p_admin_id, p_admin_email, 'upsert_admin', 'admin_user', v_uid::text,
           'set role ' || p_role, jsonb_build_object('email', v_email, 'role', p_role),
           v_before, jsonb_build_object('role', p_role, 'status', 'active'));
end;
$$;

-- ── enable / disable / revoke an admin (owner-only; no self-lockout) ────────
create or replace function public.admin_set_admin_status(
  p_admin_id uuid, p_admin_email text, p_target_user_id uuid, p_status text
) returns bigint
language plpgsql security definer set search_path = public as $$
begin
  perform admin_assert_owner(p_admin_id);
  if p_status not in ('active', 'disabled', 'revoked') then
    raise exception 'BAD_STATUS: %', p_status using errcode = '22023';
  end if;
  if p_target_user_id = p_admin_id and p_status <> 'active' then
    raise exception 'NO_SELF_LOCKOUT' using errcode = '22023';
  end if;
  if not exists (select 1 from public.admin_users where user_id = p_target_user_id) then
    raise exception 'ADMIN_NOT_FOUND: %', p_target_user_id using errcode = 'P0002';
  end if;
  update public.admin_users set status = p_status, updated_at = now()
   where user_id = p_target_user_id;
  return admin_log_audit(p_admin_id, p_admin_email, 'set_admin_status', 'admin_user',
           p_target_user_id::text, p_status, jsonb_build_object('status', p_status), null, null);
end;
$$;

-- ── execution grants: service_role only ─────────────────────────────────────
do $$
declare fn text;
begin
  foreach fn in array array[
    'admin_upsert_admin(uuid,text,text,text)',
    'admin_set_admin_status(uuid,text,uuid,text)'
  ]
  loop
    execute format('revoke execute on function public.%s from public, anon, authenticated;', fn);
    execute format('grant execute on function public.%s to service_role;', fn);
  end loop;
end;
$$;

-- ============================================================================
-- End of 0030
-- ============================================================================
