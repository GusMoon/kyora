import { describe, expect, it } from "vitest";
import {
  applyChanges,
  formatDuration,
  fromLocalInput,
  groupByStatus,
  isOverdue,
  mergeTaskTags,
  moveSubtask,
  moveToColumn,
  newTag,
  newTask,
  parseMinutes,
  runningSeconds,
  softDelete,
  stamp,
  startTimer,
  stepStatus,
  stopTimer,
  subtasksOf,
  summary,
  tagsOf,
  toLocalInput,
  toggleTaskTag,
  totalSeconds,
  updateFields,
  withStatus,
  type Task,
} from "../src/data/tasks";
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

describe("tareas: edición completa", () => {
  const later = new Date("2026-11-11T11:00:00Z");

  it("updated_at siempre es mayor que el guardado, aunque el reloj vaya atrasado (si no, sync_guard lo descarta en silencio)", () => {
    const a = task("a", { updated_at: "2030-01-01T00:00:00.000Z" });
    expect(stamp(a.updated_at, new Date("2020-01-01"))).toBe("2030-01-01T00:00:00.001Z");
    expect(updateFields(a, { name: "b" }, new Date("2020-01-01")).updated_at > a.updated_at).toBe(true);
    expect(stamp("2026-11-11T10:00:00.000Z", later)).toBe(later.toISOString());
  });

  it("cambia cualquier campo y recorta el nombre, sin dejarlo vacío", () => {
    const a = task("a");
    const b = updateFields(a, { name: "  Nuevo  ", description: "texto", expected_min: 30, due: later.toISOString(), position: 7 }, later);
    expect(b).toMatchObject({ name: "Nuevo", description: "texto", expected_min: 30, due: later.toISOString(), position: 7 });
    expect(updateFields(a, { name: "   " }, later).name).toBe("a");
    expect(updateFields(b, { expected_min: null, due: null }, later)).toMatchObject({ expected_min: null, due: null });
  });

  it("al pasar a Hecha guarda la hora de fin y al salir de Hecha la quita", () => {
    const done = updateFields(task("a"), { status: "done" }, later);
    expect(done.finished).toBe(done.updated_at);
    expect(updateFields(done, { status: "doing" }, later).finished).toBeNull();
    expect(updateFields(done, { name: "x" }, later).finished).toBe(done.finished); // otro cambio no la toca
  });

  it("el cronómetro suma el tiempo al detenerse y no se duplica si se pulsa dos veces", () => {
    const t0 = new Date("2026-11-11T10:00:00Z");
    const running = startTimer(task("a", { real_s: 100 }), t0);
    expect(running.timer_started).toBe(t0.toISOString());
    expect(startTimer(running, new Date("2026-11-11T10:05:00Z"))).toBe(running); // ya corre
    const mid = new Date("2026-11-11T10:01:30Z");
    expect(runningSeconds(running, mid)).toBe(90);
    expect(totalSeconds(running, mid)).toBe(190);
    const stopped = stopTimer(running, mid);
    expect(stopped).toMatchObject({ real_s: 190, timer_started: null });
    expect(stopTimer(stopped, mid)).toBe(stopped); // ya está detenido
    expect(totalSeconds(stopped, new Date("2026-11-12T00:00:00Z"))).toBe(190); // detenido no sigue contando
  });

  it("al terminar una tarea con el cronómetro en marcha, se detiene y suma", () => {
    const running = startTimer(task("a"), new Date("2026-11-11T10:00:00Z"));
    const done = updateFields(running, { status: "done" }, new Date("2026-11-11T10:10:00Z"));
    expect(done).toMatchObject({ status: "done", timer_started: null, real_s: 600 });
    expect(done.finished).not.toBeNull();
  });

  it("da formato a las duraciones", () => {
    expect(formatDuration(0)).toBe("0 s");
    expect(formatDuration(45)).toBe("45 s");
    expect(formatDuration(750)).toBe("12 min 30 s");
    expect(formatDuration(3725)).toBe("1 h 02 min");
    expect(formatDuration(-5)).toBe("0 s");
  });

  it("lee los minutos esperados: solo enteros desde cero", () => {
    expect(parseMinutes("90")).toBe(90);
    expect(parseMinutes(" 0 ")).toBe(0);
    for (const bad of ["", "-5", "1.5", "abc", "1e3", "9999999"]) expect(parseMinutes(bad)).toBeNull();
  });

  it("convierte la fecha de entrega a y desde el campo de fecha y hora local", () => {
    const iso = new Date(2026, 10, 13, 18, 30).toISOString();
    expect(toLocalInput(iso)).toBe("2026-11-13T18:30");
    expect(fromLocalInput("2026-11-13T18:30")).toBe(iso);
    expect(toLocalInput(null)).toBe("");
    expect(fromLocalInput("")).toBeNull();
    expect(fromLocalInput("no es fecha")).toBeNull();
  });

  it("reordena subtareas intercambiando posiciones, y sin salirse de los extremos", () => {
    const subs = [task("s1", { parent_id: "p", position: 0 }), task("s2", { parent_id: "p", position: 1 }), task("s3", { parent_id: "p", position: 2 })];
    const moved = moveSubtask(subs, "s3", -1, later);
    expect(moved.map((t) => [t.id, t.position])).toEqual([["s3", 1], ["s2", 2]]);
    expect(moved.every((t) => t.updated_at > T0.toISOString())).toBe(true);
    expect(moveSubtask(subs, "s1", -1)).toEqual([]);
    expect(moveSubtask(subs, "s3", 1)).toEqual([]);
    expect(moveSubtask(subs, "nada", 1)).toEqual([]);
  });

  it("con posiciones repetidas (tareas hechas en el escritorio) una subtarea igualmente puede cambiar de lugar", () => {
    const subs = [task("s1", { parent_id: "p", position: 0 }), task("s2", { parent_id: "p", position: 0 })];
    const moved = moveSubtask(subs, "s2", -1, later);
    expect(moved).toHaveLength(1);
    expect(moved[0].position).toBe(-1); // pasa antes que s1
  });
});

