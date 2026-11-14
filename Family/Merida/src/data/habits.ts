import type { SupabaseClient } from "@supabase/supabase-js";
import { stamp } from "./tasks";
import { dayKey, isoDayKey, parseDayKey } from "./events";

/** Los hábitos son los del móvil (Kyra): las tablas `habits` y `habit_checks` de Server/supabase/schema.sql §9. Merida los
 * enseña en el calendario y deja marcarlos o crearlos; se escriben con las mismas reglas (borrado suave, `updated_at` creciente). */
export interface Habit {
  id: string;
  name: string;
  weekdays: number; // máscara: lunes = 1 … domingo = 64 (127 = todos los días)
  remind_at: number | null; // minutos desde medianoche (hora local); null = sin aviso
  position: number;
  created_at: string;
  updated_at: string;
  deleted_at: string | null;
}

/** Que un hábito se cumplió (o ya no) un día. Desmarcar es `done = false`: así también se sincroniza. */
export interface HabitCheck {
  habit_id: string;
  day: string; // «aaaa-mm-dd»
  done: boolean;
  updated_at: string;
}

export const EVERY_DAY = 127;
export const WEEKDAY_LETTERS = ["L", "M", "X", "J", "V", "S", "D"];

/** El bit del día de la semana de una fecha (lunes = 1 … domingo = 64). */
export function weekdayBit(d: Date): number {
  return 1 << ((d.getDay() + 6) % 7);
}

export const maskOf = (days: number[]): number => days.reduce((m, i) => m | (1 << i), 0); // i: 0 = lunes … 6 = domingo

/** «a diario», «L X V»… para mostrar los días que toca. */
export function weekdaysLabel(mask: number): string {
  if (mask === EVERY_DAY) return "a diario";
  return WEEKDAY_LETTERS.filter((_, i) => mask & (1 << i)).join(" ");
}

export const minutesToHHMM = (m: number): string => `${String(Math.floor(m / 60)).padStart(2, "0")}:${String(m % 60).padStart(2, "0")}`;

/** «18:30» → 1110; vacío o inválido → null. */
export function hhmmToMinutes(text: string): number | null {
  const m = /^(\d{1,2}):(\d{2})$/.exec(text.trim());
  if (!m) return null;
  const mins = Number(m[1]) * 60 + Number(m[2]);
  return Number(m[1]) < 24 && Number(m[2]) < 60 ? mins : null;
}

/** Los hábitos que tocan ese día: por la máscara de la semana y solo desde el día en que se crearon. Primero los que avisan
 * a una hora (por hora), luego el resto en su orden. */
export function habitsOn(habits: Habit[], key: string): Habit[] {
  const bit = weekdayBit(parseDayKey(key));
  return habits
    .filter((h) => !h.deleted_at && h.weekdays & bit && key >= isoDayKey(h.created_at))
    .sort((a, b) => (a.remind_at ?? 1e9) - (b.remind_at ?? 1e9) || a.position - b.position || a.name.localeCompare(b.name));
}

export function isChecked(checks: HabitCheck[], habitId: string, key: string): boolean {
  return checks.some((c) => c.habit_id === habitId && c.day === key && c.done);
}

/** Cuántos hábitos tocan ese día y cuántos están hechos. */
export function habitProgress(habits: Habit[], checks: HabitCheck[], key: string): { total: number; done: number } {
  const list = habitsOn(habits, key);
  return { total: list.length, done: list.filter((h) => isChecked(checks, h.id, key)).length };
}

/** La marca de ese día con el valor contrario. Siempre sube `updated_at` (sync_guard ignora lo que no sea más nuevo). */
export function toggleCheck(checks: HabitCheck[], habitId: string, key: string, now: Date = new Date()): HabitCheck {
  const prev = checks.find((c) => c.habit_id === habitId && c.day === key);
  return { habit_id: habitId, day: key, done: !(prev?.done ?? false), updated_at: stamp(prev?.updated_at ?? "1970-01-01T00:00:00.000Z", now) };
}

export function applyChecks(checks: HabitCheck[], changed: HabitCheck[]): HabitCheck[] {
  const map = new Map(checks.map((c) => [`${c.habit_id}|${c.day}`, c]));
  for (const c of changed) map.set(`${c.habit_id}|${c.day}`, c);
  return [...map.values()];
}

/** La racha: días seguidos (contando hacia atrás desde `key`) en que se cumplió cada vez que tocaba. Un día que no toca no la rompe. */
export function streak(habit: Habit, checks: HabitCheck[], key: string): number {
  let n = 0;
  const d = parseDayKey(key);
  const first = isoDayKey(habit.created_at);
  for (let i = 0; i < 400; i++) {
    const k = dayKey(new Date(d.getFullYear(), d.getMonth(), d.getDate() - i));
    if (k < first) break;
    if (!(habit.weekdays & weekdayBit(parseDayKey(k)))) continue;
    if (isChecked(checks, habit.id, k)) n++;
    else if (i === 0) continue; // hoy aún puede cumplirse
    else break;
  }
  return n;
}

export function newHabit(name: string, opts: { weekdays?: number; remindAt?: number | null; position?: number; now?: Date; id?: string } = {}): Habit {
  const now = (opts.now ?? new Date()).toISOString();
  return {
    id: opts.id ?? crypto.randomUUID(),
    name: name.trim(),
    weekdays: opts.weekdays && opts.weekdays > 0 && opts.weekdays <= 127 ? opts.weekdays : EVERY_DAY,
    remind_at: opts.remindAt ?? null,
    position: opts.position ?? 0,
    created_at: now,
    updated_at: now,
    deleted_at: null,
  };
}

export type HabitPatch = Partial<Pick<Habit, "name" | "weekdays" | "remind_at">>;

export function updateHabit(h: Habit, patch: HabitPatch, now: Date = new Date()): Habit {
  return { ...h, ...patch, name: patch.name !== undefined ? patch.name.trim() || h.name : h.name, updated_at: stamp(h.updated_at, now) };
}

export function softDeleteHabit(h: Habit, now: Date = new Date()): Habit {
  const at = stamp(h.updated_at, now);
  return { ...h, deleted_at: at, updated_at: at };
}

export function applyHabits(habits: Habit[], changed: Habit[]): Habit[] {
  const byId = new Map(habits.map((h) => [h.id, h]));
  for (const h of changed) byId.set(h.id, h);
  return [...byId.values()].filter((h) => !h.deleted_at);
}

const HABIT_COLUMNS = "id,name,weekdays,remind_at,position,created_at,updated_at,deleted_at";
const CHECK_COLUMNS = "habit_id,day,done,updated_at";

export async function loadHabits(client: SupabaseClient): Promise<{ habits: Habit[]; checks: HabitCheck[] }> {
  const [h, c] = await Promise.all([
    client.from("habits").select(HABIT_COLUMNS).is("deleted_at", null).limit(500),
    client.from("habit_checks").select(CHECK_COLUMNS).limit(10000),
  ]);
  if (h.error) throw h.error;
  if (c.error) throw c.error;
  return { habits: (h.data ?? []) as unknown as Habit[], checks: (c.data ?? []) as unknown as HabitCheck[] };
}

export async function saveHabits(client: SupabaseClient, rows: Habit[]): Promise<void> {
  if (!rows.length) return;
  const { error } = await client.from("habits").upsert(rows, { onConflict: "id" });
  if (error) throw error;
}

export async function saveChecks(client: SupabaseClient, rows: HabitCheck[]): Promise<void> {
  if (!rows.length) return;
  const { error } = await client.from("habit_checks").upsert(rows, { onConflict: "habit_id,day" });
  if (error) throw error;
}
