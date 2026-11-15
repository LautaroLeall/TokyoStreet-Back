# Esquema de Base de Datos y Contrato RPC — Tokyo Street

Referencia viva del modelo definido en [`doc/md/03_BASE_DE_DATOS_Y_SEGURIDAD.md`](file:///F:/LLDP/VISUAL%20CODE%20STUDIO/TokyoStreet/doc/md/03_BASE_DE_DATOS_Y_SEGURIDAD.md).

## 1. Tablas del Esquema `public` (`0001_schema_base.sql`)

| Tabla            | Rol en el sistema                                                             | Restricciones clave                                              |
| ---------------- | ----------------------------------------------------------------------------- | ---------------------------------------------------------------- |
| `event_settings` | Fila única (`id = 1`) con cupo, estado (`paused`/`open`/`closed`) y vigencias | `CHECK (id = 1)`, bloqueo `FOR UPDATE` al asignar premios        |
| `stands`         | Nómina de hasta 70 puestos del festival                                       | `number UNIQUE`, estado `active` / `disabled`                    |
| `staff_roles`    | Vínculo `auth.users` → rol (`org` o `stand`)                                  | `CHECK ((role = 'stand') = (stand_id IS NOT NULL))`              |
| `participants`   | Asistentes registrados en el Pasaporte                                        | `dni UNIQUE`, `auth_user_id UNIQUE`, `whatsapp_norm` generado    |
| `qr_tokens`      | Tokens dinámicos de un solo uso emitidos por stands                           | Guarda únicamente `token_hash` (SHA-256), nunca el valor crudo   |
| `numeric_codes`  | Códigos temporales de 6 dígitos cuando falla la cámara                        | Índice parcial `UNIQUE (code) WHERE used_at IS NULL`             |
| `stamps`         | Sellos acreditados por participante y stand                                   | `UNIQUE (participant_id, stand_id)`                              |
| `winners`        | Tickets ganadores emitidos dentro del cupo                                    | `participant_id UNIQUE`, `ticket_code UNIQUE`, `position UNIQUE` |
| `attempts`       | Control anti-fuerza bruta en recuperación y códigos                           | Índice `(kind, key, at DESC)`                                    |
| `audit_log`      | Trazabilidad inmutable de acciones sensibles                                  | Solo inserción desde funciones internas `_audit`                 |

## 2. Arquitectura Modular de Funciones RPC y Seguridad

Todas las funciones públicas devuelven `jsonb` con `{ ok: boolean, error?: string, ... }` y están divididas por dominio en archivos de menos de 300 líneas:

- **`0002_participant_functions.sql` (Helpers y Participante):**
  - Helpers internos: `is_org`, `my_stand_id`, `_require_org`, `_require_stand`, `_audit`, `_gen_ticket_code`, `_mask_dni`, `_token_status`, `_progress`.
  - RPCs Públicas / Participante: `get_public_status`, `register_participant`, `recover_session`, `get_my_passport`, `participant_generate_code`.
- **`0003_stand_functions.sql` (Acreditación y Feriantes):**
  - Núcleo transaccional: `_credit_stamp` (bloqueo `FOR UPDATE`) y `redeem_qr` (canje idempotente en `/s/:token`).
  - RPCs de Feriante (`stand`): `stand_generate_qr`, `stand_check_token`, `stand_credit_by_code`, `stand_get_summary`.
- **`0004_org_functions.sql` (Panel de Organización):**
  - RPCs de Organización (`org`): `org_get_dashboard`, `org_list_stands`, `org_upsert_stand`, `org_import_stands`, `org_set_stand_status`, `org_list_tokens`, `org_revoke_token`, `org_list_winners`, `org_verify_ticket`, `org_mark_delivered`, `org_update_settings`.
- **`0005_security_rls.sql` (Seguridad y Permisos):**
  - `ENABLE` + `FORCE ROW LEVEL SECURITY` en las 10 tablas, revocación de escritura directa REST y `GRANT EXECUTE` quirúrgico.
- **Edge Function Administrativa (`supabase/functions/admin-create-stand-users`):**
  - Aprovisionamiento y reseteo en lote de `stand01..stand70@tokyostreet.com.ar` y revocación de sesión activa.
