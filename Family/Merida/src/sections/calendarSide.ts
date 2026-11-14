import { h } from "../ui/dom";
import { STATUS_LABEL } from "../data/tasks";
import {
  EVENT_COLORS,
  WEEKDAYS,
  combineDayTime,
  dayKey,
  isoDayKey,
  longDate,
  newEvent,
  parseDayKey,
  softDeleteEvent,
  updateEvent,
  type CalendarEvent,
} from "../data/events";
import { KIND_LABEL, agendaForDay, type AgendaData, type AgendaItem, type Kind, type View } from "../data/agenda";
import { WEEKDAY_LETTERS, EVERY_DAY, hhmmToMinutes, minutesToHHMM, newHabit, softDeleteHabit, streak, updateHabit, weekdaysLabel, type Habit } from "../data/habits";
import { isOverdue, newReminder, softDeleteReminder, toggleReminder, updateReminder, type Reminder } from "../data/reminders";
import type { Store } from "../store";

/** El panel del día del Calendario: lo que hay ese día (eventos, entregas, recordatorios y hábitos) y el formulario para
 * añadir o editar. Está aparte de la cuadrícula para que escribir en el formulario no se pierda al repintar las vistas. */

export type Composer = "event" | "reminder" | "habit";

export interface CalState {
  view: View;
  selected: string; // «aaaa-mm-dd»
  show: Record<Kind, boolean>; // qué clases se ven (las que dejes marcadas en el panel de la izquierda)
  expanded: boolean; // el día elegido está abierto (expandido sobre el calendario)
  formOpen: boolean; // se está añadiendo algo (se abre desde la paleta de comandos)
  edit: { kind: Exclude<Kind, "task">; id: string } | null; // lo que se está editando en el panel
  compose: Composer; // lo que se va a crear
  
  draftTime: string | null; // la hora con que abrir el formulario (al hacer doble clic en una hora de la cuadrícula)
}

export interface Actions {
  events(rows: CalendarEvent[]): Promise<void>;
  reminders(rows: Reminder[]): Promise<void>;
  habits(rows: Habit[]): Promise<void>;
  check(habitId: string, key: string): Promise<void>;
  openTask(id: string): void;
}

const COLOR_NAMES: Record<string, string> = { "#35d4ff": "Cian", "#c8f73a": "Lima", "#ff5a1f": "Naranja", "#ff4fd8": "Magenta", "#ffd23f": "Amarillo", "#c9cebc": "Salvia" };
const COMPOSERS: { id: Composer; label: string }[] = [
  { id: "event", label: "Evento" },
  { id: "reminder", label: "Recordatorio" },
  { id: "habit", label: "Hábito" },
];

export interface Side {
  el: HTMLElement;
  render(): void;
  /** Lleva el foco al primer campo del formulario (si lo hay). */
  focusTitle(): void;
}

