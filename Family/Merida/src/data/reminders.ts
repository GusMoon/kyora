import type { SupabaseClient } from "@supabase/supabase-js";
import { stamp } from "./tasks";
import { isoDayKey, parseDayKey } from "./events";

/** Un recordatorio: algo que hay que recordar a una hora (tabla `reminders` de Server/supabase/schema.sql §14). A diferencia
 * de una tarea no tiene estados ni subtareas: llega su hora, avisa y se marca como hecho. */
export interface Reminder {
  id: string;
  title: string;
  notes: string;
  remind_at: string; // ISO
  done: boolean;
  created_at: string;
  updated_at: string;
  deleted_at: string | null;
}

export function newReminder(title: string, at: Date, opts: { notes?: string; now?: Date; id?: string } = {}): Reminder {
  const now = (opts.now ?? new Date()).toISOString();
  return { id: opts.id ?? crypto.randomUUID(), title: title.trim(), notes: opts.notes ?? "", remind_at: at.toISOString(), done: false, created_at: now, updated_at: now, deleted_at: null };
}

export type ReminderPatch = Partial<Pick<Reminder, "title" | "notes" | "remind_at" | "done">>;

export function updateReminder(r: Reminder, patch: ReminderPatch, now: Date = new Date()): Reminder {
  return { ...r, ...patch, title: patch.title !== undefined ? patch.title.trim() || r.title : r.title, updated_at: stamp(r.updated_at, now) };
}

export const toggleReminder = (r: Reminder, now: Date = new Date()): Reminder => updateReminder(r, { done: !r.done }, now);

export function softDeleteReminder(r: Reminder, now: Date = new Date()): Reminder {
  const at = stamp(r.updated_at, now);
  return { ...r, deleted_at: at, updated_at: at };
}

/** Lo mueve a otro día (la misma hora) o, con `minutes`, a esa hora de ese día. */
export function moveReminderTo(r: Reminder, key: string, minutes: number | null = null, now: Date = new Date()): Reminder {
  const from = new Date(r.remind_at);
  const to = parseDayKey(key);
  const m = minutes ?? from.getHours() * 60 + from.getMinutes();
  return updateReminder(r, { remind_at: new Date(to.getFullYear(), to.getMonth(), to.getDate(), Math.floor(m / 60), m % 60).toISOString() }, now);
}

export function remindersOnDay(reminders: Reminder[], key: string): Reminder[] {
  return reminders.filter((r) => !r.deleted_at && isoDayKey(r.remind_at) === key).sort((a, b) => a.remind_at.localeCompare(b.remind_at));
}

export function applyReminders(reminders: Reminder[], changed: Reminder[]): Reminder[] {
  const byId = new Map(reminders.map((r) => [r.id, r]));
  for (const r of changed) byId.set(r.id, r);
  return [...byId.values()].filter((r) => !r.deleted_at);
}

/** Los pendientes cuya hora ya llegó (para resaltarlos). */
export const isOverdue = (r: Reminder, now: Date = new Date()): boolean => !r.done && new Date(r.remind_at).getTime() <= now.getTime();

const COLUMNS = "id,title,notes,remind_at,done,created_at,updated_at,deleted_at";

export async function loadReminders(client: SupabaseClient): Promise<Reminder[]> {
  const { data, error } = await client.from("reminders").select(COLUMNS).is("deleted_at", null).limit(2000);
  if (error) throw error;
  return (data ?? []) as unknown as Reminder[];
}

export async function saveReminders(client: SupabaseClient, rows: Reminder[]): Promise<void> {
  if (!rows.length) return;
  const { error } = await client.from("reminders").upsert(rows, { onConflict: "id" });
  if (error) throw error;
}
