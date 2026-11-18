import type { Task, Tag, TaskTag } from "./data/tasks";
import type { Track } from "./data/music";
import type { Message } from "./data/chat";
import type { CloudFile } from "./data/cloud";
import type { CalendarEvent } from "./data/events";
import type { FinanceCategory, FinanceEntry } from "./data/finance";
import type { Reminder } from "./data/reminders";
import type { Habit, HabitCheck } from "./data/habits";
import type { ServerStats } from "./data/server";
import type { Improvement } from "./data/improvements";

export type Area = "tasks" | "tracks" | "messages" | "files" | "tags" | "events" | "finance" | "reminders" | "habits" | "improvements" | "server";

const AREAS: Area[] = ["tasks", "tracks", "messages", "files", "tags", "events", "finance", "reminders", "habits", "improvements", "server"];

/** Una orden de una parte de Merida a otra («abre esta tarea», «nuevo evento»). Caduca a los 3 segundos si nadie la toma. */
export interface Intent {
  name: string;
  arg?: string;
  at: number;
}

const INTENT_TTL_MS = 3000;

/** Lo que Merida tiene cargado. Vive mientras dure la sesión, así cambiar de sección no vuelve a pedirlo todo. */
export class Store {
  tasks: Task[] = [];
  tags: Tag[] = []; // las etiquetas de las tareas
  taskTags: TaskTag[] = []; // qué etiqueta tiene cada tarea
  tracks: Track[] = [];
  messages: Message[] = [];
  files: CloudFile[] = []; // la nube: los archivos que hay en el servidor
  events: CalendarEvent[] = [];
  serverStats: ServerStats | null = null; // lo que ocupa el proyecto de Supabase
  reminders: Reminder[] = [];
  habits: Habit[] = []; // los hábitos de Kyra
  habitChecks: HabitCheck[] = []; // qué días se cumplió cada uno
  financeEntries: FinanceEntry[] = [];
  financeCategories: FinanceCategory[] = [];
  improvements: Improvement[] = []; // las mejoras pendientes del proyecto (compartidas con Kyra)
  conversationId: string | null = null;
  loaded: Record<Area, boolean> = Object.fromEntries(AREAS.map((a) => [a, false])) as Record<Area, boolean>;
  errors: Partial<Record<Area, string>> = {};
  private listeners = new Set<(area: Area) => void>();
  private intent: Intent | null = null;
  private intentListeners = new Set<() => void>();

  on(fn: (area: Area) => void): () => void {
    this.listeners.add(fn);
    return () => this.listeners.delete(fn);
  }

  emit(area: Area) {
    for (const fn of this.listeners) fn(area);
  }

  fail(area: Area, message: string) {
    this.errors[area] = message;
    this.emit(area);
  }

  /** Deja una orden para la sección que toque. Si ya está abierta, la recibe al momento; si no, al montarse. */
  raise(name: string, arg?: string) {
    this.intent = { name, arg, at: Date.now() };
    for (const fn of this.intentListeners) fn();
  }

  /** Toma (y borra) la orden pendiente si es una de `names` y no caducó. */
  take(...names: string[]): Intent | null {
    const i = this.intent;
    if (!i || !names.includes(i.name) || Date.now() - i.at > INTENT_TTL_MS) return null;
    this.intent = null;
    return i;
  }

  onIntent(fn: () => void): () => void {
    this.intentListeners.add(fn);
    return () => this.intentListeners.delete(fn);
  }
}
