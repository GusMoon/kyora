import type { SupabaseClient } from "@supabase/supabase-js";

/** Las cuentas y la presencia (Server/supabase/schema.sql §7b y la función admin-users). Las cuentas solo las crea el administrador, con
 * un nombre y una contraseña (sin correo); al crearla recibe un código de 6 dígitos que la persona canjea la primera vez. */

export type Role = "admin" | "intern";

/** Una cuenta en el panel del administrador (`list_presence`). */
export interface PresenceEntry {
  id: string;
  username: string;
  role: Role;
  verified: boolean;
  last_seen: string | null;
  online: boolean; // visto en los últimos 90 s
  code_pending: boolean; // tiene un código vigente sin canjear
  me: boolean;
}

/** El dominio inventado de las cuentas sin correo: el nombre es lo de antes de la @. */
export const ACCOUNT_DOMAIN = "kyra.local";

/** Con qué correo se entra: lo escrito si ya es un correo; si es solo un nombre de usuario, `<nombre>@kyra.local`. */
export function loginEmail(identifier: string): string {
  const text = identifier.trim();
  return text.includes("@") ? text : `${text.toLowerCase()}@${ACCOUNT_DOMAIN}`;
}

export const roleLabel = (role: string): string => (role === "admin" ? "administrador" : "visitante");

/** «en línea», «hace un momento», «hace 5 min», «hace 3 h», «hace 2 d» o «nunca entró». */
export function lastSeenText(entry: Pick<PresenceEntry, "online" | "last_seen">, now: number = Date.now()): string {
  if (entry.online) return "en línea";
  if (!entry.last_seen) return "nunca entró";
  const minutes = Math.floor((now - new Date(entry.last_seen).getTime()) / 60000);
  if (minutes < 1) return "hace un momento";
  if (minutes < 60) return `hace ${minutes} min`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `hace ${hours} h`;
  return `hace ${Math.floor(hours / 24)} d`;
}

/** El nombre de usuario: 3 a 24 caracteres, minúsculas, números, punto, guion y guion bajo (empieza y acaba en letra o número). */
export function usernameProblem(raw: string): string | null {
  const name = raw.trim().toLowerCase();
  if (!/^[a-z0-9][a-z0-9._-]{1,22}[a-z0-9]$/.test(name) || name.includes("..")) {
    return "El nombre: 3 a 24 caracteres, minúsculas, números, punto, guion o guion bajo.";
  }
  return null;
}

export const passwordProblem = (raw: string): string | null => (raw.length < 6 ? "La contraseña debe tener al menos 6 caracteres." : null);

const ADMIN_ERRORS: Record<string, string> = {
  invalid_username: "El nombre: 3 a 24 caracteres, minúsculas, números, punto, guion o guion bajo.",
  invalid_password: "La contraseña debe tener al menos 6 caracteres.",
  username_taken: "Ese nombre de usuario ya existe.",
  not_admin: "Solo el administrador puede hacer eso.",
  unauthorized: "La sesión caducó: vuelve a entrar.",
  cannot_change_self: "No puedes hacer eso con tu propia cuenta.",
  user_not_found: "Esa cuenta ya no existe.",
};

const CLAIM_ERRORS: Record<string, string> = {
  code_invalid: "Ese código no es correcto.",
  code_expired: "El código caducó: pídele otro al administrador.",
  code_locked: "Demasiados intentos con el código: pídele otro al administrador.",
};

/** El error de una función RPC de Postgres, en español (los códigos del código de 6 dígitos). */
export function explainClaim(err: unknown): string {
  const text = String((err as { message?: string } | null)?.message ?? err ?? "");
  for (const [key, message] of Object.entries(CLAIM_ERRORS)) if (text.includes(key)) return message;
  return "No se pudo comprobar el código. Intenta otra vez.";
}

/** Llama a la función admin-users con la sesión del administrador. Lanza un Error con el motivo en español. */
async function adminCall<T>(client: SupabaseClient, body: Record<string, unknown>): Promise<T> {
  const { data, error } = await client.functions.invoke("admin-users", { body });
  if (error) {
    // supabase-js deja la respuesta en error.context (un Response) cuando el servidor contestó con un error
    let code = "";
    try {
      const res = (error as { context?: Response }).context;
      const parsed = res && typeof res.json === "function" ? ((await res.json()) as { error?: string }) : null;
      code = parsed?.error ?? "";
    } catch {
      /* sin cuerpo legible */
    }
    const status = (error as { context?: { status?: number } }).context?.status;
    if (!code && status === 404) throw new Error("Falta desplegar la función admin-users en Supabase (ver Server/supabase/README.md).");
    throw new Error(ADMIN_ERRORS[code] ?? "No se pudo completar. Intenta otra vez.");
  }
  return data as T;
}

export async function listPresence(client: SupabaseClient): Promise<PresenceEntry[]> {
  const { data, error } = await client.rpc("list_presence");
  if (error) throw error;
  return (data ?? []) as PresenceEntry[];
}

/** «Sigo aquí»: se manda cada ~30 s. Un fallo no importa (el siguiente latido lo vuelve a intentar). */
export async function touchPresence(client: SupabaseClient): Promise<void> {
  try {
    await client.rpc("touch_presence");
  } catch {
    /* sin conexión */
  }
}

export interface IssuedCode {
  username: string;
  code: string;
}

export async function createAccount(client: SupabaseClient, input: { username: string; password: string; role: Role }): Promise<IssuedCode> {
  const data = await adminCall<{ username: string; code: string }>(client, { action: "create", ...input, username: input.username.trim() });
  return { username: data.username, code: data.code };
}

export async function setRole(client: SupabaseClient, userId: string, role: Role): Promise<void> {
  await adminCall(client, { action: "set_role", user_id: userId, role });
}

export async function regenerateCode(client: SupabaseClient, userId: string, username: string): Promise<IssuedCode> {
  const data = await adminCall<{ code: string }>(client, { action: "regenerate_code", user_id: userId });
  return { username, code: data.code };
}

export async function removeAccount(client: SupabaseClient, userId: string): Promise<void> {
  await adminCall(client, { action: "remove", user_id: userId });
}

/** El perfil de quien tiene sesión: ¿ya verificó su código? (sin la columna, se da por verificado). */
export async function myVerified(client: SupabaseClient): Promise<boolean> {
  const { data, error } = await client.rpc("my_profile");
  if (error) return true; // sin respuesta no se bloquea nada: el servidor igualmente no deja entrar al chat
  const p = data as { verified?: boolean } | null;
  return p?.verified !== false;
}

/** Canjea el código de 6 dígitos de la cuenta. Lanza un Error con el motivo en español. */
export async function claimAccount(client: SupabaseClient, code: string): Promise<void> {
  const { error } = await client.rpc("claim_account", { p_code: code.trim() });
  if (error) throw new Error(explainClaim(error));
}
