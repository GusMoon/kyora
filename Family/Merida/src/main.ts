import "@fontsource-variable/space-grotesk/wght.css";
import "@fontsource/ibm-plex-mono/400.css";
import "@fontsource/ibm-plex-mono/500.css";
import "@fontsource/ibm-plex-mono/700.css";
import "./styles/tokens.css";
import "./styles/base.css";
import "./styles/sections.css";
import "./styles/board.css";
import "./styles/console.css";
import "./styles/settings.css";
import "./styles/fx.css";
import "./styles/backdrop.css";
import "./styles/cloud.css";

import type { Session } from "@supabase/supabase-js";
import { missingConfig } from "./config";
import { explainError, supabase } from "./supabase";
import { Store, type Area } from "./store";
import { Player } from "./player";
import { Status } from "./status";
import { PrefsStore, applyAccent } from "./prefs";
import { Backdrop } from "./backdrop";
import { Library } from "./data/library";
import { fxConfig, hideBlocks, resetHidden, revealBlocks } from "./ui/fx";
import { Shell, ROUTES, type RouteId } from "./ui/shell";
import { isTyping } from "./ui/dom";
import { loginScreen, missingConfigScreen } from "./ui/login";
import { loadTasks } from "./data/tasks";
import { listTracks } from "./data/music";
import { listCloud } from "./data/cloud";
import { defaultConversation, latestCreatedAt, listMessages, mergeMessages, watchMessages } from "./data/chat";
import { tasksSection, tasksStatement } from "./sections/tasks";
import { musicSection, musicStatement } from "./sections/music";
import { chatSection, chatStatement } from "./sections/chat";
import { cloudSection, cloudStatement } from "./sections/cloud";
import { settingsSection, settingsStatement } from "./sections/settings";
import type { Ctx, Section } from "./sections/context";

const root = document.getElementById("app")!;

// Las preferencias de este navegador (Configuración): el acento y los efectos se aplican antes de pintar nada.
// El fondo de pantalla va detrás de todo; los colores de la app salen de él (o de la portada que suena) si así se elige.
const prefs = new PrefsStore();
const backdrop = new Backdrop();
document.body.prepend(backdrop.el);
const applyPrefs = () => {
  applyAccent((prefs.value.tint && backdrop.accent ? (backdrop.accent as `#${string}`) : null) ?? prefs.value.accent);
  fxConfig.hack = prefs.value.hack;
  fxConfig.holo = prefs.value.holo;
};
applyPrefs();
prefs.on(applyPrefs);
backdrop.on(applyPrefs);

const SECTIONS: Record<RouteId, { mount: Section; statement: (s: Store, st: Status) => string }> = {
  inicio: { mount: () => () => {}, statement: () => "" }, // el mosaico ya está siempre montado
  tareas: { mount: tasksSection, statement: (s) => tasksStatement(s.tasks, s.loaded.tasks, s.errors.tasks) },
  musica: { mount: musicSection, statement: (s) => musicStatement(s.tracks, s.loaded.tracks, s.errors.tracks) },
  nube: { mount: cloudSection, statement: (s) => cloudStatement(s.files, s.loaded.files, s.errors.files) },
  chat: { mount: chatSection, statement: (s) => chatStatement(s.messages, s.loaded.messages, s.errors.messages) },
  configuracion: { mount: settingsSection, statement: (_s, st) => settingsStatement(st.data) },
};

/** La sección de la dirección; sin ninguna, la que se eligió en Configuración («Al abrir Merida»). */
function currentRoute(): RouteId {
  const id = location.hash.replace(/^#\/?/, "");
  if (!id) return prefs.value.start;
  return (ROUTES.some((r) => r.id === id) ? id : "inicio") as RouteId;
}

/** La app con sesión abierta. Devuelve cómo cerrarla. */
function startApp(session: Session): () => void {
  const client = supabase();
  const store = new Store();
  const player = new Player(client);
  const status = new Status();
  const signOut = () => void client.auth.signOut();
  const shell = new Shell({ store });
  const library = new Library();
  const cleanups: (() => void)[] = [];
  let unmount: (() => void) | null = null;

  async function reload(area: Area) {
    try {
      if (area === "tasks") store.tasks = await loadTasks(client);
      if (area === "tracks") store.tracks = await listTracks(client);
      if (area === "files") store.files = await listCloud(client, session.user.id);
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
      const role = p?.role === "admin" ? "admin" : p?.role ? "pasante" : "";
      status.set({
        account: p?.username ? `${p.username}, ${role}` : (session.user.email ?? "sin perfil"),
        username: p?.username ?? "",
        role,
        email: session.user.email ?? "",
      });
    }
  }

  // mientras suena algo con portada, esa portada es el fondo (como en Kyra)
  const syncCover = () => {
    const p = player.state;
    backdrop.setCover(prefs.value.cover && p.playing && p.track?.cover_url ? p.track.cover_url : null);
  };
  cleanups.push(player.on(syncCover), prefs.on(syncCover));

  const ctx: Ctx = { client, shell, store, player, status, prefs, backdrop, library, signOut, reload };

  let first = true;
  let seq = 0;
  /** Cambia de sección, como en Kyra:
   * 1. lo que estaba abierto sale como holograma (210 ms) y sus textos se des-escriben;
   * 2. la tesela nueva crece hasta ocupar la pantalla y las demás se esconden en el borde izquierdo (View Transitions),
   *    y **a la vez** los bloques de la sección entran como holograma, uno tras otro, y sus textos se escriben con el
   *    efecto hacking. La entrada empieza dentro del propio cambio, antes de que se pinte nada, así nunca se ve el
   *    bloque entero y luego su efecto: se ve ya con el efecto.
   * Sin soporte o con «reducir movimiento» (o los efectos apagados en Configuración) todo cambia al instante. */
  function route() {
    const id = currentRoute();
    if (!first && id === shell.route) return;
    const previous = shell.route;
    const firstTime = first;
    const token = ++seq;
    const swap = () => {
      unmount?.();
      shell.setSection(id, SECTIONS[id].statement(store, status));
      unmount = SECTIONS[id].mount(ctx);
      shell.body.scrollTop = 0;
      resetHidden();
      // lo nuevo nace escondido y entra con su efecto (al volver al mosaico las teselas ya se mueven solas: solo se escriben sus títulos)
      const { blocks, texts } = shell.fxTargets(id);
      void revealBlocks(id === "inicio" && !firstTime ? [] : blocks, texts);
    };
    if (first) {
      first = false;
      swap();
      return;
    }
    const leaving = previous === "inicio" ? Promise.resolve() : (() => {
      const { blocks, texts } = shell.fxTargets(previous);
      return hideBlocks(blocks, texts);
    })();
    void leaving.then(() => {
      if (token !== seq) return; // ya se pidió otra sección mientras salía esta
      const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
      if (reduce || !("startViewTransition" in document)) swap();
      else document.startViewTransition(swap);
    });
  }

  const onKey = (e: KeyboardEvent) => {
    if (e.ctrlKey || e.metaKey || e.altKey || isTyping(e.target)) return;
    const r = e.key === "Escape" ? ROUTES[0] : ROUTES.find((x) => x.key.toLowerCase() === e.key.toLowerCase());
    if (r) location.hash = `#/${r.id}`;
  };
  const onFocus = () => {
    void reload("tasks");
    void reload("tracks");
    void reload("files");
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
  void reload("files");
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
    backdrop.reset(); // el fondo es temporal: dura lo que dure la sesión
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
