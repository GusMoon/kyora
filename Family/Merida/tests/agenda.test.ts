import { describe, expect, it } from "vitest";
import { agendaForDay, agendaStatement, isoWeek, layoutDay, minutesAtY, pendingAlerts, rangeFor, stepSelected, type AgendaData, type AgendaItem } from "../src/data/agenda";
import { EVERY_DAY, applyChecks, habitProgress, habitsOn, hhmmToMinutes, isChecked, maskOf, minutesToHHMM, newHabit, softDeleteHabit, streak, toggleCheck, updateHabit, weekdayBit, weekdaysLabel, type HabitCheck } from "../src/data/habits";
import { applyReminders, isOverdue, moveReminderTo, newReminder, remindersOnDay, softDeleteReminder, toggleReminder, updateReminder } from "../src/data/reminders";
import { dayKey, moveEventTo, moveTaskTo, newEvent } from "../src/data/events";
import { newTask } from "../src/data/tasks";
import { DEFAULT_PREFS, loadPrefs } from "../src/prefs";

const D = (y: number, m: number, d: number, h = 0, min = 0) => new Date(y, m - 1, d, h, min);
const none: AgendaData = { events: [], tasks: [], reminders: [], habits: [], checks: [] };

describe("hábitos", () => {
  it("la máscara de la semana va de lunes (1) a domingo (64)", () => {
    expect(weekdayBit(D(2026, 11, 9))).toBe(1); // lunes
    expect(weekdayBit(D(2026, 11, 15))).toBe(64); // domingo
    expect(maskOf([0, 2, 4])).toBe(21);
    expect(weekdaysLabel(EVERY_DAY)).toBe("a diario");
    expect(weekdaysLabel(maskOf([0, 2, 4]))).toBe("L X V");
  });

  it("las horas de aviso van en minutos desde medianoche", () => {
    expect(minutesToHHMM(450)).toBe("07:30");
    expect(hhmmToMinutes("07:30")).toBe(450);
    expect(hhmmToMinutes("24:00")).toBeNull();
    expect(hhmmToMinutes("")).toBeNull();
  });

  it("solo tocan los días elegidos y desde que se crearon", () => {
    const h = newHabit("Correr", { weekdays: maskOf([0, 2]), now: D(2026, 11, 3) }); // lunes y miércoles, creado el martes 3
    expect(habitsOn([h], "2026-11-02")).toEqual([]); // antes de crearlo
    expect(habitsOn([h], "2026-11-04")).toHaveLength(1); // miércoles
    expect(habitsOn([h], "2026-11-05")).toEqual([]); // jueves
    expect(habitsOn([softDeleteHabit(h)], "2026-11-04")).toEqual([]);
  });

  it("los que avisan a una hora van primero, por hora", () => {
    const a = newHabit("A", { now: D(2026, 11, 1), position: 0 });
    const b = newHabit("B", { now: D(2026, 11, 1), remindAt: 600, position: 1 });
    const c = newHabit("C", { now: D(2026, 11, 1), remindAt: 480, position: 2 });
    expect(habitsOn([a, b, c], "2026-11-10").map((x) => x.name)).toEqual(["C", "B", "A"]);
  });

  it("marcar y desmarcar siempre sube updated_at (sync_guard ignora lo que no sea más nuevo)", () => {
    const t0 = D(2026, 11, 10, 9);
    const on = toggleCheck([], "h", "2026-11-10", t0);
    expect(on).toMatchObject({ habit_id: "h", day: "2026-11-10", done: true });
    const off = toggleCheck([on], "h", "2026-11-10", t0); // mismo instante exacto
    expect(off.done).toBe(false);
    expect(new Date(off.updated_at).getTime()).toBeGreaterThan(new Date(on.updated_at).getTime());
    expect(isChecked(applyChecks([on], [off]), "h", "2026-11-10")).toBe(false);
  });

  it("cuenta lo hecho de un día", () => {
    const hs = [newHabit("A", { id: "a", now: D(2026, 11, 1) }), newHabit("B", { id: "b", now: D(2026, 11, 1) })];
    const checks: HabitCheck[] = [{ habit_id: "a", day: "2026-11-10", done: true, updated_at: "2026-11-10T10:00:00Z" }];
    expect(habitProgress(hs, checks, "2026-11-10")).toEqual({ total: 2, done: 1 });
  });

  it("la racha cuenta días seguidos, salta los que no tocan y hoy aún puede cumplirse", () => {
    const h = newHabit("Leer", { id: "h", weekdays: maskOf([0, 1, 2, 3, 4]), now: D(2026, 10, 1) }); // entre semana
    const ck = (day: string): HabitCheck => ({ habit_id: "h", day, done: true, updated_at: "2026-11-01T00:00:00Z" });
    // lunes 9, viernes 6, jueves 5 hechos; martes 10 (hoy) todavía no: la racha de 3 sigue viva
    expect(streak(h, [ck("2026-11-09"), ck("2026-11-06"), ck("2026-11-05")], "2026-11-10")).toBe(3);
    // si el jueves 5 falló, se corta en el viernes y el lunes
    expect(streak(h, [ck("2026-11-09"), ck("2026-11-06")], "2026-11-10")).toBe(2);
    expect(streak(h, [], "2026-11-10")).toBe(0);
  });

  it("editar sube updated_at y no admite un nombre vacío", () => {
    const h = newHabit("Agua", { now: D(2026, 11, 1) });
    const u = updateHabit(h, { name: "   ", weekdays: 3 }, D(2026, 11, 1));
    expect(u.name).toBe("Agua");
    expect(u.weekdays).toBe(3);
    expect(new Date(u.updated_at).getTime()).toBeGreaterThan(new Date(h.updated_at).getTime());
    expect(newHabit("X", { weekdays: 0 }).weekdays).toBe(EVERY_DAY);
  });
});

