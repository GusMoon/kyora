import { describe, expect, it } from "vitest";
import { blocksFor, lastMessage, lineWidths, statusCounts } from "../src/data/home";
import { newTask, type Task } from "../src/data/tasks";
import type { Message } from "../src/data/chat";
import { Status, latencyText } from "../src/status";

const task = (name: string, patch: Partial<Task> = {}): Task => ({ ...newTask(name, { id: name }), ...patch });
const msg = (id: string, body: string | null, device = "pc", patch: Partial<Message> = {}): Message => ({
  id, conversation_id: "c", sender_device: device, kind: "text", body, status: "sent",
  sent_at: "2026-11-11T10:00:00Z", created_at: "2026-11-11T10:00:00Z", deleted_at: null, attachments: [], ...patch,
});

describe("teselas del inicio", () => {
  it("cuenta las tareas principales por estado y no las subtareas ni las borradas", () => {
    const counts = statusCounts([
      task("a"), task("b", { status: "doing" }), task("c", { status: "doing" }),
      task("h", { parent_id: "a" }), task("x", { deleted_at: "2026-11-11T10:00:00Z" }), task("d", { status: "done" }),
    ]);
    expect(counts).toEqual({ pending: 1, doing: 2, review: 0, done: 1 });
    expect(blocksFor({ pending: 9, doing: 2, review: 0, done: 1 })).toEqual([5, 2, 0, 1]);
  });

  it("el último mensaje sale recortado y con el nombre del dispositivo; sin texto usa el archivo", () => {
    expect(lastMessage([])).toBeNull();
    expect(lastMessage([msg("1", "Hola"), msg("2", "  Qué   tal  ", "movil")])).toEqual({ device: "móvil", text: "Qué tal" });
    const long = lastMessage([msg("1", "a".repeat(200))])!;
    expect(long.text.length).toBe(90);
    expect(long.text.endsWith("…")).toBe(true);
    const file = msg("3", null, "pc", { attachments: [{ id: "f", storage_path: "p", file_name: "foto.jpg", mime_type: "image/jpeg", size_bytes: 1 }] });
    expect(lastMessage([file])?.text).toBe("foto.jpg");
  });

  it("el terminal dibujado siempre tiene el mismo número de líneas, entre 0.2 y 1", () => {
    expect(lineWidths([])).toHaveLength(5);
    const w = lineWidths([msg("1", "x".repeat(500)), msg("2", "hola")]);
    expect(w).toHaveLength(5);
    expect(w.every((n) => n >= 0.2 && n <= 1)).toBe(true);
    expect(w[4]).toBeCloseTo(0.2, 1);
  });
});

describe("estado del sistema", () => {
  it("avisa a quien escucha en cuanto cambia algo y dice el tiempo de respuesta en palabras", () => {
    const status = new Status();
    const seen: string[] = [];
    status.on((s) => seen.push(`${s.account}|${s.live}`));
    status.set({ account: "gustavo, admin" });
    status.set({ live: "live" });
    expect(seen).toEqual(["…|connecting", "gustavo, admin|connecting", "gustavo, admin|live"]);
    expect(latencyText(undefined)).toBe("midiendo");
    expect(latencyText(null)).toBe("sin respuesta");
    expect(latencyText(83.6)).toBe("84 ms");
  });
});
