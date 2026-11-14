import type { SupabaseClient } from "@supabase/supabase-js";
import { stamp } from "./tasks";

/** Ingresos y gastos (tablas `finance_categories` y `finance_entries` de Server/supabase/schema.sql §14).
 * El importe se guarda en centavos (entero) para no arrastrar errores de redondeo. */

export type FinanceKind = "income" | "expense";

export interface FinanceCategory {
  id: string;
  name: string;
  kind: FinanceKind;
  color: string;
  updated_at: string;
  deleted_at: string | null;
}

export interface FinanceEntry {
  id: string;
  kind: FinanceKind;
  amount_cents: number;
  currency: string;
  category_id: string | null;
  description: string;
  occurred_on: string; // «aaaa-mm-dd»
  created_at: string;
  updated_at: string;
  deleted_at: string | null;
}

export const KIND_NAME: Record<FinanceKind, string> = { income: "Ingreso", expense: "Gasto" };

export const DEFAULT_CATEGORIES: { name: string; kind: FinanceKind; color: string }[] = [
  { name: "Sueldo", kind: "income", color: "#c8f73a" },
  { name: "Otros ingresos", kind: "income", color: "#35d4ff" },
  { name: "Comida", kind: "expense", color: "#ff5a1f" },
  { name: "Transporte", kind: "expense", color: "#ffd23f" },
  { name: "Casa", kind: "expense", color: "#ff4fd8" },
  { name: "Servicios", kind: "expense", color: "#35d4ff" },
  { name: "Salud", kind: "expense", color: "#c9cebc" },
  { name: "Ocio", kind: "expense", color: "#c8f73a" },
  { name: "Otros gastos", kind: "expense", color: "#9aa1ac" },
];

/** «1,234.50», «1.234,50», «120,5», «$ 80», «80» → centavos. null si no es un importe válido (o es 0 o negativo). */
export function parseAmount(text: string): number | null {
  if (/^\s*[-−–]/.test(text)) return null; // un importe negativo no vale: el tipo (ingreso o gasto) ya dice si suma o resta
  let t = text.replace(/[^\d.,]/g, "");
  if (!t || !/\d/.test(t)) return null;
  const lastDot = t.lastIndexOf(".");
  const lastComma = t.lastIndexOf(",");
  const sep = Math.max(lastDot, lastComma);
  let int = t;
  let frac = "";
  if (sep >= 0) {
    const after = t.length - sep - 1;
    const other = lastDot > lastComma ? "," : ".";
    const onlyOne = t.split(t[sep]).length === 2; // un solo separador de ese tipo
    // decimal si es el único de su tipo y detrás hay 1 o 2 cifras, o si el otro tipo ya aparece antes (1.234,50)
    if (after > 0 && after <= 2 && (onlyOne || t.includes(other))) {
      int = t.slice(0, sep);
      frac = t.slice(sep + 1);
    }
  }
  t = int.replace(/[.,]/g, "");
  if (!t && !frac) return null;
  const cents = Number(t || "0") * 100 + Number((frac + "00").slice(0, 2));
  return Number.isSafeInteger(cents) && cents > 0 ? cents : null;
}

/** 123450 → «$1,234.50» (o la moneda que toque), con el formato de España/Latinoamérica del navegador. */
export function formatMoney(cents: number, currency = "MXN"): string {
  try {
    return new Intl.NumberFormat("es-MX", { style: "currency", currency }).format(cents / 100);
  } catch {
    return `${(cents / 100).toFixed(2)} ${currency}`;
  }
}

/** «2026-11» del día «2026-11-13». */
export const monthOf = (day: string) => day.slice(0, 7);

