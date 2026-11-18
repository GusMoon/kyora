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
import "./styles/forms.css";
import "./styles/modules.css";
import "./styles/calendar.css";
import "./styles/family.css";

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
import { Shell } from "./ui/shell";
import { ROUTES, type RouteId } from "./routes";
import { routeForKey } from "./hotkeys";
import { isTyping } from "./ui/dom";
import { Palette } from "./ui/palette";
import { buildPaletteItems } from "./paletteItems";
import { countsAsUnread, shouldNotify, showAlert, showNotification } from "./notify";
import { pendingAlerts } from "./data/agenda";
import { VaultSession } from "./vault/session";
import { loginScreen, missingConfigScreen, verifyScreen } from "./ui/login";
import { myVerified, touchPresence } from "./data/users";
import { loadTags, loadTaskTags, loadTasks } from "./data/tasks";
import { loadEvents } from "./data/events";
import { loadFinance } from "./data/finance";
import { loadImprovements } from "./data/improvements";
import { loadReminders } from "./data/reminders";
import { loadHabits } from "./data/habits";
import { loadServerStats, loadWarned, overQuota, percent, saveWarned, shouldRenotify, warningText } from "./data/server";
import { listTracks } from "./data/music";
import { listCloud } from "./data/cloud";
import { defaultConversation, latestCreatedAt, listMessages, mergeMessages, watchMessages, type Message } from "./data/chat";
import { familyMembers, type FamilyMember } from "./data/family-chat";
import { CallController } from "./data/call-controller";
import { browserEnv } from "./data/webrtc";
import { callPanel } from "./ui/call-panel";
import { tasksSection, tasksStatement } from "./sections/tasks";
import { calendarSection } from "./sections/calendar";
import { musicSection, musicStatement } from "./sections/music";
import { chatSection, chatStatement } from "./sections/chat";
import { cloudSection, cloudStatement } from "./sections/cloud";
import { vaultSection } from "./sections/vault";
import { financeSection } from "./sections/finance";
import { improvementsSection, improvementsStatement } from "./sections/improvements";
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

// Calendario, Contraseñas y Finanzas ponen su propio enunciado al montarse (dependen de la moneda y de la bóveda).
const SECTIONS: Record<RouteId, { mount: Section; statement: (s: Store, st: Status) => string }> = {
  inicio: { mount: () => () => {}, statement: () => "" }, // el mosaico ya está siempre montado
  tareas: { mount: tasksSection, statement: (s) => tasksStatement(s.tasks, s.loaded.tasks, s.errors.tasks) },
  calendario: { mount: calendarSection, statement: () => "" },
  musica: { mount: musicSection, statement: (s) => musicStatement(s.tracks, s.loaded.tracks, s.errors.tracks) },
  nube: { mount: cloudSection, statement: (s) => cloudStatement(s.files, s.loaded.files, s.errors.files) },
  chat: { mount: chatSection, statement: (s) => chatStatement(s.messages, s.loaded.messages, s.errors.messages) },
  contrasenas: { mount: vaultSection, statement: () => "" },
  finanzas: { mount: financeSection, statement: () => "" },
  mejoras: { mount: improvementsSection, statement: (s) => improvementsStatement(s.improvements, s.loaded.improvements, s.errors.improvements) },
  configuracion: { mount: settingsSection, statement: (_s, st) => settingsStatement(st.data) },
};

