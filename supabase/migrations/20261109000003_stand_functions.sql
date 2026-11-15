-- ==============================================================================
-- TOKYO STREET 3.ª EDICIÓN — MIGRACIÓN 003: ACREDITACIÓN Y RPCs DE FERIANTES
-- ==============================================================================
-- Archivo: 20261109000003_stand_functions.sql
-- Épica: E3-4 y E3-5 (Núcleo transaccional FOR UPDATE, /s/:token y panel /stand)
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. NÚCLEO TRANSACCIONAL DE ACREDITACIÓN DE SELLOS Y TICKET GANADOR
-- ------------------------------------------------------------------------------

-- Acredita un sello y, al alcanzar el objetivo, asigna ticket bajo bloqueo FOR UPDATE
create or replace function public._credit_stamp(
  p_participant uuid,
  p_stand int,
  p_token uuid,
  p_method text
) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_set   public.event_settings;
  v_count int;
  v_pos   int;
  v_code  text;
  v_prize text := 'none';
begin
  begin
    insert into public.stamps (participant_id, stand_id, token_id, method)
    values (p_participant, p_stand, p_token, p_method);
  exception when unique_violation then
    return jsonb_build_object('ok', false, 'error', 'already_stamped');
  end;

  select count(*) into v_count from public.stamps where participant_id = p_participant;
  select * into v_set from public.event_settings where id = 1;

  if v_count >= v_set.stamps_target then
    update public.participants
    set completed_at = coalesce(completed_at, now())
    where id = p_participant;

    -- Bloqueo exclusivo FOR UPDATE: serializa la emisión dentro del cupo prize_cap
    select * into v_set from public.event_settings where id = 1 for update;

    if exists (select 1 from public.winners where participant_id = p_participant) then
      v_prize := 'won';
    else
      select count(*) into v_pos from public.winners;
      if v_pos < v_set.prize_cap then
        for i in 1..5 loop
          begin
            v_code := _gen_ticket_code();
            insert into public.winners (participant_id, ticket_code, position)
            values (p_participant, v_code, v_pos + 1);
            v_prize := 'won';
            exit;
          exception when unique_violation then
            if exists (select 1 from public.winners where participant_id = p_participant) then
              v_prize := 'won';
              exit;
            end if;
          end;
        end loop;
      else
        v_prize := 'exhausted';
      end if;
    end if;
  end if;

  perform _audit('stamp_credited', 'stamp', p_participant::text,
    jsonb_build_object('stand', p_stand, 'method', p_method, 'count', v_count, 'prize', v_prize)
  );

  return jsonb_build_object(
    'ok', true,
    'prize_status', v_prize,
    'stamp_number', v_count
  ) || _progress(p_participant);
end;
$$;

-- Canje de sello por escaneo de QR desde el celular del comprador (/s/:token)
create or replace function public.redeem_qr(p_token text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_part  public.participants;
  v_set   public.event_settings;
  v_tok   public.qr_tokens;
  v_stand public.stands;
  v_res   jsonb;
begin
  select * into v_part from public.participants where auth_user_id = auth.uid();
  if not found then
    return jsonb_build_object('ok', false, 'error', 'not_registered');
  end if;

  select * into v_set from public.event_settings where id = 1;
  if v_set.game_status <> 'open' then
    return jsonb_build_object('ok', false, 'error', 'game_not_open');
  end if;

  select * into v_tok from public.qr_tokens
  where token_hash = encode(digest(coalesce(p_token, ''), 'sha256'), 'hex')
  for update;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'invalid_code');
  end if;

  if v_tok.revoked_at is not null then
    return jsonb_build_object('ok', false, 'error', 'code_revoked');
  end if;

  if v_tok.used_at is not null then
    if v_tok.used_by = v_part.id then
      select * into v_stand from public.stands where id = v_tok.stand_id;
      return jsonb_build_object(
        'ok', true,
        'idempotent', true,
        'stand', jsonb_build_object('id', v_stand.id, 'number', v_stand.number, 'name', v_stand.name)
      ) || _progress(v_part.id);
    end if;
    return jsonb_build_object('ok', false, 'error', 'code_already_used');
  end if;

  if v_tok.expires_at <= now() then
    return jsonb_build_object('ok', false, 'error', 'code_expired');
  end if;

  select * into v_stand from public.stands where id = v_tok.stand_id;
  if v_stand.status <> 'active' then
    return jsonb_build_object('ok', false, 'error', 'stand_disabled');
  end if;

  v_res := _credit_stamp(v_part.id, v_tok.stand_id, v_tok.id, 'qr');

  if (v_res ->> 'ok')::boolean then
    update public.qr_tokens
    set used_at = now(), used_by = v_part.id
    where id = v_tok.id;

    v_res := v_res || jsonb_build_object(
      'stand', jsonb_build_object('id', v_stand.id, 'number', v_stand.number, 'name', v_stand.name)
    );
  end if;

  return v_res;
end;
$$;

-- ------------------------------------------------------------------------------
-- 2. FUNCIONES DEL PANEL DE FERIANTE (/stand)
-- ------------------------------------------------------------------------------

-- Generación de QR dinámico para el stand (75 s de vigencia, control anti-ráfaga)
create or replace function public.stand_generate_qr() returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_stand_id int := public._require_stand();
  v_stand    public.stands;
  v_set      public.event_settings;
  v_raw      text;
  v_exp      timestamptz;
