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

// ---------------------------------------------------------------------------------------------------------------------
// Edición completa de una tarea: todos los campos de `tasks`, el cronómetro y las etiquetas.
// Regla de oro: toda escritura debe llevar un `updated_at` MAYOR que el guardado; si no, sync_guard (en el servidor) la
// descarta en silencio y el cambio parece guardado pero no lo está. `stamp` lo garantiza aunque el reloj vaya atrasado.
// ---------------------------------------------------------------------------------------------------------------------

/** Una hora ISO que siempre es posterior a `prev` (al menos 1 ms). */
export function stamp(prev: string, now: Date = new Date()): string {
  return new Date(Math.max(now.getTime(), new Date(prev).getTime() + 1)).toISOString();
}

export type TaskPatch = Partial<Pick<Task, "name" | "description" | "expected_min" | "due" | "status" | "position">>;

/** La tarea con los campos cambiados. Cambiar el estado ajusta `finished` igual que `withStatus`. */
export function updateFields(task: Task, patch: TaskPatch, now: Date = new Date()): Task {
  const at = stamp(task.updated_at, now);
  const next: Task = { ...task, ...patch, updated_at: at };
  if (patch.name !== undefined) next.name = patch.name.trim() || task.name;
  if (patch.status !== undefined && patch.status !== task.status) {
    next.finished = patch.status === "done" ? (task.finished ?? at) : null;
    if (patch.status === "done" && task.timer_started) return stopTimer(next, now); // al terminarla el cronómetro se detiene
  }
  return next;
}

/** Enciende el cronómetro (si ya corre, no cambia nada). */
export function startTimer(task: Task, now: Date = new Date()): Task {
  if (task.timer_started) return task;
  return { ...task, timer_started: now.toISOString(), updated_at: stamp(task.updated_at, now) };
}

/** Detiene el cronómetro y suma el tiempo transcurrido a `real_s`. */
export function stopTimer(task: Task, now: Date = new Date()): Task {
  if (!task.timer_started) return task;
  return { ...task, real_s: task.real_s + runningSeconds(task, now), timer_started: null, updated_at: stamp(task.updated_at, now) };
}

/** Los segundos de la sesión que está corriendo (0 si está detenido). */
export function runningSeconds(task: Task, now: Date = new Date()): number {
  if (!task.timer_started) return 0;
  return Math.max(0, Math.floor((now.getTime() - new Date(task.timer_started).getTime()) / 1000));
}

/** El tiempo real total: lo guardado más lo que lleva la sesión en marcha. */
export function totalSeconds(task: Task, now: Date = new Date()): number {
  return task.real_s + runningSeconds(task, now);
}

/** «1 h 05 min», «12 min 30 s», «45 s». */
export function formatDuration(totalS: number): string {
  const s = Math.max(0, Math.floor(totalS));
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const sec = s % 60;
  if (h) return `${h} h ${String(m).padStart(2, "0")} min`;
  if (m) return `${m} min ${String(sec).padStart(2, "0")} s`;
  return `${sec} s`;
}

/** «90» → 90; vacío o inválido → null. Solo enteros ≥ 0 (la base de datos lo exige). */
export function parseMinutes(text: string): number | null {
  const t = text.trim();
  if (!/^\d{1,6}$/.test(t)) return null;
  return Number(t);
}

const pad2 = (n: number) => String(n).padStart(2, "0");