export function todayKey(now: Date = new Date()): string {
  return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}-${String(now.getDate()).padStart(2, "0")}`;
}

export function shiftMonthKey(month: string, delta: number): string {
  const [y, m] = month.split("-").map(Number);
  const t = y * 12 + (m - 1) + delta;
  return `${Math.floor(t / 12)}-${String((t % 12) + 1).padStart(2, "0")}`;
}

export function entriesInMonth(entries: FinanceEntry[], month: string): FinanceEntry[] {
  return entries
    .filter((e) => !e.deleted_at && monthOf(e.occurred_on) === month)
    .sort((a, b) => (a.occurred_on !== b.occurred_on ? b.occurred_on.localeCompare(a.occurred_on) : b.created_at.localeCompare(a.created_at)));
}

export interface CategoryTotal {
  categoryId: string | null;
  name: string;
  color: string;
  kind: FinanceKind;
  total: number;
  share: number; // 0 a 1 dentro de su tipo (ingresos o gastos)
}

export interface MonthSummary {
  income: number;
  expense: number;
  balance: number;
  count: number;
  byCategory: CategoryTotal[];
}

/** Ingresos, gastos, balance y el desglose por categoría de los movimientos que se le pasen (ya filtrados por mes). */
export function summarize(entries: FinanceEntry[], categories: FinanceCategory[]): MonthSummary {
  const live = entries.filter((e) => !e.deleted_at);
  const names = new Map(categories.map((c) => [c.id, c]));
  let income = 0;
  let expense = 0;
  const totals = new Map<string, CategoryTotal>();
  for (const e of live) {
    if (e.kind === "income") income += e.amount_cents;
    else expense += e.amount_cents;
    const cat = e.category_id ? names.get(e.category_id) : undefined;
    const key = `${e.kind}:${e.category_id ?? ""}`;
    const row = totals.get(key) ?? { categoryId: cat ? cat.id : null, name: cat?.name ?? "Sin categoría", color: cat?.color ?? "#9aa1ac", kind: e.kind, total: 0, share: 0 };
    row.total += e.amount_cents;
    totals.set(key, row);
  }
  const byCategory = [...totals.values()].sort((a, b) => (a.kind !== b.kind ? (a.kind === "expense" ? -1 : 1) : b.total - a.total));
  for (const row of byCategory) row.share = (row.kind === "income" ? income : expense) ? row.total / (row.kind === "income" ? income : expense) : 0;
  return { income, expense, balance: income - expense, count: live.length, byCategory };
}

export function newEntry(
  input: { kind: FinanceKind; amount_cents: number; category_id?: string | null; description?: string; occurred_on?: string; currency?: string },
  now: Date = new Date(),
  id: string = crypto.randomUUID(),
): FinanceEntry {
  const at = now.toISOString();
  return {
    id,
    kind: input.kind,
    amount_cents: input.amount_cents,
    currency: input.currency ?? "MXN",
    category_id: input.category_id ?? null,
    description: (input.description ?? "").trim(),
    occurred_on: input.occurred_on ?? todayKey(now),
    created_at: at,
    updated_at: at,
    deleted_at: null,
  };
}

export type EntryPatch = Partial<Pick<FinanceEntry, "kind" | "amount_cents" | "category_id" | "description" | "occurred_on">>;

export function updateEntry(e: FinanceEntry, patch: EntryPatch, now: Date = new Date()): FinanceEntry {
  return { ...e, ...patch, updated_at: stamp(e.updated_at, now) };
}

export function softDeleteEntry(e: FinanceEntry, now: Date = new Date()): FinanceEntry {
  const at = stamp(e.updated_at, now);
  return { ...e, deleted_at: at, updated_at: at };
}

export function newCategory(name: string, kind: FinanceKind, color: string, now: Date = new Date(), id: string = crypto.randomUUID()): FinanceCategory {
  return { id, name: name.trim(), kind, color, updated_at: now.toISOString(), deleted_at: null };
}

export function financeStatement(entries: FinanceEntry[], loaded: boolean, error?: string, now: Date = new Date(), currency = "MXN"): string {
  if (error) return error;
  if (!loaded) return "Cargando tus finanzas.";
  const month = entriesInMonth(entries, monthOf(todayKey(now)));
  if (!month.length) return "Este mes aún no hay movimientos. Registra el primero abajo.";
  const s = summarize(month, []);
  return `Este mes: ${formatMoney(s.income, currency)} de ingresos, ${formatMoney(s.expense, currency)} de gastos; balance ${formatMoney(s.balance, currency)}.`;
}

export function applyEntries(entries: FinanceEntry[], changed: FinanceEntry[]): FinanceEntry[] {
  const byId = new Map(entries.map((e) => [e.id, e]));
  for (const e of changed) byId.set(e.id, e);
  return [...byId.values()].filter((e) => !e.deleted_at);
}

export function applyCategories(categories: FinanceCategory[], changed: FinanceCategory[]): FinanceCategory[] {
  const byId = new Map(categories.map((c) => [c.id, c]));
  for (const c of changed) byId.set(c.id, c);
  return [...byId.values()].filter((c) => !c.deleted_at);
}

const ENTRY_COLUMNS = "id,kind,amount_cents,currency,category_id,description,occurred_on,created_at,updated_at,deleted_at";

export async function loadFinance(client: SupabaseClient): Promise<{ entries: FinanceEntry[]; categories: FinanceCategory[] }> {
  const [entries, categories] = await Promise.all([
    client.from("finance_entries").select(ENTRY_COLUMNS).is("deleted_at", null).order("occurred_on", { ascending: false }).limit(5000),
    client.from("finance_categories").select("id,name,kind,color,updated_at,deleted_at").is("deleted_at", null).limit(500),
  ]);
  if (entries.error) throw entries.error;
  if (categories.error) throw categories.error;
  return { entries: (entries.data ?? []) as unknown as FinanceEntry[], categories: (categories.data ?? []) as unknown as FinanceCategory[] };
}

export async function saveEntries(client: SupabaseClient, rows: FinanceEntry[]): Promise<void> {
  if (!rows.length) return;
  const { error } = await client.from("finance_entries").upsert(rows, { onConflict: "id" });
  if (error) throw error;
}

export async function saveCategories(client: SupabaseClient, rows: FinanceCategory[]): Promise<void> {
  if (!rows.length) return;
  const { error } = await client.from("finance_categories").upsert(rows, { onConflict: "id" });
  if (error) throw error;
}
