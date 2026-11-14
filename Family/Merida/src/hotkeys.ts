import { DEFAULT_KEYS, ROUTES, routeTitle, type KeyMap, type RouteId } from "./routes";

/** Atajos editables de las secciones. Una sola letra o número, sin duplicados. `Esc` (volver al mosaico) y `Ctrl+K` (la
 * paleta) son fijos y no se pueden asignar: una tecla suelta nunca choca con ellos. Es el equivalente web de
 * Family/Kyora/kyora/core/hotkey_edit.py. */

/** «k», « K » → «K». Devuelve "" si no es una sola letra (sin acento) o número. */
export function normalizeKey(raw: string): string {
  const k = raw.trim().toUpperCase();
  return /^[A-Z0-9]$/.test(k) ? k : "";
}

/** Revisa un mapa completo: todas válidas y sin repetir. Devuelve el motivo o null si está bien. */
export function validateKeys(keys: KeyMap): string | null {
  const seen = new Map<string, RouteId>();
  for (const r of ROUTES) {
    const k = normalizeKey(keys[r.id] ?? "");
    if (!k) return `«${routeTitle(r.id)}» necesita una letra o un número.`;
    const other = seen.get(k);
    if (other) return `La tecla ${k} ya abre ${routeTitle(other)}.`;
    seen.set(k, r.id);
  }
  return null;
}

/** Lo que había guardado, validado: o todo el mapa vale, o se vuelve a las teclas de siempre. */
export function resolveKeys(raw: unknown): KeyMap {
  if (!raw || typeof raw !== "object") return { ...DEFAULT_KEYS };
  const candidate = { ...DEFAULT_KEYS };
  for (const r of ROUTES) {
    const v = (raw as Record<string, unknown>)[r.id];
    if (typeof v === "string") candidate[r.id] = normalizeKey(v) || "";
  }
  return validateKeys(candidate) === null ? candidate : { ...DEFAULT_KEYS };
}

export type KeyEdit = { ok: true; keys: KeyMap } | { ok: false; error: string };

/** Cambia la tecla de una sección. Si ya la usa otra, no cambia nada y dice cuál. */
export function applyKeyEdit(keys: KeyMap, id: RouteId, raw: string): KeyEdit {
  const k = normalizeKey(raw);
  if (!k) return { ok: false, error: "Usa una sola letra (sin acento) o un número." };
  const owner = ROUTES.find((r) => r.id !== id && keys[r.id] === k);
  if (owner) return { ok: false, error: `La tecla ${k} ya abre ${routeTitle(owner.id)}.` };
  return { ok: true, keys: { ...keys, [id]: k } };
}

/** La sección que abre esta tecla (`event.key`), o null. */
export function routeForKey(keys: KeyMap, key: string): RouteId | null {
  const k = normalizeKey(key);
  if (!k) return null;
  return ROUTES.find((r) => keys[r.id] === k)?.id ?? null;
}
