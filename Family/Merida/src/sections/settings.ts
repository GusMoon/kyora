import { h } from "../ui/dom";
import { icon } from "../ui/icons";
import { LIVE_TEXT, latencyText, type StatusData } from "../status";
import { ACCENTS, START_OPTIONS, type AccentId, type StartRoute } from "../prefs";
import { summary } from "../data/tasks";
import { explainError } from "../supabase";
import { addCommand, checkCommandInput, listCommands, removeCommand, type ChatCommand } from "../data/commands";
import { FOLDER, SERVICE_DOWN, type MusicEvent, type Recipient } from "../data/library";
import type { Ctx, Section } from "./context";

export const BROWSERS: { id: string; name: string }[] = [
  { id: "chrome", name: "Chrome" },
  { id: "edge", name: "Edge" },
  { id: "brave", name: "Brave" },
  { id: "firefox", name: "Firefox" },
  { id: "opera", name: "Opera" },
  { id: "vivaldi", name: "Vivaldi" },
];

export function settingsStatement(st: StatusData): string {
  const who = st.username ? `${st.username}${st.role ? ` (${st.role})` : ""}` : st.email || "tu cuenta";
  return `Sesión de ${who}. Lo que cambies aquí se aplica al momento.`;
}

let uid = 0;
const nextId = (base: string) => `${base}-${++uid}`;

/** Un bloque de Configuración. El título se escribe con el efecto hacking al abrir. */
function block(title: string, ...content: (Node | null)[]): HTMLElement {
  const id = nextId("cfg");
  return h(
    "section",
    { class: "cfg-block", "aria-labelledby": id },
    h("h3", { class: "cfg-title", id }, h("span", { "data-hack": "" }, title)),
    ...content,
  );
}

const row = (label: string, value: Node, meter?: HTMLElement) =>
  h("div", { class: `sys-row${meter ? " has-meter" : ""}` }, h("span", { class: "label sys-label" }, label), meter ? h("span", { class: "meter", "aria-hidden": "true" }, meter) : null, value);

/** Un grupo de opciones (radio) en cuadros. `render(option)` pone lo de dentro de cada cuadro. */
function choice<T extends string>(legend: string, name: string, options: { id: T; name: string }[], current: T, onPick: (id: T) => void, render?: (o: { id: T; name: string }) => Node[]): HTMLElement {
  const set = h("fieldset", { class: "choice" }, h("legend", { class: "sr-only" }, legend));
  for (const o of options) {
    const input = h("input", { type: "radio", name, value: o.id, checked: o.id === current, class: "choice-input" });
    input.addEventListener("change", () => input.checked && onPick(o.id));
    set.append(h("label", { class: "choice-item" }, input, ...(render ? render(o) : [h("span", {}, o.name)]), icon("check", "icon choice-check")));
  }
  return set;
}

function toggle(label: string, help: string, checked: boolean, onChange: (on: boolean) => void): HTMLElement {
  const id = nextId("sw");
  const input = h("input", { type: "checkbox", role: "switch", id, checked, class: "switch-input" });
  input.addEventListener("change", () => onChange(input.checked));
  return h("div", { class: "switch-row" }, input, h("label", { for: id, class: "switch-label" }, h("span", { class: "switch-box", "aria-hidden": "true" }), h("span", {}, label)), h("p", { class: "cfg-help" }, help));
}