describe("recordatorios", () => {
  it("se crean, se marcan, se editan y se borran subiendo updated_at", () => {
    const t0 = D(2026, 11, 10, 9);
    const r = newReminder("  Llamar  ", D(2026, 11, 12, 16, 30), { now: t0, id: "r" });
    expect(r).toMatchObject({ title: "Llamar", done: false, deleted_at: null });
    const done = toggleReminder(r, t0);
    expect(done.done).toBe(true);
    expect(new Date(done.updated_at).getTime()).toBeGreaterThan(new Date(r.updated_at).getTime());
    expect(updateReminder(done, { title: " " }, t0).title).toBe("Llamar");
    const gone = softDeleteReminder(done, t0);
    expect(gone.deleted_at).not.toBeNull();
    expect(applyReminders([r], [gone])).toEqual([]);
  });

  it("salen en su día, por hora, y se pueden mover de día o de hora", () => {
    const a = newReminder("A", D(2026, 11, 12, 18), { id: "a" });
    const b = newReminder("B", D(2026, 11, 12, 8), { id: "b" });
    expect(remindersOnDay([a, b], "2026-11-12").map((x) => x.id)).toEqual(["b", "a"]);
    const sameTime = moveReminderTo(a, "2026-11-14");
    expect(dayKey(new Date(sameTime.remind_at))).toBe("2026-11-14");
    expect(new Date(sameTime.remind_at).getHours()).toBe(18);
    const other = moveReminderTo(a, "2026-11-14", 7 * 60 + 15);
    expect([new Date(other.remind_at).getHours(), new Date(other.remind_at).getMinutes()]).toEqual([7, 15]);
  });

  it("vencido = pendiente y con la hora ya pasada", () => {
    const r = newReminder("A", D(2026, 11, 12, 10));
    expect(isOverdue(r, D(2026, 11, 12, 11))).toBe(true);
    expect(isOverdue(r, D(2026, 11, 12, 9))).toBe(false);
    expect(isOverdue({ ...r, done: true }, D(2026, 11, 12, 11))).toBe(false);
  });
});

