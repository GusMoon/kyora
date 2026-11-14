import { h } from "../ui/dom";
import { icon } from "../ui/icons";
import { explainError } from "../supabase";
import {
  DEFAULT_CATEGORIES,
  KIND_NAME,
  applyCategories,
  applyEntries,
  entriesInMonth,
  financeStatement,
  formatMoney,
  monthOf,
  newCategory,
  newEntry,
  parseAmount,
  saveCategories,
  saveEntries,
  shiftMonthKey,
  softDeleteEntry,
  summarize,
  todayKey,
  updateEntry,
  type FinanceCategory,
  type FinanceEntry,
  type FinanceKind,
} from "../data/finance";
import { MONTHS } from "../data/events";
import { stamp } from "../data/tasks";
import type { Ctx, Section } from "./context";

export { financeStatement };

const COLORS: Record<string, string> = { "#c8f73a": "Lima", "#ff5a1f": "Naranja", "#35d4ff": "Cian", "#ff4fd8": "Magenta", "#ffd23f": "Amarillo", "#c9cebc": "Salvia", "#9aa1ac": "Gris" };

/** «noviembre 2026» de «2026-11». */
export const monthName = (month: string): string => {
  const [y, m] = month.split("-").map(Number);
  return `${MONTHS[m - 1]} ${y}`;
};

const dayFmt = new Intl.DateTimeFormat("es", { day: "numeric", month: "short" });
const shortDay = (key: string): string => {
  const [y, m, d] = key.split("-").map(Number);
  return dayFmt.format(new Date(y, m - 1, d));
};

