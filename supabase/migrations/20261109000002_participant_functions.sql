-- ==============================================================================
-- TOKYO STREET 3.ª EDICIÓN — MIGRACIÓN 002: HELPERS Y RPCs DE PARTICIPANTE
-- ==============================================================================
-- Archivo: 20261109000002_participant_functions.sql
-- Épica: E3-2 y E3-3 (Helpers de seguridad/dominio y flujo de libreta /pasaporte)
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. FUNCIONES AUXILIARES INTERNAS DE SEGURIDAD Y DOMINIO
-- ------------------------------------------------------------------------------

-- Verifica si el usuario autenticado posee rol 'org'
create or replace function public.is_org() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.staff_roles
    where user_id = auth.uid() and role = 'org'
  );
$$;

-- Obtiene el stand_id asignado al usuario autenticado con rol 'stand'
create or replace function public.my_stand_id() returns int
language sql stable security definer set search_path = public as $$
  select stand_id from public.staff_roles
  where user_id = auth.uid() and role = 'stand';
$$;

-- Guardia reusable para exigir rol 'org' en RPCs administrativas
create or replace function public._require_org() returns void
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_org() then
    raise exception 'forbidden: org role required' using errcode = '42501';
  end if;
end;
$$;

-- Guardia reusable para exigir rol 'stand' y devolver su stand_id
create or replace function public._require_stand() returns int
language plpgsql stable security definer set search_path = public as $$
declare
  v_stand_id int := public.my_stand_id();
begin
  if v_stand_id is null then
    raise exception 'forbidden: stand role required' using errcode = '42501';
  end if;
  return v_stand_id;
end;
$$;

-- Registra evento inmutable en audit_log
create or replace function public._audit(
  p_action text,
  p_entity text,
  p_id text,
  p_detail jsonb default null
) returns void
language sql security definer set search_path = public as $$
  insert into public.audit_log (actor, action, entity, entity_id, detail)
  values (auth.uid(), p_action, p_entity, p_id, p_detail);
$$;

-- Genera código de ticket TS-XXXX-XXXX sin caracteres ambiguos (0/O, 1/I/L)
create or replace function public._gen_ticket_code() returns text
language plpgsql volatile set search_path = public, extensions as $$
declare
  alphabet constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  bytes bytea := gen_random_bytes(8);
  out text := '';
begin
  for i in 0..7 loop
    out := out || substr(alphabet, (get_byte(bytes, i) % length(alphabet)) + 1, 1);
  end loop;
  return 'TS-' || substr(out, 1, 4) || '-' || substr(out, 5, 4);
end;
$$;

-- Enmascara DNI para privacidad visual (ej. '***5678')
create or replace function public._mask_dni(p_dni text) returns text
language sql immutable as $$
  select case
    when char_length(coalesce(p_dni, '')) <= 4 then '****'
    else '***' || right(p_dni, 4)
  end;
$$;

-- Calcula estado canónico de un token QR ('used', 'revoked', 'expired', 'active')
create or replace function public._token_status(
  p_used_at timestamptz,
  p_revoked_at timestamptz,
  p_expires_at timestamptz
) returns text
language sql stable as $$
  select case
    when p_used_at is not null then 'used'
    when p_revoked_at is not null then 'revoked'
    when p_expires_at <= now() then 'expired'
    else 'active'
  end;
$$;

-- Resumen estructurado del progreso y ticket del participante
create or replace function public._progress(p_participant uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'stamp_count', (select count(*)::int from public.stamps where participant_id = p_participant),
    'target',      (select stamps_target from public.event_settings where id = 1),
    'completed',   (select completed_at is not null from public.participants where id = p_participant),
    'ticket',      (
      select jsonb_build_object(
        'code', w.ticket_code,
        'position', w.position,
        'status', w.status,
        'created_at', w.created_at,
        'delivered_at', w.delivered_at
      )
      from public.winners w where w.participant_id = p_participant
    )
  );
$$;

-- ------------------------------------------------------------------------------
-- 2. FUNCIONES PÚBLICAS Y DE PARTICIPANTE (/pasaporte)
-- ------------------------------------------------------------------------------

-- Estado público del juego y reloj oficial del servidor
create or replace function public.get_public_status() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_set public.event_settings;
begin
  select * into v_set from public.event_settings where id = 1;
  return jsonb_build_object(
    'ok', true,
    'game_status', v_set.game_status,
    'stamps_target', v_set.stamps_target,
    'prize_cap', v_set.prize_cap,
    'qr_ttl_seconds', v_set.qr_ttl_seconds,
    'code_ttl_seconds', v_set.code_ttl_seconds,
    'privacy_version', v_set.privacy_version,
    'server_now', now(),
    'server_iso', to_char(now() at time zone 'America/Argentina/Tucuman', 'YYYY-MM-DD"T"HH24:MI:SSOF')
  );
end;
$$;

