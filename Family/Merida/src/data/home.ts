import { STATUSES, type Task, type TaskStatus } from "./tasks";
import { deviceLabel, type Message } from "./chat";

/** Cuántas tareas principales hay en cada estado: es lo que dibuja la tesela de Tareas. */
export function statusCounts(tasks: Task[]): Record<TaskStatus, number> {
  const counts = { pending: 0, doing: 0, review: 0, done: 0 } as Record<TaskStatus, number>;
  for (const t of tasks) if (!t.deleted_at && !t.parent_id) counts[t.status in counts ? t.status : "pending"] += 1;
  return counts;
}

/** Cuántos bloques se dibujan por columna: nunca más de `max`, y al menos uno si hay algo. */
export function blocksFor(counts: Record<TaskStatus, number>, max = 5): number[] {
  return STATUSES.map((s) => Math.min(max, counts[s]));
}

/** El último mensaje con texto, recortado, para la tesela de Chat. */
export function lastMessage(messages: Message[], maxChars = 90): { device: string; text: string } | null {
  for (let i = messages.length - 1; i >= 0; i--) {
    const m = messages[i];
    const text = (m.body ?? "").replace(/\s+/g, " ").trim() || (m.attachments?.[0]?.file_name ?? "");
    if (!text) continue;
    return { device: deviceLabel(m.sender_device), text: text.length > maxChars ? `${text.slice(0, maxChars - 1).trimEnd()}…` : text };
  }
  return null;
}

/** El largo de cada línea del terminal dibujado (de 0.2 a 1), según los últimos mensajes. Sin mensajes, líneas fijas. */
export function lineWidths(messages: Message[], lines = 5): number[] {
  const recent = messages.slice(-lines);
  const widths = recent.map((m) => Math.min(1, Math.max(0.2, ((m.body ?? "").length || 12) / 60)));
  const fallback = [0.9, 0.55, 0.75, 0.4, 0.65];
  while (widths.length < lines) widths.unshift(fallback[widths.length % fallback.length]);
  return widths;
}
