import { afterEach, describe, expect, it, vi } from "vitest";
import type { SupabaseClient } from "@supabase/supabase-js";
import { tasksSection } from "../src/sections/tasks";
import { chatSection } from "../src/sections/chat";
import { calendarSection } from "../src/sections/calendar";
import { financeSection } from "../src/sections/finance";
import { vaultSection } from "../src/sections/vault";
import { Shell } from "../src/ui/shell";
import { Store } from "../src/store";
import { Status } from "../src/status";
import { DEFAULT_PREFS, PrefsStore } from "../src/prefs";
import { Backdrop } from "../src/backdrop";
import { Library } from "../src/data/library";
import { newTask, newTag, type Tag, type Task } from "../src/data/tasks";
import { newCategory } from "../src/data/finance";
import { dayKey, newEvent } from "../src/data/events";
import { newReminder } from "../src/data/reminders";
import { newHabit } from "../src/data/habits";
import type { Player } from "../src/player";
import type { Ctx, Section } from "../src/sections/context";
import type { RouteId } from "../src/routes";
import type { VaultSession } from "../src/vault/session";
import type { VaultItem } from "../src/data/vault";

type Row = Record<string, unknown>;

/** Un Supabase de mentira en memoria: guarda lo que se sube y lo anota para comprobarlo. */
function fakeClient() {
  const tables: Record<string, Row[]> = {};
  const calls: { table: string; op: string; payload: unknown }[] = [];
  const uploads: { path: string; type?: string }[] = [];
  const rpcs: { fn: string; args: Record<string, unknown> }[] = [];
  const from = (name: string) => {
    const rows = (tables[name] ??= []);
    let op = "select";
    let payload: unknown;
    const b: Record<string, unknown> = {
      select: () => b,
      order: () => b,
      limit: () => b,
      is: () => b,
      eq: () => b,
      upsert: (p: unknown) => ((op = "upsert"), (payload = p), b),
      insert: (p: unknown) => ((op = "insert"), (payload = p), b),
      then: (res: (v: unknown) => unknown) => {
        if (op !== "select") {
          calls.push({ table: name, op, payload });
          rows.push(...((Array.isArray(payload) ? payload : [payload]) as Row[]));
        }
        return Promise.resolve({ data: op === "select" ? rows : null, error: null }).then(res);
      },
    };
    return b;
  };
  const client = {
    from,
    rpc: async (fn: string, args: Record<string, unknown>) => {
      rpcs.push({ fn, args });
      if (fn === "send_message") return { data: { id: args.p_id, conversation_id: args.p_conversation_id, sender_device: "web", kind: "file", body: args.p_body || null, status: "sent", sent_at: args.p_sent_at, created_at: args.p_sent_at, deleted_at: null, attachments: ((args.p_attachments as Row[]) ?? []).map((a, i) => ({ id: `a${i}`, ...a })) }, error: null };
      return { data: [], error: null };
    },
    storage: { from: () => ({ upload: async (path: string, _f: unknown, o?: { contentType?: string }) => (uploads.push({ path, type: o?.contentType }), { data: { path }, error: null }), createSignedUrl: async () => ({ data: null, error: { message: "sin red" } }) }) },
  } as unknown as SupabaseClient;
  return { client, tables, calls, uploads, rpcs };
}

const flush = async (n = 6) => {
  for (let i = 0; i < n; i++) await new Promise((r) => setTimeout(r, 0));
};

function mount(route: RouteId, section: Section, setup: (store: Store) => void = () => {}, extra: Partial<Ctx> = {}) {
  const fake = fakeClient();
  const store = new Store();
  setup(store);
  const prefs = new PrefsStore({ ...DEFAULT_PREFS, keys: { ...DEFAULT_PREFS.keys } });
  const shell = new Shell({ store, prefs });
  document.body.append(shell.root);
  shell.setSection(route, "");
  const ctx: Ctx = {
    client: fake.client, shell, store, player: {} as Player, status: new Status(), prefs, backdrop: new Backdrop({ storage: null }), library: new Library(),
    vault: {} as never, userId: "user-1", signOut() {}, reload: vi.fn(async () => {}), ...extra,
  };
  const unmount = section(ctx);
  return { shell, store, unmount, ctx, ...fake };
}

const click = (el: Element | null | undefined) => (el as HTMLElement).click();
const byText = (root: ParentNode, tag: string, text: string) => [...root.querySelectorAll<HTMLElement>(tag)].find((e) => e.textContent?.trim() === text)!;
const typeInto = (el: HTMLInputElement | HTMLTextAreaElement | HTMLSelectElement, value: string, event = "input") => {
  el.value = value;
  el.dispatchEvent(new Event(event, { bubbles: true }));
};

afterEach(() => {
  document.body.replaceChildren();
  location.hash = "";
});

