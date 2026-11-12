import { describe, expect, it } from "vitest";
import { applyChanges, groupByStatus, isOverdue, newTask, softDelete, stepStatus, subtasksOf, summary, withStatus, type Task } from "../src/data/tasks";
import { tasksStatement } from "../src/sections/tasks";

const T0 = new Date("2026-11-11T10:00:00Z");

function task(name: string, patch: Partial<Task> = {}): Task {
  return { ...newTask(name, { now: T0, id: name }), ...patch };
}

describe("tareas", () => {
  it("agrupa solo las principales y vivas, en su orden", () => {
    const tasks = [
      task("b", { position: 2 }),
      task("a", { position: 1 }),
      task("hija", { parent_id: "a" }),
      task("borrada", { deleted_at: T0.toISOString() }),
      task("x", { status: "doing" }),
    ];
    const g = groupByStatus(tasks);
    expect(g.pending.map((t) => t.id)).toEqual(["a", "b"]);
    expect(g.doing.map((t) => t.id)).toEqual(["x"]);
    expect(g.review).toEqual([]);
    expect(subtasksOf(tasks, "a").map((t) => t.id)).toEqual(["hija"]);
  });

  it("una tarea nueva va al final de su columna, con hora en UTC", () => {
    const siblings = [task("a", { position: 0 }), task("b", { position: 4 })];
    const t = newTask("  Llamar  ", { siblings, now: T0, id: "n" });
    expect(t).toMatchObject({ id: "n", name: "Llamar", position: 5, status: "pending", parent_id: null, real_s: 0 });
    expect(t.created_at).toBe("2026-11-11T10:00:00.000Z");
  });

  it("al terminarla guarda la hora y al volver atrás la quita; updated_at siempre avanza", () => {
    const later = new Date("2026-11-11T11:00:00Z");
    const done = withStatus(task("a"), "done", later);
    expect(done.finished).toBe(later.toISOString());
    expect(done.updated_at).toBe(later.toISOString());
    expect(withStatus(done, "review", later).finished).toBeNull();
  });

  it("recorre el flujo sin salirse de los extremos", () => {
    expect(stepStatus("pending", -1)).toBeNull();
    expect(stepStatus("pending", 1)).toBe("doing");
    expect(stepStatus("review", 1)).toBe("done");
    expect(stepStatus("done", 1)).toBeNull();
  });

  it("borra suave la tarea y sus subtareas, y la lista local las quita", () => {
    const tasks = [task("a"), task("h1", { parent_id: "a" }), task("otra")];
    const deleted = softDelete(tasks, "a", T0);
    expect(deleted.map((t) => t.id).sort()).toEqual(["a", "h1"]);
    expect(deleted.every((t) => t.deleted_at === T0.toISOString())).toBe(true);
    expect(applyChanges(tasks, deleted).map((t) => t.id)).toEqual(["otra"]);
  });

  it("cuenta abiertas y las que vencen hoy (o ya vencieron)", () => {
    const now = new Date(2026, 10, 11, 9, 0);
    const tasks = [
      task("hoy", { due: new Date(2026, 10, 11, 18, 0).toISOString() }),
      task("ayer", { due: new Date(2026, 10, 10, 18, 0).toISOString() }),
      task("mañana", { due: new Date(2026, 10, 12, 18, 0).toISOString() }),
      task("hecha", { status: "done", due: new Date(2026, 10, 10).toISOString() }),
    ];
    expect(summary(tasks, now)).toEqual({ open: 3, done: 1, dueToday: 2 });
    expect(isOverdue(tasks[1], now)).toBe(true);
    expect(isOverdue(tasks[3], now)).toBe(false);
  });

  it("el enunciado dice lo que pasa", () => {
    expect(tasksStatement([], false)).toBe("Cargando tus tareas.");
    expect(tasksStatement([], true)).toMatch(/^Nada pendiente/);
    expect(tasksStatement([task("a")], true)).toBe("1 abierta; ninguna vence hoy.");
    expect(tasksStatement([], true, "Sin conexión")).toBe("Sin conexión");
  });
});
