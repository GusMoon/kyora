import { h } from "../ui/dom";
import { icon } from "../ui/icons";
import { LIVE_TEXT, latencyText, type StatusData } from "../status";
import { ACCENTS, START_OPTIONS, type AccentId, type StartRoute } from "../prefs";
import { summary } from "../data/tasks";
import { explainError } from "../supabase";
import { addCommand, checkCommandInput, listCommands, removeCommand, type ChatCommand } from "../data/commands";
import { FOLDER, SERVICE_DOWN, type MusicEvent, type Recipient } from "../data/library";
import { DEFAULT_KEYS, ROUTES } from "../routes";
import { applyKeyEdit } from "../hotkeys";
import { normalize } from "../palette";
import { permission, requestPermission, showNotification } from "../notify";
import type { Message } from "../data/chat";
import type { Ctx, Section } from "./context";

/** Las monedas que se ofrecen en Finanzas (el código ISO que guarda cada movimiento). */
export const CURRENCIES: { id: string; name: string }[] = [
  { id: "MXN", name: "Peso mexicano (MXN)" },
  { id: "USD", name: "Dólar estadounidense (USD)" },
  { id: "EUR", name: "Euro (EUR)" },
  { id: "COP", name: "Peso colombiano (COP)" },
  { id: "ARS", name: "Peso argentino (ARS)" },
  { id: "CLP", name: "Peso chileno (CLP)" },
  { id: "PEN", name: "Sol peruano (PEN)" },
  { id: "GBP", name: "Libra esterlina (GBP)" },
  { id: "CAD", name: "Dólar canadiense (CAD)" },
];