// ---------------------------------------------------------------------------------------------------------------------
describe("Tareas: la vista completa", () => {
  const T0 = new Date("2026-11-11T10:00:00Z");
  const tasks: Task[] = [
    newTask("Revisar contrato", { id: "t1", now: T0 }),
    { ...newTask("Subtarea uno", { id: "s1", parentId: "t1", now: T0 }), position: 0 },
    { ...newTask("Subtarea dos", { id: "s2", parentId: "t1", now: T0 }), position: 1 },
  ];
  const tags: Tag[] = [newTag("casa", "#ff5a1f", T0, "tag1")];
  const setup = (s: Store) => {
    s.tasks = tasks;
    s.tags = tags;
    s.loaded.tasks = true;
    s.loaded.tags = true;
  };

  it("pulsar una tarea abre todos sus campos y «Tablero» vuelve", () => {
    const { shell } = mount("tareas", tasksSection, setup);
    expect(shell.body.querySelector(".board-flow")?.hasAttribute("hidden")).toBe(false);
    click(shell.body.querySelector(".card-name"));
    const detail = shell.body.querySelector<HTMLElement>(".task-detail")!;
    expect(detail.hidden).toBe(false);
    expect(shell.body.querySelector<HTMLElement>(".board-flow")!.hidden).toBe(true);
    for (const label of ["Nombre", "Estado", "Entrega", "Duración esperada (min)", "Tiempo real", "Descripción"]) expect(detail.textContent).toContain(label);
    expect(detail.textContent).toContain("Subtareas (2)");
    expect(detail.textContent).toContain("Etiquetas");
    // los datos de solo lectura de la base de datos
    for (const label of ["Identificador", "Creada", "Última actualización", "Terminada", "Posición", "Cronómetro"]) expect(detail.textContent).toContain(label);
    expect(detail.textContent).toContain("t1");
    click(byText(detail, "button", "Tablero"));
    expect(detail.hidden).toBe(true);
    expect(shell.body.querySelector<HTMLElement>(".board-flow")!.hidden).toBe(false);
  });

  it("editar el nombre, la entrega y los minutos guarda la tarea con updated_at mayor, sin perder los otros cambios", async () => {
    const { shell, store, calls } = mount("tareas", tasksSection, setup);
    click(shell.body.querySelector(".card-name"));
    const detail = shell.body.querySelector<HTMLElement>(".task-detail")!;
    typeInto(detail.querySelector<HTMLInputElement>('input[aria-label="Nombre"]')!, "  Contrato firmado ", "change");
    typeInto(detail.querySelector<HTMLInputElement>('input[aria-label="Duración esperada en minutos"]')!, "45", "change");
    typeInto(detail.querySelector<HTMLInputElement>('input[aria-label="Entrega"]')!, "2026-11-20T18:30", "change");
    typeInto(detail.querySelector<HTMLTextAreaElement>("textarea")!, "Revisar la cláusula 4", "change");
    await flush();
    const saved = store.tasks.find((t) => t.id === "t1")!;
    expect(saved).toMatchObject({ name: "Contrato firmado", expected_min: 45, description: "Revisar la cláusula 4" });
    expect(saved.due).toBe(new Date(2026, 10, 20, 18, 30).toISOString());
    expect(saved.updated_at > T0.toISOString()).toBe(true);
    expect(calls.filter((c) => c.table === "tasks" && c.op === "upsert")).toHaveLength(4);
    // cada subida llevaba todo lo anterior: la última tiene los cuatro cambios juntos
    const last = (calls.filter((c) => c.table === "tasks").at(-1)!.payload as Task[])[0];
    expect(last).toMatchObject({ name: "Contrato firmado", expected_min: 45, description: "Revisar la cláusula 4" });
  });

  it("unos minutos que no son un número válido se rechazan y el campo vuelve a su valor", async () => {
    const { shell, store, calls } = mount("tareas", tasksSection, setup);
    click(shell.body.querySelector(".card-name"));
    const mins = shell.body.querySelector<HTMLInputElement>('input[aria-label="Duración esperada en minutos"]')!;
    typeInto(mins, "-3", "change");
    await flush();
    expect(calls).toHaveLength(0);
    expect(store.tasks.find((t) => t.id === "t1")!.expected_min).toBeNull();
    expect(mins.value).toBe("");
  });

  it("cambiar el estado desde la vista guarda «terminada»", async () => {
    const { shell, store } = mount("tareas", tasksSection, setup);
    click(shell.body.querySelector(".card-name"));
    typeInto(shell.body.querySelector<HTMLSelectElement>('select[aria-label="Estado"]')!, "done", "change");
    await flush();
    const t = store.tasks.find((x) => x.id === "t1")!;
    expect(t.status).toBe("done");
    expect(t.finished).not.toBeNull();
  });

  it("el cronómetro se inicia y se detiene, y guarda el tiempo", async () => {
    vi.useFakeTimers({ toFake: ["Date", "setInterval", "clearInterval"] });
    try {
      vi.setSystemTime(new Date("2026-11-11T12:00:00Z"));
      const { shell, store } = mount("tareas", tasksSection, setup);
      click(shell.body.querySelector(".card-name"));
      const start = byText(shell.body, "button", "Iniciar");
      click(start);
      expect(store.tasks.find((t) => t.id === "t1")!.timer_started).not.toBeNull();
      expect(shell.body.querySelector(".timer-readout")?.getAttribute("data-running")).toBe("true");
      vi.setSystemTime(new Date("2026-11-11T12:02:04Z")); // el reloj falso también avanza con el temporizador: +1 s = 12:02:05
      vi.advanceTimersByTime(1000);
      expect(shell.body.querySelector(".timer-readout")?.textContent).toBe("2 min 05 s");
      click(byText(shell.body, "button", "Detener"));
      const t = store.tasks.find((x) => x.id === "t1")!;
      expect(t).toMatchObject({ timer_started: null, real_s: 125 });
    } finally {
      vi.useRealTimers();
    }
  });

  it("pulsar una etiqueta la pone en la tarea y volver a pulsarla la quita; crear una etiqueta nueva también la pone", async () => {
    const { shell, store, calls } = mount("tareas", tasksSection, setup);
    click(shell.body.querySelector(".card-name"));
    const chip = () => byText(shell.body, "button", "casa");
    expect(chip().getAttribute("aria-pressed")).toBe("false");
    click(chip());
    await flush();
    expect(chip().getAttribute("aria-pressed")).toBe("true");
    expect(store.taskTags).toHaveLength(1);
    expect(calls.at(-1)).toMatchObject({ table: "task_tags", op: "upsert" });
    click(chip());
    await flush();
    expect(chip().getAttribute("aria-pressed")).toBe("false");
    expect(store.taskTags[0].deleted_at).not.toBeNull();

    typeInto(shell.body.querySelector<HTMLInputElement>('input[aria-label="Nombre de la etiqueta nueva"]')!, "urgente");
    shell.body.querySelector<HTMLFormElement>("form.sub-form:last-of-type")?.dispatchEvent(new Event("submit", { cancelable: true }));
    const forms = [...shell.body.querySelectorAll<HTMLFormElement>("form.sub-form")];
    forms.find((f) => f.querySelector('input[aria-label="Nombre de la etiqueta nueva"]'))!.dispatchEvent(new Event("submit", { cancelable: true }));
    await flush();
    expect(store.tags.map((t) => t.name)).toContain("urgente");
    expect(calls.some((c) => c.table === "tags")).toBe(true);
  });

  it("las subtareas se añaden y se pueden subir y bajar", async () => {
    const { shell, store } = mount("tareas", tasksSection, setup);
    click(shell.body.querySelector(".card-name"));
    typeInto(shell.body.querySelector<HTMLInputElement>('input[aria-label^="Nueva subtarea"]')!, "Subtarea tres");
    shell.body.querySelector<HTMLInputElement>('input[aria-label^="Nueva subtarea"]')!.closest("form")!.dispatchEvent(new Event("submit", { cancelable: true }));
    await flush();
    expect(store.tasks.filter((t) => t.parent_id === "t1").map((t) => t.name)).toEqual(["Subtarea uno", "Subtarea dos", "Subtarea tres"]);
    click(shell.body.querySelector('button[aria-label="Subir Subtarea dos"]'));
    await flush();
    const order = store.tasks.filter((t) => t.parent_id === "t1").sort((a, b) => a.position - b.position).map((t) => t.name);
    expect(order.slice(0, 2)).toEqual(["Subtarea dos", "Subtarea uno"]);
  });

  describe("arrastrar tarjetas", () => {
    const drag = (type: string, el: Element, y = 0) => {
      const ev = new Event(type, { bubbles: true, cancelable: true }) as Event & { dataTransfer?: unknown; clientY?: number };
      ev.dataTransfer = { setData() {}, effectAllowed: "", dropEffect: "" };
      ev.clientY = y;
      el.dispatchEvent(ev);
      return ev;
    };
    const board = (s: Store) => {
      s.tasks = [
        { ...newTask("Uno", { id: "u", now: T0 }), position: 0 },
        { ...newTask("Dos", { id: "d", now: T0 }), position: 1 },
        { ...newTask("Hecha", { id: "h", now: T0 }), status: "done", position: 0, finished: T0.toISOString() },
      ];
      s.loaded.tasks = true;
    };
    const card = (shell: Shell, id: string) => shell.body.querySelector<HTMLElement>(`.card[data-id="${id}"]`)!;
    const column = (shell: Shell, status: string) => shell.body.querySelector<HTMLElement>(`.column[data-status="${status}"]`)!;

    it("las tarjetas se pueden arrastrar y mientras tanto se marcan las columnas", () => {
      const { shell } = mount("tareas", tasksSection, board);
      expect(card(shell, "u").getAttribute("draggable")).toBe("true");
      drag("dragstart", card(shell, "u"));
      expect(card(shell, "u").classList.contains("is-dragging")).toBe(true);
      expect(shell.body.querySelector(".board-flow")!.classList.contains("is-dragging")).toBe(true);
      const over = drag("dragover", column(shell, "doing"));
      expect(over.defaultPrevented).toBe(true); // sin esto el navegador no deja soltar
      expect(column(shell, "doing").classList.contains("is-over")).toBe(true);
      drag("dragend", card(shell, "u"));
      expect(shell.body.querySelector(".is-dragging, .is-over")).toBeNull();
    });

    it("soltar una tarjeta en otra columna cambia su estado y lo sube al servidor", async () => {
      const { shell, store, calls } = mount("tareas", tasksSection, board);
      drag("dragstart", card(shell, "u"));
      drag("drop", column(shell, "doing"));
      await flush();
      expect(store.tasks.find((t) => t.id === "u")).toMatchObject({ status: "doing", position: 0 });
      expect(calls.at(-1)).toMatchObject({ table: "tasks", op: "upsert" });
      expect(column(shell, "doing").querySelector(".card")?.getAttribute("data-id")).toBe("u");
      expect(shell.body.querySelector(".is-dragging")).toBeNull();
    });

    it("soltarla en Hecha guarda la hora de fin", async () => {
      const { shell, store } = mount("tareas", tasksSection, board);
      drag("dragstart", card(shell, "d"));
      drag("drop", column(shell, "done"));
      await flush();
      const t = store.tasks.find((x) => x.id === "d")!;
      expect(t.status).toBe("done");
      expect(t.finished).not.toBeNull();
    });

    it("soltarla en la misma columna donde ya estaba al final no sube nada", async () => {
      const { shell, calls } = mount("tareas", tasksSection, board);
      drag("dragstart", card(shell, "d"));
      drag("drop", column(shell, "pending"), 99999); // muy abajo: al final, donde ya está
      await flush();
      expect(calls).toHaveLength(0);
    });

    it("una columna vacía también recibe tarjetas, y sin arrastrar nada no reacciona", async () => {
      const { shell, store } = mount("tareas", tasksSection, board);
      expect(drag("dragover", column(shell, "review")).defaultPrevented).toBe(false); // nada en vuelo
      drag("dragstart", card(shell, "u"));
      drag("drop", column(shell, "review"));
      await flush();
      expect(store.tasks.find((t) => t.id === "u")!.status).toBe("review");
    });
  });

  it("una orden «abrir tarea» de la paleta abre su vista completa", () => {
    const { shell, store } = mount("tareas", tasksSection, (s) => setup(s));
    store.raise("open-task", "t1");
    expect(shell.body.querySelector<HTMLElement>(".task-detail")!.hidden).toBe(false);
    expect(shell.body.querySelector<HTMLInputElement>('input[aria-label="Nombre"]')!.value).toBe("Revisar contrato");
  });

  it("una orden «nueva tarea» lleva el foco al campo de añadir", () => {
    const { shell, store } = mount("tareas", tasksSection, setup);
    store.raise("new-task");
    expect(document.activeElement).toBe(shell.body.querySelector("#new-task"));
  });
});