export function createSide(store: Store, state: CalState, actions: Actions, rerender: () => void): Side {
  const el = h("aside", { class: "cal-side", "aria-label": "Día elegido" });
  let titleInput: HTMLInputElement | null = null;

  const data = (): AgendaData => ({ events: store.events, tasks: store.tasks, reminders: store.reminders, habits: store.habits, checks: store.habitChecks });
  const today = () => dayKey(new Date());

  // ---------- una fila de la lista del día
  function entry(item: AgendaItem): HTMLElement {
    const actionsRow = (...buttons: (HTMLElement | null)[]) => h("span", { class: "cal-entry-actions" }, buttons);
    const edit = (kind: "event" | "reminder" | "habit", label: string) =>
      h("button", { class: "btn-quiet", type: "button", "aria-label": `Editar ${label}`, onClick: () => { state.edit = { kind, id: item.id }; render(); } }, "Editar");

    if (item.kind === "event") {
      const e = store.events.find((x) => x.id === item.id);
      return h("li", { class: "cal-entry is-event", style: `--chip:${item.color}` },
        h("span", { class: "cal-time readout" }, item.time),
        h("span", { class: "cal-entry-title" }, item.title),
        e?.description ? h("p", { class: "cal-entry-desc" }, e.description) : null,
        e ? actionsRow(edit("event", `el evento ${item.title}`), h("button", { class: "btn-quiet", type: "button", "aria-label": `Borrar el evento ${item.title}`, onClick: () => { if (confirm(`¿Borrar «${item.title}»?`)) void actions.events([softDeleteEvent(e)]); } }, "Borrar")) : null,
      );
    }
    if (item.kind === "task") {
      const t = store.tasks.find((x) => x.id === item.id);
      return h("li", { class: "cal-entry is-task", style: `--chip:${item.color}` },
        h("span", { class: "cal-time readout" }, item.time),
        h("span", { class: `cal-entry-title${item.done ? " is-done" : ""}` }, item.title),
        h("span", { class: "label cal-status" }, `tarea · ${t ? STATUS_LABEL[t.status] : ""}`),
        actionsRow(h("button", { class: "btn-quiet", type: "button", onClick: () => actions.openTask(item.id) }, "Abrir")),
      );
    }
    if (item.kind === "reminder") {
      const r = store.reminders.find((x) => x.id === item.id);
      const late = r ? isOverdue(r) : false;
      return h("li", { class: `cal-entry is-reminder${late ? " is-late" : ""}`, style: `--chip:${item.color}` },
        h("span", { class: "cal-time readout" }, item.time),
        h("label", { class: "cal-entry-title cal-check-row" },
          h("input", { type: "checkbox", checked: item.done, "aria-label": `Marcar «${item.title}» como hecho`, onChange: () => { if (r) void actions.reminders([toggleReminder(r)]); } }),
          h("span", { class: item.done ? "is-done" : "" }, item.title),
        ),
        r?.notes ? h("p", { class: "cal-entry-desc" }, r.notes) : null,
        r ? actionsRow(edit("reminder", `el recordatorio ${item.title}`), h("button", { class: "btn-quiet", type: "button", "aria-label": `Borrar el recordatorio ${item.title}`, onClick: () => { if (confirm(`¿Borrar «${item.title}»?`)) void actions.reminders([softDeleteReminder(r)]); } }, "Borrar")) : null,
      );
    }
    const habit = store.habits.find((x) => x.id === item.id);
    const future = state.selected > today();
    const run = habit ? streak(habit, store.habitChecks, state.selected) : 0;
    return h("li", { class: "cal-entry is-habit", style: `--chip:${item.color}` },
      h("span", { class: "cal-time readout" }, item.time),
      h("label", { class: "cal-entry-title cal-check-row" },
        h("input", { type: "checkbox", checked: item.done, disabled: future, "aria-label": `Marcar el hábito «${item.title}»`, onChange: () => void actions.check(item.id, state.selected) }),
        h("span", { class: item.done ? "is-done" : "" }, item.title),
      ),
      h("span", { class: "label cal-status" }, `hábito · ${habit ? weekdaysLabel(habit.weekdays) : ""}${run > 1 ? ` · racha de ${run}` : ""}`),
      habit ? actionsRow(edit("habit", `el hábito ${item.title}`), h("button", { class: "btn-quiet", type: "button", "aria-label": `Borrar el hábito ${item.title}`, onClick: () => { if (confirm(`¿Borrar el hábito «${item.title}»? Dejará de salir todos los días.`)) void actions.habits([softDeleteHabit(habit)]); } }, "Borrar")) : null,
    );
  }

  // ---------- los formularios
  function eventForm(existing: CalendarEvent | null): HTMLElement {
    const startD = existing ? new Date(existing.starts_at) : null;
    const endD = existing?.ends_at ? new Date(existing.ends_at) : null;
    const startText = startD && !existing?.all_day ? minutesToHHMM(startD.getHours() * 60 + startD.getMinutes()) : (state.draftTime ?? "09:00");
    const title = h("input", { type: "text", maxlength: 200, placeholder: "Título del evento", "aria-label": "Título", autocomplete: "off" });
    title.value = existing?.title ?? "";
    const date = h("input", { type: "date", "aria-label": "Fecha" });
    date.value = existing ? isoDayKey(existing.starts_at) : state.selected;
    const allDay = h("input", { type: "checkbox", "aria-label": "Todo el día", checked: existing?.all_day ?? false });
    const start = h("input", { type: "time", "aria-label": "Hora de inicio" });
    start.value = startText;
    const end = h("input", { type: "time", "aria-label": "Hora de fin (opcional)" });
    end.value = endD ? minutesToHHMM(endD.getHours() * 60 + endD.getMinutes()) : "";
    const color = h("select", { "aria-label": "Color" }, EVENT_COLORS.map((c) => h("option", { value: c }, COLOR_NAMES[c] ?? c)));
    color.value = existing?.color ?? EVENT_COLORS[0];
    const desc = h("textarea", { rows: 3, "aria-label": "Descripción", placeholder: "Descripción (opcional)" });
    desc.value = existing?.description ?? "";
    const error = h("p", { class: "form-error", role: "alert" });
    const sync = () => {
      start.disabled = end.disabled = allDay.checked;
    };
    allDay.addEventListener("change", sync);
    sync();
    titleInput = title;

    const form = h("form", { class: "cal-form", "data-kind": "event" },
      title,
      h("div", { class: "cal-form-row" }, date, h("label", { class: "check" }, allDay, " Todo el día")),
      h("div", { class: "cal-form-row" }, h("label", { class: "label" }, "De ", start), h("label", { class: "label" }, "a ", end)),
      h("div", { class: "cal-form-row" }, h("label", { class: "label" }, "Color ", color)),
      desc,
      error,
      formActions(existing ? "Guardar" : "Añadir evento", !!existing),
    );
    form.addEventListener("submit", (e) => {
      e.preventDefault();
      const name = title.value.trim();
      if (!name) return void (error.textContent = "Escribe un título.");
      if (!date.value) return void (error.textContent = "Elige la fecha.");
      const s = allDay.checked ? combineDayTime(date.value, "00:00") : combineDayTime(date.value, start.value);
      let en: Date | null = null;
      if (!allDay.checked && end.value) {
        en = combineDayTime(date.value, end.value);
        if (en <= s) return void (error.textContent = "La hora de fin debe ser después de la de inicio.");
      }
      error.textContent = "";
      if (existing) void actions.events([updateEvent(existing, { title: name, description: desc.value, starts_at: s.toISOString(), ends_at: en ? en.toISOString() : null, all_day: allDay.checked, color: color.value })]);
      else void actions.events([newEvent(name, s, { end: en, allDay: allDay.checked, description: desc.value, color: color.value })]);
      finish(date.value);
    });
    return form;
  }

  function reminderForm(existing: Reminder | null): HTMLElement {
    const at = existing ? new Date(existing.remind_at) : null;
    const title = h("input", { type: "text", maxlength: 200, placeholder: "¿Qué quieres recordar?", "aria-label": "Título", autocomplete: "off" });
    title.value = existing?.title ?? "";
    const date = h("input", { type: "date", "aria-label": "Fecha" });
    date.value = existing ? isoDayKey(existing.remind_at) : state.selected;
    const time = h("input", { type: "time", "aria-label": "Hora" });
    time.value = at ? minutesToHHMM(at.getHours() * 60 + at.getMinutes()) : (state.draftTime ?? "09:00");
    const notes = h("textarea", { rows: 2, "aria-label": "Notas", placeholder: "Notas (opcional)" });
    notes.value = existing?.notes ?? "";
    const error = h("p", { class: "form-error", role: "alert" });
    titleInput = title;
    const form = h("form", { class: "cal-form", "data-kind": "reminder" },
      title,
      h("div", { class: "cal-form-row" }, date, time),
      notes,
      error,
      formActions(existing ? "Guardar" : "Añadir recordatorio", !!existing),
    );
    form.addEventListener("submit", (e) => {
      e.preventDefault();
      const name = title.value.trim();
      if (!name) return void (error.textContent = "Escribe qué quieres recordar.");
      if (!date.value) return void (error.textContent = "Elige la fecha.");
      if (hhmmToMinutes(time.value) === null) return void (error.textContent = "Elige la hora.");
      error.textContent = "";
      const when = combineDayTime(date.value, time.value);
      if (existing) void actions.reminders([updateReminder(existing, { title: name, notes: notes.value, remind_at: when.toISOString(), done: when.getTime() === new Date(existing.remind_at).getTime() ? existing.done : false })]);
      else void actions.reminders([newReminder(name, when, { notes: notes.value })]);
      finish(date.value);
    });
    return form;
  }

  function habitForm(existing: Habit | null): HTMLElement {
    const name = h("input", { type: "text", maxlength: 120, placeholder: "Nombre del hábito (ej. Beber agua)", "aria-label": "Título", autocomplete: "off" });
    name.value = existing?.name ?? "";
    let mask = existing?.weekdays ?? EVERY_DAY;
    const days = h("div", { class: "cal-wd-row", role: "group", "aria-label": "Días de la semana" },
      WEEKDAY_LETTERS.map((letter, i) => {
        const b = h("button", { class: "cal-wd", type: "button", "aria-pressed": String(!!(mask & (1 << i))), "aria-label": WEEKDAYS[i], onClick: () => {
          mask ^= 1 << i;
          b.setAttribute("aria-pressed", String(!!(mask & (1 << i))));
        } }, letter);
        return b;
      }),
    );
    const time = h("input", { type: "time", "aria-label": "Hora del aviso (opcional)" });
    time.value = existing?.remind_at != null ? minutesToHHMM(existing.remind_at) : "";
    const error = h("p", { class: "form-error", role: "alert" });
    titleInput = name;
    const form = h("form", { class: "cal-form", "data-kind": "habit" },
      name,
      h("p", { class: "label" }, "Días que toca"),
      days,
      h("div", { class: "cal-form-row" }, h("label", { class: "label" }, "Aviso a las ", time)),
      h("p", { class: "cfg-help" }, "Los hábitos son los mismos de Kyra en el móvil. Márcalos cada día desde aquí o desde allá."),
      error,
      formActions(existing ? "Guardar" : "Añadir hábito", !!existing),
    );
    form.addEventListener("submit", (e) => {
      e.preventDefault();
      const n = name.value.trim();
      if (!n) return void (error.textContent = "Escribe el nombre del hábito.");
      if (!mask) return void (error.textContent = "Elige al menos un día.");
      const remindAt = time.value ? hhmmToMinutes(time.value) : null;
      if (time.value && remindAt === null) return void (error.textContent = "La hora del aviso no es válida.");
      error.textContent = "";
      if (existing) void actions.habits([updateHabit(existing, { name: n, weekdays: mask, remind_at: remindAt })]);
      else void actions.habits([newHabit(n, { weekdays: mask, remindAt, position: store.habits.length })]);
      finish(null);
    });
    return form;
  }

  function formActions(label: string, _editing: boolean): HTMLElement {
    return h("div", { class: "cal-form-actions" },
      h("button", { class: "btn-solid", type: "submit" }, label),
      h("button", { class: "btn-quiet", type: "button", onClick: () => { state.edit = null; state.formOpen = false; render(); } }, "Cancelar"),
    );
  }

  /** Tras guardar: ir al día de lo creado (si lo hay) y repintar todo. */
  function finish(day: string | null) {
    state.edit = null;
    state.formOpen = false;
    state.draftTime = null;
    if (day) state.selected = day;
    rerender();
  }

  function composer(): HTMLElement | null {
    titleInput = null;
    const editing = state.edit;
    if (!editing && !state.formOpen) return null; // el formulario solo se abre desde la paleta de comandos (o al editar algo)
    let kind: Composer = state.compose;
    let form: HTMLElement;
    if (editing) {
      kind = editing.kind;
      if (editing.kind === "event") form = eventForm(store.events.find((x) => x.id === editing.id) ?? null);
      else if (editing.kind === "reminder") form = reminderForm(store.reminders.find((x) => x.id === editing.id) ?? null);
      else form = habitForm(store.habits.find((x) => x.id === editing.id) ?? null);
    } else {
      form = kind === "event" ? eventForm(null) : kind === "reminder" ? reminderForm(null) : habitForm(null);
    }
    return h("section", { class: "cal-compose", "aria-label": editing ? `Editar ${KIND_LABEL[kind].toLowerCase()}` : "Añadir al calendario" },
      editing
        ? h("h3", { class: "label" }, `Editar ${KIND_LABEL[kind].toLowerCase()}`)
        : h("div", { class: "tabs cal-compose-tabs", role: "group", "aria-label": "Qué añadir" },
            COMPOSERS.map((c) => h("button", { class: "tab", type: "button", "aria-pressed": String(c.id === kind), onClick: () => { state.compose = c.id; render(); } }, c.label)),
          ),
      form,
    );
  }

  function render() {
    const items = agendaForDay(data(), state.selected);
    const day = parseDayKey(state.selected);
    const form = composer();
    el.classList.toggle("has-form", !!form);
    el.replaceChildren(
      h("h3", { class: "cal-day-title" }, longDate(day)),
      h("div", { class: "cal-day-body" },
        items.length ? h("ul", { class: "cal-list" }, items.map(entry)) : h("p", { class: "cfg-help" }, "Nada este día."),
        form ? null : h("p", { class: "cfg-help cal-hint" }, "Para añadir algo a este día abre la paleta de comandos (", h("kbd", {}, "Ctrl"), " + ", h("kbd", {}, "K"), ") y elige «Nuevo evento», «Nuevo recordatorio» o «Nuevo hábito»."),
      ),
      ...(form ? [form] : []),
    );
  }

  return {
    el,
    render,
    focusTitle: () => titleInput?.focus(),
  };
}