describe("mover eventos y tareas a una hora", () => {
  it("el evento conserva su duración al cambiar de hora y el de todo el día solo cambia de día", () => {
    const e = newEvent("Cita", D(2026, 11, 10, 10), { end: D(2026, 11, 10, 11, 30), id: "e" });
    const m = moveEventTo(e, "2026-11-12", 14 * 60);
    expect(new Date(m.starts_at).getHours()).toBe(14);
    expect(new Date(m.ends_at!).getTime() - new Date(m.starts_at).getTime()).toBe(90 * 60_000);
    const all = newEvent("Cumple", D(2026, 11, 10), { allDay: true });
    const n = moveEventTo(all, "2026-11-12", 14 * 60);
    expect([new Date(n.starts_at).getDate(), new Date(n.starts_at).getHours()]).toEqual([12, 0]);
  });

  it("la tarea cambia de día y, con hora, de hora; sin fecha previa cae a las 09:00", () => {
    const t = { ...newTask("T", { id: "t" }), due: D(2026, 11, 10, 18).toISOString() };
    expect(new Date(moveTaskTo(t, "2026-11-11").due!).getHours()).toBe(18);
    expect(new Date(moveTaskTo(t, "2026-11-11", 8 * 60 + 30).due!).getMinutes()).toBe(30);
    expect(new Date(moveTaskTo(newTask("N", { id: "n" }), "2026-11-11").due!).getHours()).toBe(9);
  });
});

describe("la agenda del día", () => {
  const key = "2026-11-12"; // jueves
  const data: AgendaData = {
    events: [newEvent("Reunión", D(2026, 11, 12, 10), { end: D(2026, 11, 12, 11), id: "e", color: "#ff5a1f" }), newEvent("Cumple", D(2026, 11, 12), { allDay: true, id: "c" })],
    tasks: [{ ...newTask("Informe", { id: "t" }), due: D(2026, 11, 12, 15).toISOString() }, { ...newTask("Hecha", { id: "t2", status: "done" }), due: D(2026, 11, 12, 16).toISOString() }],
    reminders: [newReminder("Llamar", D(2026, 11, 12, 9), { id: "r" })],
    habits: [newHabit("Agua", { id: "h1", now: D(2026, 11, 1), remindAt: 8 * 60 }), newHabit("Estirar", { id: "h2", now: D(2026, 11, 1), position: 1 })],
    checks: [{ habit_id: "h2", day: key, done: true, updated_at: "2026-11-12T10:00:00Z" }],
  };

  it("junta las cuatro clases, lo de todo el día primero y lo demás por hora", () => {
    const items = agendaForDay(data, key);
    expect(items.map((i) => `${i.kind}:${i.id}`)).toEqual(["event:c", "habit:h2", "habit:h1", "reminder:r", "event:e", "task:t", "task:t2"]);
    const byId = Object.fromEntries(items.map((i) => [i.id, i]));
    expect(byId.e).toMatchObject({ start: 600, end: 660, color: "#ff5a1f", time: "10:00–11:00", allDay: false });
    expect(byId.c).toMatchObject({ allDay: true, time: "todo el día" });
    expect(byId.h1).toMatchObject({ start: 480, allDay: false, done: false });
    expect(byId.h2).toMatchObject({ allDay: true, done: true });
    expect(byId.t2.done).toBe(true);
  });

  it("filtra por clase y por texto sin acentos ni mayúsculas", () => {
    expect(agendaForDay(data, key, "reminder").map((i) => i.id)).toEqual(["r"]);
    expect(agendaForDay(data, key, "habit").map((i) => i.id)).toEqual(["h2", "h1"]);
    expect(agendaForDay(data, key, "all", "REUNION").map((i) => i.id)).toEqual(["e"]);
    expect(agendaForDay(data, key, "all", "zzz")).toEqual([]);
  });

  it("un evento de varios días trae su tramo y va a la franja de todo el día", () => {
    const trip = newEvent("Viaje", D(2026, 11, 12, 9), { end: D(2026, 11, 14, 12), id: "v" });
    const d = { ...none, events: [trip] };
    expect(agendaForDay(d, "2026-11-12")[0]).toMatchObject({ span: "start", allDay: true });
    expect(agendaForDay(d, "2026-11-13")[0]).toMatchObject({ span: "mid", allDay: true });
    expect(agendaForDay(d, "2026-11-14")[0]).toMatchObject({ span: "end", allDay: true });
    expect(agendaForDay(d, "2026-11-15")).toEqual([]);
  });

  it("el enunciado de hoy resume lo pendiente", () => {
    const now = D(2026, 11, 12, 7);
    expect(agendaStatement(data, true, undefined, now)).toBe("Hoy: 2 eventos, 1 entrega, 1 recordatorio y 1 hábito por cumplir.");
    expect(agendaStatement(none, true, undefined, now)).toBe("Hoy no tienes nada pendiente en el calendario.");
    expect(agendaStatement(none, false)).toBe("Cargando tu calendario.");
    expect(agendaStatement(none, true, "Sin red")).toBe("Sin red");
  });
});

