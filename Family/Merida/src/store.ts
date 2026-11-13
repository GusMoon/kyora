import type { Task } from "./data/tasks";
import type { Track } from "./data/music";
import type { Message } from "./data/chat";
import type { CloudFile } from "./data/cloud";

export type Area = "tasks" | "tracks" | "messages" | "files";

/** Lo que Merida tiene cargado. Vive mientras dure la sesión, así cambiar de sección no vuelve a pedirlo todo. */
export class Store {
  tasks: Task[] = [];
  tracks: Track[] = [];
  messages: Message[] = [];
  files: CloudFile[] = []; // la nube: los archivos que hay en el servidor
  conversationId: string | null = null;
  loaded: Record<Area, boolean> = { tasks: false, tracks: false, messages: false, files: false };
  errors: Partial<Record<Area, string>> = {};
  private listeners = new Set<(area: Area) => void>();

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
}