describe("tareas: arrastrar entre columnas", () => {
  const now = new Date("2026-11-11T11:00:00Z");
  const a = task("a", { position: 0 });
  const b = task("b", { position: 1 });
  const c = task("c", { position: 2 });
  const d = task("d", { status: "doing", position: 0 });
  const all = [a, b, c, d];

  it("soltar en otra columna cambia el estado y la deja al final", () => {
    const [moved, ...rest] = moveToColumn(all, "a", "doing", null, now);
    expect(rest).toEqual([]);
    expect(moved).toMatchObject({ id: "a", status: "doing", position: 1 });
    expect(moved.updated_at > a.updated_at).toBe(true);
  });

  it("soltar antes de otra tarjeta la mete en ese lugar y renumera solo las que cambian", () => {
    const changed = moveToColumn(all, "a", "doing", "d", now);
    expect(Object.fromEntries(changed.map((t) => [t.id, [t.status, t.position]]))).toEqual({ a: ["doing", 0], d: ["doing", 1] });
    expect(changed.every((t) => t.updated_at > T0.toISOString())).toBe(true);
  });

  it("dentro de la misma columna reordena: c antes de a", () => {
    const changed = moveToColumn(all, "c", "pending", "a", now);
    expect(Object.fromEntries(changed.map((t) => [t.id, t.position]))).toEqual({ c: 0, a: 1, b: 2 });
    expect(changed.every((t) => t.status === "pending")).toBe(true);
  });

  it("soltarla donde ya estaba no cambia nada (ni sube nada al servidor)", () => {
    expect(moveToColumn(all, "b", "pending", "c", now)).toEqual([]); // justo antes de la que ya le sigue
    expect(moveToColumn(all, "c", "pending", null, now)).toEqual([]); // ya es la última
  });

  it("a Hecha guarda la hora de fin y detiene el cronómetro; sale de Hecha y la quita", () => {
    const running = startTimer(task("t", { position: 0 }), new Date("2026-11-11T10:00:00Z"));
    const [done] = moveToColumn([running], "t", "done", null, now);
    expect(done).toMatchObject({ status: "done", timer_started: null, real_s: 3600 });
    expect(done.finished).not.toBeNull();
    const [back] = moveToColumn([done], "t", "review", null, new Date("2026-11-11T12:00:00Z"));
    expect(back).toMatchObject({ status: "review", finished: null });
  });

  it("solo se arrastran tareas principales y vivas: una subtarea, una borrada o un id raro no hacen nada", () => {
    const sub = task("sub", { parent_id: "a" });
    const gone = task("gone", { deleted_at: T0.toISOString() });
    expect(moveToColumn([a, sub, gone], "sub", "done", null, now)).toEqual([]);
    expect(moveToColumn([a, sub, gone], "gone", "done", null, now)).toEqual([]);
    expect(moveToColumn([a], "nada", "done", null, now)).toEqual([]);
  });

  it("con posiciones repetidas (hechas en el escritorio) todas quedan numeradas 0, 1, 2…", () => {
    const x = task("x", { position: 0 });
    const y = task("y", { position: 0 });
    const z = task("z", { position: 0, status: "doing" });
    const changed = moveToColumn([x, y, z], "z", "pending", "y", now);
    const pos = Object.fromEntries(changed.map((t) => [t.id, t.position]));
    expect(pos.z).toBe(1); // entre x y y
    expect(pos.y).toBe(2);
  });
});