// ---------------------------------------------------------------------------------------------------------------------
describe("Chat: adjuntar archivos", () => {
  const setup = (s: Store) => {
    s.conversationId = "conv";
    s.loaded.messages = true;
  };
  const pdf = (name: string, size = 1234) => {
    const f = new File(["%PDF"], name, { type: "application/pdf" });
    Object.defineProperty(f, "size", { value: size });
    return f;
  };
  const pick = (shell: Shell, files: File[]) => {
    const input = shell.body.querySelector<HTMLInputElement>("#chat-files")!;
    Object.defineProperty(input, "files", { value: files, configurable: true });
    input.dispatchEvent(new Event("change"));
  };

  it("elegir archivos los deja en la lista, se pueden quitar y el botón de enviar se activa sin texto", () => {
    const { shell } = mount("chat", chatSection, setup);
    const send = shell.body.querySelector<HTMLButtonElement>(".chat-send")!;
    expect(send.disabled).toBe(true);
    pick(shell, [pdf("contrato.pdf"), pdf("otro.pdf")]);
    expect(shell.body.querySelectorAll(".staged-item")).toHaveLength(2);
    expect(send.disabled).toBe(false);
    click(shell.body.querySelector('.staged-item button[aria-label="Quitar contrato.pdf"]'));
    expect(shell.body.querySelectorAll(".staged-item")).toHaveLength(1);
  });

  it("un archivo demasiado grande o vacío se rechaza con su motivo", () => {
    const { shell } = mount("chat", chatSection, setup);
    pick(shell, [pdf("enorme.pdf", 60 * 1024 * 1024), pdf("vacio.pdf", 0)]);
    expect(shell.body.querySelectorAll(".staged-item")).toHaveLength(0);
    expect(shell.body.querySelector(".form-error")?.textContent).toMatch(/enorme\.pdf.*límite/);
    expect(shell.body.querySelector(".form-error")?.textContent).toMatch(/vacio\.pdf.*vacío/);
  });

  it("enviar sube cada archivo a <cuenta>/<conversación>/<mensaje>/<nombre> y manda el mensaje con sus adjuntos", async () => {
    const { shell, store, uploads, rpcs } = mount("chat", chatSection, setup);
    pick(shell, [pdf("Mi contrato (1).pdf", 2048)]);
    const text = shell.body.querySelector<HTMLTextAreaElement>("#chat-text")!;
    typeInto(text, "te lo mando");
    shell.body.querySelector<HTMLFormElement>("form.chat-composer")!.dispatchEvent(new Event("submit", { cancelable: true }));
    await flush();
    expect(uploads).toHaveLength(1);
    const send = rpcs.find((r) => r.fn === "send_message")!;
    const id = send.args.p_id as string;
    expect(uploads[0]).toEqual({ path: `user-1/conv/${id}/Mi_contrato__1_.pdf`, type: "application/pdf" });
    expect(send.args).toMatchObject({ p_conversation_id: "conv", p_body: "te lo mando", p_device: "web" });
    expect(send.args.p_attachments).toEqual([{ storage_path: `user-1/conv/${id}/Mi_contrato__1_.pdf`, file_name: "Mi contrato (1).pdf", mime_type: "application/pdf", size_bytes: 2048, width: null, height: null, duration_ms: null, thumb_path: null }]);
    expect(store.messages).toHaveLength(1);
    expect(store.messages[0].id).toBe(id);
    expect(store.messages[0].local).toBeUndefined(); // ya no está «enviándose»
    expect(store.messages[0].attachments).toHaveLength(1);
    expect(shell.body.querySelectorAll(".staged-item")).toHaveLength(0); // la lista queda vacía tras enviar
  });

  it("si la subida falla el mensaje queda «no se envió» y Reintentar lo manda con el mismo id sin pedir los archivos otra vez", async () => {
    const fake = mount("chat", chatSection, setup);
    const { shell, store, uploads, rpcs } = fake;
    const original = (fake.client.storage.from as unknown as () => { upload: (...a: unknown[]) => Promise<unknown> })();
    let fail = true;
    const realUpload = original.upload;
    (fake.client.storage as unknown as { from: () => unknown }).from = () => ({
      ...original,
      upload: async (...a: unknown[]) => (fail ? { data: null, error: { message: "sin red" } } : realUpload(...a)),
      createSignedUrl: async () => ({ data: null, error: { message: "x" } }),
    });
    pick(shell, [pdf("a.pdf")]);
    shell.body.querySelector<HTMLFormElement>("form.chat-composer")!.dispatchEvent(new Event("submit", { cancelable: true }));
    await flush();
    expect(store.messages[0].local).toBe("failed");
    expect(rpcs.filter((r) => r.fn === "send_message")).toHaveLength(0);
    const id = store.messages[0].id;
    fail = false;
    click(byText(shell.body, "button", "Reintentar"));
    await flush();
    expect(uploads).toHaveLength(1);
    expect(uploads[0].path).toBe(`user-1/conv/${id}/a.pdf`);
    expect(rpcs.filter((r) => r.fn === "send_message")).toHaveLength(1);
    expect(store.messages).toHaveLength(1);
    expect(store.messages[0].local).toBeUndefined();
  });

  it("soltar archivos sobre el chat los añade", () => {
    const { shell } = mount("chat", chatSection, setup);
    const drop = new Event("drop", { bubbles: true, cancelable: true }) as Event & { dataTransfer?: unknown };
    drop.dataTransfer = { types: ["Files"], files: [pdf("soltado.pdf")] };
    shell.body.dispatchEvent(drop);
    expect(shell.body.querySelector(".staged-name")?.textContent).toBe("soltado.pdf");
    expect(drop.defaultPrevented).toBe(true);
  });

  it("pegar una imagen del portapapeles la añade, pero pegar texto sigue siendo texto", () => {
    const { shell } = mount("chat", chatSection, setup);
    const text = shell.body.querySelector<HTMLTextAreaElement>("#chat-text")!;
    const img = new File(["x"], "captura.png", { type: "image/png" });
    const paste = new Event("paste", { bubbles: true, cancelable: true }) as Event & { clipboardData?: unknown };
    paste.clipboardData = { files: [img] };
    text.dispatchEvent(paste);
    expect(shell.body.querySelector(".staged-name")?.textContent).toBe("captura.png");
    expect(paste.defaultPrevented).toBe(true);
    const plain = new Event("paste", { bubbles: true, cancelable: true }) as Event & { clipboardData?: unknown };
    plain.clipboardData = { files: [] };
    text.dispatchEvent(plain);
    expect(plain.defaultPrevented).toBe(false);
  });
});

