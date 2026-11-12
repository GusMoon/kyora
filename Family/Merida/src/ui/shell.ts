import { h, s } from "./dom";
import type { Store } from "../store";
import type { Player } from "../player";
import { LIVE_TEXT, latencyText, type Status } from "../status";
import { blocksFor, lastMessage, lineWidths, statusCounts } from "../data/home";
import { formatTime } from "../data/music";
import { summary } from "../data/tasks";
import { tasksStatement } from "../sections/tasks";
import { musicStatement } from "../sections/music";
import { chatStatement } from "../sections/chat";

export type RouteId = "inicio" | "tareas" | "musica" | "chat";
export type SectionId = Exclude<RouteId, "inicio">;

export const ROUTES: { id: RouteId; title: string; key: string }[] = [
  { id: "inicio", title: "Inicio", key: "I" },
  { id: "tareas", title: "Tareas", key: "T" },
  { id: "musica", title: "Música", key: "M" },
  { id: "chat", title: "Chat", key: "C" },
];

export interface ShellDeps {
  store: Store;
  player: Player;
  status: Status;
  signOut: () => void;
}

const SLOTS = 5; // bloques que caben por columna en el dibujo de Tareas

const svgIcon = (d: string, cls = "icon") =>
  s("svg", { viewBox: "0 0 24 24", class: cls, "aria-hidden": "true", focusable: "false" }, s("path", { d, fill: "none", stroke: "currentColor", "stroke-width": 2, "stroke-linecap": "square" }));
const arrowIcon = () => svgIcon("M7 17 L17 7 M9 7 H17 V15", "icon tile-arrow");
const closeIcon = () => svgIcon("M6 6 L18 18 M18 6 L6 18");

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
          const on = slot < count;
          group.append(s("rect", { x, y, width: 36, height: 19, class: on ? "art-on" : "art-off" }));
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

interface SectionTile {
  el: HTMLElement;
  link: HTMLAnchorElement;
  statement: HTMLElement;
  panel: HTMLElement;
}

/** Una tesela que abre una sección. En el mosaico y en la columna, toda ella es un enlace (el del título se estira);
 * abierta, deja de serlo: muestra el enunciado, la sección y el botón de cerrar. */
function sectionTile(route: SectionId, num: string, title: string, key: string, onClose: () => void, foot: HTMLElement, art: Element): SectionTile {
  const link = h("a", { class: "tile-link", href: `#/${route}` }, title);
  const statement = h("p", { class: "tile-statement", "aria-live": "polite" });
  const panel = h("div", { class: "tile-panel" });
  const el = h(
    "section",
    { class: `tile tile-${route}`, "data-route": route, "aria-labelledby": `tile-${route}-title` },
    h(
      "header",
      { class: "tile-head" },
      h("span", { class: "tile-num" }, `/${num}`),
      h("h2", { class: "tile-title", id: `tile-${route}-title` }, link),
      h("span", { class: "tile-tools" }, h("kbd", { class: "tile-key", title: `Tecla ${key}` }, key), arrowIcon(), h("button", { class: "tile-close", type: "button", "aria-label": "Cerrar y volver al inicio", title: "Cerrar (Esc)", onClick: onClose }, closeIcon())),
    ),
    statement,
    foot,
    art,
    panel,
  );
  return { el, link, statement, panel };
}

/** El tablero de Merida: seis teselas siempre montadas. En Inicio forman un mosaico a pantalla completa; al abrir una
 * sección, su tesela crece hasta ocupar la derecha y las demás se apilan en una columna a la izquierda (el CSS decide
 * con `data-mode`, y main.ts anima el cambio con View Transitions). */
export class Shell {
  readonly root: HTMLElement;
  private current: RouteId = "inicio";
  private readonly sections: Record<SectionId, SectionTile>;
  private readonly idle = h("div");
  private readonly cleanups: (() => void)[] = [];

