# Políticas RLS y Seguridad — Tokyo Street

## Principio de Autoridad Única

1. **Cero acceso directo a tablas:** Todas las tablas del esquema `public` tienen `ENABLE ROW LEVEL SECURITY` **sin políticas permisivas** y con `REVOKE ALL` para `anon` y `authenticated`. Ningún cliente puede hacer `SELECT`, `INSERT`, `UPDATE` ni `DELETE` por REST directo.
2. **Ejecución exclusiva por RPC (`SECURITY DEFINER`):** Solo se otorga `GRANT EXECUTE` sobre las funciones de negocio expuestas, cada una con `SET search_path = public, extensions` fijo.
3. **Validación explícita de rol dentro de cada RPC:** Como las sesiones anónimas de Supabase operan bajo el rol PostgreSQL `authenticated`, cada función verifica internamente `is_org()`, `my_stand_id()` o la pertenencia de `participants.auth_user_id = auth.uid()`.

## Privacidad de Datos Personales

- **Feriantes (`stand`):** Nunca reciben nombre, DNI ni WhatsApp de ningún participante. Solo consultan conteos agregados (`sellos acreditados`, `participantes únicos`) e historial anónimo de su propio puesto.
- **Participantes:** Solo ven su propio progreso y su ticket con DNI parcialmente enmascarado (`***1234`).
- **Organización (`org`):** Listados generales con DNI enmascarado por defecto; el DNI completo solo se revela en `org_verify_ticket(code)` al validar la entrega física del premio, dejando registro en `audit_log`.