// ---------------------------------------------------------------------------------------------------------------------
describe("Calendario", () => {
  const monthView = (shell: Shell) => click(byText(shell.body, ".cal-views .tab", "Mes"));
  const submit = (shell: Shell) => shell.body.querySelector<HTMLFormElement>("form.cal-form")!.dispatchEvent(new Event("submit", { cancelable: true }));
  const dropOn = (target: Element, payload: unknown) => {
    const drop = new Event("drop", { bubbles: true, cancelable: true }) as Event & { dataTransfer?: unknown };
    drop.dataTransfer = { getData: () => JSON.stringify(payload) };
    target.dispatchEvent(drop);
  };
  const at = (h: number, m = 0) => {
    const d = new Date();
    d.setHours(h, m, 0, 0);
    return d;
  };
  const weekAgo = new Date(Date.now() - 7 * 86_400_000);
  const overlay = (shell: Shell) => shell.body.querySelector<HTMLElement>(".cal-expand")!;
  const isOpen = (shell: Shell) => !overlay(shell).hidden;
  const titleOf = (shell: Shell) => [...shell.body.querySelectorAll(".cal-block-title")].map((e) => e.textContent);

  it("abre en la vista semanal y cambia a día y a mes, y se acuerda de la última", () => {
    const { shell, ctx } = mount("calendario", calendarSection, (s) => (s.loaded.events = true));
    expect(shell.body.querySelector(".cal-tg")?.getAttribute("data-cols")).toBe("7");
    expect(shell.body.querySelector(".cal-cell")).toBeNull();
    expect(byText(shell.body, ".cal-views .tab", "Semana").getAttribute("aria-pressed")).toBe("true");
    expect(shell.body.querySelectorAll(".cal-tg-day")).toHaveLength(7);

    monthView(shell);
    expect(shell.body.querySelectorAll(".cal-cell")).toHaveLength(42);
    expect(shell.body.querySelector(`.cal-cell[data-day="${dayKey(new Date())}"]`)?.getAttribute("data-today")).toBe("true");
    expect(ctx.prefs.value.calendarView).toBe("month");

    click(byText(shell.body, ".cal-views .tab", "Día"));
    expect(shell.body.querySelector(".cal-tg")?.getAttribute("data-cols")).toBe("1");
    expect(shell.body.querySelectorAll(".cal-col")).toHaveLength(1);
    expect(ctx.prefs.value.calendarView).toBe("day");
  });

  it("las opciones están a la izquierda y el calendario a la derecha; ya no hay cuadro de fecha, título ni buscador", () => {
    const { shell } = mount("calendario", calendarSection);
    const layout = shell.body.querySelector(".cal")!;
    expect([...layout.children].map((c) => c.className)).toEqual(["cal-left", "cal-main"]);
    expect([...shell.body.querySelectorAll(".cal-left .label")].map((l) => l.textContent)).toEqual(["Ir a", "Formato", "Mostrar"]);
    expect(shell.body.querySelector(".cal-badge")).toBeNull();
    expect(shell.body.querySelector(".cal-range")).toBeNull();
    expect(shell.body.querySelector(".cal-search")).toBeNull();
    expect(shell.body.querySelector('input[type="search"]')).toBeNull();
    expect(shell.body.querySelector(".cal-title")?.classList.contains("sr-only")).toBe(true); // solo para lectores de pantalla
    expect(shell.body.querySelector(".cal-left")?.textContent).toMatch(/paleta de comandos/);
  });

  it("navega por el periodo de la vista con anterior, hoy y siguiente", () => {
    const { shell } = mount("calendario", calendarSection);
    const title = () => shell.body.querySelector(".cal-title")!.textContent;
    const first = title();
    click(shell.body.querySelector('button[aria-label="Semana siguiente"]'));
    expect(title()).not.toBe(first);
    click(byText(shell.body, ".cal-nav button", "Hoy"));
    expect(title()).toBe(first);
    monthView(shell);
    expect(shell.body.querySelector('button[aria-label="Mes anterior"]')).not.toBeNull();
  });

  it("el día 1 del mes lleva el nombre del mes (ya no hay título arriba)", () => {
    const { shell } = mount("calendario", calendarSection);
    monthView(shell);
    const firsts = [...shell.body.querySelectorAll(".cal-cell")].filter((c) => c.getAttribute("data-day")!.endsWith("-01"));
    expect(firsts.length).toBeGreaterThan(0);
    expect(firsts[0].querySelector(".cal-day")?.textContent).toMatch(/^1 [a-záéíóú]{3}/);
  });

  it("pulsar un día del mes lo expande con todo lo que hay; Cerrar y Esc lo cierran", () => {
    const { shell } = mount("calendario", calendarSection, (s) => {
      s.events = [newEvent("Cita", at(10), { id: "e" })];
      s.loaded.events = true;
    });
    monthView(shell);
    expect(isOpen(shell)).toBe(false);
    const today = dayKey(new Date());
    click(shell.body.querySelector(`.cal-cell[data-day="${today}"] .cal-day`));
    expect(isOpen(shell)).toBe(true);
    expect(overlay(shell).getAttribute("aria-modal")).toBe("true");
    expect(shell.body.querySelector(".cal-grid")?.hasAttribute("inert")).toBe(true);
    expect(overlay(shell).querySelector(".cal-entry-title")?.textContent).toBe("Cita");
    expect(overlay(shell).querySelector("form")).toBeNull(); // el formulario no está: se abre desde la paleta
    click(overlay(shell).querySelector(".cal-close"));
    expect(isOpen(shell)).toBe(false);
    expect(shell.body.querySelector(".cal-grid")?.hasAttribute("inert")).toBe(false);

    click(shell.body.querySelector(`.cal-cell[data-day="${today}"]`));
    expect(isOpen(shell)).toBe(true);
    const esc = new KeyboardEvent("keydown", { key: "Escape", bubbles: true, cancelable: true });
    document.body.dispatchEvent(esc);
    expect(esc.defaultPrevented).toBe(true);
    expect(isOpen(shell)).toBe(false);
  });

  it("Esc no cierra el día si hay otra ventana encima (la paleta)", () => {
    const { shell } = mount("calendario", calendarSection);
    monthView(shell);
    click(shell.body.querySelector(`.cal-cell[data-day="${dayKey(new Date())}"]`));
    const other = document.createElement("div");
    other.setAttribute("aria-modal", "true");
    document.body.append(other);
    document.body.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true, cancelable: true }));
    expect(isOpen(shell)).toBe(true);
  });

  it("en la semana, pulsar la cabecera de un día lo expande", () => {
    const { shell } = mount("calendario", calendarSection);
    const head = shell.body.querySelector<HTMLElement>(".cal-tg-day")!;
    click(head);
    expect(isOpen(shell)).toBe(true);
    expect(overlay(shell).querySelector(".cal-day-title")?.textContent).toBeTruthy();
  });

  it("el formulario no está a la vista: se abre desde la paleta con «nuevo evento» y crea el evento en el día elegido", async () => {
    const { shell, store, calls } = mount("calendario", calendarSection, (s) => (s.loaded.events = true));
    expect(shell.body.querySelector("form.cal-form")).toBeNull();
    store.raise("new-event");
    expect(isOpen(shell)).toBe(true);
    expect(document.activeElement).toBe(shell.body.querySelector('input[aria-label="Título"]'));
    typeInto(shell.body.querySelector<HTMLInputElement>('input[aria-label="Título"]')!, "Reunión");
    typeInto(shell.body.querySelector<HTMLInputElement>('input[aria-label="Hora de inicio"]')!, "15:30");
    submit(shell);
    await flush();
    expect(store.events).toHaveLength(1);
    expect(store.events[0]).toMatchObject({ title: "Reunión", all_day: false });
    expect(new Date(store.events[0].starts_at).getHours()).toBe(15);
    expect(calls.at(-1)).toMatchObject({ table: "events", op: "upsert" });
    expect(shell.body.querySelector("form.cal-form")).toBeNull(); // se cierra al guardar
    expect(shell.body.querySelector(".cal-entry-title")?.textContent).toBe("Reunión");
    click(overlay(shell).querySelector(".cal-close"));
    expect(shell.body.querySelector(".cal-block.is-event .cal-block-title")?.textContent).toBe("Reunión"); // ya sale en la columna de horas
  });

  it("«nuevo evento» desde la paleta usa el día que tenías abierto", () => {
    const { shell, store } = mount("calendario", calendarSection);
    monthView(shell);
    const target = [...shell.body.querySelectorAll<HTMLElement>(".cal-cell")].find((c) => c.dataset.day !== dayKey(new Date()) && c.dataset.out === "false")!;
    click(target);
    store.raise("new-event");
    expect(shell.body.querySelector<HTMLInputElement>('input[aria-label="Fecha"]')?.value).toBe(target.dataset.day);
  });

  it("no deja crear un evento sin título ni con la hora de fin antes de la de inicio", () => {
    const { shell, store } = mount("calendario", calendarSection);
    store.raise("new-event");
    submit(shell);
    expect(shell.body.querySelector(".cal-form .form-error")?.textContent).toBe("Escribe un título.");
    typeInto(shell.body.querySelector<HTMLInputElement>('input[aria-label="Título"]')!, "X");
    typeInto(shell.body.querySelector<HTMLInputElement>('input[aria-label="Hora de inicio"]')!, "10:00");
    typeInto(shell.body.querySelector<HTMLInputElement>('input[aria-label="Hora de fin (opcional)"]')!, "09:00");
    submit(shell);
    expect(shell.body.querySelector(".cal-form .form-error")?.textContent).toMatch(/fin debe ser después/);
    expect(store.events).toHaveLength(0);
  });

  it("Cancelar cierra el formulario sin guardar", () => {
    const { shell, store } = mount("calendario", calendarSection);
    store.raise("new-event");
    click(byText(shell.body, ".cal-form-actions button", "Cancelar"));
    expect(shell.body.querySelector("form.cal-form")).toBeNull();
    expect(isOpen(shell)).toBe(true); // el día sigue abierto
  });

  it("los eventos, tareas y recordatorios son realmente arrastrables (draggable=\"true\", no vacío) y los hábitos no", () => {
    const { shell } = mount("calendario", calendarSection, (s) => {
      s.events = [newEvent("Cita", at(10), { id: "e" })];
      s.tasks = [{ ...newTask("Tarea", { id: "t" }), due: at(11).toISOString() }];
      s.reminders = [newReminder("Aviso", at(12), { id: "r" })];
      s.habits = [newHabit("Agua", { id: "h", now: weekAgo })];
      s.loaded.events = true;
    });
    for (const view of ["Semana", "Mes"]) {
      click(byText(shell.body, ".cal-views .tab", view));
      const movable = [...shell.body.querySelectorAll(".cal-chip:not(.is-habit), .cal-block:not(.is-habit)")];
      expect(movable.length).toBeGreaterThanOrEqual(3);
      for (const el of movable) expect(el.getAttribute("draggable")).toBe("true");
      for (const el of shell.body.querySelectorAll(".cal-chip.is-habit")) expect(el.getAttribute("draggable")).toBeNull();
    }
  });

  it("las tareas con entrega ese día salen en el día (mes) y se pueden mover a otro arrastrándolas", async () => {
    const { shell, store } = mount("calendario", calendarSection, (s) => {
      s.tasks = [{ ...newTask("Pagar la luz", { id: "luz" }), due: at(18).toISOString() }];
      s.loaded.events = true;
    });
    monthView(shell);
    const today = dayKey(new Date());
    expect(shell.body.querySelector(`.cal-cell[data-day="${today}"] .cal-chip.is-task .cal-chip-title`)?.textContent).toBe("Pagar la luz");
    const target = [...shell.body.querySelectorAll<HTMLElement>(".cal-cell")].find((c) => c.dataset.day !== today && c.dataset.out === "false")!;
    dropOn(target, { type: "task", id: "luz" });
    await flush();
    expect(dayKey(new Date(store.tasks[0].due!))).toBe(target.dataset.day);
    expect(new Date(store.tasks[0].due!).getHours()).toBe(18);
  });

  it("soltar un evento en otra columna de la semana lo cambia de día conservando la hora", async () => {
    const { shell, store } = mount("calendario", calendarSection, (s) => {
      s.events = [newEvent("Cita", at(10, 15), { id: "e" })];
      s.loaded.events = true;
    });
    const todayKey = dayKey(new Date());
    const col = [...shell.body.querySelectorAll<HTMLElement>(".cal-col")].find((c) => c.dataset.day !== todayKey)!;
    dropOn(col, { type: "event", id: "e" });
    await flush();
    expect(dayKey(new Date(store.events[0].starts_at))).toBe(col.dataset.day);
    const moved = new Date(store.events[0].starts_at);
    expect([moved.getHours(), moved.getMinutes()]).toEqual([10, 15]);
  });

  it("los eventos de varios días salen unidos de un día al siguiente", () => {
    const start = new Date();
    const end = new Date(start.getFullYear(), start.getMonth(), start.getDate() + 2, 12);
    const { shell } = mount("calendario", calendarSection, (s) => {
      s.events = [newEvent("Viaje", new Date(start.getFullYear(), start.getMonth(), start.getDate(), 9), { end, id: "v" })];
      s.loaded.events = true;
    });
    const spans = [...shell.body.querySelectorAll(".cal-tg-allday-cell .cal-chip.is-event")].map((c) => [...c.classList].find((k) => k.startsWith("span-")));
    expect(spans).toContain("span-start");
    expect(spans).toContain("span-mid");
    expect(spans).toContain("span-end");
  });

  it("crea un recordatorio desde la paleta, sale con su campana en la hora y se marca como hecho", async () => {
    const { shell, store, calls } = mount("calendario", calendarSection, (s) => (s.loaded.events = true));
    store.raise("new-reminder");
    expect(shell.body.querySelector("form.cal-form")?.getAttribute("data-kind")).toBe("reminder");
    typeInto(shell.body.querySelector<HTMLInputElement>('input[aria-label="Título"]')!, "Llamar al banco");
    typeInto(shell.body.querySelector<HTMLInputElement>('input[aria-label="Hora"]')!, "16:45");
    submit(shell);
    await flush();
    expect(store.reminders).toHaveLength(1);
    expect(store.reminders[0]).toMatchObject({ title: "Llamar al banco", done: false });
    expect(new Date(store.reminders[0].remind_at).getHours()).toBe(16);
    expect(calls.at(-1)).toMatchObject({ table: "reminders", op: "upsert" });

    click(shell.body.querySelector('input[aria-label="Marcar «Llamar al banco» como hecho"]'));
    await flush();
    expect(store.reminders[0].done).toBe(true);
    expect(new Date(store.reminders[0].updated_at).getTime()).toBeGreaterThan(new Date(store.reminders[0].created_at).getTime());
    click(overlay(shell).querySelector(".cal-close"));
    const block = shell.body.querySelector(".cal-block.is-reminder")!;
    expect(block.querySelector(".cal-bell")).not.toBeNull();
    expect(block.classList.contains("is-done")).toBe(true);
  });

  it("no deja crear un recordatorio sin título", () => {
    const { shell, store } = mount("calendario", calendarSection);
    store.raise("new-reminder");
    submit(shell);
    expect(shell.body.querySelector(".cal-form .form-error")?.textContent).toBe("Escribe qué quieres recordar.");
    expect(store.reminders).toHaveLength(0);
  });

  it("los hábitos de hoy se marcan y se desmarcan con un clic, y se suben con su día", async () => {
    const { shell, store, calls } = mount("calendario", calendarSection, (s) => {
      s.habits = [newHabit("Estirar", { id: "h1", now: weekAgo })];
      s.loaded.events = true;
    });
    const today = dayKey(new Date());
    const chip = () => shell.body.querySelector<HTMLElement>(`.cal-tg-allday-cell[data-day="${today}"] .cal-chip.is-habit`)!;
    expect(chip().textContent).toContain("Estirar");
    click(chip());
    await flush();
    expect(store.habitChecks).toMatchObject([{ habit_id: "h1", day: today, done: true }]);
    expect(calls.at(-1)).toMatchObject({ table: "habit_checks", op: "upsert" });
    expect(chip().classList.contains("is-done")).toBe(true);
    expect(isOpen(shell)).toBe(false); // marcar un hábito no abre el día
    click(chip());
    await flush();
    expect(store.habitChecks[0].done).toBe(false);
    expect(new Date(store.habitChecks[0].updated_at).getTime()).toBeGreaterThan(0);
  });

  it("un hábito con hora de aviso sale en la columna de horas y el del mes se resume en «Hábitos 1/2»", async () => {
    const { shell } = mount("calendario", calendarSection, (s) => {
      s.habits = [newHabit("Beber agua", { id: "a", now: weekAgo, remindAt: 9 * 60 }), newHabit("Leer", { id: "b", now: weekAgo, position: 1 })];
      s.habitChecks = [{ habit_id: "a", day: dayKey(new Date()), done: true, updated_at: new Date().toISOString() }];
      s.loaded.events = true;
    });
    expect(shell.body.querySelector(".cal-block.is-habit .cal-block-title")?.textContent).toBe("Beber agua");
    monthView(shell);
    const today = dayKey(new Date());
    expect(shell.body.querySelector(`.cal-cell[data-day="${today}"] .cal-chip.is-summary .cal-chip-title`)?.textContent).toBe("Hábitos 1/2");
  });

  it("no deja marcar un hábito de un día futuro desde el día expandido", () => {
    const { shell } = mount("calendario", calendarSection, (s) => {
      s.habits = [newHabit("Estirar", { id: "h1", now: weekAgo })];
    });
    const tomorrow = new Date();
    tomorrow.setDate(tomorrow.getDate() + 1);
    click(shell.body.querySelector(`.cal-tg-day[data-today="false"][aria-label*=" ${tomorrow.getDate()} "]`));
    expect(shell.body.querySelector<HTMLInputElement>('.cal-expand input[aria-label^="Marcar el hábito"]')?.disabled).toBe(true);
  });

  it("crea un hábito con sus días y la hora del aviso", async () => {
    const { shell, store, calls } = mount("calendario", calendarSection);
    store.raise("new-habit");
    typeInto(shell.body.querySelector<HTMLInputElement>('input[aria-label="Título"]')!, "Correr");
    for (const day of ["sábado", "domingo"]) click(shell.body.querySelector(`.cal-wd[aria-label="${day}"]`)); // fuera sábado y domingo
    typeInto(shell.body.querySelector<HTMLInputElement>('input[aria-label="Hora del aviso (opcional)"]')!, "07:30");
    submit(shell);
    await flush();
    expect(store.habits).toHaveLength(1);
    expect(store.habits[0]).toMatchObject({ name: "Correr", weekdays: 31, remind_at: 450 });
    expect(calls.at(-1)).toMatchObject({ table: "habits", op: "upsert" });
  });

  it("un hábito sin días elegidos no se crea", () => {
    const { shell, store } = mount("calendario", calendarSection);
    store.raise("new-habit");
    typeInto(shell.body.querySelector<HTMLInputElement>('input[aria-label="Título"]')!, "Nada");
    for (const b of shell.body.querySelectorAll(".cal-wd")) click(b);
    submit(shell);
    expect(shell.body.querySelector(".cal-form .form-error")?.textContent).toBe("Elige al menos un día.");
    expect(store.habits).toHaveLength(0);
  });

  it("«Mostrar» enseña cuántos hay de cada clase y las casillas esconden o enseñan cada una", () => {
    const { shell } = mount("calendario", calendarSection, (s) => {
      s.events = [newEvent("Reunión", at(10), { id: "e" })];
      s.reminders = [newReminder("Pagar el agua", at(12), { id: "r" })];
      s.tasks = [{ ...newTask("Entregar informe", { id: "t" }), due: at(14).toISOString() }];
      s.loaded.events = true;
    });
    expect([...shell.body.querySelectorAll(".cal-show .cal-opt-name")].map((e) => e.textContent)).toEqual(["Eventos", "Tareas", "Recordatorios", "Hábitos"]);
    expect([...shell.body.querySelectorAll(".cal-show .cal-opt-count")].map((e) => e.textContent)).toEqual(["1", "1", "1", "0"]);
    expect(titleOf(shell)).toEqual(["Reunión", "Pagar el agua", "Entregar informe"]);
    click(shell.body.querySelector('input[aria-label="Mostrar recordatorios"]'));
    expect(titleOf(shell)).toEqual(["Reunión", "Entregar informe"]);
    click(shell.body.querySelector('input[aria-label="Mostrar eventos"]'));
    expect(titleOf(shell)).toEqual(["Entregar informe"]);
    click(shell.body.querySelector('input[aria-label="Mostrar recordatorios"]'));
    expect(titleOf(shell)).toEqual(["Pagar el agua", "Entregar informe"]);
  });

  it("el enunciado resume lo de hoy: eventos, entregas, recordatorios y hábitos", () => {
    const { shell } = mount("calendario", calendarSection, (s) => {
      s.events = [newEvent("Reunión", at(10), { id: "e" })];
      s.reminders = [newReminder("Pagar", at(12), { id: "r" })];
      s.habits = [newHabit("Estirar", { id: "h", now: weekAgo })];
      s.loaded.events = true;
    });
    expect(shell.root.textContent).toMatch(/Hoy: 1 evento, 1 recordatorio y 1 hábito por cumplir\./);
  });

  it("una orden «abrir día» (de la paleta) abre ese día", () => {
    const { shell, store } = mount("calendario", calendarSection);
    store.raise("open-day", "2026-12-24");
    expect(isOpen(shell)).toBe(true);
    expect(overlay(shell).querySelector(".cal-day-title")?.textContent).toMatch(/24 de diciembre de 2026/);
  });

  it("pulsar una pastilla del mes abre su día con el evento para editarlo", () => {
    const { shell } = mount("calendario", calendarSection, (s) => {
      s.events = [newEvent("Cita", at(10), { id: "e" })];
      s.loaded.events = true;
    });
    monthView(shell);
    click(shell.body.querySelector(".cal-chip.is-event"));
    expect(isOpen(shell)).toBe(true);
    expect(shell.body.querySelector(".cal-compose h3")?.textContent).toBe("Editar evento");
    expect(shell.body.querySelector<HTMLInputElement>('input[aria-label="Título"]')?.value).toBe("Cita");
  });

  it("el «+N más» del mes expande el día con todo", () => {
    const { shell } = mount("calendario", calendarSection, (s) => {
      s.events = ["A", "B", "C", "D", "E"].map((n, i) => newEvent(n, at(8 + i), { id: n }));
      s.loaded.events = true;
    });
    monthView(shell);
    expect(shell.body.querySelector(".cal-more")?.textContent).toBe("+2 más");
    click(shell.body.querySelector(".cal-more"));
    expect(isOpen(shell)).toBe(true);
    expect(overlay(shell).querySelectorAll(".cal-entry")).toHaveLength(5);
  });
});



