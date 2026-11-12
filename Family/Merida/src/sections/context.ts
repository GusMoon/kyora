import type { SupabaseClient } from "@supabase/supabase-js";
import type { Shell } from "../ui/shell";
import type { Store } from "../store";
import type { Player } from "../player";
import type { Status } from "../status";

export interface Ctx {
  client: SupabaseClient;
  shell: Shell;
  store: Store;
  player: Player;
  status: Status;
  signOut: () => void;
  /** Vuelve a pedir al servidor lo de un área (tareas, canciones o mensajes). */
  reload: (area: "tasks" | "tracks" | "messages") => Promise<void>;
}

/** Monta una sección en `shell.body` y devuelve cómo desmontarla. */
export type Section = (ctx: Ctx) => () => void;
