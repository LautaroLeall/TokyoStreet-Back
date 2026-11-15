// ==============================================================================
// TOKYO STREET 3.ª EDICIÓN — EDGE FUNCTION: admin-create-stand-users (Épica E6-5)
// ==============================================================================
// Descripción:
//   1. Verifica que el usuario autenticado tenga rol 'org' en public.staff_roles.
//   2. Permite crear en lote (hasta 70 cuentas), restablecer contraseña o revocar
//      acceso de los usuarios de stands usando SUPABASE_SERVICE_ROLE_KEY.
//   3. Devuelve por única vez las credenciales generadas para descarga CSV o
//      impresión de tarjetas A6 de feriantes.
// ==============================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function generateReadablePassword(length = 10): string {
  const alphabet = "ABCDEFGHJKMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789";
  const bytes = new Uint8Array(length);
  crypto.getRandomValues(bytes);
  let out = "TS3-";
  for (let i = 0; i < length; i++) {
    out += alphabet[bytes[i] % alphabet.length];
  }
  return out;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const authHeader = req.headers.get("Authorization") ?? "";

    if (!supabaseUrl || !serviceRoleKey) {
      return new Response(
        JSON.stringify({ ok: false, error: "missing_env_vars" }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const adminClient = createClient(supabaseUrl, serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    // 1. Validar identidad del invocador mediante su JWT
    const token = authHeader.replace(/^Bearer\s+/i, "").trim();
    if (!token) {
      return new Response(
        JSON.stringify({ ok: false, error: "unauthorized" }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const { data: userData, error: userErr } =
      await adminClient.auth.getUser(token);
    if (userErr || !userData?.user) {
      return new Response(
        JSON.stringify({ ok: false, error: "invalid_token" }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const callerId = userData.user.id;

    // 2. Verificar que posea rol 'org' en public.staff_roles
    const { data: roleRow, error: roleErr } = await adminClient
      .from("staff_roles")
      .select("role")
      .eq("user_id", callerId)
      .maybeSingle();

    if (roleErr || roleRow?.role !== "org") {
      return new Response(
        JSON.stringify({ ok: false, error: "forbidden_org_only" }),
        {
          status: 403,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // 3. Procesar solicitud
    const body = await req.json().catch(() => ({}));
    const action = body.action || "provision_batch";
    const standNumbers: number[] = Array.isArray(body.stand_numbers)
      ? body.stand_numbers
      : [];

    // Obtener stands objetivo (límite contractual: hasta 70 puestos)
    let standsQuery = adminClient
      .from("stands")
      .select("id, number, name, category, status")
      .order("number", { ascending: true })
      .limit(70);

    if (standNumbers.length > 0) {
      standsQuery = standsQuery.in("number", standNumbers);
    }

    const { data: stands, error: standsErr } = await standsQuery;
    if (standsErr || !stands) {
      return new Response(
        JSON.stringify({ ok: false, error: "stands_query_failed" }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Mapear asignaciones actuales en staff_roles
    const { data: existingRoles } = await adminClient
      .from("staff_roles")
      .select("user_id, stand_id")
      .eq("role", "stand");

    const standToUserMap = new Map<number, string>();
    for (const r of existingRoles ?? []) {
      if (r.stand_id && r.user_id) {
        standToUserMap.set(r.stand_id, r.user_id);
      }
    }

    if (action === "revoke_access" && body.stand_id) {
      const targetUserId = standToUserMap.get(Number(body.stand_id));
      if (!targetUserId) {
        return new Response(
          JSON.stringify({ ok: false, error: "stand_user_not_found" }),
          {
            status: 404,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }

      await adminClient.auth.admin.updateUserById(targetUserId, {
        ban_duration: "87600h",
        password: generateReadablePassword(16),
      });

      await adminClient.from("audit_log").insert({
        actor: callerId,
        action: "stand_user_revoked",
        entity: "stand",
        entity_id: String(body.stand_id),
      });

      return new Response(
        JSON.stringify({ ok: true, stand_id: body.stand_id, revoked: true }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Acción por defecto: provision_batch o reset_password
    const credentials: Array<{
      stand_id: number;
      stand_number: number;
      stand_name: string;
      category: string | null;
      email: string;
      password: string;
      status: string;
    }> = [];

    for (const stand of stands) {
      const padded = String(stand.number).padStart(2, "0");
      const email = `stand${padded}@tokyostreet.com.ar`;
      const password = generateReadablePassword(8);
      const existingUserId = standToUserMap.get(stand.id);

      if (existingUserId) {
        const { error: updErr } = await adminClient.auth.admin.updateUserById(
          existingUserId,
          {
            email,
            password,
            email_confirm: true,
            ban_duration: "none",
          },
        );
        if (updErr) continue;

        credentials.push({
          stand_id: stand.id,
          stand_number: stand.number,
          stand_name: stand.name,
          category: stand.category,
          email,
          password,
          status: "updated",
        });
      } else {
        const { data: created, error: createErr } =
          await adminClient.auth.admin.createUser({
            email,
            password,
            email_confirm: true,
            user_metadata: {
              stand_id: stand.id,
              stand_number: stand.number,
              stand_name: stand.name,
            },
          });

        if (createErr || !created?.user) continue;

        await adminClient.from("staff_roles").upsert({
          user_id: created.user.id,
          role: "stand",
          stand_id: stand.id,
        });

        credentials.push({
          stand_id: stand.id,
          stand_number: stand.number,
          stand_name: stand.name,
          category: stand.category,
          email,
          password,
          status: "created",
        });
      }
    }

    await adminClient.from("audit_log").insert({
      actor: callerId,
      action: "stand_users_provisioned",
      entity: "stand",
      entity_id: "batch",
      detail: { count: credentials.length },
    });

    return new Response(
      JSON.stringify({
        ok: true,
        count: credentials.length,
        credentials,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (err) {
    return new Response(
      JSON.stringify({
        ok: false,
        error: "internal_error",
        message: err instanceof Error ? err.message : "Error inesperado",
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