-- Registro de participante con sesión anónima e idempotencia
create or replace function public.register_participant(
  p_full_name text,
  p_dni text,
  p_whatsapp text,
  p_accepted_version text,
  p_marketing_opt_in boolean default false
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid         uuid := auth.uid();
  v_set         public.event_settings;
  v_dni_clean   text;
  v_name_clean  text;
  v_wa_clean    text;
  v_participant public.participants;
begin
  if v_uid is null then
    raise exception 'forbidden: session required' using errcode = '42501';
  end if;

  select * into v_participant from public.participants where auth_user_id = v_uid;
  if found then
    return jsonb_build_object(
      'ok', true,
      'participant_id', v_participant.id,
      'idempotent', true
    ) || _progress(v_participant.id);
  end if;

  select * into v_set from public.event_settings where id = 1;
  if coalesce(p_accepted_version, '') <> v_set.privacy_version then
    return jsonb_build_object('ok', false, 'error', 'privacy_outdated');
  end if;

  v_name_clean := trim(regexp_replace(coalesce(p_full_name, ''), '\s+', ' ', 'g'));
  if char_length(v_name_clean) < 3 or char_length(v_name_clean) > 80 then
    return jsonb_build_object('ok', false, 'error', 'invalid_name');
  end if;

  v_dni_clean := regexp_replace(coalesce(p_dni, ''), '\D', '', 'g');
  if not (v_dni_clean ~ '^[0-9]{7,9}$') then
    return jsonb_build_object('ok', false, 'error', 'invalid_dni');
  end if;

  v_wa_clean := trim(coalesce(p_whatsapp, ''));
  if char_length(regexp_replace(v_wa_clean, '\D', '', 'g')) < 8 then
    return jsonb_build_object('ok', false, 'error', 'invalid_whatsapp');
  end if;

  if exists (select 1 from public.participants where dni = v_dni_clean) then
    return jsonb_build_object('ok', false, 'error', 'dni_already_registered');
  end if;

  insert into public.participants (
    auth_user_id, full_name, dni, whatsapp, privacy_version, marketing_opt_in
  ) values (
    v_uid, v_name_clean, v_dni_clean, v_wa_clean, p_accepted_version, coalesce(p_marketing_opt_in, false)
  ) returning * into v_participant;

  perform _audit('participant_registered', 'participant', v_participant.id::text,
    jsonb_build_object('dni_masked', _mask_dni(v_dni_clean))
  );

  return jsonb_build_object('ok', true, 'participant_id', v_participant.id) || _progress(v_participant.id);
end;
$$;

-- Recuperación de sesión anónima vía DNI + últimos 10 dígitos de WhatsApp
create or replace function public.recover_session(
  p_dni text,
  p_whatsapp text
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid       uuid := auth.uid();
  v_dni_clean text := regexp_replace(coalesce(p_dni, ''), '\D', '', 'g');
  v_wa_norm   text := right(regexp_replace(coalesce(p_whatsapp, ''), '\D', '', 'g'), 10);
  v_p         public.participants;
begin
  if v_uid is null then
    raise exception 'forbidden: session required' using errcode = '42501';
  end if;

  if (
    select count(*) from public.attempts
    where kind = 'recover' and key = v_uid::text and at > now() - interval '10 minutes'
  ) >= 5 or (
    select count(*) from public.attempts
    where kind = 'recover_dni' and key = v_dni_clean and at > now() - interval '10 minutes'
  ) >= 10 then
    return jsonb_build_object('ok', false, 'error', 'too_many_attempts');
  end if;

  insert into public.attempts (kind, key) values ('recover', v_uid::text), ('recover_dni', v_dni_clean);

  select * into v_p from public.participants
  where dni = v_dni_clean and whatsapp_norm = v_wa_norm;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;

  update public.participants set auth_user_id = v_uid where id = v_p.id;

  perform _audit('session_recovered', 'participant', v_p.id::text,
    jsonb_build_object('dni_masked', _mask_dni(v_dni_clean))
  );

  return jsonb_build_object('ok', true, 'participant_id', v_p.id) || _progress(v_p.id);
end;
$$;

-- Obtiene la libreta y sellos acreditados del participante actual
create or replace function public.get_my_passport() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_uid    uuid := auth.uid();
  v_p      public.participants;
  v_stamps jsonb;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'error', 'unauthenticated');
  end if;

  select * into v_p from public.participants where auth_user_id = v_uid;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'not_registered');
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'stand_id', s.id,
      'stand_number', s.number,
      'stand_name', s.name,
      'stand_category', s.category,
      'stamped_at', st.created_at,
      'method', st.method
    ) order by st.created_at asc
  ), '[]'::jsonb)
  into v_stamps
  from public.stamps st
  join public.stands s on s.id = st.stand_id
  where st.participant_id = v_p.id;

  return jsonb_build_object(
    'ok', true,
    'participant', jsonb_build_object(
      'id', v_p.id,
      'full_name', v_p.full_name,
      'dni_masked', _mask_dni(v_p.dni),
      'whatsapp', v_p.whatsapp
    ),
    'stamps', v_stamps
  ) || _progress(v_p.id);
end;
$$;

-- Generación de código numérico temporal de 6 dígitos (contingencia sin cámara)
create or replace function public.participant_generate_code() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid  uuid := auth.uid();
  v_p    public.participants;
  v_set  public.event_settings;
  v_code text;
  v_exp  timestamptz;
begin
  if v_uid is null then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  select * into v_p from public.participants where auth_user_id = v_uid;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'not_registered');
  end if;

  select * into v_set from public.event_settings where id = 1;
  if v_set.game_status <> 'open' then
    return jsonb_build_object('ok', false, 'error', 'game_not_open');
  end if;

  delete from public.numeric_codes where participant_id = v_p.id and used_at is null;
  v_exp := now() + make_interval(secs => v_set.code_ttl_seconds);

  for i in 1..5 loop
    v_code := lpad(floor(random() * 1000000)::text, 6, '0');
    begin
      insert into public.numeric_codes (code, participant_id, expires_at)
      values (v_code, v_p.id, v_exp);
      exit;
    exception when unique_violation then
      if i = 5 then
        return jsonb_build_object('ok', false, 'error', 'server_busy');
      end if;
    end;
  end loop;

  return jsonb_build_object('ok', true, 'code', v_code, 'expires_at', v_exp, 'server_now', now());
end;
$$;
