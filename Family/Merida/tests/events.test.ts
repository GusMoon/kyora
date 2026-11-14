import { describe, expect, it } from "vitest";
import {
  dayCounts,
  dayKey,
  eventOnDay,
  eventsOnDay,
  eventsStatement,
  isoDayKey,
  longDate,
  monthGrid,
  monthTitle,
  moveEventToDay,
  moveTaskToDay,
  newEvent,
  shiftMonth,
  softDeleteEvent,
  tasksDueOn,
  updateEvent,
  weekDays,
  applyEvents,
} from "../src/data/events";
import { newTask } from "../src/data/tasks";
import { combineDayTime } from "../src/sections/calendar";

const T0 = new Date(2026, 10, 13, 10, 0); // viernes 13 de noviembre de 2026

describe("calendario: cuadrícula", () => {
  it("un mes son 6 semanas de lunes a domingo", () => {
    const grid = monthGrid(2026, 10); // noviembre de 2026 empieza en domingo
    expect(grid).toHaveLength(6);
    expect(grid.every((w) => w.length === 7)).toBe(true);
    expect(grid[0][0].getDay()).toBe(1); // lunes
    expect(grid[0][6].getDay()).toBe(0); // domingo
    expect(dayKey(grid[0][6])).toBe("2026-11-01"); // el 1 cae en domingo: es el último de la primera semana
    expect(dayKey(grid[0][0])).toBe("2026-10-26");
    expect(dayKey(grid[5][6])).toBe("2026-12-06");
  });

  it("cambia de mes y desborda el año", () => {
    expect(shiftMonth(2026, 10, 1)).toEqual({ year: 2026, month: 11 });
    expect(shiftMonth(2026, 11, 1)).toEqual({ year: 2027, month: 0 });
    expect(shiftMonth(2026, 0, -1)).toEqual({ year: 2025, month: 11 });
    expect(shiftMonth(2026, 5, -17)).toEqual({ year: 2025, month: 0 });
  });

  it("la semana de una fecha va de lunes a domingo", () => {
    const week = weekDays(T0);
    expect(week.map(dayKey)).toEqual(["2026-11-09", "2026-11-10", "2026-11-11", "2026-11-12", "2026-11-13", "2026-11-14", "2026-11-15"]);
    expect(weekDays(new Date(2026, 10, 15)).map(dayKey)[0]).toBe("2026-11-09"); // un domingo pertenece a la semana que termina
  });

  it("los textos salen en español", () => {
    expect(longDate(T0)).toBe("viernes 13 de noviembre de 2026");
    expect(monthTitle(2026, 10)).toBe("noviembre 2026");
  });

  it("combina un día y una hora (con la hora vacía, a las 09:00)", () => {
    expect(combineDayTime("2026-11-13", "18:30").getHours()).toBe(18);
    expect(combineDayTime("2026-11-13", "").getHours()).toBe(9);
    expect(dayKey(combineDayTime("2026-11-13", "23:59"))).toBe("2026-11-13");
  });
});