export const financeSection: Section = (ctx: Ctx) => {
  const { store, shell, client, prefs } = ctx;
  const cleanups: (() => void)[] = [];
  let month = monthOf(todayKey());
  let filter: "all" | FinanceKind = "all";
  let search = "";
  let editingId: string | null = null;
  let formKind: FinanceKind = "expense";
  const currency = () => prefs.value.currency;

  const notice = h("p", { class: "notice", role: "status" });
  const summaryEl = h("div", { class: "fin-summary" });
  const breakdown = h("div", { class: "fin-breakdown" });
  const formBox = h("div", { class: "fin-form-box" });
  const listEl = h("div", { class: "fin-list" });
  const catBox = h("details", { class: "fin-cats" });
  const nav = h("div", { class: "cal-nav fin-nav" });

  async function commitEntries(changed: FinanceEntry[]) {
    store.financeEntries = applyEntries(store.financeEntries, changed);
    store.emit("finance");
    try {
      await saveEntries(client, changed);
      notice.textContent = "";
    } catch (err) {
      notice.textContent = `No se guardó el movimiento. ${explainError(err)}`;
      await ctx.reload("finance");
    }
  }

  async function commitCategories(changed: FinanceCategory[]) {
    store.financeCategories = applyCategories(store.financeCategories, changed);
    store.emit("finance");
    try {
      await saveCategories(client, changed);
      notice.textContent = "";
    } catch (err) {
      notice.textContent = `No se guardó la categoría. ${explainError(err)}`;
      await ctx.reload("finance");
    }
  }

  const catName = (id: string | null) => store.financeCategories.find((c) => c.id === id);

  // ----- mes y resumen
  function renderNav() {
    nav.replaceChildren(
      h("button", { class: "btn-step", type: "button", "aria-label": "Mes anterior", onClick: () => { month = shiftMonthKey(month, -1); render(); } }, icon("chevronLeft", "icon")),
      h("h2", { class: "cal-title", "aria-live": "polite" }, monthName(month)),
      h("button", { class: "btn-step", type: "button", "aria-label": "Mes siguiente", onClick: () => { month = shiftMonthKey(month, 1); render(); } }, icon("chevronRight", "icon")),
      h("button", { class: "btn-edge", type: "button", onClick: () => { month = monthOf(todayKey()); render(); } }, "Este mes"),
    );
  }

  function monthEntries(): { entries: FinanceEntry[]; other: number } {
    const all = entriesInMonth(store.financeEntries, month);
    const entries = all.filter((e) => e.currency === currency());
    return { entries, other: all.length - entries.length };
  }

  function renderSummary() {
    const { entries, other } = monthEntries();
    const s = summarize(entries, store.financeCategories);
    const card = (label: string, value: number, cls: string) => h("div", { class: `fin-card ${cls}` }, h("span", { class: "label" }, label), h("strong", { class: "readout" }, formatMoney(value, currency())));
    summaryEl.replaceChildren(
      card("Ingresos", s.income, "is-income"),
      card("Gastos", s.expense, "is-expense"),
      card("Balance", s.balance, s.balance < 0 ? "is-negative" : "is-balance"),
      ...(other ? [h("p", { class: "cfg-note" }, `${other} ${other === 1 ? "movimiento está" : "movimientos están"} en otra moneda y no se cuenta${other === 1 ? "" : "n"} aquí (la moneda se cambia en Configuración).`)] : []),
    );
    const rows = s.byCategory;
    breakdown.replaceChildren(
      h("h3", { class: "label" }, "Por categoría"),
      rows.length
        ? h(
            "ul",
            { class: "fin-bars" },
            rows.map((r) =>
              h("li", { class: `fin-bar is-${r.kind}` },
                h("span", { class: "fin-bar-name" }, h("span", { class: "swatch", style: `background:${r.color}`, "aria-hidden": "true" }), `${r.name} `, h("span", { class: "label" }, r.kind === "income" ? "ingreso" : "gasto")),
                h("span", { class: "fin-track", "aria-hidden": "true" }, h("span", { class: "fin-fill", style: `inline-size:${Math.max(2, Math.round(r.share * 100))}%;background:${r.color}` })),
                h("span", { class: "readout fin-amount" }, `${formatMoney(r.total, currency())} · ${Math.round(r.share * 100)}%`),
              ),
            ),
          )
        : h("p", { class: "cfg-help" }, "Sin movimientos este mes."),
    );
  }

  // ----- alta y edición
  let amountInput: HTMLInputElement | null = null;

  function renderForm() {
    const editing = editingId ? store.financeEntries.find((e) => e.id === editingId) ?? null : null;
    if (editing) formKind = editing.kind;
    const kind = h("select", { "aria-label": "Tipo" }, (["expense", "income"] as FinanceKind[]).map((k) => h("option", { value: k, selected: k === formKind }, KIND_NAME[k])));
    kind.value = formKind;
    const amount = h("input", { type: "text", inputmode: "decimal", placeholder: "Importe", "aria-label": "Importe", autocomplete: "off", value: editing ? (editing.amount_cents / 100).toFixed(2) : "" });
    amount.value = editing ? (editing.amount_cents / 100).toFixed(2) : "";
    amountInput = amount;
    const category = h("select", { "aria-label": "Categoría" });
    const fillCategories = () => {
      const k = kind.value as FinanceKind;
      const list = store.financeCategories.filter((c) => c.kind === k).sort((a, b) => a.name.localeCompare(b.name, "es"));
      category.replaceChildren(h("option", { value: "" }, "Sin categoría"), ...list.map((c) => h("option", { value: c.id }, c.name)));
      category.value = editing && editing.kind === k && editing.category_id && list.some((c) => c.id === editing.category_id) ? editing.category_id : "";
    };
    fillCategories();
    kind.addEventListener("change", () => {
      formKind = kind.value as FinanceKind;
      fillCategories();
    });
    const date = h("input", { type: "date", "aria-label": "Fecha", value: editing?.occurred_on ?? `${month}-${month === monthOf(todayKey()) ? todayKey().slice(8) : "01"}` });
    date.value = editing?.occurred_on ?? `${month}-${month === monthOf(todayKey()) ? todayKey().slice(8) : "01"}`;
    const desc = h("input", { type: "text", maxlength: 200, placeholder: "Descripción (opcional)", "aria-label": "Descripción", autocomplete: "off", value: editing?.description ?? "" });
    desc.value = editing?.description ?? "";
    const error = h("p", { class: "form-error", role: "alert" });
    const form = h(
      "form",
      { class: "fin-form" },
      h("h3", { class: "label" }, editing ? "Editar movimiento" : "Nuevo movimiento"),
      h("div", { class: "fin-form-row" }, kind, amount),
      category,
      h("div", { class: "fin-form-row" }, date, desc),
      error,
      h("div", { class: "cal-form-actions" },
        h("button", { class: "btn-solid", type: "submit" }, editing ? "Guardar" : "Añadir"),
        editing ? h("button", { class: "btn-quiet", type: "button", onClick: () => { editingId = null; renderForm(); } }, "Cancelar") : null,
      ),
    );
    form.addEventListener("submit", (e) => {
      e.preventDefault();
      const cents = parseAmount(amount.value);
      if (cents === null) {
        error.textContent = "Escribe un importe mayor que cero, por ejemplo 250 o 1,250.50.";
        return;
      }
      if (!date.value) {
        error.textContent = "Elige la fecha.";
        return;
      }
      error.textContent = "";
      const k = kind.value as FinanceKind;
      const cat = category.value || null;
      if (editing) void commitEntries([updateEntry(editing, { kind: k, amount_cents: cents, category_id: cat, description: desc.value.trim(), occurred_on: date.value })]);
      else void commitEntries([newEntry({ kind: k, amount_cents: cents, category_id: cat, description: desc.value, occurred_on: date.value, currency: currency() })]);
      if (date.value.slice(0, 7) !== month) month = date.value.slice(0, 7);
      editingId = null;
      render();
      if (!editing) amountInput?.focus();
    });
    formBox.replaceChildren(form);
  }

  // ----- la lista del mes
  function renderList() {
    const { entries } = monthEntries();
    const searchBox = h("input", { type: "text", placeholder: "Buscar", "aria-label": "Buscar en los movimientos", value: search, autocomplete: "off" });
    searchBox.value = search;
    searchBox.addEventListener("input", () => {
      search = searchBox.value;
      renderListBody();
      searchBox.focus();
    });
    const tab = (id: "all" | FinanceKind, label: string) => h("button", { class: "tab", type: "button", "aria-pressed": String(filter === id), "aria-selected": String(filter === id), onClick: () => { filter = id; renderList(); } }, label);
    const body = h("div", {});
    const renderListBody = () => {
      const qq = search.trim().toLowerCase();
      const rows = entries.filter((e) => (filter === "all" || e.kind === filter) && (!qq || e.description.toLowerCase().includes(qq) || (catName(e.category_id)?.name ?? "").toLowerCase().includes(qq)));
      body.replaceChildren(
        rows.length
          ? h(
              "ul",
              { class: "fin-rows" },
              rows.map((e) => {
                const cat = catName(e.category_id);
                return h("li", { class: `fin-row is-${e.kind}` },
                  h("time", { class: "readout fin-date", datetime: e.occurred_on }, shortDay(e.occurred_on)),
                  h("span", { class: "fin-desc" }, e.description || h("span", { class: "label" }, KIND_NAME[e.kind])),
                  h("span", { class: "fin-cat" }, cat ? h("span", { class: "swatch", style: `background:${cat.color}`, "aria-hidden": "true" }) : null, cat?.name ?? "Sin categoría"),
                  h("strong", { class: "readout fin-money" }, `${e.kind === "income" ? "+" : "−"}${formatMoney(e.amount_cents, e.currency)}`),
                  h("span", { class: "fin-actions" },
                    h("button", { class: "btn-quiet", type: "button", "aria-label": `Editar ${e.description || KIND_NAME[e.kind]}`, onClick: () => { editingId = e.id; renderForm(); shell.body.scrollTop = 0; amountInput?.focus(); } }, "Editar"),
                    h("button", { class: "btn-quiet", type: "button", "aria-label": `Borrar ${e.description || KIND_NAME[e.kind]}`, onClick: () => { if (confirm("¿Borrar este movimiento?")) void commitEntries([softDeleteEntry(e)]); } }, "Borrar"),
                  ),
                );
              }),
            )
          : h("p", { class: "cfg-help" }, entries.length ? "Nada coincide con el filtro." : "Este mes aún no hay movimientos."),
      );
    };
    renderListBody();
    listEl.replaceChildren(
      h("div", { class: "fin-filter" }, h("div", { class: "tabs", role: "group", "aria-label": "Mostrar" }, tab("all", "Todos"), tab("income", "Ingresos"), tab("expense", "Gastos")), searchBox),
      body,
    );
  }

  // ----- categorías
  function renderCategories() {
    const list = [...store.financeCategories].sort((a, b) => (a.kind !== b.kind ? (a.kind === "income" ? -1 : 1) : a.name.localeCompare(b.name, "es")));
    const name = h("input", { type: "text", maxlength: 60, placeholder: "Nueva categoría", "aria-label": "Nombre de la categoría", autocomplete: "off" });
    const kind = h("select", { "aria-label": "Tipo de la categoría" }, h("option", { value: "expense" }, "Gasto"), h("option", { value: "income" }, "Ingreso"));
    const color = h("select", { "aria-label": "Color de la categoría" }, Object.entries(COLORS).map(([v, n]) => h("option", { value: v }, n)));
    const addForm = h("form", { class: "sub-form" }, name, kind, color, h("button", { class: "btn-quiet", type: "submit" }, "Añadir"));
    addForm.addEventListener("submit", (e) => {
      e.preventDefault();
      const n = name.value.trim();
      if (!n) return;
      if (store.financeCategories.some((c) => c.kind === kind.value && c.name.toLowerCase() === n.toLowerCase())) {
        notice.textContent = `Ya existe la categoría «${n}».`;
        return;
      }
      name.value = "";
      void commitCategories([newCategory(n, kind.value as FinanceKind, color.value)]);
    });
    catBox.replaceChildren(
      h("summary", { class: "label" }, `Categorías (${list.length})`),
      list.length
        ? h(
            "ul",
            { class: "fin-cat-list" },
            list.map((c) =>
              h("li", {}, h("span", { class: "swatch", style: `background:${c.color}`, "aria-hidden": "true" }), h("span", {}, c.name), h("span", { class: "label" }, c.kind === "income" ? "ingreso" : "gasto"),
                h("button", { class: "btn-quiet", type: "button", "aria-label": `Borrar la categoría ${c.name}`, onClick: () => { if (confirm(`¿Borrar la categoría «${c.name}»? Sus movimientos quedan «sin categoría».`)) void commitCategories([{ ...c, deleted_at: stamp(c.updated_at), updated_at: stamp(c.updated_at) }]); } }, "Borrar")),
            ),
          )
        : h("div", { class: "fin-seed" }, h("p", { class: "cfg-help" }, "Aún no hay categorías."), h("button", { class: "btn-edge", type: "button", onClick: () => void commitCategories(DEFAULT_CATEGORIES.map((c) => newCategory(c.name, c.kind, c.color))) }, "Crear las básicas")),
      addForm,
    );
  }

  function render() {
    shell.setStatement(financeStatement(store.financeEntries, store.loaded.finance, store.errors.finance, new Date(), currency()));
    renderNav();
    renderSummary();
    renderForm();
    renderList();
    const open = catBox.open;
    renderCategories();
    catBox.open = open;
  }

  shell.body.append(notice, nav, summaryEl, h("div", { class: "fin-cols" }, h("div", { class: "fin-col" }, formBox, breakdown), h("div", { class: "fin-col" }, listEl)), catBox);
  const handleIntent = () => {
    if (store.take("new-entry")) {
      editingId = null;
      month = monthOf(todayKey());
      render();
      amountInput?.focus();
    }
  };
  render();
  handleIntent();
  cleanups.push(store.onIntent(handleIntent));
  cleanups.push(
    store.on((area) => {
      if (area !== "finance") return;
      shell.setStatement(financeStatement(store.financeEntries, store.loaded.finance, store.errors.finance, new Date(), currency()));
      renderSummary();
      renderList();
      const open = catBox.open;
      renderCategories();
      catBox.open = open;
      if (!formBox.contains(document.activeElement)) renderForm();
    }),
  );
  cleanups.push(prefs.on(render));
  return () => {
    for (const fn of cleanups) fn();
  };
};