describe("tareas: etiquetas", () => {
  const later = new Date("2026-11-11T11:00:00Z");
  const casa = newTag("  casa ", "#ff5a1f", T0, "t-casa");
  const trabajo = newTag("trabajo", "#35d4ff", T0, "t-trabajo");

  it("una etiqueta nueva lleva su color y el nombre recortado", () => {
    expect(casa).toMatchObject({ id: "t-casa", name: "casa", color: "#ff5a1f", deleted_at: null });
  });

  it("poner una etiqueta crea el enlace; quitarla lo borra suave; ponerla otra vez lo revive, siempre con updated_at mayor", () => {
    const on = toggleTaskTag([], "a", casa.id, true, T0);
    expect(on).toMatchObject({ task_id: "a", tag_id: "t-casa", deleted_at: null });
    const off = toggleTaskTag([on], "a", casa.id, false, T0); // mismo reloj: debe avanzar igualmente
    expect(off.deleted_at).toBe(off.updated_at);
    expect(off.updated_at > on.updated_at).toBe(true);
    const back = toggleTaskTag([off], "a", casa.id, true, later);
    expect(back.deleted_at).toBeNull();
    expect(back.updated_at > off.updated_at).toBe(true);
  });

  it("lista las etiquetas vivas de una tarea por nombre, sin las quitadas ni las de otras tareas", () => {
    const links = [
      toggleTaskTag([], "a", trabajo.id, true, T0),
      toggleTaskTag([], "a", casa.id, true, T0),
      { ...toggleTaskTag([], "a", "t-borrada", true, T0), deleted_at: T0.toISOString() },
      toggleTaskTag([], "b", casa.id, true, T0),
    ];
    expect(tagsOf([casa, trabajo], links, "a").map((t) => t.name)).toEqual(["casa", "trabajo"]);
    expect(tagsOf([casa, trabajo], links, "b").map((t) => t.name)).toEqual(["casa"]);
    expect(tagsOf([casa, { ...trabajo, deleted_at: T0.toISOString() }], links, "a").map((t) => t.name)).toEqual(["casa"]);
  });

  it("junta los enlaces por tarea y etiqueta sin duplicar", () => {
    const on = toggleTaskTag([], "a", casa.id, true, T0);
    const off = toggleTaskTag([on], "a", casa.id, false, later);
    const merged = mergeTaskTags([on], [off, toggleTaskTag([], "a", trabajo.id, true, T0)]);
    expect(merged).toHaveLength(2);
    expect(merged.find((l) => l.tag_id === casa.id)?.deleted_at).not.toBeNull();
  });
});
