-- ==============================================================================
-- TOKYO STREET 3.ª EDICIÓN — MIGRACIÓN 004: RPCs DEL PANEL DE ORGANIZACIÓN
-- ==============================================================================
-- Archivo: 20261109000004_org_functions.sql
-- Épica: E3-6 y E6 (Mesa, control global, gestión/CSV de stands y ganadores)
-- ==============================================================================

-- 1. Dashboard general de métricas en tiempo real para la organización
create or replace function public.org_get_dashboard() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform public._require_org();

  return jsonb_build_object(
    'ok', true,
    'participants',      (select count(*)::int from public.participants),
    'stamps',            (select count(*)::int from public.stamps),
    'active_stands',     (select count(*)::int from public.stands where status = 'active'),
    'completed',         (select count(*)::int from public.participants where completed_at is not null),
    'tickets_pending',   (select count(*)::int from public.winners where status = 'pending'),
    'tickets_delivered', (select count(*)::int from public.winners where status = 'delivered'),
    'prize_cap',         (select prize_cap from public.event_settings where id = 1),
    'game_status',       (select game_status from public.event_settings where id = 1),
    'last_stamp_at',     (select max(created_at) from public.stamps),
    'tokens', jsonb_build_object(
      'generated', (select count(*)::int from public.qr_tokens),
      'used',      (select count(*)::int from public.qr_tokens where used_at is not null),
      'expired',   (select count(*)::int from public.qr_tokens where used_at is null and revoked_at is null and expires_at <= now()),
      'revoked',   (select count(*)::int from public.qr_tokens where revoked_at is not null)
    )
  );
end;
$$;

-- 2. Listado completo de stands con sellos y participantes únicos
create or replace function public.org_list_stands() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform public._require_org();

  return jsonb_build_object(
    'ok', true,
    'stands', (
      select coalesce(jsonb_agg(
        jsonb_build_object(
          'id', s.id,
          'number', s.number,
          'name', s.name,
          'category', s.category,
          'contact_name', s.contact_name,
          'status', s.status,
          'created_at', s.created_at,
          'stamps_count', count(st.id)::int,
          'unique_participants', count(distinct st.participant_id)::int
        ) order by s.number asc
      ), '[]'::jsonb)
      from public.stands s
      left join public.stamps st on st.stand_id = s.id
      group by s.id
    )
  );
end;
$$;