/** La sección de la dirección; sin ninguna, la que se eligió en Configuración («Al abrir Merida»). */
function currentRoute(): RouteId {
  const id = location.hash.replace(/^#\/?/, "");
  if (!id) return prefs.value.start;
  return (ROUTES.some((r) => r.id === id) ? id : "inicio") as RouteId;
}

/** ¿Hay una ventana modal abierta (la paleta u otra)? Esc la cierra a ella primero, no vuelve al mosaico. */
const modalOpen = () => !!document.querySelector('[aria-modal="true"]');

/** La app con sesión abierta. Devuelve cómo cerrarla. */
function startApp(session: Session): () => void {
  const client = supabase();
  const store = new Store();
  const player = new Player(client);
  const status = new Status();
  const signOut = () => void client.auth.signOut();
  const vault = new VaultSession(client);
  const shell = new Shell({ store, vault, prefs });
  const library = new Library();
  const cleanups: (() => void)[] = [];
  let unmount: (() => void) | null = null;
  let unread = 0; // mensajes de otros dispositivos que llegaron sin que estuvieras viendo el chat

  async function reload(area: Area) {
    try {
      if (area === "tasks") store.tasks = await loadTasks(client);
      if (area === "tags") {
        [store.tags, store.taskTags] = await Promise.all([loadTags(client), loadTaskTags(client)]);
      }
      if (area === "tracks") store.tracks = await listTracks(client);
      if (area === "files") store.files = await listCloud(client, session.user.id);
      if (area === "events") store.events = await loadEvents(client);
      if (area === "server") {
        store.serverStats = await loadServerStats(client);
        syncQuota();
      }
      if (area === "reminders") store.reminders = await loadReminders(client);
      if (area === "habits") {
        const x = await loadHabits(client);
        store.habits = x.habits;
        store.habitChecks = x.checks;
      }
      if (area === "finance") {
        const f = await loadFinance(client);
        store.financeEntries = f.entries;
        store.financeCategories = f.categories;
      }
      if (area === "improvements") store.improvements = await loadImprovements(client);
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

  // ----- el espacio del servidor: insignia en la Nube y, con los avisos activados, una notificación (una vez al día) al llegar al 80 %
  const warned = loadWarned(window.localStorage);
  function syncQuota() {
    const stats = store.serverStats;
    const over = stats ? overQuota(stats, { db: prefs.value.quotaDbMb, files: prefs.value.quotaFilesMb }) : [];
    shell.setAlert("nube", over.length ? percent(Math.max(...over.map((q) => q.ratio))) : null, over.map(warningText).join(" "));
    if (!over.length || !prefs.value.notify) return;
    const now = Date.now();
    let changed = false;
    for (const q of over) {
      if (!shouldRenotify(warned[q.id] ?? null, now)) continue;
      if (showAlert({ key: `quota:${q.id}`, title: "Espacio del servidor", body: warningText(q) }, { sound: prefs.value.sound }, () => (location.hash = "#/nube"))) {
        warned[q.id] = now;
        changed = true;
      }
    }
    if (changed) saveWarned(window.localStorage, warned);
  }
  cleanups.push(prefs.on(syncQuota)); // si cambias el límite o activas los avisos, se vuelve a comprobar

  // ----- mensajes sin leer y avisos
  /** Si estás viendo el chat (pestaña visible y chat abierto), no hay nada sin leer. */
  function syncUnread() {
    if (!document.hidden && shell.route === "chat") unread = 0;
    shell.setUnread(unread);
  }

  /** Cuenta los mensajes nuevos como sin leer y, si lo pediste, muestra el aviso. `live` = llegó por el tiempo real (o al
   * reconectar); al volver a la pestaña (`resume`) solo se cuentan, no se avisa de lo que ya tienes delante. */
  function announce(added: Message[], source: "live" | "resume") {
    const view = { hidden: document.hidden, route: shell.route };
    unread += added.filter((m) => countsAsUnread(m, view)).length;
    syncUnread();
    if (source !== "live" || !prefs.value.notify) return;
    const toShow = added.filter((m) => shouldNotify(m, view, true)).slice(-3); // pocas a la vez: no inundar
    for (const m of toShow) showNotification(m, { preview: prefs.value.preview, sound: prefs.value.sound && m === toShow[toShow.length - 1] }, () => (location.hash = "#/chat"));
  }

  /** Pide solo los mensajes que llegaron después del último que tenemos. */
  async function catchUp(source: "live" | "resume" = "live") {
    if (!store.conversationId) return;
    try {
      const fresh = await listMessages(client, store.conversationId, { after: latestCreatedAt(store.messages), limit: 200 });
      if (fresh.length) {
        const known = new Set(store.messages.map((m) => m.id));
        const added = fresh.filter((m) => !known.has(m.id) && !m.deleted_at);
        store.messages = mergeMessages(store.messages, fresh);
        store.emit("messages");
        if (added.length) announce(added, source);
      }
    } catch {
      /* el siguiente cambio o la reconexión lo vuelven a intentar */
    }
  }

  async function measure() {
    const start = performance.now();
    const { data, error } = await client.rpc("my_profile");
    status.set({ latency: error ? null : performance.now() - start });
    if (!error) void touchPresence(client); // «sigo aquí»: así el administrador ve quién está en línea
    if (!error) {
      const p = data as { username?: string; role?: string } | null;
      const role = p?.role === "admin" ? "admin" : p?.role ? "visitante" : "";
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

  // Las llamadas de la familia suenan en cualquier sección: el controlador y su panel flotante viven mientras dure la sesión.
  let family: FamilyMember[] = [];
  const calls = new CallController({ client, userId: session.user.id, env: browserEnv(), members: () => family });
  void familyMembers(client).then((list) => (family = list)).catch(() => {}); // sin ser de la familia no hay nombres (ni llamadas)
  const callUi = callPanel(calls);
  document.body.append(callUi.el);
  cleanups.push(calls.attach(), callUi.destroy);

  const ctx: Ctx = { client, shell, store, player, status, prefs, backdrop, library, vault, userId: session.user.id, calls, signOut, reload };

  const go = (hash: string) => {
    location.hash = hash;
  };
  const palette = new Palette(() => buildPaletteItems({ client, store, prefs, vault, go }));

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
      syncUnread();
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
    // Ctrl+K: la paleta de comandos, también escribiendo en un campo
    if ((e.ctrlKey || e.metaKey) && !e.altKey && !e.shiftKey && e.key.toLowerCase() === "k") {
      e.preventDefault();
      palette.toggle();
      return;
    }
    // Esc: vuelve al mosaico. Si hay una ventana abierta, la cierra ella; si estás escribiendo, la primera vez solo sale del campo
    // (así lo que escribías se guarda antes de cambiar de sección).
    if (e.key === "Escape") {
      if (e.defaultPrevented || palette.isOpen || modalOpen()) return;
      if (isTyping(e.target)) {
        (e.target as HTMLElement).blur();
        return;
      }
      if (shell.route !== "inicio") location.hash = "#/inicio";
      return;
    }
    if (e.ctrlKey || e.metaKey || e.altKey || isTyping(e.target)) return;
    const id = routeForKey(prefs.value.keys, e.key);
    if (id) location.hash = `#/${id}`;
  };
  const onFocus = () => {
    void reload("tasks");
    void reload("tags");
    void reload("tracks");
    void reload("files");
    void reload("events");
    void reload("reminders");
    void reload("habits");
    void reload("finance");
    void reload("improvements");
    void reload("server");
    void catchUp("resume");
    syncUnread();
  };
  const onVisible = () => syncUnread();
  // la bóveda se bloquea sola tras unos minutos sin tocar nada: cualquier toque reinicia el reloj (como mucho una vez por segundo)
  let lastTouch = 0;
  const touch = () => {
    const now = Date.now();
    if (now - lastTouch < 1000) return;
    lastTouch = now;
    vault.touch();
  };
  window.addEventListener("hashchange", route);
  window.addEventListener("keydown", onKey);
  window.addEventListener("keydown", touch);
  window.addEventListener("pointerdown", touch);
  window.addEventListener("focus", onFocus);
  document.addEventListener("visibilitychange", onVisible);
  const pulse = window.setInterval(() => void measure(), 30_000);
  // los recordatorios que llegan a su hora y los hábitos con aviso: una notificación del navegador (misma preferencia y permiso que
  // los mensajes). Solo avisa de lo de los últimos 15 minutos, así que abrir Merida tarde no lanza una ráfaga de avisos viejos.
  const fired = new Set<string>();
  const checkAlerts = () => {
    if (!prefs.value.notify) return;
    const data = { events: store.events, tasks: store.tasks, reminders: store.reminders, habits: store.habits, checks: store.habitChecks };
    for (const a of pendingAlerts(data, new Date(), fired)) {
      fired.add(a.key);
      showAlert(a, { sound: prefs.value.sound }, () => (location.hash = "#/calendario"));
    }
  };
  const alertTimer = window.setInterval(checkAlerts, 20_000);
  const serverTimer = window.setInterval(() => void reload("server"), 30 * 60_000); // el espacio cambia despacio
  cleanups.push(() => {
    window.removeEventListener("hashchange", route);
    window.removeEventListener("keydown", onKey);
    window.removeEventListener("keydown", touch);
    window.removeEventListener("pointerdown", touch);
    window.removeEventListener("focus", onFocus);
    document.removeEventListener("visibilitychange", onVisible);
    window.clearInterval(pulse);
    window.clearInterval(alertTimer);
    window.clearInterval(serverTimer);
    palette.close();
    vault.destroy(); // sin clave ni entradas en memoria al cerrar sesión
  });

  root.replaceChildren(shell.root);
  route();
  void measure();
  void reload("tasks");
  void reload("tags");
  void reload("tracks");
  void reload("files");
  void reload("events");
  void reload("reminders");
  void reload("habits");
  void reload("finance");
  void reload("improvements");
  void reload("server");
  void vault.refresh();
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
          } else void catchUp("live");
        },
        (state) => {
          status.set({ live: state });
          if (state === "live" && wasLive) void catchUp("live"); // al volver tras un corte, ponerse al día
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

  /** Una cuenta nueva (creada por el administrador) pide primero su código de 6 dígitos; una ya verificada entra directo. */
  const enter = async (session: Session) => {
    const id = session.user.id;
    const verified = await myVerified(client);
    if (userId !== id) return; // mientras tanto cambió la sesión
    if (verified) {
      stop = startApp(session);
      return;
    }
    root.replaceChildren(verifyScreen(client, () => userId === id && (stop = startApp(session)), () => void client.auth.signOut()));
    document.title = "Verificar | Merida";
  };

  const apply = (session: Session | null) => {
    if (session && session.user.id !== userId) {
      stop?.();
      stop = null;
      userId = session.user.id;
      onLogin = false;
      void enter(session);
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
