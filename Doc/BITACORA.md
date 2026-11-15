# Bitácora de Desarrollo — Backend Tokyo Street

Registro cronológico de inicialización, migraciones SQL, políticas de seguridad, Edge Functions y pruebas del servidor.

---

## [2026-11-15] — Modularización y Simplificación Integral de Migraciones SQL (< 300 líneas por archivo)

- **División Modular por Dominio de Negocio (`supabase/migrations/`)**:
  - Se reemplazó el archivo monolítico de funciones por **3 migraciones especializadas y desacopladas**, manteniendo **todos los archivos del repositorio por debajo de las 300 líneas**:
    1. `20261109000001_schema_base.sql` (153 líneas): Extensiones, enums, 10 tablas e índices.
    2. `20261109000002_participant_functions.sql` (268 líneas): Helpers internos reutilizables (`is_org`, `my_stand_id`, `_require_org`, `_require_stand`, `_audit`, `_gen_ticket_code`, `_mask_dni`, `_token_status`, `_progress`) y RPCs de `/pasaporte` (`get_public_status`, `register_participant`, `recover_session`, `get_my_passport`, `participant_generate_code`).
    3. `20261109000003_stand_functions.sql` (248 líneas): Núcleo transaccional `_credit_stamp` (con `FOR UPDATE`), canje `redeem_qr` (`/s/:token`) y RPCs del panel `/stand` (`stand_generate_qr`, `stand_check_token`, `stand_credit_by_code`, `stand_get_summary`).
    4. `20261109000004_org_functions.sql` (267 líneas): Las 11 RPCs administrativas del panel `/org` simplificadas mediante `_require_org()` y `_token_status()`.
    5. `20261109000005_security_rls.sql` (167 líneas): Políticas RLS forzadas (`FORCE ROW LEVEL SECURITY`), revocación de helpers internos y `GRANT EXECUTE` explícitos.
- **Limpieza de Archivos Redundantes**:
  - Eliminación de placeholders vacíos (`.gitkeep`) y unificación del índice documental en el `README.md` raíz.

---

## [2026-11-14] — Fase 2 (Épicas E3, E5 y E6): Blindaje RLS, Nuevas RPCs Operativas y Edge Function `admin-create-stand-users`

- **Seguridad y Blindaje RLS**:
  - Ajuste de firma en `REVOKE EXECUTE ON FUNCTION public._credit_stamp(uuid, int, uuid, text)` alineada con los 4 parámetros de acreditación.
  - Alineación de políticas RLS en `participants`, `stamps`, `winners` y `numeric_codes` utilizando `auth_user_id = auth.uid()`, garantizando aislamiento estricto de sesión anónima.
  - Permisos `GRANT EXECUTE` añadidos para `stand_check_token` y `org_import_stands`.
- **Nuevas Funciones RPC Operativas**:
  - `stand_check_token(p_token text)`: Permite al panel `/stand` consultar cada 3.5 s si el QR activo ya fue consumido (`used`), venció (`expired`) o fue revocado (`revoked`), disparando el aviso `"✔ Sello acreditado"`.
  - `org_import_stands(p_rows jsonb)`: Permite importar o actualizar masivamente el catálogo de hasta 70 stands desde un CSV en `/org`.
  - Inclusión del campo `whatsapp` en `org_list_winners` para facilitar la exportación CSV desde organización.
- **Edge Function Administrativa (`supabase/functions/admin-create-stand-users/index.ts` — Épica E6-5)**:
  - Verificación de JWT del invocador y comprobación obligatoria de rol `'org'` en `public.staff_roles`.
  - Aprovisionamiento en lote (`provision_batch`) y restablecimiento de contraseñas para hasta 70 cuentas de stands (`stand01@tokyostreet.com.ar` … `stand70@tokyostreet.com.ar`) con contraseñas legibles (`TS3-XXXXXXXX`).
  - Soporte para revocación inmediata de acceso (`revoke_access`) y registro inmutable en `audit_log`.

---

## [2026-11-09] — Fase 2 (Épica E3): Esquema Base, Concurrencia FOR UPDATE y Seed de 70 Stands

- **Esquema Relacional (`20261109000001_schema_base.sql`)**:
  - Extensión `pgcrypto` y enums `stand_status` (`active`, `disabled`), `game_status` (`paused`, `open`, `closed`), `ticket_status` (`pending`, `delivered`).
  - Creación de las 10 tablas (`event_settings`, `stands`, `staff_roles`, `participants`, `qr_tokens`, `numeric_codes`, `stamps`, `winners`, `attempts`, `audit_log`) e índices de alto rendimiento.
- **Lógica Transaccional y Semilla (`seed.sql`)**:
  - Bloqueo transaccional `select * from public.event_settings where id = 1 for update` al sellar el sello número 15 para evitar condiciones de carrera sobre `prize_cap`.
  - Carga inicial de los 70 stands oficiales distribuidos por rubro, incluyendo el Stand 70 ("Tokyo Street Centro de Informes & Sello Bonus").

---

## [2026-11-07] — Fase 1 (Épica E0): Inicialización y Estructura Base

- **Separación de repositorios**: Inicialización limpia de `Backend/` (`https://github.com/LautaroLeall/TokyoStreet-Back.git`, rama `LautyGod`) independiente de `Frontend/`.
- **Blindaje de secretos y CLI (`supabase/config.toml`)**: Exclusión estricta de `.env*` en `.gitignore`, habilitación de `enable_anonymous_sign_ins = true` y desactivación de `enable_signup` libre para cuentas de staff.
