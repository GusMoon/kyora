import type { SupabaseClient } from "@supabase/supabase-js";
import type { Shell } from "../ui/shell";
import type { Store } from "../store";
import type { Player } from "../player";
import type { Status } from "../status";
import type { PrefsStore } from "../prefs";
import type { Backdrop } from "../backdrop";
import type { Area } from "../store";
import type { Library } from "../data/library";

export interface Ctx {
  client: SupabaseClient;
  shell: Shell;
  store: Store;
  player: Player;
  status: Status;
  prefs: PrefsStore;
  backdrop: Backdrop; // el fondo de pantalla (temporal, mientras dure la sesión)
  library: Library; // el servicio local de música (tus listas de YouTube)
  signOut: () => void;
  /** Vuelve a pedir al servidor lo de un área (tareas, canciones, mensajes o archivos de la nube). */
  reload: (area: Area) => Promise<void>;
}

/** Monta una sección en `shell.body` y devuelve cómo desmontarla. */
export type Section = (ctx: Ctx) => () => void;
