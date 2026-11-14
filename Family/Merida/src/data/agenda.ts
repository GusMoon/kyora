import { MONTHS, WEEKDAYS, dayKey, eventsOnDay, isoDayKey, monthGrid, monthTitle, parseDayKey, shiftMonth, tasksDueOn, weekDays, type CalendarEvent } from "./events";
import { habitsOn, isChecked, minutesToHHMM, type Habit, type HabitCheck } from "./habits";
import { remindersOnDay, type Reminder } from "./reminders";
import type { Task } from "./tasks";
import { normalize } from "../palette";

/** Lo que enseña el calendario: eventos, entregas de tareas, recordatorios y hábitos, mezclados por día. Todo puro (sin DOM)
 * para poder probarlo: la sección solo lo dibuja. */

export type Kind = "event" | "task" | "reminder" | "habit";
export type Filter = "all" | Kind;
export type View = "day" | "week" | "month";

export const KINDS: Kind[] = ["event", "task", "reminder", "habit"];
export const KIND_LABEL: Record<Kind, string> = { event: "Evento", task: "Tarea", reminder: "Recordatorio", habit: "Hábito" };
export const FILTERS: { id: Filter; label: string }[] = [
  { id: "all", label: "Todo" },
  { id: "event", label: "Eventos" },
  { id: "task", label: "Tareas" },
  { id: "reminder", label: "Recordatorios" },
  { id: "habit", label: "Hábitos" },
];
export const VIEWS: { id: View; label: string }[] = [
  { id: "day", label: "Día" },
  { id: "week", label: "Semana" },
  { id: "month", label: "Mes" },
];

/** El color de cada clase (los eventos traen el suyo). */
export const KIND_COLOR: Record<Exclude<Kind, "event">, string> = { task: "var(--accent)", reminder: "#ffd23f", habit: "#5be38a" };

export interface AgendaData {
  events: CalendarEvent[];
  tasks: Task[];
  reminders: Reminder[];
  habits: Habit[];
  checks: HabitCheck[];
}

export interface AgendaItem {
  kind: Kind;
  id: string;
  title: string;
  day: string;
  start: number | null; // minutos desde medianoche; null = sin hora
  end: number | null; // minutos; null = la duración de siempre
  allDay: boolean; // va en la franja de «todo el día» (sin hora, de todo el día o de varios días)
  color: string;
  done: boolean;
  span: "single" | "start" | "mid" | "end"; // un evento de varios días se pinta unido de un día al siguiente
  time: string; // «18:00», «18:00–19:00» o «todo el día»
}

const minutesOf = (iso: string): number => {
  const d = new Date(iso);
  return d.getHours() * 60 + d.getMinutes();
};

const KIND_ORDER: Record<Kind, number> = { event: 0, reminder: 1, task: 2, habit: 3 };

/** Lo que hay ese día. `filter`: una clase, «all» o la lista de clases que se quieren ver. */
export function agendaForDay(data: AgendaData, key: string, filter: Filter | readonly Kind[] = "all", query = ""): AgendaItem[] {
  const out: AgendaItem[] = [];
  const want = (k: Kind) => (typeof filter === "string" ? filter === "all" || filter === k : filter.includes(k));
  if (want("event")) {
    for (const e of eventsOnDay(data.events, key)) {
      const s = isoDayKey(e.starts_at);
      const en = e.ends_at ? isoDayKey(e.ends_at) : s;
      const span = s === en ? "single" : key === s ? "start" : key === en ? "end" : "mid";
      const allDay = e.all_day || span !== "single";
      const start = allDay ? null : minutesOf(e.starts_at);
      const end = !allDay && e.ends_at ? minutesOf(e.ends_at) : null;
      out.push({
        kind: "event", id: e.id, title: e.title, day: key, start, end, allDay, color: e.color, done: false, span,
        time: allDay ? "todo el día" : `${minutesToHHMM(start!)}${end !== null ? `–${minutesToHHMM(end)}` : ""}`,
      });
    }
  }
  if (want("task")) {
    for (const t of tasksDueOn(data.tasks, key)) {
      const start = minutesOf(t.due!);
      out.push({ kind: "task", id: t.id, title: t.name, day: key, start, end: null, allDay: false, color: KIND_COLOR.task, done: t.status === "done", span: "single", time: minutesToHHMM(start) });
    }
  }
  if (want("reminder")) {
    for (const r of remindersOnDay(data.reminders, key)) {
      const start = minutesOf(r.remind_at);
      out.push({ kind: "reminder", id: r.id, title: r.title, day: key, start, end: null, allDay: false, color: KIND_COLOR.reminder, done: r.done, span: "single", time: minutesToHHMM(start) });
    }
  }
  if (want("habit")) {
    for (const h of habitsOn(data.habits, key)) {
      const timed = h.remind_at !== null;
      out.push({
        kind: "habit", id: h.id, title: h.name, day: key, start: h.remind_at, end: null, allDay: !timed, color: KIND_COLOR.habit,
        done: isChecked(data.checks, h.id, key), span: "single", time: timed ? minutesToHHMM(h.remind_at!) : "todo el día",
      });
    }
  }
  const q = normalize(query);
  const list = q ? out.filter((i) => normalize(i.title).includes(q)) : out;
  return list.sort((a, b) => Number(b.allDay) - Number(a.allDay) || (a.start ?? -1) - (b.start ?? -1) || KIND_ORDER[a.kind] - KIND_ORDER[b.kind] || a.title.localeCompare(b.title));
}

