import type { SupabaseClient } from "@supabase/supabase-js";
import { stamp, type Task } from "./tasks";

/** Los eventos del calendario (tabla `events` de Server/supabase/schema.sql §11). Las tareas con fecha de entrega
 * también salen en el calendario, pero siguen siendo tareas: arrastrarlas cambia su `due`. */
export interface CalendarEvent {
  id: string;
  title: string;
  description: string;
  starts_at: string;
  ends_at: string | null;
  all_day: boolean;
  color: string;
  task_id: string | null;
  created_at: string;
  updated_at: string;
  deleted_at: string | null;
}

export const MONTHS = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre"];
export const WEEKDAYS = ["lunes", "martes", "miércoles", "jueves", "viernes", "sábado", "domingo"];
export const WEEKDAY_SHORT = ["lun", "mar", "mié", "jue", "vie", "sáb", "dom"];
export const EVENT_COLORS = ["#35d4ff", "#c8f73a", "#ff5a1f", "#ff4fd8", "#ffd23f", "#c9cebc"];

const pad2 = (n: number) => String(n).padStart(2, "0");

/** «2026-11-13» en hora local: la clave de un día. */
export function dayKey(d: Date): string {
  return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}`;
}

/** La clave del día de una hora ISO (en hora local). */
export function isoDayKey(iso: string): string {
  return dayKey(new Date(iso));
}

/** Una clave «aaaa-mm-dd» → fecha local a las 00:00. */
export function parseDayKey(key: string): Date {
  const [y, m, d] = key.split("-").map(Number);
  return new Date(y, m - 1, d);
}

/** La cuadrícula de un mes: 6 semanas de lunes a domingo (como calendar_grid.py de Kyora). `month` va de 0 a 11. */
export function monthGrid(year: number, month: number): Date[][] {
  const first = new Date(year, month, 1);
  const offset = (first.getDay() + 6) % 7; // lunes = 0
  const start = new Date(year, month, 1 - offset);
  return Array.from({ length: 6 }, (_, w) => Array.from({ length: 7 }, (_, d) => new Date(start.getFullYear(), start.getMonth(), start.getDate() + w * 7 + d)));
}

/** El mes `delta` meses después (o antes), desbordando bien el año. */
export function shiftMonth(year: number, month: number, delta: number): { year: number; month: number } {
  const t = year * 12 + month + delta;
  return { year: Math.floor(t / 12), month: ((t % 12) + 12) % 12 };
}

/** Los siete días (lunes a domingo) de la semana de una fecha. */
export function weekDays(date: Date): Date[] {
  const start = new Date(date.getFullYear(), date.getMonth(), date.getDate() - ((date.getDay() + 6) % 7));
  return Array.from({ length: 7 }, (_, i) => new Date(start.getFullYear(), start.getMonth(), start.getDate() + i));
}

export function longDate(d: Date): string {
  const wd = WEEKDAYS[(d.getDay() + 6) % 7];
  return `${wd} ${d.getDate()} de ${MONTHS[d.getMonth()]} de ${d.getFullYear()}`;
}

export const monthTitle = (year: number, month: number) => `${MONTHS[month]} ${year}`;

/** ¿El evento cae en ese día? Cubre los de varios días (de `starts_at` a `ends_at`). */
export function eventOnDay(e: CalendarEvent, key: string): boolean {
  if (e.deleted_at) return false;
  const start = isoDayKey(e.starts_at);
  const end = e.ends_at ? isoDayKey(e.ends_at) : start;
  return key >= start && key <= (end < start ? start : end);
}

const byStart = (a: CalendarEvent, b: CalendarEvent) => (a.all_day !== b.all_day ? (a.all_day ? -1 : 1) : a.starts_at.localeCompare(b.starts_at));

export function eventsOnDay(events: CalendarEvent[], key: string): CalendarEvent[] {
  return events.filter((e) => eventOnDay(e, key)).sort(byStart);
}

/** Las tareas (principales o subtareas) que vencen ese día. */
export function tasksDueOn(tasks: Task[], key: string): Task[] {
  return tasks.filter((t) => !t.deleted_at && t.due && isoDayKey(t.due) === key).sort((a, b) => (a.due ?? "").localeCompare(b.due ?? ""));
}

/** Cuántas cosas hay cada día (eventos + tareas que vencen), para las marcas de la cuadrícula. */
export function dayCounts(events: CalendarEvent[], tasks: Task[], days: Date[]): Map<string, { events: number; tasks: number }> {
  const out = new Map<string, { events: number; tasks: number }>();
  for (const d of days) {
    const k = dayKey(d);
    out.set(k, { events: events.filter((e) => eventOnDay(e, k)).length, tasks: tasksDueOn(tasks, k).length });
  }
  return out;
}

export function newEvent(
  title: string,
  start: Date,
  opts: { end?: Date | null; allDay?: boolean; description?: string; color?: string; taskId?: string | null; now?: Date; id?: string } = {},
): CalendarEvent {
  const now = (opts.now ?? new Date()).toISOString();
  const allDay = opts.allDay ?? false;
  const s = allDay ? new Date(start.getFullYear(), start.getMonth(), start.getDate()) : start;
  return {
    id: opts.id ?? crypto.randomUUID(),
    title: title.trim(),
    description: opts.description ?? "",
    starts_at: s.toISOString(),
    ends_at: opts.end ? opts.end.toISOString() : null,
    all_day: allDay,
    color: opts.color ?? EVENT_COLORS[0],
    task_id: opts.taskId ?? null,
    created_at: now,
    updated_at: now,
    deleted_at: null,
  };
}

export type EventPatch = Partial<Pick<CalendarEvent, "title" | "description" | "starts_at" | "ends_at" | "all_day" | "color">>;

export function updateEvent(e: CalendarEvent, patch: EventPatch, now: Date = new Date()): CalendarEvent {
  return { ...e, ...patch, title: patch.title !== undefined ? patch.title.trim() || e.title : e.title, updated_at: stamp(e.updated_at, now) };
}

export function softDeleteEvent(e: CalendarEvent, now: Date = new Date()): CalendarEvent {
  const at = stamp(e.updated_at, now);
  return { ...e, deleted_at: at, updated_at: at };
}

/** Mueve un evento a otro día conservando la hora (y la duración, si la tiene). Con `minutes` (minutos desde medianoche) lo pone
 * además a esa hora; un evento de todo el día solo cambia de día. */
export function moveEventTo(e: CalendarEvent, key: string, minutes: number | null = null, now: Date = new Date()): CalendarEvent {
  const from = new Date(e.starts_at);
  const to = parseDayKey(key);
  const m = e.all_day || minutes === null ? from.getHours() * 60 + from.getMinutes() : minutes;
  const start = new Date(to.getFullYear(), to.getMonth(), to.getDate(), Math.floor(m / 60), m % 60);
  const shift = start.getTime() - from.getTime();
  return updateEvent(e, { starts_at: start.toISOString(), ends_at: e.ends_at ? new Date(new Date(e.ends_at).getTime() + shift).toISOString() : null }, now);
}

export const moveEventToDay = (e: CalendarEvent, key: string, now: Date = new Date()): CalendarEvent => moveEventTo(e, key, null, now);

/** La tarea con otra fecha de entrega (la misma hora, en el día pedido; o a `minutes`). Sin fecha previa, a las 09:00. */
export function moveTaskTo(task: Task, key: string, minutes: number | null = null, now: Date = new Date()): Task {
  const from = task.due ? new Date(task.due) : null;
  const to = parseDayKey(key);
  const m = minutes ?? (from ? from.getHours() * 60 + from.getMinutes() : 9 * 60);
  const due = new Date(to.getFullYear(), to.getMonth(), to.getDate(), Math.floor(m / 60), m % 60);
  return { ...task, due: due.toISOString(), updated_at: stamp(task.updated_at, now) };
}

export const moveTaskToDay = (task: Task, key: string, now: Date = new Date()): Task => moveTaskTo(task, key, null, now);

export function applyEvents(events: CalendarEvent[], changed: CalendarEvent[]): CalendarEvent[] {
  const byId = new Map(events.map((e) => [e.id, e]));
  for (const e of changed) byId.set(e.id, e);
  return [...byId.values()].filter((e) => !e.deleted_at);
}

export function eventsStatement(events: CalendarEvent[], tasks: Task[], loaded: boolean, error?: string, now: Date = new Date()): string {
  if (error) return error;
  if (!loaded) return "Cargando tu calendario.";
  const key = dayKey(now);
  const e = eventsOnDay(events, key).length;
  const t = tasksDueOn(tasks, key).filter((x) => x.status !== "done").length;
  if (!e && !t) return "Hoy no tienes eventos ni entregas.";
  const parts = [];
  if (e) parts.push(e === 1 ? "1 evento" : `${e} eventos`);
  if (t) parts.push(t === 1 ? "1 entrega" : `${t} entregas`);
  return `Hoy: ${parts.join(" y ")}.`;
}

const COLUMNS = "id,title,description,starts_at,ends_at,all_day,color,task_id,created_at,updated_at,deleted_at";

export async function loadEvents(client: SupabaseClient): Promise<CalendarEvent[]> {
  const { data, error } = await client.from("events").select(COLUMNS).is("deleted_at", null).limit(2000);
  if (error) throw error;
  return (data ?? []) as unknown as CalendarEvent[];
}

export async function saveEvents(client: SupabaseClient, rows: CalendarEvent[]): Promise<void> {
  if (!rows.length) return;
  const { error } = await client.from("events").upsert(rows, { onConflict: "id" });
  if (error) throw error;
}

/** «2026-11-13» y «18:30» → la fecha local. Con la hora vacía o inválida, a las 09:00. */
export function combineDayTime(key: string, time: string): Date {
  const d = parseDayKey(key);
  const [hh, mm] = /^\d{1,2}:\d{2}$/.test(time) ? time.split(":").map(Number) : [9, 0];
  return new Date(d.getFullYear(), d.getMonth(), d.getDate(), hh, mm);
}
