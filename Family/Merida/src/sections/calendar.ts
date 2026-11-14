import { h } from "../ui/dom";
import { icon } from "../ui/icons";
import { explainError } from "../supabase";
import { applyChanges, saveTasks, type Task } from "../data/tasks";
import {
  WEEKDAY_SHORT,
  applyEvents,
  combineDayTime,
  dayKey,
  eventsStatement,
  moveEventTo,
  moveTaskTo,
  parseDayKey,
  saveEvents,
  type CalendarEvent,
} from "../data/events";
import { applyChecks, applyHabits, minutesToHHMM, saveChecks, saveHabits, toggleCheck, type Habit } from "../data/habits";
import { applyReminders, moveReminderTo, saveReminders, type Reminder } from "../data/reminders";
import {
  KINDS,
  KIND_COLOR,
  KIND_LABEL,
  VIEWS,
  agendaForDay,
  agendaStatement,
  layoutDay,
  minutesAtY,
  rangeFor,
  stepSelected,
  type AgendaData,
  type AgendaItem,
  type Kind,
  type Placed,
  type View,
} from "../data/agenda";
import type { Area } from "../store";
import type { Ctx, Section } from "./context";
import { createSide, type Actions, type CalState, type Composer } from "./calendarSide";

export { eventsStatement, combineDayTime };

type DragPayload = { type: "event" | "task" | "reminder"; id: string };
const DRAGGABLE = new Set(["event", "task", "reminder"]);
const MAX_CHIPS = 3; // lo que cabe en una celda del mes antes del «+N más»
const START_HOUR = 7; // la hora a la que se abre la columna de horas (si hoy no está a la vista)
const PLURAL: Record<Kind, string> = { event: "Eventos", task: "Tareas", reminder: "Recordatorios", habit: "Hábitos" };
const SWATCH: Record<Kind, string> = { event: "#35d4ff", task: KIND_COLOR.task, reminder: KIND_COLOR.reminder, habit: KIND_COLOR.habit };

/** Un rectángulo del que sale el día al expandirse (en píxeles de pantalla). */
type Origin = Pick<DOMRect, "top" | "right" | "bottom" | "left"> | null;