// ----- la columna de horas (semana y día)
const DEFAULT_LEN = 30; // minutos que ocupa en la columna lo que no tiene fin
const EVENT_LEN = 60;
export const DAY_MIN = 1440;

export interface Placed {
  item: AgendaItem;
  top: number; // minutos desde medianoche
  len: number; // minutos de alto
  lane: number; // en qué carril va si se solapa con otros
  lanes: number; // cuántos carriles tiene su grupo
}

/** Coloca lo que tiene hora: cada uno con su alto, y lo que se solapa, uno junto a otro en carriles. */
export function layoutDay(items: AgendaItem[]): Placed[] {
  const timed = items
    .filter((i) => !i.allDay && i.start !== null)
    .map((item) => {
      const top = item.start!;
      const raw = item.end !== null ? item.end - top : item.kind === "event" ? EVENT_LEN : DEFAULT_LEN;
      const len = Math.max(DEFAULT_LEN, Math.min(raw, DAY_MIN - top));
      return { item, top, len, lane: 0, lanes: 1 };
    })
    .sort((a, b) => a.top - b.top || b.len - a.len);
  let group: Placed[] = [];
  let groupEnd = -1;
  const close = () => {
    const lanes = group.reduce((m, p) => Math.max(m, p.lane + 1), 1);
    for (const p of group) p.lanes = lanes;
    group = [];
  };
  const laneEnds: number[] = [];
  for (const p of timed) {
    if (p.top >= groupEnd) {
      close();
      laneEnds.length = 0;
    }
    let lane = laneEnds.findIndex((end) => end <= p.top);
    if (lane < 0) lane = laneEnds.length;
    laneEnds[lane] = p.top + p.len;
    p.lane = lane;
    group.push(p);
    groupEnd = Math.max(groupEnd, p.top + p.len);
  }
  close();
  return timed;
}

/** De un clic o suelta en una columna de horas a minutos desde medianoche, al cuarto de hora. */
export function minutesAtY(offsetY: number, columnHeight: number): number | null {
  if (!(columnHeight > 0)) return null;
  const raw = (Math.min(Math.max(offsetY, 0), columnHeight) / columnHeight) * DAY_MIN;
  return Math.min(Math.round(raw / 15) * 15, DAY_MIN - 15);
}

// ----- el rango que se ve y su título
const ABBR = (m: number) => MONTHS[m].slice(0, 3);
export const shortDate = (d: Date): string => `${d.getDate()} ${ABBR(d.getMonth())}`;
export const fullShort = (d: Date): string => `${shortDate(d)} ${d.getFullYear()}`;
export const MONTH_ABBR = (m: number): string => ABBR(m).toUpperCase();

/** El número de semana ISO. */
export function isoWeek(d: Date): number {
  const t = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()));
  const dow = t.getUTCDay() || 7;
  t.setUTCDate(t.getUTCDate() + 4 - dow);
  const y0 = new Date(Date.UTC(t.getUTCFullYear(), 0, 1));
  return Math.ceil(((t.getTime() - y0.getTime()) / 86_400_000 + 1) / 7);
}

export interface Range {
  days: Date[]; // lo que se pinta (42 días en el mes, 7 en la semana, 1 en el día)
  title: string;
  subtitle: string;
}