// ---------------------------------------------------------------------------------------------------------------------
describe("Finanzas", () => {
  const setup = (s: Store) => {
    s.loaded.finance = true;
    s.financeCategories = [newCategory("Comida", "expense", "#ff5a1f", new Date(), "c1"), newCategory("Sueldo", "income", "#c8f73a", new Date(), "c2")];
  };
  const submitForm = (shell: Shell) => shell.body.querySelector<HTMLFormElement>("form.fin-form")!.dispatchEvent(new Event("submit", { cancelable: true }));

  it("registra un gasto con su categoría y actualiza el resumen del mes", async () => {
    const { shell, store, calls } = mount("finanzas", financeSection, setup);
    typeInto(shell.body.querySelector<HTMLInputElement>('input[aria-label="Importe"]')!, "1,250.50");
    typeInto(shell.body.querySelector<HTMLSelectElement>('select[aria-label="Categoría"]')!, "c1", "change");
    typeInto(shell.body.querySelector<HTMLInputElement>('input[aria-label="Descripción"]')!, "Súper");
    submitForm(shell);
    await flush();
    expect(store.financeEntries).toHaveLength(1);
    expect(store.financeEntries[0]).toMatchObject({ kind: "expense", amount_cents: 125050, category_id: "c1", description: "Súper", currency: "MXN" });
    expect(calls.at(-1)).toMatchObject({ table: "finance_entries", op: "upsert" });
    const summary = shell.body.querySelector(".fin-summary")!.textContent!;
    expect(summary).toMatch(/Gastos.*1,250\.50/);
    expect(summary).toMatch(/Balance.*-.*1,250\.50/);
    expect(shell.body.querySelector(".fin-row.is-expense")?.textContent).toContain("Comida");
  });

  it("al elegir «Ingreso» la lista de categorías cambia a las de ingresos", () => {
    const { shell } = mount("finanzas", financeSection, setup);
    const kind = shell.body.querySelector<HTMLSelectElement>('select[aria-label="Tipo"]')!;
    const names = () => [...shell.body.querySelectorAll<HTMLOptionElement>('select[aria-label="Categoría"] option')].map((o) => o.textContent);
    expect(names()).toEqual(["Sin categoría", "Comida"]);
    typeInto(kind, "income", "change");
    expect(names()).toEqual(["Sin categoría", "Sueldo"]);
  });

  it("rechaza un importe vacío, cero o inválido, y no guarda nada", () => {
    const { shell, store } = mount("finanzas", financeSection, setup);
    for (const bad of ["", "0", "abc", "-5"]) {
      typeInto(shell.body.querySelector<HTMLInputElement>('input[aria-label="Importe"]')!, bad);
      submitForm(shell);
      expect(shell.body.querySelector(".fin-form .form-error")?.textContent).toMatch(/importe mayor que cero/);
    }
    expect(store.financeEntries).toHaveLength(0);
  });

  it("sin categorías ofrece crear las básicas", async () => {
    const { shell, store } = mount("finanzas", financeSection, (s) => (s.loaded.finance = true));
    click(byText(shell.body, "button", "Crear las básicas"));
    await flush();
    expect(store.financeCategories.length).toBeGreaterThanOrEqual(9);
    expect(store.financeCategories.map((c) => c.name)).toContain("Comida");
  });

  it("borrar un movimiento lo quita de la lista y lo sube como borrado suave", async () => {
    vi.spyOn(window, "confirm").mockReturnValue(true);
    const { shell, store, calls } = mount("finanzas", financeSection, setup);
    typeInto(shell.body.querySelector<HTMLInputElement>('input[aria-label="Importe"]')!, "99");
    submitForm(shell);
    await flush();
    click(shell.body.querySelector('.fin-actions button[aria-label^="Borrar"]'));
    await flush();
    expect(store.financeEntries).toHaveLength(0);
    expect((calls.at(-1)!.payload as Row[])[0].deleted_at).not.toBeNull();
  });

  it("una orden «nuevo movimiento» lleva el foco al importe", () => {
    const { shell, store } = mount("finanzas", financeSection, setup);
    store.raise("new-entry");
    expect(document.activeElement).toBe(shell.body.querySelector('input[aria-label="Importe"]'));
  });
});

