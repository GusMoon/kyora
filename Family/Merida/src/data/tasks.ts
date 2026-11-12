import type { SupabaseClient } from "@supabase/supabase-js";

/** El flujo de una tarea, en orden: es una secuencia de verdad. */
export const STATUSES = ["pending", "doing", "review", "done"] as const;
export type TaskStatus = (typeof STATUSES)[number];

export const STATUS_LABEL: Record<TaskStatus, string> = {
  pending: "Pendiente",
  doing: "Haciendo",
  review: "Revisión",
  done: "Hecha",
};

/** Una fila de `tasks` (Server/supabase/schema.sql §8), la misma que usan el móvil y el escritorio. */
export interface Task {
  id: string;
  parent_id: string | null;
  position: number;
  name: string;
  description: string;
  status: TaskStatus;
  expected_min: number | null;
  real_s: number;
  timer_started: string | null;
  due: string | null;
  finished: string | null;
  created_at: string;
  updated_at: string;
  deleted_at: string | null;
}

const COLUMNS =
  "id,parent_id,position,name,description,status,expected_min,real_s,timer_started,due,finished,created_at,updated_at,deleted_at";

const byPosition = (a: Task, b: Task) =>
  a.position !== b.position ? a.position - b.position : a.created_at.localeCompare(b.created_at);

/** Las tareas principales (sin padre) de cada estado, en su orden. */
export function groupByStatus(tasks: Task[]): Record<TaskStatus, Task[]> {
  const groups = { pending: [], doing: [], review: [], done: [] } as Record<TaskStatus, Task[]>;
  for (const t of tasks) {
    if (t.deleted_at || t.parent_id) continue;
    (groups[t.status] ?? groups.pending).push(t);
  }
  for (const s of STATUSES) groups[s].sort(byPosition);
  return groups;
}

export function subtasksOf(tasks: Task[], id: string): Task[] {
  return tasks.filter((t) => t.parent_id === id && !t.deleted_at).sort(byPosition);
}

/** Lo que dice el enunciado de la sección: cuántas siguen abiertas y cuántas vencen hoy (o ya vencieron). */
export function summary(tasks: Task[], now = new Date()) {
  const main = tasks.filter((t) => !t.deleted_at && !t.parent_id);
  const open = main.filter((t) => t.status !== "done");
  const endOfToday = new Date(now);
  endOfToday.setHours(23, 59, 59, 999);
  const dueToday = open.filter((t) => t.due && new Date(t.due) <= endOfToday).length;
  return { open: open.length, done: main.length - open.length, dueToday };
}

export function isOverdue(task: Task, now = new Date()): boolean {
  return !!task.due && task.status !== "done" && new Date(task.due) < now;
}

/** Una tarea nueva al final de su columna (o de las subtareas de su padre). El id lo crea el dispositivo. */
export function newTask(
  name: string,
  opts: { status?: TaskStatus; parentId?: string | null; siblings?: Task[]; now?: Date; id?: string } = {},
): Task {
  const now = (opts.now ?? new Date()).toISOString();
  const last = Math.max(-1, ...(opts.siblings ?? []).map((t) => t.position));
  return {
    id: opts.id ?? crypto.randomUUID(),
    parent_id: opts.parentId ?? null,
    position: last + 1,
    name: name.trim(),
    description: "",
    status: opts.status ?? "pending",
    expected_min: null,
    real_s: 0,
    timer_started: null,
    due: null,
    finished: null,
    created_at: now,
    updated_at: now,
    deleted_at: null,
  };
}

/** La tarea en otro estado. Al terminarla queda la hora; si vuelve atrás, se quita. */
export function withStatus(task: Task, status: TaskStatus, now = new Date()): Task {
  const stamp = now.toISOString();
  return { ...task, status, finished: status === "done" ? (task.finished ?? stamp) : null, updated_at: stamp };
}

/** El estado vecino en el flujo (-1 atrás, +1 adelante), o null si ya está en un extremo. */
export function stepStatus(status: TaskStatus, delta: -1 | 1): TaskStatus | null {
  const next = STATUSES.indexOf(status) + delta;
  return next >= 0 && next < STATUSES.length ? STATUSES[next] : null;
}

/** Borrado suave de una tarea y de sus subtareas: así el borrado también llega al móvil. */
export function softDelete(tasks: Task[], id: string, now = new Date()): Task[] {
  const stamp = now.toISOString();
  return tasks
    .filter((t) => (t.id === id || t.parent_id === id) && !t.deleted_at)
    .map((t) => ({ ...t, deleted_at: stamp, updated_at: stamp }));
}

/** Pone los cambios en la lista local (por id), sin duplicar. */
export function applyChanges(tasks: Task[], changed: Task[]): Task[] {
  const byId = new Map(tasks.map((t) => [t.id, t]));
  for (const t of changed) byId.set(t.id, t);
  return [...byId.values()].filter((t) => !t.deleted_at);
}

export async function loadTasks(client: SupabaseClient): Promise<Task[]> {
  const { data, error } = await client.from("tasks").select(COLUMNS).is("deleted_at", null).limit(1000);
  if (error) throw error;
  return (data ?? []) as unknown as Task[];
}

/** Sube filas completas (idempotente). Si otro dispositivo cambió lo mismo después, gana el suyo (sync_guard). */
export async function saveTasks(client: SupabaseClient, rows: Task[]): Promise<void> {
  if (!rows.length) return;
  const { error } = await client.from("tasks").upsert(rows, { onConflict: "id" });
  if (error) throw error;
}
