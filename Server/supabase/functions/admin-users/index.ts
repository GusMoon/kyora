// Cuentas de Kyra y Merida: solo el administrador las crea (el registro público está apagado).
//
// Se llama con la sesión de quien administra (cabecera Authorization: Bearer <jwt>), así que se despliega CON verificación de JWT:
//   supabase functions deploy admin-users
// y además comprueba aquí que quien llama sea administrador verificado (is_admin()). SUPABASE_URL, SUPABASE_ANON_KEY y
// SUPABASE_SERVICE_ROLE_KEY los pone Supabase solo.
//
// POST { action, ... }
//   create          { username, password, role?: "admin" | "intern" }  → { id, username, role, code }  (el código sale UNA vez)
//   set_role        { user_id, role }                                  → { ok: true }
//   regenerate_code { user_id }                                        → { code }   (la cuenta vuelve a pedir verificación)
//   remove          { user_id }                                        → { ok: true }
//
// Las cuentas no llevan correo real: el correo es <nombre>@kyra.local y nunca se usa para escribir a nadie. Del código solo se
// guarda su hash (sha256 de código + id); la persona lo canjea con la función claim_account (schema.sql §7b).
import { createClient } from "npm:@supabase/supabase-js@2.45.4";
import { codeExpiry, emailFor, hashCode, newCode, normalizeUsername, parseRole, validPassword } from "./rules.ts";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json", ...CORS } });
const fail = (error: string, status = 400) => json({ error }, status);

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });
  if (req.method !== "POST") return fail("method_not_allowed", 405);

  const url = Deno.env.get("SUPABASE_URL")!;
  const authorization = req.headers.get("Authorization") ?? "";
  if (!authorization.startsWith("Bearer ")) return fail("unauthorized", 401);

  // Quién llama (con SU sesión, para que is_admin() y auth.uid() sean los suyos).
  const caller = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false },
  });
  const { data: who, error: whoError } = await caller.auth.getUser();
  if (whoError || !who.user) return fail("unauthorized", 401);
  const { data: isAdmin, error: adminError } = await caller.rpc("is_admin");
  if (adminError) return fail("server_error", 500);
  if (isAdmin !== true) return fail("not_admin", 403);
  const callerId = who.user.id;

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return fail("bad_request");
  }

  const db = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });

  try {
    switch (body.action) {
      case "create":
        return await create(db, body);
      case "set_role":
        return await setRole(db, callerId, body);
      case "regenerate_code":
        return await regenerate(db, callerId, body);
      case "remove":
        return await remove(db, callerId, body);
      default:
        return fail("unknown_action");
    }
  } catch (error) {
    console.error("admin-users", error);
    return fail("server_error", 500);
  }
});

type Db = ReturnType<typeof createClient>;

async function create(db: Db, body: Record<string, unknown>) {
  const username = normalizeUsername(body.username);
  if (!username) return fail("invalid_username");
  if (!validPassword(body.password)) return fail("invalid_password");
  const role = parseRole(body.role ?? "intern");
  if (!role) return fail("invalid_role");

  // ilike sin distinguir mayúsculas; «_» y «%» son comodines de LIKE, así que se escapan
  const { data: taken } = await db.from("profiles").select("id").ilike("username", username.replace(/[\\%_]/g, "\\$&")).maybeSingle();
  if (taken) return fail("username_taken", 409);

  const { data: created, error } = await db.auth.admin.createUser({
    email: emailFor(username),
    password: body.password,
    email_confirm: true,
    user_metadata: { username },
  });
  if (error || !created.user) {
    return fail(/already|registered|exists/i.test(error?.message ?? "") ? "username_taken" : "create_failed", error ? 409 : 500);
  }
  const id = created.user.id;

  // El trigger handle_new_user ya creó el perfil como pasante sin verificar; aquí se fija el rol y el código.
  const code = newCode();
  const { error: profileError } = await db
    .from("profiles")
    .update({ role, verified: false, code_hash: await hashCode(code, id), code_expires_at: codeExpiry(), code_attempts: 0 })
    .eq("id", id);
  if (profileError) {
    await db.auth.admin.deleteUser(id); // no dejar una cuenta a medias
    return fail("create_failed", 500);
  }
  // Todas las cuentas entran al chat familiar (solo ven algo cuando están verificadas).
  const { error: familyError } = await db.from("family_members").upsert({ user_id: id });
  if (familyError) console.error("admin-users family", familyError.message);

  return json({ id, username, role, code }, 201);
}

async function setRole(db: Db, callerId: string, body: Record<string, unknown>) {
  const id = String(body.user_id ?? "");
  const role = parseRole(body.role);
  if (!id || !role) return fail("bad_request");
  if (id === callerId) return fail("cannot_change_self", 409); // para no quedarse sin administrador
  const { data, error } = await db.from("profiles").update({ role }).eq("id", id).select("id");
  if (error) throw error;
  if (!data?.length) return fail("user_not_found", 404);
  return json({ ok: true });
}

async function regenerate(db: Db, callerId: string, body: Record<string, unknown>) {
  const id = String(body.user_id ?? "");
  if (!id) return fail("bad_request");
  if (id === callerId) return fail("cannot_change_self", 409);
  const code = newCode();
  const { data, error } = await db
    .from("profiles")
    .update({ verified: false, code_hash: await hashCode(code, id), code_expires_at: codeExpiry(), code_attempts: 0 })
    .eq("id", id)
    .select("id");
  if (error) throw error;
  if (!data?.length) return fail("user_not_found", 404);
  return json({ code });
}

async function remove(db: Db, callerId: string, body: Record<string, unknown>) {
  const id = String(body.user_id ?? "");
  if (!id) return fail("bad_request");
  if (id === callerId) return fail("cannot_change_self", 409);
  const { error } = await db.auth.admin.deleteUser(id); // el perfil y la familia caen en cascada
  if (error) return fail("user_not_found", 404);
  return json({ ok: true });
}
