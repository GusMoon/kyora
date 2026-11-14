import type { SupabaseClient } from "@supabase/supabase-js";
import type { Shell } from "../ui/shell";
import type { Store } from "../store";
import type { Player } from "../player";
import type { Status } from "../status";
import type { PrefsStore } from "../prefs";
import type { Backdrop } from "../backdrop";
import type { Area } from "../store";
import type { Library } from "../data/library";
import type { VaultSession } from "../vault/session";

export interface Ctx {
  client: SupabaseClient;
  shell: Shell;
  store: Store;
  player: Player;
  status: Status;
  prefs: PrefsStore;
  backdrop: Backdrop; // el fondo de pantalla (temporal, mientras dure la sesión)
  library: Library; // el servicio local de música (tus listas de YouTube)
  vault: VaultSession; // la bóveda de contraseñas: la clave vive solo en memoria
  userId: string; // el id de la cuenta (la primera carpeta de lo que se sube a Storage)
  signOut: () => void;
  /** Vuelve a pedir al servidor lo de un área (tareas, etiquetas, canciones, mensajes, archivos, eventos o finanzas). */
  reload: (area: Area) => Promise<void>;
}

/** Monta una sección en `shell.body` y devuelve cómo desmontarla. */
export type Section = (ctx: Ctx) => () => void;
