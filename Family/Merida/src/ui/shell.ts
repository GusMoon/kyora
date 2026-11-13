import { h, s } from "./dom";
import { icon, type IconName } from "./icons";
import type { Store } from "../store";
import { blocksFor, lastMessage, lineWidths, statusCounts } from "../data/home";
import { cloudStatement } from "../data/cloud";
import { tasksStatement } from "../sections/tasks";
import { musicStatement } from "../sections/music";
import { chatStatement } from "../sections/chat";

export type RouteId = "inicio" | "tareas" | "musica" | "nube" | "chat" | "configuracion";
export type SectionId = Exclude<RouteId, "inicio">;

export const ROUTES: { id: RouteId; title: string; key: string }[] = [
  { id: "inicio", title: "Inicio", key: "I" },
  { id: "tareas", title: "Tareas", key: "T" },
  { id: "musica", title: "Música", key: "M" },
  { id: "nube", title: "Nube", key: "N" },
  { id: "chat", title: "Chat", key: "C" },
  { id: "configuracion", title: "Configuración", key: "A" },
];

export interface ShellDeps {
  store: Store;
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
  return s(
    "svg",
    { viewBox: "0 0 130 124", class: "tile-art", "aria-hidden": "true", focusable: "false" },
    ...grooves,
    s("circle", { cx: 60, cy: 64, r: 14, class: "art-on" }),
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

interface SectionTile {
  el: HTMLElement;
  link: HTMLAnchorElement;
  statement: HTMLElement;
  panel: HTMLElement;
  face: HTMLElement; // el cuadrado del dock
}

/** Una tesela que abre una sección. En el mosaico toda ella es un enlace (el del título se estira); abierta, ocupa la
 * pantalla con su sección; cuando otra está abierta, se encoge a un cuadrado con su icono en el borde izquierdo. */
function sectionTile(route: SectionId, title: string, key: string, iconName: IconName, onClose: () => void, ...body: (Element | null)[]): SectionTile {
  const link = h("a", { class: "tile-link", href: `#/${route}` }, title);
  const statement = h("p", { class: "tile-statement", "aria-live": "polite" });
  const panel = h("div", { class: "tile-panel" });
  const face = h("a", { class: "dock-face", href: `#/${route}`, "aria-label": `${title} (tecla ${key})` }, icon(iconName, "icon dock-icon"), h("span", { class: "dock-label", "aria-hidden": "true" }, title));
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
        h("kbd", { class: "tile-key", title: `Tecla ${key}` }, key),
        icon("arrow", "icon tile-arrow"),
        h("button", { class: "tile-close", type: "button", "aria-label": "Cerrar y volver al inicio", title: "Cerrar (Esc)", onClick: onClose }, icon("close")),
      ),
    ),
    statement,
    ...body,
    panel,
    face,
  );
  return { el, link, statement, panel, face };
}

/** El tablero de Merida: cinco teselas siempre montadas. En Inicio forman un mosaico con Configuración en el centro
 * exacto; al abrir una sección su tesela ocupa toda la pantalla y las demás se esconden en el borde izquierdo como
 * cuadrados con su icono (salen al pasar el cursor por el borde o al llegar con el tabulador). */
export class Shell {
  readonly root: HTMLElement;
  private current: RouteId = "inicio";
  private readonly sections: Record<SectionId, SectionTile>;
  private readonly idle = h("div");
  private readonly cleanups: (() => void)[] = [];
  private readonly order: HTMLElement[]; // las teselas en el orden del documento

  constructor(deps: ShellDeps) {
    const { store } = deps;
    const goHome = () => {
      location.hash = "#/inicio";
    };

    // ----- Tareas
    const tasksNote = h("p", { class: "tile-note" });
    const tasks = tasksArt();
    const tareas = sectionTile("tareas", "Tareas", "T", "tasks", goHome, h("div", { class: "tile-foot" }, tasksNote), tasks.el);

    // ----- Música
    const musicNote = h("p", { class: "tile-note" });
    const musica = sectionTile("musica", "Música", "M", "music", goHome, h("div", { class: "tile-foot" }, musicNote), discArt());

    // ----- Chat
    const chatDevice = h("span", { class: "tile-tag label" });
    const chatText = h("p", { class: "tile-quote" });
    const chatNote = h("p", { class: "tile-note" });
    const terminal = terminalArt();
    const chat = sectionTile("chat", "Chat", "C", "chat", goHome, h("div", { class: "tile-foot" }, chatDevice, chatText, chatNote), terminal.el);

    // ----- Configuración (en el centro): un cuadrado con su icono, nada más; todo lo demás está dentro de la sección
    const configuracion = sectionTile("configuracion", "Configuración", "A", "settings", goHome, h("span", { class: "tile-glyph", "aria-hidden": "true" }, icon("settings", "icon")));

    // ----- Nube (los archivos compartidos por Supabase que hay ahora en el servidor)
    const cloudNote = h("p", { class: "tile-note" });
    const nube = sectionTile("nube", "Nube", "N", "cloud", goHome, h("div", { class: "tile-foot" }, cloudNote), cloudArt());

    this.sections = { tareas, musica, nube, chat, configuracion };
    this.order = [tareas.el, musica.el, configuracion.el, nube.el, chat.el];
    // el sensor del borde izquierdo: al pasar el cursor por ahí aparece el dock
    const edge = h("div", { class: "edge", "aria-hidden": "true" });
    this.root = h("div", { class: "board", "data-mode": "home", "data-active": "inicio" }, ...this.order, edge);

    // ----- Datos en las teselas
    const renderStore = () => {
      const { tasks: t, tracks, messages, files, loaded, errors } = store;
      tasksNote.textContent = tasksStatement(t, loaded.tasks, errors.tasks);
      tasks.update(blocksFor(statusCounts(t), SLOTS));
      musicNote.textContent = musicStatement(tracks, loaded.tracks, errors.tracks);
      const last = lastMessage(messages);
      chatDevice.textContent = last ? last.device : "";
      chatDevice.hidden = !last;
      chatText.textContent = last ? last.text : "";
      chatText.hidden = !last;
      chatNote.textContent = chatStatement(messages, loaded.messages, errors.messages);
      terminal.update(lineWidths(messages, 5));
      cloudNote.textContent = cloudStatement(files, loaded.files, errors.files);
    };
    renderStore();
    this.cleanups.push(store.on(renderStore));
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
    document.title = route === "inicio" ? "Merida" : `${r.title} | Merida`;
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
