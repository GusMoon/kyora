import { h, s } from "./dom";
import { icon, type IconName } from "./icons";
import type { Store } from "../store";
import type { PrefsStore } from "../prefs";
import type { VaultSession } from "../vault/session";
import { blocksFor, lastMessage, lineWidths, statusCounts } from "../data/home";
import { cloudStatement } from "../data/cloud";
import { eventsStatement } from "../data/events";
import { financeStatement } from "../data/finance";
import { tasksStatement } from "../sections/tasks";
import { musicStatement } from "../sections/music";
import { chatStatement } from "../sections/chat";
import { vaultStatement } from "../sections/vault";
import { DEFAULT_KEYS, ROUTES, type KeyMap, type RouteId, type SectionId } from "../routes";

export { ROUTES };
export type { RouteId, SectionId };

export interface ShellDeps {
  store: Store;
  vault?: VaultSession; // sin ella (vista previa, pruebas) la tesela de Contraseñas no dice el estado
  prefs?: PrefsStore; // para la moneda de Finanzas
}

const SLOTS = 5; // bloques que caben por columna en el dibujo de Tareas

/** Las columnas de Tareas: cada columna es un estado y se llena con tantos bloques como tareas hay (hasta 5). */
function tasksArt() {
  const group = s("g");
  const svg = s("svg", { viewBox: "0 0 168 124", class: "tile-art", "aria-hidden": "true", focusable: "false" }, group);
  return {
    el: svg,
    update(blocks: number[]) {
      group.replaceChildren();
      blocks.forEach((count, col) => {
        const x = col * 43 + 1;
        group.append(s("line", { x1: x, y1: 122, x2: x + 36, y2: 122, stroke: "currentColor", "stroke-width": 2 }));
        for (let slot = 0; slot < SLOTS; slot++) {
          const y = 98 - slot * 23;
          group.append(s("rect", { x, y, width: 36, height: 19, class: slot < count ? "art-on" : "art-off" }));
        }
      });
    },
  };
}

/** Un disco visto de frente, en alambre: surcos, etiqueta y brazo. */
function discArt() {
  const grooves = [54, 44, 34, 24].map((r) => s("circle", { cx: 60, cy: 64, r, class: r === 54 ? "art-line" : "art-faint" }));
  // el disco (surcos y etiqueta) va en su grupo para poder girar sin mover el brazo
  const disc = s("g", { class: "art-disc" }, ...grooves, s("circle", { cx: 60, cy: 64, r: 14, class: "art-on" }), s("circle", { cx: 60, cy: 50, r: 3, class: "art-hole" }));
  return s(
    "svg",
    { viewBox: "0 0 130 124", class: "tile-art", "aria-hidden": "true", focusable: "false" },
    disc,
    s("path", { d: "M122 4 L122 34 L96 78", class: "art-line" }),
    s("rect", { x: 90, y: 74, width: 14, height: 10, class: "art-on", transform: "rotate(28 97 79)" }),
  );
}

/** Un terminal: una línea por mensaje reciente (más larga si el mensaje es más largo) y el cursor al final. */
function terminalArt() {
  const group = s("g");
  const svg = s("svg", { viewBox: "0 0 168 112", class: "tile-art", "aria-hidden": "true", focusable: "false" }, group);
  return {
    el: svg,
    update(widths: number[]) {
      group.replaceChildren();
      widths.forEach((w, i) => {
        const y = 6 + i * 21;
        group.append(s("path", { d: `M0 ${y} L8 ${y + 6} L0 ${y + 12}`, class: "art-line" }));
        group.append(s("rect", { x: 18, y: y + 1, width: Math.round(w * 140), height: 10, class: i === widths.length - 1 ? "art-on" : "art-mid" }));
      });
      const last = widths.length - 1;
      group.append(s("rect", { x: 18 + Math.round(widths[last] * 140) + 6, y: 6 + last * 21 - 1, width: 9, height: 14, class: "art-on" }));
    },
  };
}

/** Una nube en alambre con tres archivos colgando: el más nuevo, en el acento. */
function cloudArt() {
  return s(
    "svg",
    { viewBox: "0 0 150 112", class: "tile-art", "aria-hidden": "true", focusable: "false" },
    s("path", { d: "M34 68 A19 19 0 0 1 36 30 A28 28 0 0 1 90 24 A22 22 0 0 1 112 68 Z", class: "art-line" }),
    s("rect", { x: 30, y: 84, width: 26, height: 22, class: "art-off" }),
    s("rect", { x: 62, y: 84, width: 26, height: 22, class: "art-off" }),
    s("rect", { x: 94, y: 84, width: 26, height: 22, class: "art-on" }),
    s("path", { d: "M43 68 V84 M75 68 V84 M107 68 V84", class: "art-faint" }),
  );
}

