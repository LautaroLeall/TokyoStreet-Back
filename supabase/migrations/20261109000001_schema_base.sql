-- ==============================================================================
-- TOKYO STREET 3.ª EDICIÓN — MIGRACIÓN 001: ESQUEMA BASE (10 TABLAS)
-- ==============================================================================
-- Archivo: 20261109000001_schema_base.sql
-- Épica: E3-1 (Base de datos, tipos, restricciones y auditoría)
-- ==============================================================================

-- 1. Extensiones requeridas
create extension if not exists pgcrypto with schema extensions;

-- 2. Tipos enumerados de dominio
create type public.stand_status  as enum ('active', 'disabled');
create type public.game_status   as enum ('paused', 'open', 'closed');
create type public.ticket_status as enum ('pending', 'delivered');

-- 3. Tabla única de configuración del evento
create table public.event_settings (
  id               smallint primary key default 1 check (id = 1),
  event_name       text        not null default 'Tokyo Street — 3.ª edición',
  stamps_target    int         not null default 15 check (stamps_target > 0),
  prize_cap        int         not null default 50 check (prize_cap >= 0),
  game_status      public.game_status not null default 'paused',
  qr_ttl_seconds   int         not null default 75 check (qr_ttl_seconds between 30 and 300),
  code_ttl_seconds int         not null default 60 check (code_ttl_seconds between 30 and 300),
  privacy_version  text        not null default 'v1',
  updated_at       timestamptz not null default now(),
  updated_by       uuid        references auth.users(id) on delete set null
);

-- Fila singleton obligatoria
insert into public.event_settings (id) values (1) on conflict (id) do nothing;

-- 4. Puestos y stands participantes del festival
create table public.stands (
  id           serial primary key,
  number       int  not null unique check (number > 0),
  name         text not null check (char_length(trim(name)) between 2 and 100),
  category     text check (category is null or char_length(category) <= 50),
  contact_name text check (contact_name is null or char_length(contact_name) <= 100),
  status       public.stand_status not null default 'active',
  created_at   timestamptz not null default now()
);

-- 5. Roles de personal (staff_roles: vincula auth.users con 'org' o 'stand')
create table public.staff_roles (
  user_id  uuid primary key references auth.users(id) on delete cascade,
  role     text not null check (role in ('org', 'stand')),
  stand_id int  unique references public.stands(id) on delete set null,
  check ((role = 'stand') = (stand_id is not null))
);

-- 6. Participantes registrados en el Pasaporte Digital
create table public.participants (
  id                  uuid primary key default gen_random_uuid(),
  auth_user_id        uuid not null unique references auth.users(id) on delete cascade,
  full_name           text not null check (char_length(trim(full_name)) between 3 and 80),
  dni                 text not null unique check (dni ~ '^[0-9]{7,9}$'),
  whatsapp            text not null check (char_length(whatsapp) >= 8),
  whatsapp_norm       text generated always as (right(regexp_replace(whatsapp, '\D', '', 'g'), 10)) stored,
  privacy_version     text not null,
  privacy_accepted_at timestamptz not null default now(),
  marketing_opt_in    boolean not null default false,
  completed_at        timestamptz,
  created_at          timestamptz not null default now()
);

create index idx_participants_dni on public.participants (dni);
create index idx_participants_whatsapp_norm on public.participants (whatsapp_norm);
create index idx_participants_completed on public.participants (completed_at) where completed_at is not null;

-- 7. Tokens QR dinámicos de un solo uso
create table public.qr_tokens (
  id             uuid primary key default gen_random_uuid(),
  token_hash     text not null unique,
  stand_id       int  not null references public.stands(id) on delete cascade,
  created_by     uuid references auth.users(id) on delete set null,
  created_at     timestamptz not null default now(),
  expires_at     timestamptz not null,
  used_at        timestamptz,
  used_by        uuid references public.participants(id) on delete set null,
  revoked_at     timestamptz,
  revoked_reason text check (revoked_reason is null or revoked_reason in ('superseded', 'org'))
);

create index idx_qr_tokens_stand on public.qr_tokens (stand_id, created_at desc);
create index idx_qr_tokens_lookup on public.qr_tokens (token_hash);
create index idx_qr_tokens_active on public.qr_tokens (stand_id) where used_at is null and revoked_at is null;

-- 8. Códigos numéricos de 6 dígitos (contingencia sin cámara)
create table public.numeric_codes (
  id             uuid primary key default gen_random_uuid(),
  code           text not null check (code ~ '^[0-9]{6}$'),
  participant_id uuid not null references public.participants(id) on delete cascade,
  created_at     timestamptz not null default now(),
  expires_at     timestamptz not null,
  used_at        timestamptz
);

create unique index idx_numeric_codes_live on public.numeric_codes (code) where used_at is null;
create index idx_numeric_codes_participant on public.numeric_codes (participant_id, created_at desc);

-- 9. Sellos acreditados por participante y stand
create table public.stamps (
  id             bigserial primary key,
  participant_id uuid not null references public.participants(id) on delete cascade,
  stand_id       int  not null references public.stands(id) on delete cascade,
  token_id       uuid references public.qr_tokens(id) on delete set null,
  method         text not null check (method in ('qr', 'code')),
  created_at     timestamptz not null default now(),
  unique (participant_id, stand_id)
);

create index idx_stamps_stand on public.stamps (stand_id, created_at desc);
create index idx_stamps_participant on public.stamps (participant_id, created_at desc);

-- 10. Ganadores de Ticket de Premio
create table public.winners (
  id             bigserial primary key,
  participant_id uuid not null unique references public.participants(id) on delete cascade,
  ticket_code    text not null unique check (ticket_code ~ '^TS-[A-Z0-9]{4}-[A-Z0-9]{4}$'),
  position       int  not null unique check (position > 0),
  status         public.ticket_status not null default 'pending',
  created_at     timestamptz not null default now(),
  delivered_at   timestamptz,
  delivered_by   uuid references auth.users(id) on delete set null,
  check ((status = 'delivered') = (delivered_at is not null))
);

create index idx_winners_ticket_code on public.winners (ticket_code);
create index idx_winners_status on public.winners (status, created_at desc);

-- 11. Control de intentos y protección anti-fuerza bruta
create table public.attempts (
  id   bigserial primary key,
  kind text not null,
  key  text not null,
  at   timestamptz not null default now()
);

create index idx_attempts_rate on public.attempts (kind, key, at desc);

-- 12. Registro de auditoría inmutable
create table public.audit_log (
  id        bigserial primary key,
  at        timestamptz not null default now(),
  actor     uuid references auth.users(id) on delete set null,
  action    text not null,
  entity    text,
  entity_id text,
  detail    jsonb
);

create index idx_audit_log_action on public.audit_log (action, at desc);