export const settingsSection: Section = (ctx: Ctx) => {
  const { status, store, prefs, backdrop, library, signOut, shell, client } = ctx;
  const cleanups: (() => void)[] = [];
  let alive = true;
  cleanups.push(() => (alive = false));

  // ----- /A Cuenta
  const user = h("span", { class: "readout" });
  const email = h("span", { class: "readout" });
  const role = h("span", { class: "readout" });
  const account = block("Cuenta",
    h("div", { class: "sys" }, row("Usuario", user), row("Correo", email), row("Rol", role), row("Dispositivo", h("span", { class: "readout" }, "web"))),
    h("button", { class: "btn-solid cfg-signout", type: "button", onClick: signOut }, icon("power"), "Cerrar sesión"),
  );

  // ----- /B Métricas
  const latency = h("span", { class: "readout" });
  const latencyBar = h("span", { class: "meter-fill" });
  const live = h("span", { class: "readout live-text" });
  const open = h("span", { class: "readout" });
  const done = h("span", { class: "readout" });
  const doneBar = h("span", { class: "meter-fill" });
  const tracks = h("span", { class: "readout" });
  const messages = h("span", { class: "readout" });
  const clock = h("span", { class: "readout" });
  const metrics = block("Métricas",
    h("div", { class: "sys" }, row("Servidor", latency, latencyBar), row("Chat", live), row("Tareas abiertas", open), row("Tareas hechas", done, doneBar), row("Canciones", tracks), row("Mensajes", messages), row("Hora", clock)),
  );

  // ----- /C Efectos
  const reduce = window.matchMedia?.("(prefers-reduced-motion: reduce)").matches ?? false;
  const effects = block("Efectos",
    toggle("Efecto hacking", "Los textos se escriben con caracteres al azar antes de quedarse, como en Kyra.", prefs.value.hack, (on) => prefs.set({ hack: on })),
    toggle("Holograma", "Las secciones entran y salen parpadeando, con bandas de interferencia.", prefs.value.holo, (on) => prefs.set({ holo: on })),
    reduce ? h("p", { class: "cfg-note" }, "Tu sistema pide reducir el movimiento: los efectos quedan apagados aunque estén encendidos aquí.") : null,
  );

  // ----- /D Al abrir Merida
  const start = block("Al abrir Merida", choice<StartRoute>("Qué se muestra al entrar", "cfg-start", START_OPTIONS, prefs.value.start, (id) => prefs.set({ start: id })));

  // ----- /E Color de acento
  const accent = block("Color de acento",
    choice<AccentId>("Color de acento", "cfg-accent", ACCENTS, prefs.value.accent, (id) => prefs.set({ accent: id }), (o) => [
      h("span", { class: "swatch", style: `background:${ACCENTS.find((a) => a.id === o.id)!.color}`, "aria-hidden": "true" }),
      h("span", {}, o.name),
    ]),
  );

  // ----- Fondo de pantalla (temporal: dura la sesión)
  const wallState = h("p", { class: "cfg-note", role: "status" });
  const wallThumb = h("span", { class: "wall-thumb", "aria-hidden": "true" });
  const wallInput = h("input", { type: "file", accept: "image/*", id: "cfg-wall-file", hidden: true });
  const wallPick = h("button", { class: "btn-solid", type: "button", onClick: () => wallInput.click() });
  const wallClear = h("button", { class: "btn-quiet", type: "button", onClick: () => backdrop.clearWallpaper() }, "Quitar fondo");
  wallInput.addEventListener("change", () => {
    const file = wallInput.files?.[0];
    wallInput.value = "";
    if (file) void backdrop.setWallpaper(file);
  });
  const wallpaper = block("Fondo de pantalla",
    h("div", { class: "wall-row" }, wallThumb, h("div", { class: "wall-actions" }, wallState, h("div", { class: "wall-buttons" }, wallPick, wallClear, wallInput))),
    toggle("Vestir con los colores del fondo", "El acento sale de la imagen o de la portada que suena, como en Kyra. Apagado, manda el color de acento de arriba.", prefs.value.tint, (on) => prefs.set({ tint: on })),
    toggle("Portada de lo que suena, de fondo", "Mientras suena una canción con portada, esa portada es el fondo; al pausar vuelve el de antes.", prefs.value.cover, (on) => prefs.set({ cover: on })),
    h("p", { class: "cfg-note" }, "El fondo es temporal: dura mientras la sesión esté abierta. Se borra al cerrar sesión o al cerrar esta pestaña, y la imagen no sale de tu navegador."),
  );
  const renderWall = () => {
    const has = !!backdrop.wallpaper;
    wallState.textContent = backdrop.busy ? "Guardando…" : backdrop.error || (has ? "Hay un fondo puesto." : "Ahora hay el fondo liso de siempre.");
    wallState.dataset.error = String(!!backdrop.error);
    wallPick.textContent = backdrop.busy ? "Guardando…" : has ? "Cambiar imagen" : "Elegir imagen";
    wallPick.disabled = backdrop.busy;
    wallClear.hidden = !has;
    wallThumb.style.backgroundImage = has ? `url("${backdrop.wallpaper}")` : "";
    wallThumb.dataset.empty = String(!has);
  };
  renderWall();
  cleanups.push(backdrop.on(renderWall));

  // ----- /F Música (servicio local)
  const serviceState = h("p", { class: "cfg-note", role: "status" }, "Conectando con el servicio de música…");
  const musicBody = h("div", { class: "cfg-music" });
  const music = block("Música", serviceState, musicBody);

  // ----- /G Comandos del chat (en la base de datos: tabla chat_commands)
  const cmdState = h("p", { class: "cfg-note", role: "status" }, "Cargando tus comandos…");
  const cmdList = h("ul", { class: "cmd-list", "aria-label": "Comandos del chat" });
  const cmdName = h("input", { type: "text", placeholder: "Nombre (YouTube)", "aria-label": "Nombre de la web", maxlength: 60, autocomplete: "off" });
  const cmdWord = h("input", { type: "text", placeholder: "/youtube", "aria-label": "Comando", maxlength: 25, autocomplete: "off", spellcheck: "false" });
  const cmdUrl = h("input", { type: "text", placeholder: "https://youtube.com", "aria-label": "Dirección de la web", autocomplete: "off", spellcheck: "false", inputmode: "url" });
  const cmdAdd = h("button", { class: "btn-solid", type: "submit" }, "Añadir comando");
  const cmdForm = h("form", { class: "cmd-form" }, cmdName, cmdWord, cmdUrl, cmdAdd);
  const commandsBlock = block("Comandos del chat",
    h("p", { class: "cfg-help" }, "Escribe /comando en el chat y se abre la web en otra pestaña, sin mandar ningún mensaje. Se guardan en tu cuenta."),
    cmdState,
    cmdList,
    cmdForm,
  );
  let commands: ChatCommand[] = [];
  const renderCommands = () => {
    cmdList.replaceChildren(
      ...commands.map((c) =>
        h("li", { class: "cmd-item" },
          h("span", { class: "cmd-word" }, `/${c.command}`),
          h("span", { class: "cmd-name" }, c.name),
          h("span", { class: "cmd-url", title: c.url }, c.url),
          h("button", { class: "btn-edge is-danger", type: "button", "aria-label": `Quitar el comando /${c.command}`, onClick: () => void removeOne(c) }, icon("trash", "icon"), "Quitar"),
        ),
      ),
    );
  };
  async function loadCommands() {
    try {
      commands = await listCommands(client);
      if (!alive) return;
      cmdState.textContent = commands.length ? "" : "Aún no tienes comandos. Añade el primero abajo.";
      cmdState.dataset.error = "false";
    } catch (err) {
      if (!alive) return;
      cmdState.textContent = explainError(err);
      cmdState.dataset.error = "true";
    }
    renderCommands();
  }
  async function removeOne(c: ChatCommand) {
    try {
      await removeCommand(client, c.id);
      commands = commands.filter((x) => x.id !== c.id);
      cmdState.textContent = `/${c.command} quitado.`;
      cmdState.dataset.error = "false";
    } catch (err) {
      cmdState.textContent = explainError(err);
      cmdState.dataset.error = "true";
    }
    renderCommands();
  }
  cmdForm.addEventListener("submit", (e) => {
    e.preventDefault();
    void (async () => {
      const check = checkCommandInput({ name: cmdName.value, command: cmdWord.value, url: cmdUrl.value }, commands);
      cmdState.dataset.error = String(!check.ok);
      if (!check.ok) {
        cmdState.textContent = check.error;
        return;
      }
      cmdAdd.disabled = true;
      try {
        const created = await addCommand(client, check.value);
        commands = [...commands, created].sort((a, b) => a.command.localeCompare(b.command));
        cmdName.value = cmdWord.value = cmdUrl.value = "";
        cmdState.textContent = `/${created.command} guardado.`;
        cmdState.dataset.error = "false";
        renderCommands();
      } catch (err) {
        cmdState.textContent = explainError(err);
        cmdState.dataset.error = "true";
      } finally {
        cmdAdd.disabled = false;
      }
    })();
  });

  shell.body.append(h("div", { class: "cfg-grid" }, account, metrics, effects, start, accent, wallpaper, commandsBlock, music));

  // ----- datos vivos
  cleanups.push(
    status.on((st) => {
      user.textContent = st.username || "—";
      email.textContent = st.email || "—";
      role.textContent = st.role || "—";
      latency.textContent = latencyText(st.latency);
      const ms = typeof st.latency === "number" ? st.latency : null;
      latencyBar.style.inlineSize = `${ms === null ? 0 : Math.max(4, Math.min(100, 100 - ms / 10))}%`;
      live.textContent = LIVE_TEXT[st.live];
      live.dataset.state = st.live;
      shell.setStatement(settingsStatement(st));
    }),
  );
  const renderStore = () => {
    const sum = summary(store.tasks);
    const all = sum.open + sum.done;
    const pct = all ? Math.round((sum.done / all) * 100) : 0;
    open.textContent = store.loaded.tasks ? String(sum.open) : "—";
    done.textContent = store.loaded.tasks ? `${pct}%` : "—";
    doneBar.style.inlineSize = `${store.loaded.tasks ? pct : 0}%`;
    tracks.textContent = store.loaded.tracks ? String(store.tracks.length) : "—";
    messages.textContent = store.loaded.messages ? String(store.messages.length) : "—";
  };
  renderStore();
  cleanups.push(store.on(renderStore));
  const tick = () => (clock.textContent = new Date().toLocaleTimeString("es", { hour12: false }));
  tick();
  const timer = window.setInterval(tick, 1000);
  cleanups.push(() => window.clearInterval(timer));

  // ----- ajustes de música: viven en el servicio local (merida.json), no en el navegador
  async function loadMusic() {
    serviceState.textContent = "Conectando con el servicio de música…";
    musicBody.replaceChildren();
    const ok = await library.connect();
    if (!alive) return;
    if (!ok) {
      serviceState.textContent = SERVICE_DOWN;
      musicBody.replaceChildren(h("button", { class: "btn-quiet", type: "button", onClick: () => void loadMusic() }, "Reintentar"));
      return;
    }
    const res = await library.settings();
    if (!alive) return;
    if (!res.ok) {
      serviceState.textContent = res.error?.message ?? SERVICE_DOWN;
      return;
    }
    serviceState.textContent = "Servicio de música conectado en esta PC.";
    renderMusic(res.data as { browser: string; folder: string; default_recipient: string | null });
  }

  function renderMusic(cfg: { browser: string; folder: string; default_recipient: string | null }) {
    const saved = h("p", { class: "cfg-saved", role: "status" });
    const save = async (patch: Record<string, unknown>, what: string) => {
      saved.textContent = "Guardando…";
      const res = await library.saveSettings(patch);
      saved.textContent = res.ok ? `${what}: guardado.` : (res.error?.message ?? "No se pudo guardar");
    };
    const browser = choice("Navegador del que se leen las cookies", "cfg-browser", BROWSERS, cfg.browser, (id) => void save({ browser: id }, "Navegador"));
    const folder = h("input", { type: "text", value: cfg.folder, "aria-label": "Carpeta de descargas", spellcheck: "false" });
    folder.value = cfg.folder;
    const folderForm = h("form", { class: "composer composer-inline" }, folder, h("button", { class: "btn-solid", type: "submit" }, "Guardar carpeta"));
    folderForm.addEventListener("submit", (e) => {
      e.preventDefault();
      void save({ folder: folder.value.trim() }, "Carpeta");
    });
    const recipients = h("div", { class: "cfg-recipients" }, h("p", { class: "cfg-help" }, "Cargando a quién se le puede mandar…"));
    const renderRecipients = (people: Recipient[]) => {
      const options = people.map((p) => ({ id: p.id === null ? "me" : String(p.id), name: p.id === FOLDER ? "Esta PC (carpeta)" : p.name }));
      const current = cfg.default_recipient ?? "me";
      recipients.replaceChildren(choice("Destino por defecto al descargar", "cfg-recipient", options, current, (id) => void save({ default_recipient: id }, "Destino por defecto")));
    };
    cleanups.push(
      library.events((ev: MusicEvent) => {
        if (ev.kind === "recipients") renderRecipients((ev.recipients as Recipient[]) ?? []);
      }),
    );
    void library.act("music.recipients");
    musicBody.replaceChildren(
      h("p", { class: "cfg-sub label" }, "Navegador de las cookies"),
      h("p", { class: "cfg-help" }, "Merida lee tu sesión de YouTube de este navegador para ver tus listas. Si falla, en Música puedes pegar un cookies.txt."),
      browser,
      h("p", { class: "cfg-sub label" }, "Carpeta de descargas"),
      h("p", { class: "cfg-help" }, "Donde se guardan los MP3 cuando eliges «Esta PC (carpeta)»."),
      folderForm,
      h("p", { class: "cfg-sub label" }, "Destino por defecto"),
      recipients,
      saved,
    );
  }
  void loadMusic();
  void loadCommands();

  return () => {
    for (const fn of cleanups) fn();
  };
};