/** Un mes en alambre: la cabecera, cuatro columnas de días y unos cuantos marcados (el de hoy, en el acento). */
function calendarArt() {
  const cells: SVGElement[] = [];
  for (let r = 0; r < 3; r++) {
    for (let c = 0; c < 5; c++) {
      const on = r === 1 && c === 2;
      cells.push(s("rect", { x: 10 + c * 26, y: 40 + r * 22, width: 20, height: 16, class: on ? "art-on" : r === 0 && c === 4 ? "art-mid" : "art-off" }));
    }
  }
  return s(
    "svg",
    { viewBox: "0 0 150 112", class: "tile-art", "aria-hidden": "true", focusable: "false" },
    s("rect", { x: 4, y: 6, width: 142, height: 100, class: "art-line" }),
    s("path", { d: "M4 28 H146 M36 0 V14 M114 0 V14", class: "art-faint" }),
    ...cells,
  );
}

/** Un candado en alambre con el ojo de la cerradura en el acento. */
function vaultArt() {
  return s(
    "svg",
    { viewBox: "0 0 130 124", class: "tile-art", "aria-hidden": "true", focusable: "false" },
    s("g", { class: "art-shackle" }, s("path", { d: "M34 54 V38 A28 28 0 0 1 90 38 V54", class: "art-line" })),
    s("rect", { x: 18, y: 54, width: 88, height: 62, class: "art-off" }),
    s("rect", { x: 56, y: 72, width: 12, height: 12, class: "art-on" }),
    s("path", { d: "M62 84 V100", class: "art-line" }),
  );
}

/** Barras de un balance: la última, en el acento. */
function financeArt() {
  const heights = [34, 58, 44, 76, 52, 90];
  return s(
    "svg",
    { viewBox: "0 0 150 112", class: "tile-art", "aria-hidden": "true", focusable: "false" },
    s("path", { d: "M2 106 H148", class: "art-faint" }),
    ...heights.map((hh, i) => s("rect", { x: 8 + i * 24, y: 106 - hh, width: 16, height: hh, class: i === heights.length - 1 ? "art-on" : "art-off" })),
  );
}

interface SectionTile {
  el: HTMLElement;
  link: HTMLAnchorElement;
  statement: HTMLElement;
  panel: HTMLElement;
  face: HTMLElement; // el cuadrado del dock
  keyEl: HTMLElement; // la tecla que se ve en la esquina
  badge: HTMLElement; // el contador de avisos (mensajes sin leer)
  title: string;
}

/** Una tesela que abre una sección. En el mosaico toda ella es un enlace (el del título se estira); abierta, ocupa la
 * pantalla con su sección; cuando otra está abierta, se encoge a un cuadrado con su icono en el borde izquierdo. */
function sectionTile(route: SectionId, title: string, key: string, iconName: IconName, onClose: () => void, ...body: (Element | null)[]): SectionTile {
  const link = h("a", { class: "tile-link", href: `#/${route}` }, title);
  const statement = h("p", { class: "tile-statement", "aria-live": "polite" });
  const panel = h("div", { class: "tile-panel" });
  const face = h("a", { class: "dock-face", href: `#/${route}`, "aria-label": `${title} (tecla ${key})` }, icon(iconName, "icon dock-icon"), h("span", { class: "dock-label", "aria-hidden": "true" }, title));
  const keyEl = h("kbd", { class: "tile-key", title: `Tecla ${key}` }, key);
  const badge = h("span", { class: "tile-badge", hidden: true, role: "status" });
  const el = h(
    "section",
    { class: `tile tile-${route}`, "data-route": route, "aria-labelledby": `tile-${route}-title` },
    h(
      "header",
      { class: "tile-head" },
      h("span", { class: "tile-mark" }, icon(iconName, "icon tile-icon")),
      h("h2", { class: "tile-title", id: `tile-${route}-title` }, link),
      h(
        "span",
        { class: "tile-tools" },
        badge,
        keyEl,
        icon("arrow", "icon tile-arrow"),
        h(
          "button",
          { class: "tile-close", type: "button", "aria-label": "Cerrar y volver al inicio", title: "Volver al mosaico (Esc)", onClick: onClose },
          icon("close"),
          h("span", { class: "tile-close-label", "aria-hidden": "true" }, "Mosaico"),
          h("kbd", { class: "tile-close-key", "aria-hidden": "true" }, "Esc"),
        ),
      ),
    ),
    statement,
    ...body,
    panel,
    face,
  );
  return { el, link, statement, panel, face, keyEl, badge, title };
}

/** El tablero de Merida: siete teselas siempre montadas. En Inicio forman un mosaico de 3×3 con Configuración en el
 * centro exacto; al abrir una sección su tesela ocupa toda la pantalla y las demás se esconden en el borde izquierdo
 * como cuadrados con su icono (salen al pasar el cursor por el borde o al llegar con el tabulador). */