// ---------------------------------------------------------------------------------------------------------------------
describe("Contraseñas", () => {
  const item = (id: string, service: string, patch: Partial<VaultItem> = {}): VaultItem => ({ id, service, email: "", username: "", password: "", url: "", notes: "", created_at: "", updated_at: "", ...patch });

  /** Una sesión de bóveda de mentira con el estado que se pida. */
  function fakeVault(state: VaultSession["state"], items: VaultItem[] = []) {
    const listeners = new Set<() => void>();
    const vault = {
      state, items, broken: 0, error: "",
      on: (fn: () => void) => (listeners.add(fn), () => listeners.delete(fn)),
      refresh: vi.fn(async () => {}),
      create: vi.fn(async () => {}),
      unlock: vi.fn(async (pw: string) => pw === "buena-maestra-123"),
      lock: vi.fn(),
      add: vi.fn(async (input: Partial<VaultItem> & { service: string }) => item("new", input.service, input)),
      update: vi.fn(),
      remove: vi.fn(async () => {}),
    };
    return vault as unknown as VaultSession & typeof vault;
  }

  it("sin bóveda pide crear la contraseña maestra, y avisa de que no hay recuperación", () => {
    const vault = fakeVault("none");
    const { shell } = mount("contrasenas", vaultSection, undefined, { vault });
    expect(shell.body.textContent).toContain("Crear tu bóveda");
    expect(shell.body.textContent).toContain("no hay forma de recuperar");
  });

  it("al crear exige 12 caracteres, que coincidan y que marques que entiendes que no hay recuperación", async () => {
    const vault = fakeVault("none");
    const { shell } = mount("contrasenas", vaultSection, undefined, { vault });
    const form = shell.body.querySelector<HTMLFormElement>("form.vault-card")!;
    const pw = shell.body.querySelector<HTMLInputElement>('input[aria-label="Contraseña maestra"]')!;
    const again = shell.body.querySelector<HTMLInputElement>('input[aria-label="Repite la contraseña maestra"]')!;
    const ack = shell.body.querySelector<HTMLInputElement>("#vault-ack")!;
    const error = () => shell.body.querySelector(".form-error")?.textContent;
    typeInto(pw, "corta");
    form.dispatchEvent(new Event("submit", { cancelable: true }));
    expect(error()).toMatch(/al menos 12/);
    typeInto(pw, "una-maestra-bien-larga");
    typeInto(again, "otra-distinta-larga-");
    form.dispatchEvent(new Event("submit", { cancelable: true }));
    expect(error()).toMatch(/no coinciden/);
    typeInto(again, "una-maestra-bien-larga");
    form.dispatchEvent(new Event("submit", { cancelable: true }));
    expect(error()).toMatch(/no hay recuperación/);
    ack.checked = true;
    form.dispatchEvent(new Event("submit", { cancelable: true }));
    await flush();
    expect(vault.create).toHaveBeenCalledWith("una-maestra-bien-larga");
  });

  it("bloqueada pide la maestra; si es incorrecta lo dice y no abre", async () => {
    const vault = fakeVault("locked");
    const { shell } = mount("contrasenas", vaultSection, undefined, { vault });
    const form = shell.body.querySelector<HTMLFormElement>("form.vault-card")!;
    typeInto(shell.body.querySelector<HTMLInputElement>('input[aria-label="Contraseña maestra"]')!, "mala-mala-mala");
    form.dispatchEvent(new Event("submit", { cancelable: true }));
    await flush();
    expect(shell.body.querySelector(".form-error")?.textContent).toBe("La contraseña maestra no es correcta.");
    expect(vault.unlock).toHaveBeenCalledWith("mala-mala-mala");
  });

  it("abierta lista las entradas por servicio, busca, y la contraseña está oculta hasta pulsar «Mostrar»", () => {
    const vault = fakeVault("unlocked", [item("1", "Netflix", { email: "ana@correo.com", password: "Sup3r-clave" }), item("2", "Banco", { username: "ana.perez" })]);
    const { shell } = mount("contrasenas", vaultSection, undefined, { vault });
    expect([...shell.body.querySelectorAll(".vault-service")].map((e) => e.textContent)).toEqual(["Banco", "Netflix"]);
    typeInto(shell.body.querySelector<HTMLInputElement>('input[aria-label="Buscar en la bóveda"]')!, "net");
    expect([...shell.body.querySelectorAll(".vault-service")].map((e) => e.textContent)).toEqual(["Netflix"]);
    click(shell.body.querySelector(".vault-head"));
    expect(shell.body.textContent).toContain("ana@correo.com");
    expect(shell.body.textContent).not.toContain("Sup3r-clave"); // oculta
    expect(shell.body.querySelector(".vault-secret")?.getAttribute("data-shown")).toBe("false");
    click(byText(shell.body, "button", "Mostrar"));
    expect(shell.body.textContent).toContain("Sup3r-clave");
    click(byText(shell.body, "button", "Ocultar"));
    expect(shell.body.textContent).not.toContain("Sup3r-clave");
  });

  it("añade una entrada con el servicio, valida la web, y «Bloquear» bloquea la bóveda", async () => {
    const vault = fakeVault("unlocked");
    const { shell } = mount("contrasenas", vaultSection, undefined, { vault });
    click(byText(shell.body, "button", "Nueva"));
    const form = shell.body.querySelector<HTMLFormElement>("form.vault-form")!;
    form.dispatchEvent(new Event("submit", { cancelable: true }));
    expect(form.querySelector(".form-error")?.textContent).toMatch(/nombre del servicio/);
    typeInto(form.querySelector<HTMLInputElement>('input[aria-label="Servicio o aplicación"]')!, "Spotify");
    form.dispatchEvent(new Event("submit", { cancelable: true }));
    expect(form.querySelector(".form-error")?.textContent).toMatch(/al menos el correo/);
    typeInto(form.querySelector<HTMLInputElement>('input[aria-label="Correo"]')!, "yo@correo.com");
    typeInto(form.querySelector<HTMLInputElement>('input[aria-label="Dirección web"]')!, "javascript:alert(1)");
    form.dispatchEvent(new Event("submit", { cancelable: true }));
    expect(form.querySelector(".form-error")?.textContent).toMatch(/no es válida/);
    typeInto(form.querySelector<HTMLInputElement>('input[aria-label="Dirección web"]')!, "spotify.com");
    form.dispatchEvent(new Event("submit", { cancelable: true }));
    await flush();
    expect(vault.add).toHaveBeenCalledWith(expect.objectContaining({ service: "Spotify", email: "yo@correo.com", url: "https://spotify.com" }));
    click(byText(shell.body, "button", "Bloquear"));
    expect(vault.lock).toHaveBeenCalled();
  });

  it("el generador rellena la contraseña con un valor al azar del largo elegido", () => {
    const vault = fakeVault("unlocked");
    const { shell } = mount("contrasenas", vaultSection, undefined, { vault });
    click(byText(shell.body, "button", "Nueva"));
    const pass = shell.body.querySelector<HTMLInputElement>('input[aria-label="Contraseña"]')!;
    expect(pass.value).toBe("");
    typeInto(shell.body.querySelector<HTMLSelectElement>('select[aria-label="Largo de la contraseña generada"]')!, "32", "change");
    click(byText(shell.body, "button", "Generar"));
    expect(pass.value).toHaveLength(32);
  });

  it("el enunciado de la sección sigue al estado de la bóveda", () => {
    const vault = fakeVault("locked");
    const { shell } = mount("contrasenas", vaultSection, undefined, { vault });
    expect(shell.root.querySelector(".tile-contrasenas .tile-statement")?.textContent).toMatch(/bloqueada/);
  });
});