describe("calendario: eventos y tareas", () => {
  it("un evento de todo el día empieza a medianoche local, sin hora de fin", () => {
    const e = newEvent("  Cumple  ", T0, { allDay: true, id: "e1", now: T0 });
    expect(e).toMatchObject({ id: "e1", title: "Cumple", all_day: true, ends_at: null, task_id: null, deleted_at: null });
    expect(new Date(e.starts_at).getHours()).toBe(0);
    expect(isoDayKey(e.starts_at)).toBe("2026-11-13");
  });

  it("un evento de varios días cae en cada uno de ellos", () => {
    const e = newEvent("Viaje", new Date(2026, 10, 12, 9), { end: new Date(2026, 10, 14, 18), id: "v", now: T0 });
    expect(["2026-11-11", "2026-11-12", "2026-11-13", "2026-11-14", "2026-11-15"].map((k) => eventOnDay(e, k))).toEqual([false, true, true, true, false]);
  });

  it("los borrados no salen, y dentro de un día van primero los de todo el día y luego por hora", () => {
    const a = newEvent("tarde", new Date(2026, 10, 13, 17), { id: "a", now: T0 });
    const b = newEvent("mañana", new Date(2026, 10, 13, 8), { id: "b", now: T0 });
    const c = newEvent("todo", T0, { allDay: true, id: "c", now: T0 });
    const d = softDeleteEvent(newEvent("borrado", T0, { id: "d", now: T0 }), T0);
    expect(eventsOnDay([a, b, c, d], "2026-11-13").map((e) => e.id)).toEqual(["c", "b", "a"]);
  });

  it("editar sube updated_at aunque el reloj vaya atrasado (si no, el servidor lo ignora)", () => {
    const e = newEvent("x", T0, { id: "e", now: new Date(2030, 0, 1) });
    const edited = updateEvent(e, { title: "  nuevo  " }, new Date(2020, 0, 1));
    expect(edited.title).toBe("nuevo");
    expect(edited.updated_at > e.updated_at).toBe(true);
    expect(updateEvent(e, { title: "   " }).title).toBe("x"); // un título vacío no vale
  });

  it("mover un evento a otro día conserva la hora y la duración", () => {
    const e = newEvent("Reunión", new Date(2026, 10, 13, 11), { end: new Date(2026, 10, 13, 12, 30), id: "r", now: T0 });
    const moved = moveEventToDay(e, "2026-11-20");
    expect(isoDayKey(moved.starts_at)).toBe("2026-11-20");
    expect(new Date(moved.starts_at).getHours()).toBe(11);
    expect(isoDayKey(moved.ends_at!)).toBe("2026-11-20");
    expect(new Date(moved.ends_at!).getHours()).toBe(12);
    expect(new Date(moved.ends_at!).getMinutes()).toBe(30);
  });

  it("las tareas con fecha de entrega salen en su día, y arrastrarlas cambia su fecha", () => {
    const t = { ...newTask("Pagar", { id: "t", now: T0 }), due: new Date(2026, 10, 13, 18, 15).toISOString() };
    const noDue = newTask("Sin fecha", { id: "n", now: T0 });
    expect(tasksDueOn([t, noDue], "2026-11-13").map((x) => x.id)).toEqual(["t"]);
    const moved = moveTaskToDay(t, "2026-11-16");
    expect(isoDayKey(moved.due!)).toBe("2026-11-16");
    expect(new Date(moved.due!).getHours()).toBe(18);
    expect(moved.updated_at > t.updated_at).toBe(true);
    expect(new Date(moveTaskToDay(noDue, "2026-11-16").due!).getHours()).toBe(9); // sin hora previa, a las 09:00
  });

  it("cuenta lo que hay cada día para las marcas", () => {
    const e = newEvent("x", T0, { id: "e", now: T0 });
    const t = { ...newTask("t", { id: "t", now: T0 }), due: T0.toISOString() };
    const counts = dayCounts([e], [t], [T0, new Date(2026, 10, 14)]);
    expect(counts.get("2026-11-13")).toEqual({ events: 1, tasks: 1 });
    expect(counts.get("2026-11-14")).toEqual({ events: 0, tasks: 0 });
  });

  it("aplica cambios por id y quita los borrados de la lista local", () => {
    const a = newEvent("a", T0, { id: "a", now: T0 });
    const b = newEvent("b", T0, { id: "b", now: T0 });
    expect(applyEvents([a, b], [softDeleteEvent(a, T0)]).map((e) => e.id)).toEqual(["b"]);
  });

  it("el enunciado dice lo de hoy", () => {
    const e = newEvent("x", T0, { id: "e", now: T0 });
    const t = { ...newTask("t", { id: "t", now: T0 }), due: T0.toISOString() };
    expect(eventsStatement([], [], false)).toBe("Cargando tu calendario.");
    expect(eventsStatement([], [], true, undefined, T0)).toBe("Hoy no tienes eventos ni entregas.");
    expect(eventsStatement([e], [t], true, undefined, T0)).toBe("Hoy: 1 evento y 1 entrega.");
    expect(eventsStatement([], [], true, "Sin conexión")).toBe("Sin conexión");
  });
});
