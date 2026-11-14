import { h, shortWhen } from "../ui/dom";
import { icon } from "../ui/icons";
import { explainError } from "../supabase";
import {
  STATUSES,
  STATUS_LABEL,
  TAG_COLORS,
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
  saveTags,
  saveTaskTags,
  saveTasks,
  softDelete,
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
  type Tag,
  type Task,
  type TaskPatch,
  type TaskStatus,
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

const longWhen = new Intl.DateTimeFormat("es", { dateStyle: "long", timeStyle: "short" });
/** «13 de noviembre de 2026, 18:00», o «—» si no hay fecha. */
export const fullWhen = (iso: string | null): string => (iso ? longWhen.format(new Date(iso)) : "—");

const COLOR_NAMES: Record<string, string> = { "#c8f73a": "Lima", "#ff5a1f": "Naranja", "#35d4ff": "Cian", "#ff4fd8": "Magenta", "#c9cebc": "Salvia", "#ffd23f": "Amarillo" };

let uid = 0;
const nextId = (base: string) => `${base}-${++uid}`;

/** Un campo con su etiqueta (la etiqueta enlaza al control, así se lee y se pulsa). */
function field(label: string, control: HTMLElement, cls = ""): HTMLElement {
  const id = nextId("fld");
  control.id = id;
  return h("div", { class: `fld ${cls}`.trim() }, h("label", { class: "label", for: id }, label), control);
}

export const tasksSection: Section = (ctx: Ctx) => {
  const { store, shell, client } = ctx;
  const cleanups: (() => void)[] = [];
  let openId: string | null = null; // la tarea que se ve completa (vista de detalle); null = el tablero
  let quiet = false; // un cambio que no debe volver a pintar la vista (para no perder el foco mientras se escribe)
  let tick: number | null = null;

  const board = h("div", { class: "board-flow" });
  const detail = h("div", { class: "task-detail", hidden: true });
  const notice = h("p", { class: "notice", role: "status" });

  const current = (id: string) => store.tasks.find((t) => t.id === id);

  /** Aplica el cambio aquí y lo sube; si el servidor lo rechaza, vuelve a lo que diga el servidor. */
  async function commit(changed: Task[], opts: { quiet?: boolean } = {}) {
    store.tasks = applyChanges(store.tasks, changed);
    quiet = !!opts.quiet;
    store.emit("tasks");
    quiet = false;
    try {
      await saveTasks(client, changed);
      notice.textContent = "";
    } catch (err) {
      notice.textContent = `No se guardó el cambio. ${explainError(err)}`;
      await ctx.reload("tasks");
    }
  }

  async function commitLinks(rows: ReturnType<typeof toggleTaskTag>[]) {
    store.taskTags = mergeTaskTags(store.taskTags, rows);
    quiet = true; // la vista ya pinta las etiquetas sola
    store.emit("tags");
    quiet = false;
    try {
      await saveTaskTags(client, rows);
      notice.textContent = "";
    } catch (err) {
      notice.textContent = `No se guardó la etiqueta. ${explainError(err)}`;
      await ctx.reload("tags");
    }
  }

  // ----- añadir
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

  // ----- el tablero
  function chips(task: Task): HTMLElement | null {
    const tags = tagsOf(store.tags, store.taskTags, task.id);
    if (!tags.length) return null;
    return h("ul", { class: "chips", "aria-label": "Etiquetas" }, tags.map((t) => h("li", { class: "chip", style: `--chip:${t.color}` }, t.name)));
  }

  function card(task: Task): HTMLElement {
    const subs = subtasksOf(store.tasks, task.id);
    const doneSubs = subs.filter((s) => s.status === "done").length;
    const back = stepStatus(task.status, -1);
    const fwd = stepStatus(task.status, 1);
    const spent = totalSeconds(task);

    const meta = h(
      "p",
      { class: "card-meta readout" },
      task.due ? h("span", { class: isOverdue(task) ? "danger" : "" }, `${isOverdue(task) ? "vencida" : "vence"} ${shortWhen(task.due)}`) : null,
      subs.length ? h("span", {}, `${doneSubs}/${subs.length} subtareas`) : null,
      task.expected_min ? h("span", {}, `${task.expected_min} min`) : null,
      spent ? h("span", {}, task.timer_started ? `● ${formatDuration(spent)}` : formatDuration(spent)) : null,
    );

    const li = h(
      "li",
      { class: "card", "data-status": task.status, "data-id": task.id, draggable: "true" }, // «true» en texto: un atributo vacío no hace arrastrable al elemento
      h("button", { class: "card-name", type: "button", "aria-label": `Abrir la tarea ${task.name}`, onClick: () => open(task.id) }, task.name),
      meta.childNodes.length ? meta : null,
      chips(task),
      h(
        "div",
        { class: "card-actions" },
        h("button", { class: "btn-step", type: "button", disabled: !back, "aria-label": back ? `Mover a ${STATUS_LABEL[back]}` : "Ya está al principio", title: back ? `A ${STATUS_LABEL[back]}` : "", onClick: () => back && void commit([withStatus(task, back)]) }, "‹"),
        h("button", { class: "btn-step", type: "button", disabled: !fwd, "aria-label": fwd ? `Mover a ${STATUS_LABEL[fwd]}` : "Ya está hecha", title: fwd ? `A ${STATUS_LABEL[fwd]}` : "", onClick: () => fwd && void commit([withStatus(task, fwd)]) }, "›"),
        h("button", { class: "btn-edge", type: "button", onClick: () => open(task.id) }, icon("pencil", "icon"), "Ver todo"),
      ),
    );
    // arrastrar la tarjeta a otra columna (o a otro lugar de la misma); los botones ‹ › siguen sirviendo con el teclado
    li.addEventListener("dragstart", (e) => {
      dragId = task.id;
      if (e.dataTransfer) {
        e.dataTransfer.effectAllowed = "move";
        e.dataTransfer.setData("text/plain", task.id); // Firefox no arrastra sin datos
      }
      li.classList.add("is-dragging");
      board.classList.add("is-dragging");
    });
    li.addEventListener("dragend", clearDrag);
    return li;
  }

  // ----- arrastrar y soltar entre columnas
  let dragId: string | null = null;

  /** Quita las marcas de arrastre (al soltar o al cancelar). */
  function clearDrag() {
    dragId = null;
    board.classList.remove("is-dragging");
    board.querySelectorAll(".is-dragging, .is-over, .is-before").forEach((el) => el.classList.remove("is-dragging", "is-over", "is-before"));
  }

  /** La tarjeta (distinta de la que se arrastra) delante de la que caería lo soltado, según dónde está el cursor. */
  function cardBefore(column: HTMLElement, y: number): HTMLElement | null {
    const cards = [...column.querySelectorAll<HTMLElement>(".card:not(.is-dragging)")];
    return cards.find((c) => y < c.getBoundingClientRect().top + c.getBoundingClientRect().height / 2) ?? null;
  }

  function wireColumn(column: HTMLElement, status: TaskStatus) {
    column.addEventListener("dragover", (e) => {
      if (!dragId) return;
      e.preventDefault(); // sin esto no se puede soltar aquí
      if (e.dataTransfer) e.dataTransfer.dropEffect = "move";
      board.querySelectorAll(".is-over, .is-before").forEach((el) => el.classList.remove("is-over", "is-before"));
      column.classList.add("is-over");
      cardBefore(column, e.clientY)?.classList.add("is-before");
    });
    column.addEventListener("dragleave", (e) => {
      if (!(e.relatedTarget instanceof Node) || !column.contains(e.relatedTarget)) column.classList.remove("is-over");
    });
    column.addEventListener("drop", (e) => {
      if (!dragId) return;
      e.preventDefault();
      const id = dragId;
      const before = cardBefore(column, e.clientY)?.dataset.id ?? null;
      clearDrag();
      const changed = moveToColumn(store.tasks, id, status, before);
      if (changed.length) void commit(changed);
    });
  }

  function renderBoard() {
    const focusedId = (document.activeElement as HTMLElement | null)?.id;
    const groups = groupByStatus(store.tasks);
    board.replaceChildren(
      ...STATUSES.map((status, i) => {
        const column = h(
          "section",
          { class: "column", "data-status": status, "aria-labelledby": `col-${status}` },
          h("h2", { class: "column-head", id: `col-${status}` }, h("span", { class: "step" }, `[${i + 1}]`), ` ${STATUS_LABEL[status]}`, h("span", { class: "readout count" }, groups[status].length)),
          groups[status].length
            ? h("ul", { class: "cards" }, groups[status].map(card))
            : h("p", { class: "column-empty" }, status === "pending" ? "Sin pendientes. Suelta aquí una tarjeta." : "Vacía. Suelta aquí una tarjeta."),
        );
        wireColumn(column, status);
        return column;
      }),
    );
    if (focusedId) document.getElementById(focusedId)?.focus();
  }

  // ----- la vista completa de una tarea: todos los campos de la tabla `tasks`, sus etiquetas y subtareas
  function open(id: string) {
    openId = id;
    render();
    shell.body.scrollTop = 0;
    detail.querySelector<HTMLElement>("input, textarea, select, button")?.focus({ preventScroll: true });
  }

  function close() {
    openId = null;
    render();
  }

  function stopTick() {
    if (tick !== null) window.clearInterval(tick);
    tick = null;
  }

  function renderDetail(task: Task) {
    stopTick();
    const parent = task.parent_id ? current(task.parent_id) : null;
    const subs = subtasksOf(store.tasks, task.id);
    const me = () => current(task.id) ?? task; // siempre la versión de ahora (otro campo pudo cambiarla)
    const patch = (p: TaskPatch, opts: { quiet?: boolean } = { quiet: true }) => void commit([updateFields(me(), p)], opts);

    const name = h("input", { type: "text", maxlength: 200, value: task.name, "aria-label": "Nombre" });
    name.value = task.name;
    name.addEventListener("change", () => {
      const v = name.value.trim();
      if (!v) name.value = me().name;
      else if (v !== me().name) patch({ name: v });
    });

    const status = h("select", { "aria-label": "Estado" }, STATUSES.map((s) => h("option", { value: s, selected: s === task.status }, STATUS_LABEL[s])));
    status.value = task.status;
    status.addEventListener("change", () => patch({ status: status.value as TaskStatus }, { quiet: false })); // cambia el cronómetro y el «terminada»

    const due = h("input", { type: "datetime-local", value: toLocalInput(task.due), "aria-label": "Entrega" });
    due.value = toLocalInput(task.due);
    due.addEventListener("change", () => patch({ due: fromLocalInput(due.value) }));

    const expected = h("input", { type: "number", min: 0, max: 999999, step: 5, inputmode: "numeric", value: task.expected_min ?? "", placeholder: "sin estimar", "aria-label": "Duración esperada en minutos" });
    expected.value = task.expected_min === null ? "" : String(task.expected_min);
    expected.addEventListener("change", () => {
      const v = expected.value.trim() === "" ? null : parseMinutes(expected.value);
      if (expected.value.trim() !== "" && v === null) {
        expected.value = me().expected_min === null ? "" : String(me().expected_min);
        return;
      }
      patch({ expected_min: v });
    });

    const desc = h("textarea", { rows: 5, "aria-label": "Descripción", placeholder: "Añade una descripción" });
    desc.value = task.description;
    desc.addEventListener("change", () => {
      if (desc.value !== me().description) patch({ description: desc.value });
    });

    // cronómetro: el tiempo real sube mientras corre
    const clock = h("output", { class: "timer-readout readout", "aria-live": "off" });
    const timerBtn = h("button", { class: "btn-edge", type: "button" });
    const paintTimer = () => {
      const t = me();
      clock.textContent = formatDuration(totalSeconds(t));
      timerBtn.textContent = t.timer_started ? "Detener" : "Iniciar";
      clock.dataset.running = String(!!t.timer_started);
    };
    timerBtn.addEventListener("click", () => {
      const t = me();
      void commit([t.timer_started ? stopTimer(t) : startTimer(t)], { quiet: true });
      paintTimer();
    });
    paintTimer();
    tick = window.setInterval(paintTimer, 1000);

    // etiquetas: todas las que existen (pulsar pone o quita) y una para crear
    const tagBox = h("div", { class: "tag-picker" });
    const paintTags = () => {
      const on = new Set(tagsOf(store.tags, store.taskTags, task.id).map((t) => t.id));
      tagBox.replaceChildren(
        store.tags.length
          ? h(
              "ul",
              { class: "chips chips-pick" },
              [...store.tags].sort((a, b) => a.name.localeCompare(b.name)).map((t: Tag) =>
                h("li", {}, h("button", { class: "chip", type: "button", style: `--chip:${t.color}`, "aria-pressed": String(on.has(t.id)), onClick: () => { void commitLinks([toggleTaskTag(store.taskTags, task.id, t.id, !on.has(t.id))]); paintTags(); } }, t.name)),
              ),
            )
          : h("p", { class: "cfg-help" }, "Aún no hay etiquetas. Crea la primera abajo."),
      );
    };
    paintTags();
    const tagName = h("input", { type: "text", maxlength: 40, placeholder: "Nueva etiqueta", "aria-label": "Nombre de la etiqueta nueva", autocomplete: "off" });
    const tagColor = h("select", { "aria-label": "Color de la etiqueta" }, TAG_COLORS.map((c) => h("option", { value: c }, COLOR_NAMES[c] ?? c)));
    const tagForm = h("form", { class: "sub-form" }, tagName, tagColor, h("button", { class: "btn-quiet", type: "submit" }, "Crear y poner"));
    tagForm.addEventListener("submit", (e) => {
      e.preventDefault();
      const n = tagName.value.trim();
      if (!n) return;
      if (store.tags.some((t) => t.name.toLowerCase() === n.toLowerCase())) {
        notice.textContent = `Ya existe la etiqueta «${n}». Púlsala arriba para ponerla.`;
        return;
      }
      const tag = newTag(n, tagColor.value);
      store.tags = [...store.tags, tag];
      tagName.value = "";
      void (async () => {
        try {
          await saveTags(client, [tag]);
          await commitLinks([toggleTaskTag(store.taskTags, task.id, tag.id, true)]);
        } catch (err) {
          store.tags = store.tags.filter((t) => t.id !== tag.id);
          notice.textContent = `No se creó la etiqueta. ${explainError(err)}`;
        }
        paintTags();
      })();
    });

    // subtareas: marcar, renombrar, subir, bajar, borrar
    const subList = h("ul", { class: "subs subs-edit" });
    const paintSubs = () => {
      const list = subtasksOf(store.tasks, task.id);
      subList.replaceChildren(
        ...list.map((s) => {
          const box = h("input", { type: "checkbox", "aria-label": `Hecha: ${s.name}`, checked: s.status === "done" });
          box.addEventListener("change", () => {
            void commit([withStatus(current(s.id) ?? s, box.checked ? "done" : "pending")], { quiet: true });
            paintSubs();
          });
          const label = h("input", { type: "text", class: "sub-name", value: s.name, maxlength: 200, "aria-label": "Nombre de la subtarea" });
          label.value = s.name;
          label.addEventListener("change", () => {
            const v = label.value.trim();
            const cur = current(s.id) ?? s;
            if (!v) label.value = cur.name;
            else if (v !== cur.name) void commit([updateFields(cur, { name: v })], { quiet: true });
          });
          const shift = (d: -1 | 1) => () => {
            const moved = moveSubtask(subtasksOf(store.tasks, task.id), s.id, d);
            if (moved.length) void commit(moved, { quiet: true });
            paintSubs();
          };
          const i = list.findIndex((x) => x.id === s.id);
          return h(
            "li",
            {},
            box,
            label,
            h("button", { class: "btn-step", type: "button", disabled: i === 0, "aria-label": `Subir ${s.name}`, onClick: shift(-1) }, icon("up", "icon")),
            h("button", { class: "btn-step", type: "button", disabled: i === list.length - 1, "aria-label": `Bajar ${s.name}`, onClick: shift(1) }, icon("down", "icon")),
            h("button", { class: "btn-step", type: "button", "aria-label": `Borrar la subtarea ${s.name}`, onClick: () => { void commit(softDelete(store.tasks, s.id), { quiet: true }); paintSubs(); } }, icon("trash", "icon")),
            h("button", { class: "btn-quiet", type: "button", onClick: () => open(s.id) }, "Abrir"),
          );
        }),
      );
    };
    paintSubs();
    const subInput = h("input", { type: "text", "aria-label": `Nueva subtarea de ${task.name}`, placeholder: "Nueva subtarea", maxlength: 200 });
    const subForm = h("form", { class: "sub-form" }, subInput, h("button", { class: "btn-quiet", type: "submit" }, "Añadir"));
    subForm.addEventListener("submit", (e) => {
      e.preventDefault();
      const n = subInput.value.trim();
      if (!n) return;
      subInput.value = "";
      void commit([newTask(n, { parentId: task.id, siblings: subtasksOf(store.tasks, task.id) })], { quiet: true });
      paintSubs();
      subInput.focus();
    });

    // solo lectura: lo que guarda la base de datos y no se edita a mano
    const info = h(
      "dl",
      { class: "info" },
      ...(
        [
          ["Identificador", task.id],
          ["Creada", fullWhen(task.created_at)],
          ["Última actualización", fullWhen(task.updated_at)],
          ["Terminada", fullWhen(task.finished)],
          ["Posición", String(task.position)],
          ["Cronómetro", task.timer_started ? `en marcha desde ${fullWhen(task.timer_started)}` : "detenido"],
        ] as [string, string][]
      ).flatMap(([k, v]) => [h("dt", { class: "label" }, k), h("dd", { class: "readout" }, v)]),
    );

    const del = h("button", { class: "btn-edge is-danger", type: "button", onClick: () => {
      if (!confirm(`¿Borrar «${task.name}»${subs.length ? " y sus subtareas" : ""}? También se borra en el móvil.`)) return;
      void commit(softDelete(store.tasks, task.id));
      close();
    } }, icon("trash", "icon"), "Borrar tarea");

    detail.replaceChildren(
      h(
        "div",
        { class: "detail-head" },
        h("button", { class: "btn-edge", type: "button", onClick: close }, icon("chevronLeft", "icon"), parent ? "Volver" : "Tablero"),
        parent ? h("button", { class: "btn-quiet", type: "button", onClick: () => open(parent.id) }, `Subtarea de «${parent.name}»`) : null,
        h("span", { class: "label detail-status", "data-status": task.status }, STATUS_LABEL[task.status]),
      ),
      h("div", { class: "detail-grid" },
        field("Nombre", name, "span-2"),
        field("Estado", status),
        field("Entrega", due),
        field("Duración esperada (min)", expected),
        h("div", { class: "fld" }, h("span", { class: "label" }, "Tiempo real"), h("div", { class: "timer" }, clock, timerBtn)),
        field("Descripción", desc, "span-2"),
      ),
      h("section", { class: "detail-block" }, h("h3", { class: "label" }, icon("tag", "icon"), " Etiquetas"), tagBox, tagForm),
      ...(parent ? [] : [h("section", { class: "detail-block" }, h("h3", { class: "label" }, icon("tasks", "icon"), ` Subtareas (${subs.length})`), subList, subForm)]),
      h("section", { class: "detail-block" }, h("h3", { class: "label" }, "Datos de la tarea"), info),
      h("div", { class: "detail-foot" }, del),
    );
  }

  function render() {
    shell.setStatement(tasksStatement(store.tasks, store.loaded.tasks, store.errors.tasks));
    const task = openId ? current(openId) : null;
    if (openId && !task) openId = null; // la borraron (aquí o desde otro dispositivo)
    const showing = !!task;
    addForm.hidden = showing;
    board.hidden = showing;
    detail.hidden = !showing;
    if (task) {
      // al repintar la vista, el foco vuelve al mismo control (por su etiqueta)
      const active = document.activeElement as HTMLElement | null;
      const label = active && detail.contains(active) ? active.getAttribute("aria-label") : null;
      renderDetail(task);
      if (label) [...detail.querySelectorAll<HTMLElement>("[aria-label]")].find((el) => el.getAttribute("aria-label") === label)?.focus({ preventScroll: true });
    } else {
      stopTick();
      renderBoard();
    }
  }

  shell.body.append(addForm, notice, board, detail);
  const handleIntent = () => {
    const taskIntent = store.take("open-task");
    if (taskIntent?.arg && current(taskIntent.arg)) return open(taskIntent.arg);
    if (store.take("new-task")) {
      close();
      input.focus();
    }
  };
  render();
  handleIntent();
  cleanups.push(store.onIntent(handleIntent));
  cleanups.push(
    store.on((area) => {
      if (quiet) return;
      if (area === "tasks" || area === "tags") render();
    }),
  );
  cleanups.push(stopTick);
  return () => {
    for (const fn of cleanups) fn();
  };
};