-- 3. Alta o edición individual de un stand desde /org
create or replace function public.org_upsert_stand(
  p_id int default null,
  p_number int default null,
  p_name text default null,
  p_category text default null,
  p_contact_name text default null,
  p_status public.stand_status default 'active'
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_res public.stands;
begin
  perform public._require_org();

  if p_id is null then
    insert into public.stands (number, name, category, contact_name, status)
    values (p_number, trim(p_name), trim(p_category), trim(p_contact_name), coalesce(p_status, 'active'))
    returning * into v_res;
    perform _audit('stand_created', 'stand', v_res.id::text);
  else
    update public.stands
    set number       = coalesce(p_number, number),
        name         = coalesce(trim(p_name), name),
        category     = coalesce(trim(p_category), category),
        contact_name = coalesce(trim(p_contact_name), contact_name),
        status       = coalesce(p_status, status)
    where id = p_id
    returning * into v_res;
    perform _audit('stand_updated', 'stand', v_res.id::text);
  end if;

  return jsonb_build_object('ok', true, 'stand', row_to_json(v_res));
end;
$$;

-- 4. Importación masiva de stands por CSV (JSONB array de {number, name, category, contact_name})
create or replace function public.org_import_stands(p_rows jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_row   jsonb;
  v_num   int;
  v_name  text;
  v_cat   text;
  v_cont  text;
  v_count int := 0;
begin
  perform public._require_org();

  if jsonb_typeof(p_rows) <> 'array' then
    return jsonb_build_object('ok', false, 'error', 'invalid_payload');
  end if;

  for v_row in select * from jsonb_array_elements(p_rows) loop
    v_num  := (v_row ->> 'number')::int;
    v_name := trim(coalesce(v_row ->> 'name', ''));
    v_cat  := nullif(trim(coalesce(v_row ->> 'category', '')), '');
    v_cont := nullif(trim(coalesce(v_row ->> 'contact_name', '')), '');

    if v_num is not null and v_num > 0 and char_length(v_name) >= 2 then
      insert into public.stands (number, name, category, contact_name, status)
      values (v_num, v_name, v_cat, v_cont, 'active')
      on conflict (number) do update
      set name         = excluded.name,
          category     = coalesce(excluded.category, public.stands.category),
          contact_name = coalesce(excluded.contact_name, public.stands.contact_name);

      v_count := v_count + 1;
    end if;
  end loop;

  perform _audit('stands_imported', 'stand', 'bulk', jsonb_build_object('count', v_count));
  return jsonb_build_object('ok', true, 'imported_count', v_count);
end;
$$;

-- 5. Habilitar o deshabilitar un stand en tiempo real
create or replace function public.org_set_stand_status(
  p_id int,
  p_status public.stand_status
) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform public._require_org();

  update public.stands set status = p_status where id = p_id;
  perform _audit('stand_status_changed', 'stand', p_id::text, jsonb_build_object('status', p_status));

  return jsonb_build_object('ok', true, 'stand_id', p_id, 'status', p_status);
end;
$$;

-- 6. Listado y filtro de tokens QR emitidos para supervisión operativa
create or replace function public.org_list_tokens(
  p_limit int default 50,
  p_offset int default 0,
  p_status text default null,
  p_stand_id int default null
) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform public._require_org();

  return jsonb_build_object(
    'ok', true,
    'tokens', (
      select coalesce(jsonb_agg(
        jsonb_build_object(
          'id', t.id,
          'stand_id', t.stand_id,
          'stand_number', s.number,
          'stand_name', s.name,
          'created_at', t.created_at,
          'expires_at', t.expires_at,
          'used_at', t.used_at,
          'revoked_at', t.revoked_at,
          'revoked_reason', t.revoked_reason,
          'status', public._token_status(t.used_at, t.revoked_at, t.expires_at)
        ) order by t.created_at desc
      ), '[]'::jsonb)
      from public.qr_tokens t
      join public.stands s on s.id = t.stand_id
      where (p_stand_id is null or t.stand_id = p_stand_id)
        and (p_status is null or public._token_status(t.used_at, t.revoked_at, t.expires_at) = p_status)
      limit coalesce(p_limit, 50)
      offset coalesce(p_offset, 0)
    )
  );
end;
$$;

-- 7. Revocación manual de un token QR activo
create or replace function public.org_revoke_token(p_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform public._require_org();

  update public.qr_tokens
  set revoked_at = now(), revoked_reason = 'org'
  where id = p_id and revoked_at is null and used_at is null;

  perform _audit('token_revoked', 'qr_token', p_id::text);
  return jsonb_build_object('ok', true, 'token_id', p_id);
end;
$$;

-- 8. Listado de ganadores con DNI enmascarado y WhatsApp para contacto/CSV
create or replace function public.org_list_winners(
  p_limit int default 50,
  p_offset int default 0
) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform public._require_org();

  return jsonb_build_object(
    'ok', true,
    'winners', (
      select coalesce(jsonb_agg(
        jsonb_build_object(
          'id', w.id,
          'position', w.position,
          'ticket_code', w.ticket_code,
          'status', w.status,
          'created_at', w.created_at,
          'delivered_at', w.delivered_at,
          'participant_name', p.full_name,
          'dni_masked', _mask_dni(p.dni),
          'whatsapp', p.whatsapp
        ) order by w.position asc
      ), '[]'::jsonb)
      from public.winners w
      join public.participants p on p.id = w.participant_id
      limit coalesce(p_limit, 50)
      offset coalesce(p_offset, 0)
    )
  );
end;
$$;

-- 9. Verificación de ticket en Mesa 70 (revela DNI completo y registra auditoría)
create or replace function public.org_verify_ticket(p_code text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_w public.winners;
  v_p public.participants;
begin
  perform public._require_org();

  select * into v_w from public.winners where ticket_code = upper(trim(p_code));
  if not found then
    return jsonb_build_object('ok', false, 'error', 'ticket_not_found');
  end if;

  select * into v_p from public.participants where id = v_w.participant_id;
  perform _audit('ticket_verified', 'winner', v_w.ticket_code);

  return jsonb_build_object(
    'ok', true,
    'ticket', jsonb_build_object(
      'code', v_w.ticket_code,
      'position', v_w.position,
      'status', v_w.status,
      'created_at', v_w.created_at,
      'delivered_at', v_w.delivered_at,
      'participant_name', v_p.full_name,
      'dni_full', v_p.dni,
      'whatsapp', v_p.whatsapp
    )
  );
end;
$$;

-- 10. Marcado atómico de premio entregado en Mesa 70 (una sola vez)
create or replace function public.org_mark_delivered(p_code text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_w public.winners;
begin
  perform public._require_org();

  update public.winners
  set status = 'delivered', delivered_at = now(), delivered_by = auth.uid()
  where ticket_code = upper(trim(p_code)) and status = 'pending'
  returning * into v_w;

  if not found then
    if exists (select 1 from public.winners where ticket_code = upper(trim(p_code))) then
      return jsonb_build_object('ok', false, 'error', 'already_delivered');
    end if;
    return jsonb_build_object('ok', false, 'error', 'ticket_not_found');
  end if;

  perform _audit('prize_delivered', 'winner', v_w.ticket_code);
  return jsonb_build_object('ok', true, 'ticket_code', v_w.ticket_code, 'delivered_at', v_w.delivered_at);
end;
$$;

-- 11. Configuración operativa global (estado del juego, cupo prize_cap y vigencias)
create or replace function public.org_update_settings(
  p_prize_cap int default null,
  p_game_status public.game_status default null,
  p_qr_ttl_seconds int default null,
  p_code_ttl_seconds int default null,
  p_stamps_target int default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_set           public.event_settings;
  v_winners_count int;
begin
  perform public._require_org();

  select count(*) into v_winners_count from public.winners;
  if p_prize_cap is not null and p_prize_cap < v_winners_count then
    return jsonb_build_object('ok', false, 'error', 'cap_below_issued_tickets');
  end if;

  update public.event_settings
  set prize_cap        = coalesce(p_prize_cap, prize_cap),
      game_status      = coalesce(p_game_status, game_status),
      qr_ttl_seconds   = coalesce(p_qr_ttl_seconds, qr_ttl_seconds),
      code_ttl_seconds = coalesce(p_code_ttl_seconds, code_ttl_seconds),
      stamps_target    = coalesce(p_stamps_target, stamps_target),
      updated_at       = now(),
      updated_by       = auth.uid()
  where id = 1
  returning * into v_set;

  perform _audit('settings_updated', 'event_settings', '1',
    jsonb_build_object(
      'game_status', v_set.game_status,
      'prize_cap', v_set.prize_cap,
      'stamps_target', v_set.stamps_target
    )
  );

  return jsonb_build_object('ok', true, 'settings', row_to_json(v_set));
end;
$$;
