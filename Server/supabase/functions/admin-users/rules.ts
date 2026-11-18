// Reglas puras de admin-users (sin red ni Supabase, para poder probarlas).

/** Dominio inventado: las cuentas no llevan correo real. El nombre de usuario es la parte de antes de la @. */
export const ACCOUNT_DOMAIN = "kyra.local";

export type Role = "admin" | "intern";

/** Nombre de usuario válido: 3 a 24 caracteres, minúsculas, números, punto, guion y guion bajo; empieza y acaba en letra o número. */
export function normalizeUsername(raw: unknown): string | null {
  const name = String(raw ?? "").trim().toLowerCase();
  if (!/^[a-z0-9][a-z0-9._-]{1,22}[a-z0-9]$/.test(name)) return null;
  if (name.includes("..")) return null;
  return name;
}

export const emailFor = (username: string) => `${username}@${ACCOUNT_DOMAIN}`;

export function validPassword(raw: unknown): raw is string {
  return typeof raw === "string" && raw.length >= 6 && raw.length <= 72;
}

export function parseRole(raw: unknown): Role | null {
  return raw === "admin" || raw === "intern" ? raw : null;
}

/** Código de 6 dígitos (con ceros a la izquierda), sacado de números aleatorios sin sesgo. */
export function newCode(random: (n: number) => number = randomBelow): string {
  return String(random(1_000_000)).padStart(6, "0");
}

function randomBelow(n: number): number {
  const limit = Math.floor(0x1_0000_0000 / n) * n; // descarta lo que daría sesgo por el módulo
  const buf = new Uint32Array(1);
  do crypto.getRandomValues(buf); while (buf[0] >= limit);
  return buf[0] % n;
}

/** sha256(código + id) en hexadecimal: tiene que coincidir con lo que calcula claim_account en schema.sql. */
export async function hashCode(code: string, userId: string): Promise<string> {
  const bytes = new TextEncoder().encode(code + userId);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

/** El código caduca a las 72 horas. */
export const CODE_TTL_MS = 72 * 3600 * 1000;
export const codeExpiry = (now = Date.now()) => new Date(now + CODE_TTL_MS).toISOString();