export class Shell {
  readonly root: HTMLElement;
  private current: RouteId = "inicio";
  private readonly sections: Record<SectionId, SectionTile>;
  private readonly idle = h("div");
  private readonly cleanups: (() => void)[] = [];
  private readonly order: HTMLElement[]; // las teselas en el orden del documento
  private baseTitle = "Merida";
  private unread = 0;

  constructor(deps: ShellDeps) {
    const { store, vault, prefs } = deps;
    const goHome = () => {
      location.hash = "#/inicio";
    };
    const keyOf = (id: RouteId) => DEFAULT_KEYS[id];

    // ----- Tareas
    const tasksNote = h("p", { class: "tile-note" });
    const tasks = tasksArt();
    const tareas = sectionTile("tareas", "Tareas", keyOf("tareas"), "tasks", goHome, h("div", { class: "tile-foot" }, tasksNote), tasks.el);

    // ----- Calendario
    const calendarNote = h("p", { class: "tile-note" });
    const calendario = sectionTile("calendario", "Calendario", keyOf("calendario"), "calendar", goHome, h("div", { class: "tile-foot" }, calendarNote), calendarArt());

    // ----- Música
    const musicNote = h("p", { class: "tile-note" });
    const musica = sectionTile("musica", "Música", keyOf("musica"), "music", goHome, h("div", { class: "tile-foot" }, musicNote), discArt());

    // ----- Chat
    const chatDevice = h("span", { class: "tile-tag label" });
    const chatText = h("p", { class: "tile-quote" });
    const chatNote = h("p", { class: "tile-note" });
    const terminal = terminalArt();
    const chat = sectionTile("chat", "Chat", keyOf("chat"), "chat", goHome, h("div", { class: "tile-foot" }, chatDevice, chatText, chatNote), terminal.el);

    // ----- Contraseñas
    const vaultNote = h("p", { class: "tile-note" });
    const contrasenas = sectionTile("contrasenas", "Contraseñas", keyOf("contrasenas"), "lock", goHome, h("div", { class: "tile-foot" }, vaultNote), vaultArt());

    // ----- Finanzas
    const financeNote = h("p", { class: "tile-note" });
    const finanzas = sectionTile("finanzas", "Finanzas", keyOf("finanzas"), "wallet", goHome, h("div", { class: "tile-foot" }, financeNote), financeArt());

    // ----- Configuración (en el centro): un cuadrado con su icono, nada más; todo lo demás está dentro de la sección
    const configuracion = sectionTile("configuracion", "Configuración", keyOf("configuracion"), "settings", goHome, h("span", { class: "tile-glyph", "aria-hidden": "true" }, icon("settings", "icon")));

    // ----- Nube (los archivos compartidos por Supabase que hay ahora en el servidor)
    const cloudNote = h("p", { class: "tile-note" });
    const nube = sectionTile("nube", "Nube", keyOf("nube"), "cloud", goHome, h("div", { class: "tile-foot" }, cloudNote), cloudArt());

    this.sections = { tareas, calendario, musica, nube, chat, contrasenas, finanzas, configuracion };
    this.order = [tareas.el, musica.el, nube.el, configuracion.el, calendario.el, contrasenas.el, chat.el, finanzas.el];
    // el sensor del borde izquierdo: al pasar el cursor por ahí aparece el dock
    const edge = h("div", { class: "edge", "aria-hidden": "true" });
    this.root = h("div", { class: "board", "data-mode": "home", "data-active": "inicio" }, ...this.order, edge);

    // ----- Datos en las teselas
    const renderStore = () => {
      const { tasks: t, tracks, messages, files, loaded, errors } = store;
      tasksNote.textContent = tasksStatement(t, loaded.tasks, errors.tasks);
      tasks.update(blocksFor(statusCounts(t), SLOTS));
      calendarNote.textContent = eventsStatement(store.events, t, loaded.events, errors.events);
      musicNote.textContent = musicStatement(tracks, loaded.tracks, errors.tracks);
      const last = lastMessage(messages);
      chatDevice.textContent = last ? last.device : "";
      chatDevice.hidden = !last;
      chatText.textContent = last ? last.text : "";
      chatText.hidden = !last;
      chatNote.textContent = chatStatement(messages, loaded.messages, errors.messages);
      terminal.update(lineWidths(messages, 5));
      cloudNote.textContent = cloudStatement(files, loaded.files, errors.files);
      vaultNote.textContent = vault ? vaultStatement(vault) : "Tus claves, cifradas en este navegador.";
      financeNote.textContent = financeStatement(store.financeEntries, loaded.finance, errors.finance, new Date(), prefs?.value.currency);
    };
    renderStore();
    this.cleanups.push(store.on(renderStore));
    if (vault) this.cleanups.push(vault.on(renderStore));
    if (prefs) this.cleanups.push(prefs.on(() => { this.setKeys(prefs.value.keys); renderStore(); }));
    if (prefs) this.setKeys(prefs.value.keys);
  }

