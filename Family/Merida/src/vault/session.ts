import type { SupabaseClient } from "@supabase/supabase-js";
import { createVault, deleteItem, loadItems, loadMeta, newVaultItem, saveItem, unlockVault, updateVaultItem, type VaultItem, type VaultMeta } from "../data/vault";

export type VaultState = "loading" | "none" | "locked" | "unlocked" | "error";

export const IDLE_MS = 5 * 60_000; // se bloquea sola tras 5 minutos sin tocarla
export const CLIPBOARD_MS = 30_000; // lo copiado se borra del portapapeles a los 30 segundos

/** La bóveda abierta en esta pestaña. La clave y las entradas descifradas viven SOLO aquí, en memoria: al bloquear, cerrar
 * sesión o cerrar la pestaña, desaparecen. Nada sin cifrar se guarda ni sale del navegador. */
export class VaultSession {
  state: VaultState = "loading";
  items: VaultItem[] = [];
  broken = 0; // entradas que no se pudieron descifrar
  error = "";
  private key: CryptoKey | null = null;
  private meta: VaultMeta | null = null;
  private idle: ReturnType<typeof setTimeout> | null = null;
  private listeners = new Set<() => void>();

  constructor(private client: SupabaseClient, private idleMs = IDLE_MS) {}

  on(fn: () => void): () => void {
    this.listeners.add(fn);
    return () => this.listeners.delete(fn);
  }

  private set(state: VaultState, error = "") {
    this.state = state;
    this.error = error;
    for (const fn of this.listeners) fn();
  }

  /** Mira si ya hay bóveda creada (solo lee la sal y la prueba; nada se descifra todavía). */
  async refresh(): Promise<void> {
    try {
      this.meta = await loadMeta(this.client);
      if (this.state !== "unlocked") this.set(this.meta ? "locked" : "none");
    } catch (err) {
      this.set("error", err instanceof Error ? err.message : String(err));
    }
  }

  /** Cada toque (teclado, ratón) reinicia el reloj de inactividad. */
  touch() {
    if (this.state !== "unlocked") return;
    if (this.idle) clearTimeout(this.idle);
    this.idle = setTimeout(() => this.lock(), this.idleMs);
  }

  async create(password: string): Promise<void> {
    this.key = await createVault(this.client, password);
    this.items = [];
    this.broken = 0;
    this.meta = await loadMeta(this.client);
    this.set("unlocked");
    this.touch();
  }

  /** Devuelve false si la contraseña maestra no es la correcta. */
  async unlock(password: string): Promise<boolean> {
    if (!this.meta) await this.refresh();
    if (!this.meta) throw new Error("Todavía no hay bóveda.");
    const key = await unlockVault(this.meta, password);
    if (!key) return false;
    const { items, broken } = await loadItems(this.client, key);
    this.key = key;
    this.items = items;
    this.broken = broken;
    this.set("unlocked");
    this.touch();
    return true;
  }

  lock() {
    if (this.idle) clearTimeout(this.idle);
    this.idle = null;
    this.key = null;
    this.items = [];
    this.broken = 0;
    if (this.state === "unlocked") this.set(this.meta ? "locked" : "none");
  }

  async add(input: Parameters<typeof newVaultItem>[0]): Promise<VaultItem> {
    if (!this.key) throw new Error("La bóveda está bloqueada.");
    const item = newVaultItem(input);
    await saveItem(this.client, this.key, item);
    this.items = [...this.items, item];
    this.set("unlocked");
    this.touch();
    return item;
  }

  async update(id: string, patch: Partial<Omit<VaultItem, "id">>): Promise<VaultItem> {
    if (!this.key) throw new Error("La bóveda está bloqueada.");
    const prev = this.items.find((i) => i.id === id);
    if (!prev) throw new Error("La entrada ya no existe.");
    const next = updateVaultItem(prev, patch);
    await saveItem(this.client, this.key, next);
    this.items = this.items.map((i) => (i.id === id ? next : i));
    this.set("unlocked");
    this.touch();
    return next;
  }

  async remove(id: string): Promise<void> {
    const prev = this.items.find((i) => i.id === id);
    if (!prev) return;
    await deleteItem(this.client, prev);
    this.items = this.items.filter((i) => i.id !== id);
    this.set("unlocked");
    this.touch();
  }

  /** Cierra todo (al cerrar sesión): sin clave ni entradas en memoria. */
  destroy() {
    this.lock();
    this.listeners.clear();
  }
}

/** Copia al portapapeles y lo borra a los 30 segundos si sigue siendo lo mismo que se copió. */
export async function copySecret(text: string, clipboard: Pick<Clipboard, "writeText" | "readText"> | undefined = navigator.clipboard, ms = CLIPBOARD_MS): Promise<boolean> {
  if (!clipboard) return false;
  try {
    await clipboard.writeText(text);
  } catch {
    return false;
  }
  setTimeout(() => {
    void (async () => {
      try {
        if ((await clipboard.readText()) === text) await clipboard.writeText("");
      } catch {
        /* sin permiso para leer el portapapeles no se puede saber si sigue siendo lo copiado: no se toca (podría ser otra cosa) */
      }
    })();
  }, ms);
  return true;
}