/** Una hora ISO → el valor de un `<input type="datetime-local">` (hora local, sin zona). */
export function toLocalInput(iso: string | null): string {
  if (!iso) return "";
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return "";
  return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}T${pad2(d.getHours())}:${pad2(d.getMinutes())}`;
}

/** El valor de un `<input type="datetime-local">` → hora ISO en UTC (o null si está vacío o es inválido). */
export function fromLocalInput(value: string): string | null {
  if (!value) return null;
  const d = new Date(value);
  return Number.isNaN(d.getTime()) ? null : d.toISOString();
}

/** Suelta una tarea en una columna del tablero (arrastrar y soltar). Va **antes** de `beforeId`, o al final si es null. Si cambia de
 * estado se aplica `updateFields` (con «terminada» y el cronómetro); las demás de la columna renumeran su posición solo si hace
 * falta. Devuelve únicamente las filas que cambian (vacío si no cambia nada: soltarla donde ya estaba). */
export function moveToColumn(tasks: Task[], id: string, status: TaskStatus, beforeId: string | null = null, now: Date = new Date()): Task[] {
  const dragged = tasks.find((t) => t.id === id && !t.deleted_at && !t.parent_id);
  if (!dragged) return [];
  const column = groupByStatus(tasks)[status].filter((t) => t.id !== id);
  const at = beforeId === null ? -1 : column.findIndex((t) => t.id === beforeId);
  const index = at < 0 ? column.length : at;
  const order = [...column.slice(0, index), dragged, ...column.slice(index)];
  const changed: Task[] = [];
  order.forEach((t, i) => {
    if (t.id === id) {
      if (t.status !== status || t.position !== i) changed.push(updateFields(t, { status, position: i }, now));
    } else if (t.position !== i) {
      changed.push({ ...t, position: i, updated_at: stamp(t.updated_at, now) });
    }
  });
  return changed;
}

/** Cambia el orden de una subtarea con su vecina (-1 arriba, +1 abajo). Devuelve las dos filas cambiadas, o [] si ya está en el extremo. */
export function moveSubtask(subs: Task[], id: string, delta: -1 | 1, now: Date = new Date()): Task[] {
  const i = subs.findIndex((t) => t.id === id);
  const j = i + delta;
  if (i < 0 || j < 0 || j >= subs.length) return [];
  const a = subs[i];
  const b = subs[j];
  // si comparten posición (pasa con tareas hechas en el escritorio), basta con pasar `a` al otro lado de `b`
  if (a.position === b.position) return [{ ...a, position: b.position + delta, updated_at: stamp(a.updated_at, now) }];
  return [
    { ...a, position: b.position, updated_at: stamp(a.updated_at, now) },
    { ...b, position: a.position, updated_at: stamp(b.updated_at, now) },
  ];
}

// ----- etiquetas (tablas `tags` y `task_tags`)

export interface Tag {
  id: string;
  name: string;
  color: string;
  updated_at: string;
  deleted_at: string | null;
}

export interface TaskTag {
  task_id: string;
  tag_id: string;
  updated_at: string;
  deleted_at: string | null;
}

export const TAG_COLORS = ["#c8f73a", "#ff5a1f", "#35d4ff", "#ff4fd8", "#c9cebc", "#ffd23f"];

export function newTag(name: string, color: string = TAG_COLORS[0], now: Date = new Date(), id: string = crypto.randomUUID()): Tag {
  return { id, name: name.trim(), color, updated_at: now.toISOString(), deleted_at: null };
}

/** Las etiquetas vivas de una tarea, por nombre. */
export function tagsOf(tags: Tag[], links: TaskTag[], taskId: string): Tag[] {
  const ids = new Set(links.filter((l) => l.task_id === taskId && !l.deleted_at).map((l) => l.tag_id));
  return tags.filter((t) => ids.has(t.id) && !t.deleted_at).sort((a, b) => a.name.localeCompare(b.name));
}

/** La fila de `task_tags` para poner o quitar una etiqueta (quitar = borrado suave; ponerla de nuevo la revive). */
export function toggleTaskTag(links: TaskTag[], taskId: string, tagId: string, on: boolean, now: Date = new Date()): TaskTag {
  const prev = links.find((l) => l.task_id === taskId && l.tag_id === tagId);
  const at = prev ? stamp(prev.updated_at, now) : now.toISOString();
  return { task_id: taskId, tag_id: tagId, updated_at: at, deleted_at: on ? null : at };
}

/** Pone los cambios en una lista de enlaces (por tarea y etiqueta), sin duplicar. Conserva los borrados: así «quitar» se ve. */
export function mergeTaskTags(current: TaskTag[], changed: TaskTag[]): TaskTag[] {
  const byKey = new Map(current.map((l) => [`${l.task_id}:${l.tag_id}`, l]));
  for (const l of changed) byKey.set(`${l.task_id}:${l.tag_id}`, l);
  return [...byKey.values()];
}

export async function loadTags(client: SupabaseClient): Promise<Tag[]> {
  const { data, error } = await client.from("tags").select("id,name,color,updated_at,deleted_at").is("deleted_at", null).limit(500);
  if (error) throw error;
  return (data ?? []) as unknown as Tag[];
}

export async function saveTags(client: SupabaseClient, rows: Tag[]): Promise<void> {
  if (!rows.length) return;
  const { error } = await client.from("tags").upsert(rows, { onConflict: "id" });
  if (error) throw error;
}

export async function loadTaskTags(client: SupabaseClient): Promise<TaskTag[]> {
  const { data, error } = await client.from("task_tags").select("task_id,tag_id,updated_at,deleted_at").is("deleted_at", null).limit(5000);
  if (error) throw error;
  return (data ?? []) as unknown as TaskTag[];
}

export async function saveTaskTags(client: SupabaseClient, rows: TaskTag[]): Promise<void> {
  if (!rows.length) return;
  const { error } = await client.from("task_tags").upsert(rows, { onConflict: "task_id,tag_id" });
  if (error) throw error;
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
