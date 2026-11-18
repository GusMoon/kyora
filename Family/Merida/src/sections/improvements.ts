import { h, shortWhen } from "../ui/dom";
import { icon } from "../ui/icons";
import { explainError } from "../supabase";
import {
  MAX_SECTION,
  MAX_TEXT,
  buildImprovementsPrompt,
  finishImprovement,
  functionLines,
  improvementsStatement,
  newImprovement,
  saveImprovement,
  sortImprovements,
  validateImprovement,
  withImprovement,
  withoutImprovement,
  type Improvement,
} from "../data/improvements";
import type { Ctx, Section } from "./context";

export { improvementsStatement };

/** **Mejoras**: lo que se quiere agregar o mejorar en el proyecto (Merida y Kyra comparten la lista, en Supabase). Se escribe la sección, las
 * funciones que se quieren (una por línea) y una descripción; queda anotada. Cuando la función está terminada se pulsa «Hecho»: se borra de la
 * base de datos y deja de verse. */
export const improvementsSection: Section = (ctx: Ctx) => {
  const { store, shell, client } = ctx;
  const cleanups: (() => void)[] = [];
  const notice = h("p", { class: "notice", role: "status" });
  const formBox = h("div", { class: "imp-form-box" });
  const listEl = h("div", { class: "imp-list" });
  let sectionInput: HTMLInputElement | null = null;
  /** Las mejoras escogidas para el prompt (se pierde al salir de la sección; las que ya no existen se descartan al pintar). */
  const picked = new Set<string>();
  let toolbar: { all: HTMLInputElement; count: HTMLElement; copy: HTMLButtonElement } | null = null;

  /** Las escogidas, en el orden en que se ven en la lista. */
  const pickedItems = () => sortImprovements(store.improvements).filter((i) => picked.has(i.id));

  function updateToolbar() {
    if (!toolbar) return;
    const total = store.improvements.length;
    toolbar.count.textContent = picked.size ? `${picked.size} de ${total} seleccionadas` : "Escoge las mejoras para el prompt";
    toolbar.all.checked = total > 0 && picked.size === total;
    toolbar.all.indeterminate = picked.size > 0 && picked.size < total;
    toolbar.copy.disabled = picked.size === 0;
    for (const card of listEl.querySelectorAll<HTMLElement>(".imp-card")) {
      const on = picked.has(card.dataset.id ?? "");
      card.classList.toggle("is-picked", on);
      const box = card.querySelector<HTMLInputElement>(".imp-check");
      if (box) box.checked = on;
    }
  }

  /** Copia al portapapeles el prompt en Markdown de las mejoras escogidas. */
  async function copyPrompt() {
    const items = pickedItems();
    if (!items.length) return;
    try {
      await navigator.clipboard.writeText(buildImprovementsPrompt(items));
      notice.textContent = `Prompt copiado con ${items.length === 1 ? "1 mejora" : `${items.length} mejoras`}. Pégalo en tu IDE.`;
    } catch {
      notice.textContent = "No se pudo copiar: el navegador no dio permiso al portapapeles.";
    }
  }

  const statement = () => shell.setStatement(improvementsStatement(store.improvements, store.loaded.improvements, store.errors.improvements));

  /** Anota una mejora: aparece al instante y se sube; si falla, se avisa y se vuelve a leer lo del servidor. */
  async function add(item: Improvement) {
    store.improvements = withImprovement(store.improvements, item);
    store.emit("improvements");
    try {
      await saveImprovement(client, item);
      notice.textContent = "";
    } catch (err) {
      notice.textContent = `No se guardó la mejora. ${explainError(err)}`;
      await ctx.reload("improvements");
    }
  }

  /** «Hecho»: sale de la lista al instante y se borra de la base de datos; si falla, vuelve y se avisa. */
  async function done(item: Improvement) {
    store.improvements = withoutImprovement(store.improvements, item.id);
    store.emit("improvements");
    try {
      await finishImprovement(client, item.id);
      notice.textContent = "";
    } catch (err) {
      store.improvements = withImprovement(store.improvements, item);
      store.emit("improvements");
      notice.textContent = `No se pudo borrar la mejora. ${explainError(err)}`;
    }
  }

  function renderForm() {
    const section = h("input", { type: "text", maxlength: MAX_SECTION, placeholder: "Sección a agregar o mejorar (por ejemplo, Calendario)", "aria-label": "Sección", autocomplete: "off" });
    const functions = h("textarea", { rows: 4, maxlength: MAX_TEXT, placeholder: "Funciones que se quieren, una por línea", "aria-label": "Funciones" });
    const description = h("textarea", { rows: 3, maxlength: MAX_TEXT, placeholder: "Descripción", "aria-label": "Descripción" });
    const error = h("p", { class: "form-error", role: "alert" });
    sectionInput = section;
    const form = h(
      "form",
      { class: "imp-form" },
      h("h3", { class: "label" }, "Nueva mejora"),
      section,
      functions,
      description,
      error,
      h("div", { class: "cal-form-actions" }, h("button", { class: "btn-solid", type: "submit" }, icon("plus", "icon"), "Registrar")),
    );
    form.addEventListener("submit", (e) => {
      e.preventDefault();
      const input = { section: section.value, functions: functions.value, description: description.value };
      const problem = validateImprovement(input);
      if (problem) {
        error.textContent = problem;
        return;
      }
      error.textContent = "";
      void add(newImprovement(input));
      section.value = "";
      functions.value = "";
      description.value = "";
      section.focus();
    });
    formBox.replaceChildren(form);
  }

  function renderToolbar(): HTMLElement {
    const all = h("input", { type: "checkbox", "aria-label": "Seleccionar todas las mejoras" });
    const count = h("span", { class: "label imp-count", role: "status" });
    const copy = h("button", { class: "btn-solid imp-copy", type: "button", onClick: () => void copyPrompt() }, icon("copy", "icon"), "Copiar prompt (.md)");
    all.addEventListener("change", () => {
      picked.clear();
      if (all.checked) for (const i of store.improvements) picked.add(i.id);
      updateToolbar();
    });
    toolbar = { all, count, copy };
    return h("div", { class: "imp-toolbar" }, h("label", { class: "imp-all" }, all, "Todas"), count, copy);
  }

  function renderList() {
    const items = sortImprovements(store.improvements);
    for (const id of [...picked]) if (!items.some((i) => i.id === id)) picked.delete(id);
    toolbar = null;
    listEl.replaceChildren(
      items.length
        ? h(
            "div",
            { class: "imp-wrap" },
            renderToolbar(),
            h(
              "ul",
              { class: "imp-cards" },
              items.map((item) => {
              const lines = functionLines(item.functions);
              return h(
                "li",
                { class: "imp-card", "data-id": item.id },
                h(
                  "header",
                  { class: "imp-head" },
                  h(
                    "label",
                    { class: "imp-pick" },
                    h("input", {
                      type: "checkbox",
                      class: "imp-check",
                      checked: picked.has(item.id),
                      "aria-label": `Incluir en el prompt: ${item.section}`,
                      onChange: (e: Event) => {
                        if ((e.target as HTMLInputElement).checked) picked.add(item.id);
                        else picked.delete(item.id);
                        updateToolbar();
                      },
                    }),
                    h("h3", { class: "imp-section" }, item.section),
                  ),
                  h("time", { class: "label imp-when", datetime: item.created_at }, shortWhen(item.created_at)),
                ),
                lines.length ? h("ul", { class: "imp-functions" }, lines.map((l) => h("li", {}, l))) : null,
                item.description ? h("p", { class: "imp-desc" }, item.description) : null,
                h(
                  "div",
                  { class: "imp-actions" },
                  h(
                    "button",
                    {
                      class: "btn-edge imp-done",
                      type: "button",
                      "aria-label": `Marcar como hecha: ${item.section}`,
                      onClick: () => {
                        if (confirm(`¿Marcar «${item.section}» como hecha? Se borrará de la lista y de la base de datos.`)) void done(item);
                      },
                    },
                    icon("check", "icon"),
                    "Hecho",
                  ),
                ),
              );
              }),
            ),
          )
        : h("p", { class: "cfg-help" }, store.loaded.improvements ? "No hay mejoras pendientes." : "Cargando…"),
    );
    updateToolbar();
  }

  shell.body.append(notice, formBox, listEl);
  renderForm();
  renderList();
  statement();
  const handleIntent = () => {
    if (store.take("new-improvement")) sectionInput?.focus();
  };
  handleIntent();
  cleanups.push(store.onIntent(handleIntent));
  cleanups.push(
    store.on((area) => {
      if (area !== "improvements") return;
      statement();
      renderList();
    }),
  );
  return () => {
    for (const fn of cleanups) fn();
  };
};