  constructor(deps: ShellDeps) {
    const { store, player, status, signOut } = deps;
    const goHome = () => {
      location.hash = "#/inicio";
    };

    // ----- /01 Tareas
    const tasksNote = h("p", { class: "tile-note" });
    const tasks = tasksArt();
    const tareas = sectionTile("tareas", "01", "Tareas", "T", goHome, h("div", { class: "tile-foot" }, tasksNote), tasks.el);

    // ----- /02 Música
    const musicNote = h("p", { class: "tile-note" });
    const musica = sectionTile("musica", "02", "Música", "M", goHome, h("div", { class: "tile-foot" }, musicNote), discArt());

    // ----- /03 Chat
    const chatDevice = h("span", { class: "tile-tag label" });
    const chatText = h("p", { class: "tile-quote" });
    const chatNote = h("p", { class: "tile-note" });
    const terminal = terminalArt();
    const chat = sectionTile("chat", "03", "Chat", "C", goHome, h("div", { class: "tile-foot" }, chatDevice, chatText, chatNote), terminal.el);

    // ----- /04 Sonando (en lima: lo único que está vivo todo el tiempo)
    const playTitle = h("p", { class: "play-title" });
    const playSub = h("p", { class: "play-sub label" });
    const elapsed = h("span", { class: "readout" }, "0:00");
    const total = h("span", { class: "readout" }, "0:00");
    const fill = h("div", { class: "bar-fill" });
    const bar = h("div", { class: "bar", role: "slider", tabindex: 0, "aria-label": "Avance de la canción", "aria-valuemin": 0, "aria-valuemax": 100, "aria-valuenow": 0 }, fill);
    bar.addEventListener("click", (e) => {
      const r = bar.getBoundingClientRect();
      player.seek((e.clientX - r.left) / r.width);
    });
    bar.addEventListener("keydown", (e) => {
      const p = player.state;
      if (!p.duration) return;
      if (e.key === "ArrowRight") player.seek((p.time + 5) / p.duration);
      else if (e.key === "ArrowLeft") player.seek((p.time - 5) / p.duration);
      else return;
      e.preventDefault();
    });
    const prev = h("button", { class: "btn-step", type: "button", "aria-label": "Anterior", onClick: () => player.previous() }, "⏮");
    const toggle = h("button", { class: "btn-solid btn-play", type: "button", onClick: () => player.toggle() }, "Reproducir");
    const next = h("button", { class: "btn-step", type: "button", "aria-label": "Siguiente", onClick: () => player.next() }, "⏭");
    const pick = h("a", { class: "play-pick", href: "#/musica" }, "Elegir una canción");
    const sonando = h(
      "section",
      { class: "tile tile-play", "aria-labelledby": "tile-play-title" },
      h("header", { class: "tile-head" }, h("span", { class: "tile-num" }, "/04"), h("h2", { class: "tile-title", id: "tile-play-title" }, "Sonando")),
      h("div", { class: "play-body" }, playTitle, playSub, pick),
      h("div", { class: "play-deck" }, bar, h("div", { class: "deck-times" }, elapsed, total), h("div", { class: "deck-controls" }, prev, toggle, next)),
    );

    // ----- /05 Sistema
    const sysAccount = h("span", { class: "readout" });
    const sysLatency = h("span", { class: "readout" });
    const sysLatencyBar = h("span", { class: "meter-fill" });
    const sysDone = h("span", { class: "readout" });
    const sysDoneBar = h("span", { class: "meter-fill" });
    const sysClock = h("span", { class: "readout" });
    const badge = h("span", { class: "sys-badge label" });
    const sysRow = (label: string, value: HTMLElement, meter?: HTMLElement) =>
      h("div", { class: `sys-row${meter ? " has-meter" : ""}` }, h("span", { class: "label sys-label" }, label), meter ? h("span", { class: "meter", "aria-hidden": "true" }, meter) : null, value);
    const sistema = h(
      "section",
      { class: "tile tile-system", "aria-labelledby": "tile-system-title" },
      h("header", { class: "tile-head" }, h("span", { class: "tile-num" }, "/05"), h("h2", { class: "tile-title", id: "tile-system-title" }, "Sistema"), h("span", { class: "tile-tools" }, badge)),
      h("div", { class: "sys" }, sysRow("Cuenta", sysAccount), sysRow("Servidor", sysLatency, sysLatencyBar), sysRow("Tareas hechas", sysDone, sysDoneBar), sysRow("Hora", sysClock)),
    );

    // ----- /06 Salir
    const salir = h(
      "button",
      { class: "tile tile-exit", type: "button", onClick: signOut },
      h("span", { class: "exit-label" }, h("span", { class: "tile-num" }, "/06"), " > salir_"),
    );

    this.sections = { tareas, musica, chat };
    this.root = h("div", { class: "board", "data-mode": "home", "data-active": "inicio" }, tareas.el, sistema, musica.el, sonando, chat.el, salir);

    // ----- Datos en las teselas
    const renderStore = () => {
      const { tasks: t, tracks, messages, loaded, errors } = store;
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
      const sum = summary(t);
      const total = sum.open + sum.done;
      const pct = total ? Math.round((sum.done / total) * 100) : 0;
      sysDone.textContent = loaded.tasks ? `${pct}%` : "—";
      sysDoneBar.style.inlineSize = `${loaded.tasks ? pct : 0}%`;
    };
    renderStore();
    this.cleanups.push(store.on(renderStore));

    this.cleanups.push(
      player.on((p) => {
        const t = p.track;
        sonando.dataset.empty = String(!t);
        playTitle.textContent = t ? t.title : "Nada sonando";
        playSub.textContent = t ? (t.playlist ?? "sin lista") : "";
        pick.hidden = !!t;
        toggle.textContent = p.loading ? "Cargando" : p.playing ? "Pausar" : "Reproducir";
        toggle.disabled = !t || p.loading;
        prev.disabled = next.disabled = !t;
        const pct = p.duration ? (p.time / p.duration) * 100 : 0;
        fill.style.width = `${pct}%`;
        bar.setAttribute("aria-valuenow", String(Math.round(pct)));
        bar.setAttribute("aria-valuetext", `${formatTime(p.time)} de ${formatTime(p.duration)}`);
        elapsed.textContent = formatTime(p.time);
        total.textContent = formatTime(p.duration);
      }),
    );

    this.cleanups.push(
      status.on((st) => {
        sysAccount.textContent = st.account;
        sysLatency.textContent = latencyText(st.latency);
        // la barra se llena más cuanto más rápido responde (1 s o más = vacía)
        const ms = typeof st.latency === "number" ? st.latency : null;
        sysLatencyBar.style.inlineSize = `${ms === null ? 0 : Math.max(4, Math.min(100, 100 - ms / 10))}%`;
        badge.dataset.state = st.live;
        badge.textContent = st.live === "live" ? "chat en vivo, todo en línea" : `chat ${LIVE_TEXT[st.live]}`;
      }),
    );
    const tick = () => (sysClock.textContent = new Date().toLocaleTimeString("es", { hour12: false }));
    tick();
    const timer = window.setInterval(tick, 1000);
    this.cleanups.push(() => window.clearInterval(timer));
  }

  /** Dónde monta su contenido la sección abierta (en Inicio no hay nada que montar). */
  get body(): HTMLElement {
    return this.current === "inicio" ? this.idle : this.sections[this.current].panel;
  }

  get route(): RouteId {
    return this.current;
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