const PERMISSION_TEXT: Record<string, string> = {
  granted: "Permiso concedido: Merida puede mostrar avisos.",
  denied: "El navegador bloqueó los avisos de esta página. Para activarlos, cambia el permiso de notificaciones en la barra de direcciones (el candado) y vuelve a intentarlo.",
  default: "Aún no has dado permiso. Se te pedirá al activar los avisos.",
  unsupported: "Este navegador no permite notificaciones.",
};

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

  // ----- Atajos de teclado (editables): una sola letra o número por sección; Esc y Ctrl+K son fijos
  const keyState = h("p", { class: "cfg-note", role: "status" });
  const keyRows = h("div", { class: "sys keys" });
  const paintKeys = () => {
    keyRows.replaceChildren(
      ...ROUTES.map((r) => {
        const input = h("input", { type: "text", class: "key-input", maxlength: 1, readonly: true, value: prefs.value.keys[r.id], "aria-label": `Tecla para ${r.title}`, autocomplete: "off", spellcheck: "false" });
        input.value = prefs.value.keys[r.id];
        input.addEventListener("focus", () => input.select());
        input.addEventListener("keydown", (e) => {
          if (e.key === "Tab" || e.ctrlKey || e.metaKey || e.altKey) return; // moverse por la página sigue funcionando
          e.preventDefault();
          if (e.key === "Escape") return input.blur();
          const edit = applyKeyEdit(prefs.value.keys, r.id, e.key);
          keyState.dataset.error = String(!edit.ok);
          if (!edit.ok) {
            keyState.textContent = edit.error;
            return;
          }
          prefs.set({ keys: edit.keys });
          keyState.textContent = `${r.title}: tecla ${edit.keys[r.id]}.`;
          paintKeys();
          rows(r.id)?.focus();
        });
        return row(r.title, input);
      }),
      row("Paleta de comandos", h("span", { class: "readout" }, "Ctrl + K (fija)")),
      row("Volver al mosaico", h("span", { class: "readout" }, "Esc (fija)")),
    );
  };
  const rows = (id: string) => keyRows.querySelector<HTMLInputElement>(`input[aria-label="Tecla para ${ROUTES.find((r) => r.id === id)?.title}"]`);
  paintKeys();
  const keysBlock = block("Atajos de teclado",
    h("p", { class: "cfg-help" }, "Pulsa dentro de una casilla y luego la letra o el número que quieras. No se puede repetir una tecla."),
    keyRows,
    keyState,
    h("button", { class: "btn-quiet", type: "button", onClick: () => { prefs.set({ keys: { ...DEFAULT_KEYS } }); keyState.dataset.error = "false"; keyState.textContent = "Atajos restablecidos."; paintKeys(); } }, "Restablecer atajos"),
  );

  // ----- Avisos de mensajes (notificaciones del navegador, solo con la pestaña abierta)
  const permText = h("p", { class: "cfg-note", role: "status" });
  const paintPerm = () => {
    permText.textContent = PERMISSION_TEXT[permission()] ?? "";
  };
  paintPerm();
  const notifyToggle = toggle("Avisar de mensajes nuevos", "Una notificación cuando llega un mensaje de la PC o del móvil y no estás viendo el chat. Funciona con la pestaña abierta, aunque esté en segundo plano; con la pestaña cerrada no avisa.", prefs.value.notify && permission() === "granted", (on) => {
    const input = notifyToggle.querySelector<HTMLInputElement>("input")!;
    if (!on) return prefs.set({ notify: false });
    void (async () => {
      const result = await requestPermission();
      paintPerm();
      if (result === "granted") prefs.set({ notify: true });
      else {
        prefs.set({ notify: false });
        input.checked = false;
      }
    })();
  });
  const sample: Message = { id: "demo", conversation_id: "", sender_device: "movil", kind: "text", body: "Así se verá un aviso de Merida.", status: "sent", sent_at: "", created_at: "", deleted_at: null, attachments: [] };
  const notifyBlock = block("Avisos de mensajes",
    notifyToggle,
    toggle("Sonido corto", "Un pitido breve al llegar el aviso.", prefs.value.sound, (on) => prefs.set({ sound: on })),
    toggle("Mostrar el texto del mensaje", "Apagado, el aviso solo dice «Mensaje nuevo» (útil si compartes pantalla).", prefs.value.preview, (on) => prefs.set({ preview: on })),
    h("button", { class: "btn-edge", type: "button", onClick: () => { paintPerm(); if (!showNotification(sample, { preview: prefs.value.preview, sound: prefs.value.sound })) permText.textContent = `${PERMISSION_TEXT[permission()] ?? ""} No se pudo mostrar el aviso de prueba.`; } }, icon("bell", "icon"), "Probar aviso"),
    permText,
  );

  // ----- Finanzas: la moneda
  const currencySelect = h("select", { "aria-label": "Moneda de Finanzas" }, CURRENCIES.map((c) => h("option", { value: c.id, selected: c.id === prefs.value.currency }, c.name)));
  if (!CURRENCIES.some((c) => c.id === prefs.value.currency)) currencySelect.prepend(h("option", { value: prefs.value.currency }, prefs.value.currency));
  currencySelect.value = prefs.value.currency;
  currencySelect.addEventListener("change", () => prefs.set({ currency: currencySelect.value }));
  const financeBlock = block("Finanzas", h("p", { class: "cfg-help" }, "La moneda de los movimientos nuevos y de los resúmenes. Los movimientos ya guardados conservan la suya."), currencySelect);

  // ----- Servidor: los límites de tu plan de Supabase (la Nube avisa al llegar al 80 % de ellos)
  const limitInput = (label: string, value: number, key: "quotaDbMb" | "quotaFilesMb") => {
    const input = h("input", { type: "number", min: "1", max: "10000000", step: "1", "aria-label": label, inputmode: "numeric" });
    input.value = String(value);
    input.addEventListener("change", () => {
      const n = Number(input.value);
      if (Number.isInteger(n) && n >= 1 && n <= 10_000_000) prefs.set({ [key]: n });
      else input.value = String(prefs.value[key]);
    });
    return h("label", { class: "label cfg-field" }, label, input);
  };
  const serverBlock = block("Servidor",
    h("p", { class: "cfg-help" }, "Los límites de tu plan de Supabase. La Nube mide lo que ocupas y avisa al llegar al 80 %. El plan gratuito da 500 MB de base de datos y 1 GB (1024 MB) de archivos."),
    limitInput("Base de datos (MB)", prefs.value.quotaDbMb, "quotaDbMb"),
    limitInput("Archivos (MB)", prefs.value.quotaFilesMb, "quotaFilesMb"),
  );

  // ----- Organización: cuatro grupos con un índice fijo a la izquierda (salto directo, marca la sección que estás viendo y un
  //       buscador que deja solo los ajustes que coinciden)
  const GROUPS: { name: string; blocks: HTMLElement[] }[] = [
    { name: "Cuenta", blocks: [account, metrics] },
    { name: "Apariencia", blocks: [effects, accent, wallpaper] },
    { name: "Uso", blocks: [start, keysBlock, notifyBlock] },
    { name: "Módulos", blocks: [financeBlock, serverBlock, commandsBlock, music] },
  ];
  const titleOf = (el: HTMLElement) => el.querySelector(".cfg-title")?.textContent?.trim() ?? "";
  const reduceMotion = window.matchMedia?.("(prefers-reduced-motion: reduce)").matches ?? false;
  const navButtons = new Map<HTMLElement, HTMLButtonElement>();
  for (const g of GROUPS) {
    for (const el of g.blocks) {
      el.id = `cfg-${normalize(titleOf(el)).replace(/[^a-z0-9]+/g, "-")}`;
      el.tabIndex = -1; // así el salto del índice puede dejar el foco en el bloque
    }
  }
  const jump = (el: HTMLElement) => {
    el.scrollIntoView({ behavior: reduceMotion ? "auto" : "smooth", block: "start" });
    el.focus({ preventScroll: true });
    setActive(el);
  };
  const setActive = (el: HTMLElement | null) => {
    for (const [block, btn] of navButtons) {
      if (block === el) btn.setAttribute("aria-current", "true");
      else btn.removeAttribute("aria-current");
    }
  };
  const search = h("input", { type: "search", class: "cfg-search", placeholder: "Buscar un ajuste…", "aria-label": "Buscar un ajuste", autocomplete: "off", spellcheck: "false" });
  const noMatch = h("p", { class: "cfg-note cfg-nomatch", role: "status", hidden: true }, "Ningún ajuste coincide con la búsqueda.");
  const nav = h(
    "nav",
    { class: "cfg-nav", "aria-label": "Ajustes" },
    search,
    ...GROUPS.map((g) =>
      h(
        "div",
        { class: "cfg-nav-group" },
        h("p", { class: "cfg-nav-title label" }, g.name),
        h(
          "ul",
          {},
          g.blocks.map((el) => {
            const btn = h("button", { class: "cfg-nav-link", type: "button", onClick: () => jump(el) }, titleOf(el));
            navButtons.set(el, btn);
            return h("li", {}, btn);
          }),
        ),
      ),
    ),
  );
  const sections = GROUPS.map((g) => ({ g, el: h("section", { class: "cfg-group", "aria-label": g.name }, h("h2", { class: "cfg-group-title label" }, g.name), h("div", { class: "cfg-grid" }, ...g.blocks)) }));
  const content = h("div", { class: "cfg-content" }, ...sections.map((x) => x.el), noMatch);
  const layout = h("div", { class: "cfg-layout" }, nav, content);

  /** Deja solo los bloques cuyo texto contiene lo buscado (sin acentos ni mayúsculas); un grupo sin bloques también se esconde. */
  const filter = () => {
    const q = normalize(search.value);
    let any = false;
    for (const { g, el } of sections) {
      let shown = 0;
      for (const block of g.blocks) {
        const hit = !q || normalize(`${titleOf(block)} ${block.textContent ?? ""}`).includes(q);
        block.hidden = !hit;
        navButtons.get(block)!.closest("li")!.hidden = !hit;
        if (hit) shown++;
      }
      el.hidden = shown === 0;
      any ||= shown > 0;
    }
    for (const group of nav.querySelectorAll<HTMLElement>(".cfg-nav-group")) group.hidden = ![...group.querySelectorAll("li")].some((li) => !li.hidden);
    noMatch.hidden = any;
  };
  search.addEventListener("input", filter);
  search.addEventListener("keydown", (e) => {
    if (e.key === "Escape" && search.value) {
      e.stopPropagation(); // el primer Esc solo vacía la búsqueda
      search.value = "";
      filter();
    }
  });

  // la sección que se ve queda marcada en el índice (no existe en jsdom: ahí solo marca la última pulsada)
  if (typeof IntersectionObserver !== "undefined") {
    const seen = new Set<HTMLElement>();
    const observer = new IntersectionObserver(
      (entries) => {
        for (const e of entries) {
          if (e.isIntersecting) seen.add(e.target as HTMLElement);
          else seen.delete(e.target as HTMLElement);
        }
        const first = GROUPS.flatMap((g) => g.blocks).find((b) => seen.has(b));
        if (first) setActive(first);
      },
      { root: shell.body, rootMargin: "0px 0px -60% 0px", threshold: 0 },
    );
    for (const g of GROUPS) for (const el of g.blocks) observer.observe(el);
    cleanups.push(() => observer.disconnect());
  }
  setActive(account);

  shell.body.append(layout);

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