begin
  select * into v_stand from public.stands where id = v_stand_id;
  if v_stand.status <> 'active' then
    return jsonb_build_object('ok', false, 'error', 'stand_disabled');
  end if;

  select * into v_set from public.event_settings where id = 1;
  if v_set.game_status <> 'open' then
    return jsonb_build_object('ok', false, 'error', 'game_not_open');
  end if;

  if exists (
    select 1 from public.qr_tokens
    where stand_id = v_stand_id and created_at > now() - interval '2 seconds'
  ) then
    return jsonb_build_object('ok', false, 'error', 'too_fast');
  end if;

  update public.qr_tokens
  set revoked_at = now(), revoked_reason = 'superseded'
  where stand_id = v_stand_id and used_at is null and revoked_at is null and expires_at > now();

  v_raw := translate(encode(gen_random_bytes(18), 'base64'), '+/=', '-_');
  v_exp := now() + make_interval(secs => v_set.qr_ttl_seconds);

  insert into public.qr_tokens (token_hash, stand_id, created_by, expires_at)
  values (encode(digest(v_raw, 'sha256'), 'hex'), v_stand_id, auth.uid(), v_exp);

  return jsonb_build_object(
    'ok', true,
    'token', v_raw,
    'expires_at', v_exp,
    'server_now', now(),
    'stand', jsonb_build_object('id', v_stand.id, 'number', v_stand.number, 'name', v_stand.name)
  );
end;
$$;

-- Sondeo ligero del estado del QR activo del stand (usado / vigente / vencido / revocado)
create or replace function public.stand_check_token(p_token text) returns jsonb
language plpgsql stable security definer set search_path = public, extensions as $$
declare
  v_stand_id int := public._require_stand();
  v_tok      public.qr_tokens;
begin
  select * into v_tok from public.qr_tokens
  where stand_id = v_stand_id
    and token_hash = encode(digest(coalesce(p_token, ''), 'sha256'), 'hex');

  if not found then
    return jsonb_build_object('ok', false, 'error', 'invalid_code');
  end if;

  return jsonb_build_object(
    'ok', true,
    'status', public._token_status(v_tok.used_at, v_tok.revoked_at, v_tok.expires_at),
    'used_at', v_tok.used_at,
    'expires_at', v_tok.expires_at,
    'server_now', now()
  );
end;
$$;

-- Acreditación contingente por código numérico de 6 dígitos ingresado por el feriante
create or replace function public.stand_credit_by_code(p_code text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_stand_id   int := public._require_stand();
  v_stand      public.stands;
  v_set        public.event_settings;
  v_code_clean text := regexp_replace(coalesce(p_code, ''), '\D', '', 'g');
  v_nc         public.numeric_codes;
  v_res        jsonb;
begin
  select * into v_stand from public.stands where id = v_stand_id;
  if v_stand.status <> 'active' then
    return jsonb_build_object('ok', false, 'error', 'stand_disabled');
  end if;

  select * into v_set from public.event_settings where id = 1;
  if v_set.game_status <> 'open' then
    return jsonb_build_object('ok', false, 'error', 'game_not_open');
  end if;

  if (
    select count(*) from public.attempts
    where kind = 'code_guess' and key = v_stand_id::text and at > now() - interval '5 minutes'
  ) >= 10 then
    return jsonb_build_object('ok', false, 'error', 'too_many_attempts');
  end if;

  select * into v_nc from public.numeric_codes
  where code = v_code_clean and used_at is null
  for update;

  if not found or v_nc.expires_at <= now() then
    insert into public.attempts (kind, key) values ('code_guess', v_stand_id::text);
    return jsonb_build_object('ok', false, 'error', 'invalid_code');
  end if;

  v_res := _credit_stamp(v_nc.participant_id, v_stand_id, null, 'code');

  if (v_res ->> 'ok')::boolean then
    update public.numeric_codes set used_at = now() where id = v_nc.id;
  end if;

  return v_res;
end;
$$;

-- Resumen de actividad del stand sin exponer datos personales de participantes
create or replace function public.stand_get_summary() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_stand_id     int := public._require_stand();
  v_stand        public.stands;
  v_stamps_total int;
  v_unique_parts int;
  v_last_stamp   timestamptz;
  v_history      jsonb;
begin
  select * into v_stand from public.stands where id = v_stand_id;
  select count(*)::int, count(distinct participant_id)::int, max(created_at)
  into v_stamps_total, v_unique_parts, v_last_stamp
  from public.stamps
  where stand_id = v_stand_id;

  select coalesce(jsonb_agg(
    jsonb_build_object('created_at', created_at, 'method', method) order by created_at desc
  ), '[]'::jsonb)
  into v_history
  from (
    select created_at, method
    from public.stamps
    where stand_id = v_stand_id
    order by created_at desc
    limit 10
  ) h;

  return jsonb_build_object(
    'ok', true,
    'stand', jsonb_build_object(
      'id', v_stand.id,
      'number', v_stand.number,
      'name', v_stand.name,
      'category', v_stand.category,
      'status', v_stand.status
    ),
    'stamps_count', v_stamps_total,
    'unique_participants', v_unique_parts,
    'last_stamp_at', v_last_stamp,
    'recent_activity', v_history
  );
end;
$$;
