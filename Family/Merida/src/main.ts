import "@fontsource-variable/space-grotesk/wght.css";
import "@fontsource/ibm-plex-mono/400.css";
import "@fontsource/ibm-plex-mono/500.css";
import "@fontsource/ibm-plex-mono/700.css";
import "@fontsource/vt323/400.css";
import "./styles/tokens.css";
import "./styles/base.css";
import "./styles/sections.css";
import "./styles/board.css";
import "./styles/console.css";

import type { Session } from "@supabase/supabase-js";
import { missingConfig } from "./config";
import { explainError, supabase } from "./supabase";
import { Store, type Area } from "./store";
import { Player } from "./player";
import { Status } from "./status";
import { Shell, ROUTES, type RouteId } from "./ui/shell";
import { isTyping } from "./ui/dom";
import { loginScreen, missingConfigScreen } from "./ui/login";
import { loadTasks } from "./data/tasks";
import { listTracks } from "./data/music";
import { defaultConversation, latestCreatedAt, listMessages, mergeMessages, watchMessages } from "./data/chat";
import { tasksSection, tasksStatement } from "./sections/tasks";
import { musicSection, musicStatement } from "./sections/music";
import { chatSection, chatStatement } from "./sections/chat";
import type { Ctx, Section } from "./sections/context";

const root = document.getElementById("app")!;

const SECTIONS: Record<RouteId, { mount: Section; statement: (s: Store) => string }> = {
  inicio: { mount: () => () => {}, statement: () => "" }, // el mosaico ya está siempre montado
  tareas: { mount: tasksSection, statement: (s) => tasksStatement(s.tasks, s.loaded.tasks, s.errors.tasks) },
  musica: { mount: musicSection, statement: (s) => musicStatement(s.tracks, s.loaded.tracks, s.errors.tracks) },
  chat: { mount: chatSection, statement: (s) => chatStatement(s.messages, s.loaded.messages, s.errors.messages) },
};

function currentRoute(): RouteId {
  const id = location.hash.replace(/^#\/?/, "");
  return (ROUTES.some((r) => r.id === id) ? id : "inicio") as RouteId;
}

/** La app con sesión abierta. Devuelve cómo cerrarla. */
function startApp(session: Session): () => void {
  const client = supabase();
  const store = new Store();
  const player = new Player(client);
  const status = new Status();
  const signOut = () => void client.auth.signOut();
  const shell = new Shell({ store, player, status, signOut });
  const cleanups: (() => void)[] = [];
  let unmount: (() => void) | null = null;

  async function reload(area: Area) {
    try {
      if (area === "tasks") store.tasks = await loadTasks(client);
      if (area === "tracks") store.tracks = await listTracks(client);
      if (area === "messages") {
        store.conversationId ??= await defaultConversation(client);
        store.messages = mergeMessages([], await listMessages(client, store.conversationId, { limit: 100 }));
      }
      store.loaded[area] = true;
      delete store.errors[area];
      store.emit(area);
    } catch (err) {
      store.fail(area, explainError(err));
    }
  }

  /** Pide solo los mensajes que llegaron después del último que tenemos. */
  async function catchUp() {
    if (!store.conversationId) return;
    try {
      const fresh = await listMessages(client, store.conversationId, { after: latestCreatedAt(store.messages), limit: 200 });
      if (fresh.length) {
        store.messages = mergeMessages(store.messages, fresh);
        store.emit("messages");
      }
    } catch {
      /* el siguiente cambio o la reconexión lo vuelven a intentar */
    }
  }

  async function measure() {
    const start = performance.now();
    const { data, error } = await client.rpc("my_profile");
    status.set({ latency: error ? null : performance.now() - start });
    if (!error) {
      const p = data as { username?: string; role?: string } | null;
      status.set({ account: p?.username ? `${p.username}, ${p.role === "admin" ? "admin" : "pasante"}` : (session.user.email ?? "sin perfil") });
    }
  }

  const ctx: Ctx = { client, shell, store, player, status, signOut, reload };

  let first = true;
  /** Cambia de sección. La tesela que se abre crece hasta ocupar la derecha y las demás se apilan a la izquierda: el
   * navegador anima el paso de un acomodo al otro (View Transitions). Sin soporte, o con «reducir movimiento», cambia
   * al instante. */
  function route() {
    const id = currentRoute();
    if (!first && id === shell.route) return;
    const swap = () => {
      unmount?.();
      shell.setSection(id, SECTIONS[id].statement(store));
      unmount = SECTIONS[id].mount(ctx);
      shell.body.scrollTop = 0;
    };
    const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    if (first || reduce || !("startViewTransition" in document)) swap();
    else document.startViewTransition(swap);
    first = false;
  }

  const onKey = (e: KeyboardEvent) => {
    if (e.ctrlKey || e.metaKey || e.altKey || isTyping(e.target)) return;
    const r = e.key === "Escape" ? ROUTES[0] : ROUTES.find((x) => x.key.toLowerCase() === e.key.toLowerCase());
    if (r) location.hash = `#/${r.id}`;
  };
  const onFocus = () => {
    void reload("tasks");
    void reload("tracks");
    void catchUp();
  };
  window.addEventListener("hashchange", route);
  window.addEventListener("keydown", onKey);
  window.addEventListener("focus", onFocus);
  const pulse = window.setInterval(() => void measure(), 30_000);
  cleanups.push(() => {
    window.removeEventListener("hashchange", route);
    window.removeEventListener("keydown", onKey);
    window.removeEventListener("focus", onFocus);
    window.clearInterval(pulse);
  });

  root.replaceChildren(shell.root);
  route();
  void measure();
  void reload("tasks");
  void reload("tracks");
  void reload("messages").then(() => {
    if (!store.conversationId) return;
    let wasLive = false;
    cleanups.push(
      watchMessages(
        client,
        store.conversationId,
        ({ id, deleted }) => {
          if (deleted) {
            store.messages = store.messages.filter((m) => m.id !== id);
            store.emit("messages");
          } else void catchUp();
        },
        (state) => {
          status.set({ live: state });
          if (state === "live" && wasLive) void catchUp(); // al volver tras un corte, ponerse al día
          if (state === "live") wasLive = true;
        },
      ),
    );
  });

  return () => {
    unmount?.();
    for (const fn of cleanups) fn();
    player.stop();
    shell.destroy();
  };
}

function showLogin() {
  root.replaceChildren(loginScreen(supabase()));
  document.title = "Entrar | Merida";
}

async function boot() {
  const missing = missingConfig();
  if (missing.length) {
    root.replaceChildren(missingConfigScreen(missing));
    return;
  }
  const client = supabase();
  let stop: (() => void) | null = null;
  let userId: string | null = null;
  let onLogin = false;

  const apply = (session: Session | null) => {
    if (session && session.user.id !== userId) {
      stop?.();
      userId = session.user.id;
      onLogin = false;
      stop = startApp(session);
    } else if (!session && !onLogin) {
      // sin sesión: a la pantalla de acceso (solo una vez, para no borrar lo que estés escribiendo)
      stop?.();
      stop = null;
      userId = null;
      onLogin = true;
      showLogin();
    }
  };

  const { data } = await client.auth.getSession();
  apply(data.session);
  client.auth.onAuthStateChange((_event, session) => {
    // Se difiere: dentro de este aviso supabase-js no deja hacer otras llamadas.
    setTimeout(() => apply(session), 0);
  });
}

void boot();