  /** Cambia la tecla que se muestra en cada tesela y en el dock (los atajos son editables en Configuración). */
  setKeys(keys: KeyMap) {
    for (const [id, tile] of Object.entries(this.sections) as [SectionId, SectionTile][]) {
      const key = keys[id] ?? DEFAULT_KEYS[id];
      tile.keyEl.textContent = key;
      tile.keyEl.title = `Tecla ${key}`;
      tile.face.setAttribute("aria-label", `${tile.title} (tecla ${key})`);
    }
  }

  /** Un aviso en la esquina de una tesela (por ejemplo «84 %» en la Nube cuando el servidor casi se llena). Sin texto, se quita. */
  setAlert(route: SectionId, text: string | null, label = "") {
    const badge = this.sections[route]?.badge;
    if (!badge) return;
    badge.hidden = !text;
    badge.textContent = text ?? "";
    badge.classList.toggle("is-warn", !!text);
    if (label) badge.setAttribute("aria-label", label);
  }

  /** Los mensajes sin leer: un contador en la tesela de Chat y `(n)` delante del título de la pestaña. */
  setUnread(n: number) {
    this.unread = Math.max(0, n);
    const badge = this.sections.chat.badge;
    badge.hidden = this.unread === 0;
    badge.textContent = this.unread > 99 ? "99+" : String(this.unread);
    badge.setAttribute("aria-label", this.unread === 1 ? "1 mensaje sin leer" : `${this.unread} mensajes sin leer`);
    this.renderTitle();
  }

  private renderTitle() {
    document.title = this.unread ? `(${this.unread}) ${this.baseTitle}` : this.baseTitle;
  }

  /** Dónde monta su contenido la sección abierta (en Inicio no hay nada que montar). */
  get body(): HTMLElement {
    return this.current === "inicio" ? this.idle : this.sections[this.current].panel;
  }

  get route(): RouteId {
    return this.current;
  }

  /** Lo que entra y sale con los efectos: los bloques (holograma) y los textos (hacking). */
  fxTargets(route: RouteId = this.current): { blocks: HTMLElement[]; texts: HTMLElement[] } {
    if (route === "inicio") {
      const texts = this.order.flatMap((tile) => [...tile.querySelectorAll<HTMLElement>(".tile-link")]);
      return { blocks: [...this.order], texts };
    }
    const tile = this.sections[route];
    const blocks = [tile.el.querySelector<HTMLElement>(".tile-head")!, tile.statement, ...([...tile.panel.children] as HTMLElement[])];
    const texts = [tile.link, tile.statement, ...tile.panel.querySelectorAll<HTMLElement>("[data-hack]")];
    return { blocks: blocks.filter(Boolean), texts };
  }

  /** Abre una sección (o vuelve al mosaico con "inicio"). */
  setSection(route: RouteId, statement: string) {
    const previous = this.current;
    // si el foco estaba dentro de la tesela que se cierra (el botón ×, un campo…), vuelve a su enlace en el mosaico
    const returnFocus = previous !== "inicio" && route === "inicio" && (this.sections[previous as SectionId].el.contains(document.activeElement) || document.activeElement === document.body);
    this.current = route;
    this.root.dataset.mode = route === "inicio" ? "home" : "focus";
    this.root.dataset.active = route;
    for (const [id, tile] of Object.entries(this.sections) as [SectionId, SectionTile][]) {
      const active = id === route;
      tile.el.classList.toggle("is-active", active);
      tile.panel.replaceChildren();
      tile.statement.textContent = active ? statement : "";
      if (active) tile.link.setAttribute("aria-current", "page");
      else tile.link.removeAttribute("aria-current");
    }
    // el puesto de cada una en el dock (las que no están abiertas, en su orden)
    const docked = this.order.filter((tile) => !tile.classList.contains("is-active"));
    this.root.style.setProperty("--dock-n", String(docked.length));
    docked.forEach((tile, i) => tile.style.setProperty("--dock-i", String(i)));
    const r = ROUTES.find((x) => x.id === route)!;
    this.baseTitle = route === "inicio" ? "Merida" : `${r.title} | Merida`;
    this.renderTitle();
    if (returnFocus) this.sections[previous as SectionId].link.focus({ preventScroll: true });
  }

  setStatement(text: string) {
    if (this.current !== "inicio") this.sections[this.current].statement.textContent = text;
  }

  destroy() {
    for (const fn of this.cleanups) fn();
    this.root.remove();
  }
}