describe("la columna de horas", () => {
  const item = (id: string, start: number, end: number | null, kind: AgendaItem["kind"] = "event", allDay = false): AgendaItem => ({
    kind, id, title: id, day: "2026-11-12", start, end, allDay, color: "#fff", done: false, span: "single", time: "",
  });

  it("lo que no se solapa ocupa todo el ancho y lo que sí se reparte en carriles", () => {
    const p = layoutDay([item("a", 540, 600), item("b", 570, 660), item("c", 570, 630), item("d", 720, 780)]);
    const by = Object.fromEntries(p.map((x) => [x.item.id, x]));
    expect([by.a.lanes, by.b.lanes, by.c.lanes]).toEqual([3, 3, 3]);
    expect(new Set([by.a.lane, by.b.lane, by.c.lane]).size).toBe(3);
    expect(by.d).toMatchObject({ lane: 0, lanes: 1 });
  });

  it("un carril libre se reutiliza dentro del mismo grupo", () => {
    const p = layoutDay([item("a", 540, 570), item("b", 540, 660), item("c", 580, 620)]);
    const by = Object.fromEntries(p.map((x) => [x.item.id, x]));
    expect(by.c.lane).toBe(by.a.lane); // a termina a las 9:30 y c empieza a las 9:40
    expect(by.a.lanes).toBe(2);
  });

  it("da una altura mínima de media hora y no pasa de medianoche; ignora lo de todo el día", () => {
    const p = layoutDay([item("a", 600, null, "task"), item("b", 1400, 1500), item("c", 0, null, "event", true)]);
    expect(p).toHaveLength(2);
    expect(p[0]).toMatchObject({ top: 600, len: 30 });
    expect(p[1].top + p[1].len).toBe(1440);
  });

  it("un clic o suelta se convierte en hora, al cuarto de hora, y sin alto no hay hora", () => {
    expect(minutesAtY(0, 1440)).toBe(0);
    expect(minutesAtY(600, 1440)).toBe(600);
    expect(minutesAtY(607, 1440)).toBe(600);
    expect(minutesAtY(608, 1440)).toBe(615);
    expect(minutesAtY(5000, 1440)).toBe(1425);
    expect(minutesAtY(10, 0)).toBeNull();
  });
});

