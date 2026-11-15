-- ==============================================================================
-- TOKYO STREET 3.ª EDICIÓN — MIGRACIÓN 005: SEGURIDAD, POLÍTICAS RLS Y PERMISOS
-- ==============================================================================
-- Archivo: 20261109000005_security_rls.sql
-- Épica: E3-1 y E3-7 (Defensa en profundidad, RLS estricto y GRANTs de RPCs)
-- ==============================================================================

-- 1. Habilitar y forzar Row Level Security en las 10 tablas del esquema
alter table public.event_settings enable row level security;
alter table public.event_settings force row level security;

alter table public.stands enable row level security;
alter table public.stands force row level security;

alter table public.staff_roles enable row level security;
alter table public.staff_roles force row level security;

alter table public.participants enable row level security;
alter table public.participants force row level security;

alter table public.qr_tokens enable row level security;
alter table public.qr_tokens force row level security;

alter table public.numeric_codes enable row level security;
alter table public.numeric_codes force row level security;

alter table public.stamps enable row level security;
alter table public.stamps force row level security;

alter table public.winners enable row level security;
alter table public.winners force row level security;

alter table public.attempts enable row level security;
alter table public.attempts force row level security;

alter table public.audit_log enable row level security;
alter table public.audit_log force row level security;

-- 2. Revocar mutaciones directas por REST a roles cliente
revoke insert, update, delete on all tables in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;

-- 3. Políticas RLS de defensa en profundidad (lectura selectiva por rol)

drop policy if exists "event_settings_read_public" on public.event_settings;
create policy "event_settings_read_public"
  on public.event_settings for select to anon, authenticated
  using (true);

drop policy if exists "stands_read_active_or_org" on public.stands;
create policy "stands_read_active_or_org"
  on public.stands for select to anon, authenticated
  using (status = 'active' or public.is_org());

drop policy if exists "staff_roles_read_self_or_org" on public.staff_roles;
create policy "staff_roles_read_self_or_org"
  on public.staff_roles for select to authenticated
  using (user_id = auth.uid() or public.is_org());

drop policy if exists "participants_read_self_or_org" on public.participants;
create policy "participants_read_self_or_org"
  on public.participants for select to authenticated
  using (auth_user_id = auth.uid() or public.is_org());

drop policy if exists "stamps_read_self_or_org" on public.stamps;
create policy "stamps_read_self_or_org"
  on public.stamps for select to authenticated
  using (
    exists (
      select 1 from public.participants p
      where p.id = participant_id and p.auth_user_id = auth.uid()
    )
    or public.is_org()
  );

drop policy if exists "winners_read_self_or_org" on public.winners;
create policy "winners_read_self_or_org"
  on public.winners for select to authenticated
  using (
    exists (
      select 1 from public.participants p
      where p.id = participant_id and p.auth_user_id = auth.uid()
    )
    or public.is_org()
  );

drop policy if exists "numeric_codes_read_self" on public.numeric_codes;
create policy "numeric_codes_read_self"
  on public.numeric_codes for select to authenticated
  using (
    exists (
      select 1 from public.participants p
      where p.id = participant_id and p.auth_user_id = auth.uid()
    )
    or public.is_org()
  );

drop policy if exists "qr_tokens_read_org_only" on public.qr_tokens;
create policy "qr_tokens_read_org_only"
  on public.qr_tokens for select to authenticated
  using (public.is_org());

drop policy if exists "attempts_read_org_only" on public.attempts;
create policy "attempts_read_org_only"
  on public.attempts for select to authenticated
  using (public.is_org());

drop policy if exists "audit_log_read_org_only" on public.audit_log;
create policy "audit_log_read_org_only"
  on public.audit_log for select to authenticated
  using (public.is_org());

-- 4. Permisos de Ejecución de Funciones (RPC Grants)

revoke execute on all functions in schema public from public;

-- Bloquear llamada directa por PostgREST a helpers internos
revoke execute on function public.is_org() from anon, authenticated;
revoke execute on function public.my_stand_id() from anon, authenticated;
revoke execute on function public._require_org() from anon, authenticated;
revoke execute on function public._require_stand() from anon, authenticated;
revoke execute on function public._audit(text, text, text, jsonb) from anon, authenticated;
revoke execute on function public._gen_ticket_code() from anon, authenticated;
revoke execute on function public._mask_dni(text) from anon, authenticated;
revoke execute on function public._token_status(timestamptz, timestamptz, timestamptz) from anon, authenticated;
revoke execute on function public._progress(uuid) from anon, authenticated;
revoke execute on function public._credit_stamp(uuid, int, uuid, text) from anon, authenticated;

-- RPCs Públicas y de Participante (/pasaporte y /s/:token)
grant execute on function public.get_public_status to anon, authenticated;
grant execute on function public.recover_session to anon, authenticated;
grant execute on function public.register_participant to authenticated;
grant execute on function public.get_my_passport to authenticated;
grant execute on function public.participant_generate_code to authenticated;
grant execute on function public.redeem_qr to authenticated;

-- RPCs de Feriante (/stand)
grant execute on function public.stand_generate_qr to authenticated;
grant execute on function public.stand_check_token to authenticated;
grant execute on function public.stand_credit_by_code to authenticated;
grant execute on function public.stand_get_summary to authenticated;

-- RPCs de Organización (/org)
grant execute on function public.org_get_dashboard to authenticated;
grant execute on function public.org_list_stands to authenticated;
grant execute on function public.org_upsert_stand to authenticated;
grant execute on function public.org_import_stands to authenticated;
grant execute on function public.org_set_stand_status to authenticated;
grant execute on function public.org_list_tokens to authenticated;
grant execute on function public.org_revoke_token to authenticated;
grant execute on function public.org_list_winners to authenticated;
grant execute on function public.org_verify_ticket to authenticated;
grant execute on function public.org_mark_delivered to authenticated;
grant execute on function public.org_update_settings to authenticated;
