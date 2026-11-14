import { describe, expect, it } from "vitest";
import {
  entriesInMonth,
  financeStatement,
  formatMoney,
  monthOf,
  newCategory,
  newEntry,
  parseAmount,
  shiftMonthKey,
  softDeleteEntry,
  summarize,
  updateEntry,
  applyEntries,
} from "../src/data/finance";
import { monthName } from "../src/sections/finance";

const T0 = new Date(2026, 10, 13, 10, 0);
const sueldo = newCategory("Sueldo", "income", "#c8f73a", T0, "c-sueldo");
const comida = newCategory("Comida", "expense", "#ff5a1f", T0, "c-comida");
const casa = newCategory("Casa", "expense", "#ff4fd8", T0, "c-casa");
const e = (id: string, kind: "income" | "expense", cents: number, cat: string | null, day: string) => newEntry({ kind, amount_cents: cents, category_id: cat, occurred_on: day }, T0, id);

describe("finanzas: importes", () => {
  it("lee lo que se escribe como centavos", () => {
    expect(parseAmount("250")).toBe(25000);
    expect(parseAmount("1,250.50")).toBe(125050);
    expect(parseAmount("1.250,50")).toBe(125050);
    expect(parseAmount("120,5")).toBe(12050);
    expect(parseAmount("$ 80")).toBe(8000);
    expect(parseAmount("0.99")).toBe(99);
    expect(parseAmount("1,250")).toBe(125000); // coma de miles: no es decimal
    expect(parseAmount("12.345")).toBe(1234500);
  });

  it("rechaza lo que no es un importe positivo", () => {
    for (const bad of ["", "abc", "0", "0.00", "-5", ",", "."]) expect(parseAmount(bad)).toBeNull();
  });

  it("da formato de moneda", () => {
    expect(formatMoney(125050, "USD")).toMatch(/1,250\.50/);
    expect(formatMoney(100, "XXXX")).toBe("1.00 XXXX"); // una moneda inválida no rompe nada
  });
});

describe("finanzas: meses y resumen", () => {
  it("cambia de mes por clave", () => {
    expect(monthOf("2026-11-13")).toBe("2026-11");
    expect(shiftMonthKey("2026-11", 1)).toBe("2026-12");
    expect(shiftMonthKey("2026-12", 1)).toBe("2027-01");
    expect(shiftMonthKey("2026-01", -1)).toBe("2025-12");
    expect(monthName("2026-11")).toBe("noviembre 2026");
  });

  it("filtra por mes, sin los borrados, de lo más nuevo a lo más viejo", () => {
    const all = [e("a", "expense", 100, null, "2026-11-02"), e("b", "expense", 100, null, "2026-11-20"), e("c", "expense", 100, null, "2026-10-30"), softDeleteEntry(e("d", "income", 100, null, "2026-11-05"), T0)];
    expect(entriesInMonth(all, "2026-11").map((x) => x.id)).toEqual(["b", "a"]);
  });

  it("suma ingresos, gastos y balance, y reparte por categoría dentro de su tipo", () => {
    const entries = [e("1", "income", 100000, sueldo.id, "2026-11-01"), e("2", "expense", 30000, comida.id, "2026-11-02"), e("3", "expense", 10000, comida.id, "2026-11-03"), e("4", "expense", 60000, casa.id, "2026-11-04"), e("5", "expense", 5000, null, "2026-11-05")];
    const s = summarize(entries, [sueldo, comida, casa]);
    expect(s).toMatchObject({ income: 100000, expense: 105000, balance: -5000, count: 5 });
    // primero los gastos (de mayor a menor), luego los ingresos
    expect(s.byCategory.map((c) => [c.name, c.total])).toEqual([["Casa", 60000], ["Comida", 40000], ["Sin categoría", 5000], ["Sueldo", 100000]]);
    expect(s.byCategory[0].share).toBeCloseTo(60000 / 105000);
    expect(s.byCategory[3].share).toBe(1);
  });

  it("sin movimientos todo es cero", () => {
    expect(summarize([], [])).toEqual({ income: 0, expense: 0, balance: 0, count: 0, byCategory: [] });
  });
});

describe("finanzas: edición", () => {
  it("un movimiento nuevo lleva la fecha de hoy, su moneda y un id del dispositivo", () => {
    const n = newEntry({ kind: "expense", amount_cents: 500, description: "  Café " }, T0, "x");
    expect(n).toMatchObject({ id: "x", kind: "expense", amount_cents: 500, description: "Café", occurred_on: "2026-11-13", currency: "MXN", category_id: null, deleted_at: null });
  });

  it("editar y borrar suben updated_at aunque el reloj vaya atrasado", () => {
    const n = newEntry({ kind: "expense", amount_cents: 500 }, new Date(2030, 0, 1), "x");
    const edited = updateEntry(n, { amount_cents: 700 }, new Date(2020, 0, 1));
    expect(edited.amount_cents).toBe(700);
    expect(edited.updated_at > n.updated_at).toBe(true);
    const gone = softDeleteEntry(edited, new Date(2020, 0, 1));
    expect(gone.deleted_at).toBe(gone.updated_at);
    expect(gone.updated_at > edited.updated_at).toBe(true);
    expect(applyEntries([n], [gone])).toEqual([]);
  });

  it("el enunciado resume el mes", () => {
    expect(financeStatement([], false)).toBe("Cargando tus finanzas.");
    expect(financeStatement([], true, undefined, T0)).toMatch(/^Este mes aún no hay movimientos/);
    const text = financeStatement([e("1", "income", 100000, null, "2026-11-01"), e("2", "expense", 25000, null, "2026-11-02")], true, undefined, T0, "USD");
    expect(text).toMatch(/Este mes: .*1,000\.00.* de ingresos, .*250\.00.* de gastos; balance .*750\.00/);
    expect(financeStatement([], true, "Sin conexión")).toBe("Sin conexión");
  });
});