export function rangeFor(view: View, selected: string): Range {
  const d = parseDayKey(selected);
  if (view === "month") {
    const grid = monthGrid(d.getFullYear(), d.getMonth()).flat();
    const first = new Date(d.getFullYear(), d.getMonth(), 1);
    const last = new Date(d.getFullYear(), d.getMonth() + 1, 0);
    return { days: grid, title: monthTitle(d.getFullYear(), d.getMonth()), subtitle: `${fullShort(first)} – ${fullShort(last)}` };
  }
  if (view === "week") {
    const days = weekDays(d);
    const [a, b] = [days[0], days[6]];
    const title = a.getMonth() === b.getMonth() ? `${a.getDate()} – ${b.getDate()} ${ABBR(b.getMonth())} ${b.getFullYear()}` : `${shortDate(a)} – ${shortDate(b)} ${b.getFullYear()}`;
    return { days, title, subtitle: `Semana ${isoWeek(d)} · ${fullShort(a)} – ${fullShort(b)}` };
  }
  return { days: [d], title: `${WEEKDAYS[(d.getDay() + 6) % 7]} ${d.getDate()} ${ABBR(d.getMonth())} ${d.getFullYear()}`, subtitle: `Semana ${isoWeek(d)}` };
}

/** El día elegido tras ir `delta` pasos hacia delante o atrás: un mes, una semana o un día. */
export function stepSelected(view: View, selected: string, delta: number): string {
  const d = parseDayKey(selected);
  if (view === "month") {
    const { year, month } = shiftMonth(d.getFullYear(), d.getMonth(), delta);
    const last = new Date(year, month + 1, 0).getDate();
    return dayKey(new Date(year, month, Math.min(d.getDate(), last)));
  }
  return dayKey(new Date(d.getFullYear(), d.getMonth(), d.getDate() + delta * (view === "week" ? 7 : 1)));
}

// ----- el enunciado y los avisos
export function agendaStatement(data: AgendaData, loaded: boolean, error?: string, now: Date = new Date()): string {
  if (error) return error;
  if (!loaded) return "Cargando tu calendario.";
  const key = dayKey(now);
  const events = eventsOnDay(data.events, key).length;
  const tasks = tasksDueOn(data.tasks, key).filter((t) => t.status !== "done").length;
  const reminders = remindersOnDay(data.reminders, key).filter((r) => !r.done).length;
  const hs = habitsOn(data.habits, key);
  const habits = hs.filter((h) => !isChecked(data.checks, h.id, key)).length;
  const parts: string[] = [];
  const plural = (n: number, one: string, many: string) => `${n} ${n === 1 ? one : many}`;
  if (events) parts.push(plural(events, "evento", "eventos"));
  if (tasks) parts.push(plural(tasks, "entrega", "entregas"));
  if (reminders) parts.push(plural(reminders, "recordatorio", "recordatorios"));
  if (habits) parts.push(plural(habits, "hábito por cumplir", "hábitos por cumplir"));
  if (!parts.length) return "Hoy no tienes nada pendiente en el calendario.";
  return `Hoy: ${parts.length === 1 ? parts[0] : `${parts.slice(0, -1).join(", ")} y ${parts[parts.length - 1]}`}.`;
}

export interface Alert {
  key: string; // para no avisar dos veces de lo mismo
  title: string;
  body: string;
}

const ALERT_WINDOW_MIN = 15; // pasado ese rato ya no se avisa (p. ej. si abres Merida tarde)

/** Los avisos que tocan ahora: recordatorios pendientes cuya hora llegó hace poco y hábitos de hoy con aviso a esta hora
 * que aún no están hechos. `fired` evita repetirlos; quien llama anota ahí lo que ya mostró. */
export function pendingAlerts(data: AgendaData, now: Date, fired: ReadonlySet<string>): Alert[] {
  const out: Alert[] = [];
  const nowMin = now.getHours() * 60 + now.getMinutes();
  for (const r of data.reminders) {
    if (r.deleted_at || r.done) continue;
    const late = (now.getTime() - new Date(r.remind_at).getTime()) / 60_000;
    const key = `r:${r.id}:${r.remind_at}`;
    if (late >= 0 && late <= ALERT_WINDOW_MIN && !fired.has(key)) out.push({ key, title: "Recordatorio", body: r.title });
  }
  const today = dayKey(now);
  for (const h of habitsOn(data.habits, today)) {
    if (h.remind_at === null || isChecked(data.checks, h.id, today)) continue;
    const key = `h:${h.id}:${today}`;
    const late = nowMin - h.remind_at;
    if (late >= 0 && late <= ALERT_WINDOW_MIN && !fired.has(key)) out.push({ key, title: "Hábito", body: h.name });
  }
  return out;
}
