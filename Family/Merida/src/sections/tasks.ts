import { h, shortWhen } from "../ui/dom";
import { explainError } from "../supabase";
import {
  STATUSES,
  STATUS_LABEL,
  applyChanges,
  groupByStatus,
  isOverdue,
  newTask,
  saveTasks,
  softDelete,
  stepStatus,
  subtasksOf,
  summary,
  withStatus,
  type Task,
} from "../data/tasks";
import type { Ctx, Section } from "./context";

export function tasksStatement(tasks: Task[], loaded: boolean, error?: string): string {
  if (error) return error;
  if (!loaded) return "Cargando tus tareas.";
  const { open, dueToday } = summary(tasks);
  if (!open) return "Nada pendiente. Escribe la siguiente tarea abajo.";
  const head = open === 1 ? "1 abierta" : `${open} abiertas`;
  if (!dueToday) return `${head}; ninguna vence hoy.`;
  return `${head}; ${dueToday === 1 ? "1 vence hoy" : `${dueToday} vencen hoy`}.`;
}

export const tasksSection: Section = (ctx: Ctx) => {
  const { store, shell, client } = ctx;
  const expanded = new Set<string>();
  const board = h("div", { class: "board-flow" });
  const notice = h("p", { class: "notice", role: "status" });

  /** Aplica el cambio aquí y lo sube; si el servidor lo rechaza, vuelve a lo que diga el servidor. */
  async function commit(changed: Task[]) {
    store.tasks = applyChanges(store.tasks, changed);
    store.emit("tasks");
    try {
      await saveTasks(client, changed);
      notice.textContent = "";
    } catch (err) {
      notice.textContent = `No se guardó el cambio. ${explainError(err)}`;
      await ctx.reload("tasks");
    }
  }

  const input = h("input", { id: "new-task", type: "text", autocomplete: "off", maxlength: 200, placeholder: "Qué hay que hacer" });
  const addForm = h(
    "form",
    { class: "composer composer-inline" },
    h("label", { for: "new-task", class: "sr-only" }, "Nueva tarea"),
    input,
    h("button", { class: "btn-solid", type: "submit" }, "Añadir tarea"),
  );
  addForm.addEventListener("submit", (e) => {
    e.preventDefault();
    const name = input.value.trim();
    if (!name) return;
    input.value = "";
    const siblings = groupByStatus(store.tasks).pending;
    void commit([newTask(name, { siblings })]);
  });

  function card(task: Task): HTMLElement {
    const subs = subtasksOf(store.tasks, task.id);
    const doneSubs = subs.filter((s) => s.status === "done").length;
    const open = expanded.has(task.id);
    const back = stepStatus(task.status, -1);
    const fwd = stepStatus(task.status, 1);

    const meta = h(
      "p",
      { class: "card-meta readout" },
      task.due ? h("span", { class: isOverdue(task) ? "danger" : "" }, `${isOverdue(task) ? "vencida" : "vence"} ${shortWhen(task.due)}`) : null,
      subs.length ? h("span", {}, `${doneSubs}/${subs.length} subtareas`) : null,
      task.expected_min ? h("span", {}, `${task.expected_min} min`) : null,
    );

    const detail = open ? cardDetail(task, subs) : null;

    return h(
      "li",
      { class: "card", "data-status": task.status },
      h(
        "button",
        {
          class: "card-name",
          type: "button",
          "aria-expanded": String(open),
          onClick: () => {
            if (open) expanded.delete(task.id);
            else expanded.add(task.id);
            render();
          },
        },
        task.name,
      ),
      meta.childNodes.length ? meta : null,
      detail,
      h(
        "div",
        { class: "card-actions" },
        h("button", { class: "btn-step", type: "button", disabled: !back, "aria-label": back ? `Mover a ${STATUS_LABEL[back]}` : "Ya está al principio", title: back ? `A ${STATUS_LABEL[back]}` : "", onClick: () => back && void commit([withStatus(task, back)]) }, "‹"),
        h("button", { class: "btn-step", type: "button", disabled: !fwd, "aria-label": fwd ? `Mover a ${STATUS_LABEL[fwd]}` : "Ya está hecha", title: fwd ? `A ${STATUS_LABEL[fwd]}` : "", onClick: () => fwd && void commit([withStatus(task, fwd)]) }, "›"),
        h("button", { class: "btn-quiet btn-delete", type: "button", onClick: () => { if (confirm(`¿Borrar «${task.name}»? También se borra en el móvil.`)) void commit(softDelete(store.tasks, task.id)); } }, "Borrar"),
      ),
    );
  }

  function cardDetail(task: Task, subs: Task[]): HTMLElement {
    const desc = h("textarea", { class: "card-desc", rows: 3, "aria-label": "Descripción", placeholder: "Añade una descripción" });
    desc.value = task.description;
    desc.addEventListener("change", () => {
      if (desc.value !== task.description) void commit([{ ...task, description: desc.value, updated_at: new Date().toISOString() }]);
    });

    const subInput = h("input", { type: "text", "aria-label": `Nueva subtarea de ${task.name}`, placeholder: "Nueva subtarea", maxlength: 200 });
    const subForm = h("form", { class: "sub-form" }, subInput, h("button", { class: "btn-quiet", type: "submit" }, "Añadir"));
    subForm.addEventListener("submit", (e) => {
      e.preventDefault();
      const name = subInput.value.trim();
      if (!name) return;
      void commit([newTask(name, { parentId: task.id, siblings: subs })]);
    });

    return h(
      "div",
      { class: "card-detail" },
      desc,
      subs.length
        ? h(
            "ul",
            { class: "subs" },
            subs.map((s) => {
              const box = h("input", { type: "checkbox", id: `sub-${s.id}`, checked: s.status === "done" });
              box.addEventListener("change", () => void commit([withStatus(s, box.checked ? "done" : "pending")]));
              return h("li", {}, box, h("label", { for: `sub-${s.id}`, class: s.status === "done" ? "is-done" : "" }, s.name));
            }),
          )
        : null,
      subForm,
    );
  }

  function render() {
    shell.setStatement(tasksStatement(store.tasks, store.loaded.tasks, store.errors.tasks));
    const focusedId = (document.activeElement as HTMLElement | null)?.id;
    const groups = groupByStatus(store.tasks);
    board.replaceChildren(
      ...STATUSES.map((status, i) =>
        h(
          "section",
          { class: "column", "data-status": status, "aria-labelledby": `col-${status}` },
          h("h2", { class: "column-head", id: `col-${status}` }, h("span", { class: "step" }, `[${i + 1}]`), ` ${STATUS_LABEL[status]}`, h("span", { class: "readout count" }, groups[status].length)),
          groups[status].length
            ? h("ul", { class: "cards" }, groups[status].map(card))
            : h("p", { class: "column-empty" }, status === "pending" ? "Sin pendientes." : "Vacía."),
        ),
      ),
    );
    if (focusedId) document.getElementById(focusedId)?.focus();
  }

  shell.body.append(addForm, notice, board);
  render();
  const off = store.on((area) => area === "tasks" && render());
  return off;
};