describe("el rango y la navegación", () => {
  it("mes: 42 días y su título; semana: 7 con su número ISO; día: 1", () => {
    const m = rangeFor("month", "2026-11-13");
    expect(m.days).toHaveLength(42);
    expect(m.title).toBe("noviembre 2026");
    expect(m.subtitle).toBe("1 nov 2026 – 30 nov 2026");
    const w = rangeFor("week", "2026-11-13");
    expect(w.days.map((d) => d.getDate())).toEqual([9, 10, 11, 12, 13, 14, 15]);
    expect(w.title).toBe("9 – 15 nov 2026");
    expect(w.subtitle).toMatch(/^Semana 46 /);
    expect(rangeFor("week", "2026-11-30").title).toBe("30 nov – 6 dic 2026");
    const d = rangeFor("day", "2026-11-13");
    expect(d.days).toHaveLength(1);
    expect(d.title).toBe("viernes 13 nov 2026");
  });

  it("el número de semana ISO", () => {
    expect(isoWeek(D(2026, 1, 1))).toBe(1);
    expect(isoWeek(D(2026, 12, 31))).toBe(53);
    expect(isoWeek(D(2026, 11, 13))).toBe(46);
  });

  it("avanza un mes (sin desbordar), una semana o un día", () => {
    expect(stepSelected("month", "2026-01-31", 1)).toBe("2026-02-28");
    expect(stepSelected("month", "2026-01-15", -1)).toBe("2025-12-15");
    expect(stepSelected("week", "2026-11-13", 1)).toBe("2026-11-20");
    expect(stepSelected("day", "2026-12-31", 1)).toBe("2027-01-01");
    expect(stepSelected("day", "2026-03-01", -1)).toBe("2026-02-28");
  });
});

describe("avisos del calendario", () => {
  const data = (over: Partial<AgendaData>): AgendaData => ({ ...none, ...over });

  it("avisa de un recordatorio cuando llega su hora y no lo repite", () => {
    const r = newReminder("Llamar", D(2026, 11, 12, 10), { id: "r" });
    const fired = new Set<string>();
    expect(pendingAlerts(data({ reminders: [r] }), D(2026, 11, 12, 9, 59), fired)).toEqual([]);
    const now = pendingAlerts(data({ reminders: [r] }), D(2026, 11, 12, 10, 1), fired);
    expect(now).toMatchObject([{ title: "Recordatorio", body: "Llamar" }]);
    fired.add(now[0].key);
    expect(pendingAlerts(data({ reminders: [r] }), D(2026, 11, 12, 10, 2), fired)).toEqual([]);
  });

  it("no avisa de lo viejo (más de 15 minutos), de lo hecho ni de lo borrado", () => {
    const r = newReminder("Viejo", D(2026, 11, 12, 10), { id: "r" });
    const noon = D(2026, 11, 12, 12);
    expect(pendingAlerts(data({ reminders: [r] }), noon, new Set())).toEqual([]);
    expect(pendingAlerts(data({ reminders: [{ ...r, done: true }] }), D(2026, 11, 12, 10, 1), new Set())).toEqual([]);
    expect(pendingAlerts(data({ reminders: [softDeleteReminder(r)] }), D(2026, 11, 12, 10, 1), new Set())).toEqual([]);
  });

  it("avisa de un hábito a su hora si hoy toca y aún no está hecho", () => {
    const h = newHabit("Beber agua", { id: "h", now: D(2026, 11, 1), remindAt: 9 * 60 });
    const at9 = D(2026, 11, 12, 9, 5);
    expect(pendingAlerts(data({ habits: [h] }), at9, new Set())).toMatchObject([{ title: "Hábito", body: "Beber agua" }]);
    const done: HabitCheck = { habit_id: "h", day: "2026-11-12", done: true, updated_at: "2026-11-12T08:00:00Z" };
    expect(pendingAlerts(data({ habits: [h], checks: [done] }), at9, new Set())).toEqual([]);
    expect(pendingAlerts(data({ habits: [h] }), D(2026, 11, 12, 8, 59), new Set())).toEqual([]);
    expect(pendingAlerts(data({ habits: [{ ...h, remind_at: null }] }), at9, new Set())).toEqual([]);
  });
});

describe("preferencia de vista del calendario", () => {
  it("por defecto es la semanal y solo acepta día, semana o mes", () => {
    expect(DEFAULT_PREFS.calendarView).toBe("week");
    const mem = (v: unknown) => ({ getItem: () => JSON.stringify({ calendarView: v }), setItem: () => {} });
    expect(loadPrefs(mem("month")).calendarView).toBe("month");
    expect(loadPrefs(mem("day")).calendarView).toBe("day");
    expect(loadPrefs(mem("año")).calendarView).toBe("week");
  });
});