export const calendarSection: Section = (ctx: Ctx) => {
  const { store, shell, client, prefs } = ctx;
  const cleanups: (() => void)[] = [];
  const state: CalState = {
    view: prefs.value.calendarView,
    selected: dayKey(new Date()),
    show: { event: true, task: true, reminder: true, habit: true },
    expanded: false,
    formOpen: false,
    edit: null,
    compose: "event",
    draftTime: null,
  };
  let tgScroll: number | null = null; // dónde estaba la columna de horas, para no perderlo al repintar

  const notice = h("p", { class: "notice", role: "status" });
  const loadNotice = h("p", { class: "notice", role: "status" });
  const grid = h("div", { class: "cal-grid" });

  const data = (): AgendaData => ({ events: store.events, tasks: store.tasks, reminders: store.reminders, habits: store.habits, checks: store.habitChecks });
  const shown = (): Kind[] => KINDS.filter((k) => state.show[k]);

  // ---------- guardar: se ve al instante y se sube; si falla, se vuelve a pedir lo del servidor
  async function commit(area: Area, apply: () => void, persist: () => Promise<void>, failed: string) {
    apply();
    store.emit(area);
    try {
      await persist();
      notice.textContent = "";
    } catch (err) {
      notice.textContent = `${failed} ${explainError(err)}`;
      await ctx.reload(area);
    }
  }

  const commitTasks = (rows: Task[]) => commit("tasks", () => (store.tasks = applyChanges(store.tasks, rows)), () => saveTasks(client, rows), "No se guardó la tarea.");

  const actions: Actions = {
    events: (rows: CalendarEvent[]) => commit("events", () => (store.events = applyEvents(store.events, rows)), () => saveEvents(client, rows), "No se guardó el evento."),
    reminders: (rows: Reminder[]) => commit("reminders", () => (store.reminders = applyReminders(store.reminders, rows)), () => saveReminders(client, rows), "No se guardó el recordatorio."),
    habits: (rows: Habit[]) => commit("habits", () => (store.habits = applyHabits(store.habits, rows)), () => saveHabits(client, rows), "No se guardó el hábito."),
    check: (habitId, key) => {
      const row = toggleCheck(store.habitChecks, habitId, key);
      return commit("habits", () => (store.habitChecks = applyChecks(store.habitChecks, [row])), () => saveChecks(client, [row]), "No se guardó la marca del hábito.");
    },
    openTask: (id) => {
      store.raise("open-task", id);
      location.hash = "#/tareas";
    },
  };

  const side = createSide(store, state, actions, () => renderAll());

  // ---------- el día expandido: se abre sobre el calendario, creciendo desde la celda que se pulsó
  const closeButton = h("button", { class: "btn-edge cal-close", type: "button", "aria-label": "Cerrar el día", onClick: () => closeDay() }, icon("close", "icon"), "Cerrar");
  const overlay = h("div", { class: "cal-expand", role: "dialog", "aria-modal": "false", "aria-label": "Día elegido", hidden: true }, closeButton, side.el);
  const stage = h("div", { class: "cal-stage" }, grid, overlay);

  function animateFrom(origin: Origin) {
    const s = stage.getBoundingClientRect();
    const pct = (v: number) => `${v}px`;
    if (origin && s.width > 0) {
      overlay.style.setProperty("--ft", pct(origin.top - s.top));
      overlay.style.setProperty("--fr", pct(s.right - origin.right));
      overlay.style.setProperty("--fb", pct(s.bottom - origin.bottom));
      overlay.style.setProperty("--fl", pct(origin.left - s.left));
    } else {
      for (const v of ["--ft", "--fr", "--fb", "--fl"]) overlay.style.setProperty(v, "30%");
    }
    overlay.classList.remove("is-opening");
    void overlay.offsetWidth; // reinicia la animación
    overlay.classList.add("is-opening");
  }

  /** Abre el día `key` (con su formulario de edición si se pulsó algo). Crece desde `origin`, la caja de la celda pulsada. */
  function openDay(key: string, origin: Origin, edit: CalState["edit"] = null) {
    const wasOpen = state.expanded;
    state.selected = key;
    state.expanded = true;
    state.edit = edit;
    state.formOpen = !!edit;
    renderAll();
    if (!wasOpen) animateFrom(origin);
    closeButton.focus({ preventScroll: true });
  }

  function closeDay() {
    if (!state.expanded) return;
    state.expanded = false;
    state.edit = null;
    state.formOpen = false;
    renderAll();
  }

  const rectOf = (el: Element): Origin => el.getBoundingClientRect();

  // ---------- selección y navegación
  function select(key: string) {
    state.selected = key;
    state.expanded = false;
    state.edit = null;
    state.formOpen = false;
    renderAll();
  }

  function setView(view: View) {
    if (state.view === view) return;
    state.view = view;
    tgScroll = null;
    prefs.set({ calendarView: view });
    renderAll();
    left.el.querySelector<HTMLElement>('.cal-views [aria-pressed="true"]')?.focus();
  }

  /** Suelta algo sobre un día (y, en la columna de horas, a una hora). Si no cambia nada, no sube nada. */
  function drop(key: string, payload: DragPayload, minutes: number | null) {
    if (payload.type === "event") {
      const e = store.events.find((x) => x.id === payload.id);
      const moved = e && moveEventTo(e, key, minutes);
      if (e && moved && moved.starts_at !== e.starts_at) void actions.events([moved]);
    } else if (payload.type === "task") {
      const t = store.tasks.find((x) => x.id === payload.id);
      const moved = t && moveTaskTo(t, key, minutes);
      if (t && moved && moved.due !== t.due) void commitTasks([moved]);
    } else {
      const r = store.reminders.find((x) => x.id === payload.id);
      const moved = r && moveReminderTo(r, key, minutes);
      if (r && moved && moved.remind_at !== r.remind_at) void actions.reminders([moved]);
    }
  }

  /** Hace de `el` una zona donde soltar tarjetas; `minutesOf` dice a qué hora (o null: solo el día). */
  function dropZone(el: HTMLElement, key: string, minutesOf: (e: DragEvent) => number | null = () => null) {
    el.addEventListener("dragover", (e) => {
      e.preventDefault();
      el.classList.add("is-over");
    });
    el.addEventListener("dragleave", (e) => {
      if (!el.contains(e.relatedTarget as Node | null)) el.classList.remove("is-over");
    });
    el.addEventListener("drop", (e) => {
      e.preventDefault();
      el.classList.remove("is-over");
      try {
        const payload = JSON.parse(e.dataTransfer?.getData("text/plain") ?? "") as DragPayload;
        if (DRAGGABLE.has(payload.type) && typeof payload.id === "string") drop(key, payload, minutesOf(e));
      } catch {
        /* se soltó otra cosa */
      }
    });
  }

  /** Hace de `el` algo que se pulsa con el ratón o el teclado. */
  function pressable(el: HTMLElement, label: string, run: () => void) {
    el.setAttribute("role", "button");
    el.tabIndex = 0;
    el.setAttribute("aria-label", label);
    el.addEventListener("click", (e) => {
      e.stopPropagation();
      run();
    });
    el.addEventListener("keydown", (e) => {
      if (e.key === "Enter" || e.key === " ") {
        e.preventDefault();
        e.stopPropagation();
        run();
      }
    });
  }

  function dragify(el: HTMLElement, item: AgendaItem) {
    const type = item.kind;
    if (type !== "event" && type !== "task" && type !== "reminder") return;
    el.setAttribute("draggable", "true");
    el.addEventListener("dragstart", (e) => {
      e.dataTransfer?.setData("text/plain", JSON.stringify({ type, id: item.id } satisfies DragPayload));
      if (e.dataTransfer) e.dataTransfer.effectAllowed = "move";
    });
  }

  /** Lo que hace pulsar un elemento: los hábitos se marcan, lo demás abre su día para editarlo. */
  function activate(item: AgendaItem, el: HTMLElement) {
    if (item.kind === "habit") {
      state.selected = item.day;
      if (item.day <= dayKey(new Date())) void actions.check(item.id, item.day);
      renderAll();
      return;
    }
    const kind = item.kind;
    openDay(item.day, rectOf(el), kind === "task" ? null : { kind, id: item.id });
  }

  const glyph = (item: AgendaItem): HTMLElement | null =>
    item.kind === "habit" ? h("span", { class: "cal-box", "aria-hidden": "true" }, item.done ? icon("check", "icon") : null) : item.kind === "reminder" ? h("span", { class: "cal-bell", "aria-hidden": "true" }, icon("bell", "icon")) : null;

  const itemLabel = (item: AgendaItem) => `${KIND_LABEL[item.kind]}: ${item.title}, ${item.time}${item.done ? ", hecho" : ""}`;

  /** Una pastilla (mes y franja de «todo el día»): color de su clase, hora a la derecha y, si dura varios días, unida a la del día siguiente. */
  function chip(item: AgendaItem, quiet = false): HTMLElement {
    const el = h("span", {
      class: `cal-chip is-${item.kind} span-${item.span}${item.done ? " is-done" : ""}${quiet ? " is-quiet" : ""}`,
      style: `--chip:${item.color}`,
      title: `${item.time} · ${item.title}`,
      "data-id": item.id,
    },
      glyph(item),
      h("span", { class: "cal-chip-title" }, item.title),
      item.allDay ? null : h("span", { class: "cal-chip-time readout" }, item.time),
    );
    dragify(el, item);
    pressable(el, itemLabel(item), () => activate(item, el));
    return el;
  }

  /** «Hábitos 2/3»: en el mes, todos los hábitos de un día en una sola pastilla. */
  function habitSummary(cell: HTMLElement, key: string, items: AgendaItem[]): HTMLElement {
    const prog = { total: items.length, done: items.filter((i) => i.done).length };
    const el = h("span", { class: `cal-chip is-habit is-summary span-single${prog.done === prog.total ? " is-done" : ""}`, style: "--chip:#5be38a", title: "Hábitos del día", "data-kind": "habit-summary" },
      h("span", { class: "cal-box", "aria-hidden": "true" }, prog.done === prog.total ? icon("check", "icon") : null),
      h("span", { class: "cal-chip-title" }, `Hábitos ${prog.done}/${prog.total}`),
    );
    pressable(el, `Hábitos del día: ${prog.done} de ${prog.total} hechos`, () => openDay(key, rectOf(cell)));
    return el;
  }

  // ---------- la vista del mes: cuadros separados por un pequeño margen
  function monthCell(d: Date, inMonth: boolean): HTMLElement {
    const key = dayKey(d);
    const agenda = agendaForDay(data(), key, shown());
    const habits = agenda.filter((i) => i.kind === "habit");
    const others = agenda.filter((i) => i.kind !== "habit");
    const items: HTMLElement[] = others.map((i) => chip(i, i.span !== "single" && i.span !== "start" && d.getDay() !== 1));
    const cell: HTMLElement = h("div", { class: "cal-cell", "data-day": key, "data-today": String(key === dayKey(new Date())), "data-selected": String(key === state.selected), "data-out": String(!inMonth) });
    if (habits.length) items.push(habitSummary(cell, key, habits));
    const overflow = items.length - MAX_CHIPS;
    // el día 1 lleva el mes («1 nov»): ya no hay título del mes arriba y así se sabe dónde empieza
    const label = d.getDate() === 1 ? `${d.getDate()} ${d.toLocaleDateString("es", { month: "short" }).replace(".", "")}` : String(d.getDate());
    cell.append(
      h("button", { class: "cal-day", type: "button", "aria-label": `${d.getDate()} de ${d.toLocaleDateString("es", { month: "long" })}${agenda.length ? `, ${agenda.length} ${agenda.length === 1 ? "elemento" : "elementos"}` : ""}`, "aria-pressed": String(key === state.selected), onClick: () => openDay(key, rectOf(cell)) }, label),
      h("div", { class: "cal-items" },
        items.slice(0, MAX_CHIPS),
        overflow > 0 ? h("button", { class: "cal-more readout", type: "button", onClick: () => openDay(key, rectOf(cell)) }, `+${overflow} más`) : null,
      ),
    );
    dropZone(cell, key);
    cell.addEventListener("click", (e) => {
      if (e.target === cell || (e.target as HTMLElement).classList.contains("cal-items")) openDay(key, rectOf(cell));
    });
    return cell;
  }

  function monthView(days: Date[]): HTMLElement {
    const month = parseDayKey(state.selected).getMonth();
    return h("div", { class: "cal-month" },
      h("div", { class: "cal-weekdays", "aria-hidden": "true" }, WEEKDAY_SHORT.map((w) => h("span", { class: "label" }, w))),
      h("div", { class: "cal-weeks" }, days.map((d) => monthCell(d, d.getMonth() === month))),
    );
  }

  // ---------- las vistas de semana y de día: columnas con horas
  function block(p: Placed): HTMLElement {
    const { item } = p;
    const el = h("div", {
      class: `cal-block is-${item.kind}${item.done ? " is-done" : ""}`,
      style: `--chip:${item.color};--top:${p.top};--len:${p.len};--lane:${p.lane};--lanes:${p.lanes}`,
      title: `${item.time} · ${item.title}`,
      "data-id": item.id,
    },
      glyph(item),
      h("span", { class: "cal-block-title" }, item.title),
      h("span", { class: "cal-block-time readout" }, item.time),
    );
    dragify(el, item);
    pressable(el, itemLabel(item), () => activate(item, el));
    return el;
  }

  function timeView(days: Date[]): HTMLElement {
    const todayKey = dayKey(new Date());
    const keys = days.map(dayKey);
    const agendas = days.map((_, i) => agendaForDay(data(), keys[i], shown()));

    const heads = days.map((d, i) => {
      const head: HTMLElement = h("button", { class: "cal-tg-day", type: "button", "data-today": String(keys[i] === todayKey), "data-selected": String(keys[i] === state.selected), "aria-pressed": String(keys[i] === state.selected), "aria-label": d.toLocaleDateString("es", { weekday: "long", day: "numeric", month: "long" }), onClick: () => openDay(keys[i], rectOf(head)) },
        h("span", { class: "label" }, WEEKDAY_SHORT[(d.getDay() + 6) % 7]),
        h("span", { class: "cal-tg-num" }, String(d.getDate())),
      );
      return head;
    });

    const allDay = days.map((d, i) => {
      const cell = h("div", { class: "cal-tg-allday-cell", "data-day": keys[i] }, agendas[i].filter((x) => x.allDay).map((x) => chip(x, x.span !== "single" && x.span !== "start" && d.getDay() !== 1 && days.length > 1)));
      dropZone(cell, keys[i]);
      return cell;
    });

    const cols = days.map((_, i) => {
      const col = h("div", { class: "cal-col", "data-day": keys[i], "data-today": String(keys[i] === todayKey), "data-selected": String(keys[i] === state.selected) }, layoutDay(agendas[i]).map(block));
      if (keys[i] === todayKey) {
        const now = new Date();
        col.append(h("div", { class: "cal-now", style: `--top:${now.getHours() * 60 + now.getMinutes()}`, "aria-hidden": "true" }));
      }
      const minutesAt = (e: MouseEvent) => {
        const r = col.getBoundingClientRect();
        return minutesAtY(e.clientY - r.top, r.height);
      };
      dropZone(col, keys[i], minutesAt);
      col.addEventListener("click", (e) => {
        if (e.target !== col || keys[i] === state.selected) return;
        state.selected = keys[i];
        renderAll();
      });
      col.addEventListener("dblclick", (e) => {
        if (e.target !== col) return;
        const m = minutesAt(e);
        state.compose = "event";
        state.draftTime = m === null ? null : minutesToHHMM(m);
        openDay(keys[i], rectOf(col), null);
        state.formOpen = true;
        side.render();
        side.focusTitle();
      });
      return col;
    });

    const gutter = h("div", { class: "cal-hours", "aria-hidden": "true" }, Array.from({ length: 24 }, (_, hr) => h("span", { class: "cal-hour readout", style: `--top:${hr * 60}` }, hr === 0 ? "" : `${String(hr).padStart(2, "0")}:00`)));

    const tg = h("div", { class: "cal-tg", style: `--cols:${days.length}`, "data-cols": String(days.length) },
      h("div", { class: "cal-tg-top" },
        h("span", { class: "cal-tg-corner" }),
        heads,
        h("span", { class: "cal-tg-corner label" }, "todo el día"),
        allDay,
      ),
      h("div", { class: "cal-tg-body" }, gutter, cols),
    );
    tg.addEventListener("scroll", () => (tgScroll = tg.scrollTop));
    return tg;
  }

  // ---------- el panel de la izquierda: a dónde ir, en qué formato y qué se muestra
  function buildLeft() {
    const title = h("h2", { class: "cal-title sr-only", "aria-live": "polite" });
    const prev = h("button", { class: "btn-step", type: "button", onClick: () => select(stepSelected(state.view, state.selected, -1)) }, icon("chevronLeft", "icon"));
    const next = h("button", { class: "btn-step", type: "button", onClick: () => select(stepSelected(state.view, state.selected, 1)) }, icon("chevronRight", "icon"));
    const today = h("button", { class: "btn-edge", type: "button", onClick: () => select(dayKey(new Date())) }, "Hoy");
    const viewButtons = VIEWS.map((v) => h("button", { class: "tab", type: "button", onClick: () => setView(v.id) }, v.label));
    const counts = new Map<Kind, HTMLElement>();
    const rows = KINDS.map((k) => {
      const count = h("span", { class: "cal-opt-count readout" }, "0");
      counts.set(k, count);
      const box = h("input", { type: "checkbox", checked: state.show[k], "aria-label": `Mostrar ${PLURAL[k].toLowerCase()}` });
      box.checked = state.show[k];
      box.addEventListener("change", () => {
        state.show[k] = box.checked;
        renderGrid();
      });
      return h("li", {}, h("label", { class: "cal-opt", style: `--chip:${SWATCH[k]}` }, box, h("span", { class: "cal-swatch", "aria-hidden": "true" }), h("span", { class: "cal-opt-name" }, PLURAL[k]), count));
    });
    const el = h("aside", { class: "cal-left", "aria-label": "Opciones del calendario" },
      title,
      h("section", { class: "cal-group" }, h("h3", { class: "label" }, "Ir a"), h("div", { class: "cal-nav" }, prev, today, next)),
      h("section", { class: "cal-group" }, h("h3", { class: "label" }, "Formato"), h("div", { class: "tabs cal-views", role: "group", "aria-label": "Vista" }, viewButtons)),
      h("section", { class: "cal-group" }, h("h3", { class: "label" }, "Mostrar"), h("ul", { class: "cal-show" }, rows)),
      h("p", { class: "cfg-help cal-find" }, "Para buscar un evento, recordatorio o hábito usa la paleta de comandos: ", h("kbd", {}, "Ctrl"), " + ", h("kbd", {}, "K"), "."),
    );
    const update = () => {
      const range = rangeFor(state.view, state.selected);
      const unit = state.view === "month" ? "Mes" : state.view === "week" ? "Semana" : "Día";
      title.textContent = `${range.title}. ${range.subtitle}`;
      prev.setAttribute("aria-label", `${unit} anterior`);
      next.setAttribute("aria-label", `${unit} siguiente`);
      VIEWS.forEach((v, i) => {
        viewButtons[i].setAttribute("aria-pressed", String(state.view === v.id));
        viewButtons[i].setAttribute("aria-selected", String(state.view === v.id));
      });
      const tally: Record<Kind, number> = { event: 0, task: 0, reminder: 0, habit: 0 };
      const habitIds = new Set<string>(); // los hábitos se cuentan una vez (no una por cada día en que tocan)
      for (const d of range.days) {
        for (const i of agendaForDay(data(), dayKey(d), "all")) {
          if (i.kind === "habit") habitIds.add(i.id);
          else tally[i.kind]++;
        }
      }
      tally.habit = habitIds.size;
      for (const k of KINDS) counts.get(k)!.textContent = String(tally[k]);
    };
    return { el, update };
  }
  const left = buildLeft();

  function renderGrid() {
    const range = rangeFor(state.view, state.selected);
    grid.replaceChildren(state.view === "month" ? monthView(range.days) : timeView(range.days));
    const tg = grid.querySelector<HTMLElement>(".cal-tg");
    if (tg) {
      const now = new Date();
      const showsToday = range.days.some((d) => dayKey(d) === dayKey(now));
      const hour = showsToday ? Math.max(0, now.getHours() - 1) : START_HOUR;
      // la cabecera pegajosa mide poco: scrollHeight / 24 es, con buena aproximación, el alto de una hora
      tg.scrollTop = tgScroll ?? (tg.scrollHeight / 24) * hour;
    }
  }

  function statement() {
    shell.setStatement(agendaStatement(data(), store.loaded.events, store.errors.events));
    const bits = [store.errors.reminders && `Recordatorios: ${store.errors.reminders}`, store.errors.habits && `Hábitos: ${store.errors.habits}`].filter(Boolean);
    loadNotice.textContent = bits.join(" ");
  }

  function renderAll() {
    statement();
    left.update();
    renderGrid();
    overlay.hidden = !state.expanded;
    overlay.setAttribute("aria-modal", String(state.expanded)); // la app (Esc, atajos) solo lo trata como ventana mientras está abierto
    if (state.expanded) grid.setAttribute("inert", "");
    else grid.removeAttribute("inert");
    side.render();
  }

  shell.body.append(notice, loadNotice, h("div", { class: "cal" }, left.el, h("div", { class: "cal-main" }, stage)));

  // Esc cierra el día abierto (antes de que la app vuelva al mosaico); si hay una ventana más (la paleta), ella va primero
  const onEsc = (e: KeyboardEvent) => {
    if (e.key !== "Escape" || !state.expanded || e.defaultPrevented) return;
    if (document.querySelectorAll('[aria-modal="true"]').length > 1) return;
    e.preventDefault();
    closeDay();
  };
  document.addEventListener("keydown", onEsc);
  cleanups.push(() => document.removeEventListener("keydown", onEsc));

  /** Las órdenes de la paleta: añadir algo (abre el día elegido o el de hoy con su formulario) o abrir un día. */
  const handleIntent = () => {
    const open = store.take("open-day");
    if (open?.arg) {
      openDay(open.arg, null);
      return;
    }
    const i = store.take("new-event", "new-reminder", "new-habit");
    if (!i) return;
    const compose: Composer = i.name === "new-reminder" ? "reminder" : i.name === "new-habit" ? "habit" : "event";
    const key = state.expanded ? state.selected : dayKey(new Date());
    state.compose = compose;
    state.draftTime = null;
    openDay(key, null);
    state.formOpen = true;
    side.render();
    side.focusTitle();
  };
  renderAll();
  handleIntent();
  cleanups.push(store.onIntent(handleIntent));
  cleanups.push(
    store.on((area) => {
      if (area === "events" || area === "tasks" || area === "reminders" || area === "habits") {
        // no repintar el panel si se está escribiendo en él: solo la cuadrícula
        statement();
        left.update();
        renderGrid();
        if (!side.el.contains(document.activeElement)) side.render();
      }
    }),
  );
  return () => {
    for (const fn of cleanups) fn();
  };
};
