import type { SupabaseClient } from "@supabase/supabase-js";
import { KDF_ITERATIONS, checkVerifier, decryptText, deriveKey, encryptText, fromBase64, makeVerifier, randomBytes, toBase64 } from "../vault/crypto";
import { stamp } from "./tasks";

/** Una entrada de la bóveda, ya descifrada. En el servidor solo existe cifrada (`vault_entries.payload`). */
export interface VaultItem {
  id: string;
  service: string; // el nombre del servicio o de la aplicación
  email: string; // el correo con el que se entra
  username: string;
  password: string;
  url: string;
  notes: string;
  created_at: string;
  updated_at: string;
}

export interface VaultMeta {
  salt: string;
  kdf_iter: number;
  verifier: string;
  version: number;
}

interface EntryRow {
  id: string;
  payload: string;
  version: number;
  created_at: string;
  updated_at: string;
  deleted_at: string | null;
}

/** Lo que va dentro del texto cifrado (el id y las fechas viven fuera, en claro, porque el servidor los necesita). */
type Secret = Pick<VaultItem, "service" | "email" | "username" | "password" | "url" | "notes">;

export function newVaultItem(input: Partial<Secret> & { service: string }, now: Date = new Date(), id: string = crypto.randomUUID()): VaultItem {
  const at = now.toISOString();
  return {
    id,
    service: input.service.trim(),
    email: input.email?.trim() ?? "",
    username: input.username?.trim() ?? "",
    password: input.password ?? "",
    url: input.url?.trim() ?? "",
    notes: input.notes ?? "",
    created_at: at,
    updated_at: at,
  };
}

export function updateVaultItem(item: VaultItem, patch: Partial<Secret>, now: Date = new Date()): VaultItem {
  return { ...item, ...patch, service: (patch.service ?? item.service).trim() || item.service, updated_at: stamp(item.updated_at, now) };
}

/** Busca por servicio, correo, usuario y URL (nunca por la contraseña ni las notas). */
export function searchItems(items: VaultItem[], query: string): VaultItem[] {
  const q = query.trim().toLowerCase();
  const sorted = [...items].sort((a, b) => a.service.localeCompare(b.service, "es"));
  if (!q) return sorted;
  return sorted.filter((i) => [i.service, i.email, i.username, i.url].some((f) => f.toLowerCase().includes(q)));
}

export async function loadMeta(client: SupabaseClient): Promise<VaultMeta | null> {
  const { data, error } = await client.from("vault_meta").select("salt,kdf_iter,verifier,version").maybeSingle();
  if (error) throw error;
  return (data as VaultMeta | null) ?? null;
}

/** Crea la bóveda: sal nueva, clave de la contraseña maestra y la prueba para validarla después. Devuelve la clave. */
export async function createVault(client: SupabaseClient, password: string): Promise<CryptoKey> {
  const salt = randomBytes(16);
  const key = await deriveKey(password, salt, KDF_ITERATIONS);
  const { error } = await client.from("vault_meta").insert({ salt: toBase64(salt), kdf_iter: KDF_ITERATIONS, verifier: await makeVerifier(key), version: 1 });
  if (error) throw error;
  return key;
}

/** La clave de la contraseña maestra, o null si no es la correcta. */
export async function unlockVault(meta: VaultMeta, password: string): Promise<CryptoKey | null> {
  const key = await deriveKey(password, fromBase64(meta.salt), meta.kdf_iter);
  return (await checkVerifier(key, meta.verifier)) ? key : null;
}

/** Las entradas vivas, descifradas. Las que no se puedan descifrar se cuentan aparte (no se pierden ni se muestran). */
export async function loadItems(client: SupabaseClient, key: CryptoKey): Promise<{ items: VaultItem[]; broken: number }> {
  const { data, error } = await client.from("vault_entries").select("id,payload,version,created_at,updated_at,deleted_at").is("deleted_at", null).limit(2000);
  if (error) throw error;
  const items: VaultItem[] = [];
  let broken = 0;
  for (const row of (data ?? []) as EntryRow[]) {
    try {
      const secret = JSON.parse(await decryptText(key, row.payload, row.id)) as Secret;
      items.push({ id: row.id, created_at: row.created_at, updated_at: row.updated_at, service: secret.service ?? "", email: secret.email ?? "", username: secret.username ?? "", password: secret.password ?? "", url: secret.url ?? "", notes: secret.notes ?? "" });
    } catch {
      broken++;
    }
  }
  return { items, broken };
}

/** Cifra y sube una entrada (nueva o editada). */
export async function saveItem(client: SupabaseClient, key: CryptoKey, item: VaultItem): Promise<void> {
  const secret: Secret = { service: item.service, email: item.email, username: item.username, password: item.password, url: item.url, notes: item.notes };
  const row = { id: item.id, payload: await encryptText(key, JSON.stringify(secret), item.id), version: 1, created_at: item.created_at, updated_at: item.updated_at, deleted_at: null };
  const { error } = await client.from("vault_entries").upsert(row, { onConflict: "id" });
  if (error) throw error;
}

/** Borrado suave: la fila queda en el servidor con `deleted_at` (su contenido sigue cifrado). */
export async function deleteItem(client: SupabaseClient, item: VaultItem, now: Date = new Date()): Promise<void> {
  const at = stamp(item.updated_at, now);
  const { error } = await client.from("vault_entries").update({ deleted_at: at, updated_at: at }).eq("id", item.id);
  if (error) throw error;
}
