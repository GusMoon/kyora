import { h } from "../ui/dom";
import { icon, deviceIconName } from "../ui/icons";
import { hackText } from "../ui/fx";
import { explainError } from "../supabase";
import { formatSize } from "../data/music";
import { LIVE_TEXT } from "../status";
import { listCommands, parseCommand, suggestCommands, type ChatCommand } from "../data/commands";
import { attachmentUrl, clearConversation, deleteMessages, deviceLabel, draftMessage, listMessages, mergeMessages, sendMessage, sendPayload, type Message } from "../data/chat";
import { checkFiles, uploadAttachments } from "../data/attachments";
import type { Ctx, Section } from "./context";

const IMAGE_PREVIEW_MAX = 10 * 1024 * 1024; // las fotos de más de 10 MB no se descargan solas para la vista previa

const PAGE = 50; // mensajes por tanda al cargar hacia atrás
const FIRST_LOAD = 100; // los que pide main.ts al abrir

export function chatStatement(messages: Message[], loaded: boolean, error?: string): string {
  if (error) return error;
  if (!loaded) return "Abriendo la conversación General.";
  if (!messages.length) return "La conversación General está vacía. Escribe el primer mensaje.";
  return `Conversación General: ${messages.length === 1 ? "1 mensaje" : `${messages.length} mensajes`} con la PC y el móvil.`;
}

const longDay = new Intl.DateTimeFormat("es", { day: "numeric", month: "long" });
const longDayYear = new Intl.DateTimeFormat("es", { day: "numeric", month: "long", year: "numeric" });
const hourFmt = new Intl.DateTimeFormat("es", { hour: "2-digit", minute: "2-digit", hour12: false });

/** «Hoy», «Ayer», «30 de octubre» (con el año si no es este), como los separadores del chat de Kyra. */
export function dayLabel(iso: string, now = new Date()): string {
  const d = new Date(iso);
  const day = (x: Date) => new Date(x.getFullYear(), x.getMonth(), x.getDate()).getTime();
  const diff = Math.round((day(now) - day(d)) / 86_400_000);
  if (diff === 0) return "Hoy";
  if (diff === 1) return "Ayer";
  return (d.getFullYear() === now.getFullYear() ? longDay : longDayYear).format(d);
}

export function timeLabel(iso: string): string {
  return hourFmt.format(new Date(iso));
}

export type ChatItem = { type: "day"; label: string; key: string } | { type: "msg"; message: Message };

/** Los mensajes con un separador antes del primero de cada día. */
export function withDays(messages: Message[], now = new Date()): ChatItem[] {
  const items: ChatItem[] = [];
  let last = "";
  for (const m of messages) {
    const key = new Date(m.sent_at).toDateString();
    if (key !== last) {
      items.push({ type: "day", label: dayLabel(m.sent_at, now), key });
      last = key;
    }
    items.push({ type: "msg", message: m });
  }
  return items;
}

export const chatSection: Section = (ctx: Ctx) => {
  const { store, shell, client, status } = ctx;
  const cleanups: (() => void)[] = [];
  const baseline = new Set(store.messages.map((m) => m.id)); // los que ya estaban: aparecen sin efecto
  const typed = new Set<string>(); // los nuevos que ya se escribieron con el efecto
  let hasOlder = store.messages.length >= FIRST_LOAD;
  let loadingOlder = false;
  let confirming: string | null = null; // el mensaje que pide confirmación para borrarse
  let clearing: "idle" | "confirm" | "busy" = "idle"; // el estado de «Vaciar chat»
  let staged: File[] = []; // los archivos elegidos que aún no se envían
  const pendingFiles = new Map<string, File[]>(); // los archivos de un mensaje que se está enviando o falló: para reintentar sin elegirlos otra vez
  const progress = new Map<string, string>(); // «subiendo 2/3» por mensaje
  const previews = new Map<string, string>(); // la URL firmada de las fotos ya pedidas (por ruta)
  const previewing = new Set<string>(); // las que se están pidiendo ahora

  const liveText = h("span", { class: "chat-live-text" });
  const liveBox = h("p", { class: "chat-live", role: "status" }, h("span", { class: "chat-live-dot", "aria-hidden": "true" }), liveText);
  const tools = h("div", { class: "chat-tools" });
  const problem = h("p", { class: "form-error", role: "alert" });
  const bar = h("div", { class: "chat-bar" }, liveBox, tools, problem);
  const older = h("p", { class: "chat-older", hidden: true }, "> cargando más…");
  const log = h("ol", { class: "chat-log", "aria-label": "Mensajes", "aria-live": "polite" });
  const scroller = h("div", { class: "chat-scroll", tabindex: 0 }, older, log);

  let refreshSuggestHook: () => void = () => {}; // lo pone el compositor más abajo: refresca las sugerencias al llegar los comandos
  let commands: ChatCommand[] | null = null; // los comandos «/» de este usuario; null mientras no llegan
  let alive = true;
  cleanups.push(() => (alive = false));
  async function loadCommands() {
    try {
      const list = await listCommands(client);
      if (alive) {
        commands = list;
        refreshSuggestHook();
      }
    } catch {
      /* sin comandos cargados, escribir «/algo» avisa en vez de mandarlo como mensaje */
    }
  }
  void loadCommands();

  /** Envía un mensaje. Con archivos, primero los sube a Storage y luego manda el mensaje con sus adjuntos; si algo falla,
   * el mensaje queda «no se envió» con sus archivos guardados para reintentar (mismo id: nunca se duplica). */
  async function deliver(payload: ReturnType<typeof sendPayload>, files: File[] = [], retry = false) {
    const id = payload.p_id;
    if (retry) store.messages = store.messages.map((m) => (m.id === id ? { ...m, local: "sending" as const } : m));
    else store.messages = mergeMessages(store.messages, [draftMessage(payload)]);
    if (files.length) pendingFiles.set(id, files);
    store.emit("messages");
    scroller.scrollTop = scroller.scrollHeight;
    try {
      let toSend = payload;
      if (files.length) {
        const uploaded = await uploadAttachments(client, ctx.userId, payload.p_conversation_id, id, files, (done, total) => {
          progress.set(id, done >= total ? "enviando…" : `subiendo ${done + 1}/${total}`);
          render();
        });
        toSend = { ...payload, p_attachments: uploaded };
      }
      const sent = await sendMessage(client, toSend);
      store.messages = mergeMessages(store.messages, [sent]);
      pendingFiles.delete(id);
    } catch (err) {
      problem.textContent = `No se envió el mensaje. ${explainError(err)}`;
      store.messages = store.messages.map((m) => (m.id === id ? { ...m, local: "failed" as const } : m));
    } finally {
      progress.delete(id);
    }
    store.emit("messages");
  }

  /** Pide la URL firmada de una foto para mostrarla en el mensaje (una sola vez por archivo). */
  function loadPreview(path: string, img: HTMLImageElement, size: number) {
    const cached = previews.get(path);
    if (cached) {
      img.src = cached;
      return;
    }
    if (previewing.has(path) || size > IMAGE_PREVIEW_MAX) return;
    previewing.add(path);
    void attachmentUrl(client, path)
      .then((url) => {
        previews.set(path, url);
        if (alive && img.isConnected) img.src = url;
      })
      .catch(() => {
        /* sin vista previa: queda el nombre del archivo */
      })
      .finally(() => previewing.delete(path));
  }

  async function openAttachment(path: string) {
    try {
      window.open(await attachmentUrl(client, path), "_blank", "noopener");
    } catch (err) {
      alert(explainError(err));
    }
  }

  /** Borra un mensaje (y los archivos de sus adjuntos) del servidor de verdad. */
  async function removeOne(m: Message) {
    problem.textContent = "";
    try {
      const gone = await deleteMessages(client, [m.id]);
      if (!gone.length) throw new Error("El servidor no dejó borrar este mensaje.");
      store.messages = store.messages.filter((x) => x.id !== m.id);
      store.files = store.files.filter((f) => f.messageId !== m.id);
      store.emit("files");
    } catch (err) {
      problem.textContent = `No se pudo borrar el mensaje: ${err instanceof Error && err.message.startsWith("El servidor") ? err.message : explainError(err)}`;
    } finally {
      confirming = null;
      store.emit("messages");
    }
  }

  /** Vacía toda la conversación (mensajes y archivos) del servidor. */
  async function clearAll() {
    if (!store.conversationId) return;
    problem.textContent = "";
    clearing = "busy";
    renderTools();
    try {
      const res = await clearConversation(client, store.conversationId);
      store.messages = store.messages.filter((m) => m.local);
      store.files = store.files.filter((f) => !f.messageId);
      hasOlder = false;
      if (res.deleted < res.total) problem.textContent = `Se borraron ${res.deleted} de ${res.total} mensajes: el servidor no dejó borrar el resto.`;
      store.emit("files");
    } catch (err) {
      problem.textContent = `No se pudo vaciar el chat: ${explainError(err)}`;
    } finally {
      clearing = "idle";
      store.emit("messages");
    }
  }

  function renderTools() {
    const n = store.messages.filter((m) => !m.local).length;
    if (clearing === "busy") {
      tools.replaceChildren(h("span", { class: "chat-confirm", role: "status" }, "Borrando del servidor…"));
    } else if (clearing === "confirm") {
      tools.replaceChildren(
        h("span", { class: "chat-confirm", role: "alert" }, `¿Borrar ${n === 1 ? "el mensaje" : `los ${n} mensajes`} y sus archivos del servidor? No se puede deshacer.`),
        h("button", { class: "btn-edge is-danger", type: "button", onClick: () => void clearAll() }, icon("trash", "icon"), "Sí, vaciar todo"),
        h(
          "button",
          {
            class: "btn-edge",
            type: "button",
            onClick: () => {
              clearing = "idle";
              renderTools();
            },
          },
          "Cancelar",
        ),
      );
    } else {
      tools.replaceChildren(
        h(
          "button",
          {
            class: "btn-edge is-danger",
            type: "button",
            disabled: n === 0,
            onClick: () => {
              clearing = "confirm";
              renderTools();
            },
          },
          icon("trash", "icon"),
          "Vaciar chat",
        ),
      );
    }
  }

  function footer(m: Message, mine: boolean): HTMLElement {
    const foot = h("p", { class: "msg-foot" }, h("time", { datetime: m.sent_at }, timeLabel(m.sent_at)));
    if (m.local === "sending") foot.append(h("span", { class: "msg-state" }, progress.get(m.id) ?? "en cola"));
    else if (m.local === "failed") {
      const files = pendingFiles.get(m.id) ?? [];
      foot.append(
        h("span", { class: "msg-error" }, "ERR: no se envió"),
        h("button", { class: "btn-edge", type: "button", onClick: () => void deliver({ p_id: m.id, p_conversation_id: m.conversation_id, p_body: m.body ?? "", p_sent_at: m.sent_at, p_device: "web", p_attachments: [] }, files, true) }, "Reintentar"),
      );
    } else if (mine) foot.append(h("span", { class: "msg-check", "aria-label": "enviado" }, "✓"));
    if (!m.local) {
      if (confirming === m.id) {
        foot.append(
          h("span", { class: "msg-error" }, "¿Borrar del servidor?"),
          h("button", { class: "btn-edge is-danger", type: "button", onClick: () => void removeOne(m) }, "Sí"),
          h(
            "button",
            {
              class: "btn-edge",
              type: "button",
              onClick: () => {
                confirming = null;
                render();
              },
            },
            "No",
          ),
        );
      } else {
        foot.append(
          h(
            "button",
            {
              class: "btn-edge is-danger msg-del",
              type: "button",
              "aria-label": `Borrar el mensaje de las ${timeLabel(m.sent_at)}`,
              onClick: () => {
                confirming = m.id;
                render();
              },
            },
            icon("trash", "icon"),
            "Borrar",
          ),
        );
      }
    }
    return foot;
  }

  /** Un adjunto: las fotos se ven en pequeño (pulsar la abre entera en otra pestaña); lo demás es un enlace con nombre y tamaño. */
  function attachmentEl(m: Message, a: Message["attachments"][number]): HTMLElement {
    const link = h("button", { class: "msg-file", type: "button", disabled: !!m.local, onClick: () => void openAttachment(a.storage_path) }, h("strong", {}, ":: "), a.file_name, h("span", { class: "msg-size" }, formatSize(a.size_bytes)));
    if (!a.mime_type?.toLowerCase().startsWith("image/") || m.local) return h("li", {}, link);
    const img = h("img", { class: "msg-img", alt: a.file_name, loading: "lazy" });
    loadPreview(a.storage_path, img, a.size_bytes);
    return h("li", {}, h("button", { class: "msg-thumb", type: "button", "aria-label": `Abrir ${a.file_name}`, onClick: () => void openAttachment(a.storage_path) }, img), link);
  }

  function messageEl(m: Message): HTMLElement {
    const mine = m.sender_device === "web";
    const body = m.body ? h("p", { class: "msg-text" }, m.body) : null;
    const el = h(
      "li",
      { class: `msg${mine ? " is-mine" : ""}`, "data-device": m.sender_device },
      h("span", { class: "msg-device", title: deviceLabel(m.sender_device) }, icon(deviceIconName(m.sender_device)), h("span", { class: "sr-only" }, `${deviceLabel(m.sender_device)}: `)),
      h(
        "div",
        { class: "msg-main" },
        body,
        m.attachments?.length
          ? h("ul", { class: "msg-files" }, m.attachments.map((a) => attachmentEl(m, a)))
          : null,
        footer(m, mine),
      ),
    );
    // los que llegan con el chat abierto se escriben con el efecto, una sola vez
    if (body && !baseline.has(m.id) && !typed.has(m.id) && !m.local) {
      typed.add(m.id);
      queueMicrotask(() => void hackText(body, m.body ?? ""));
    }
    return el;
  }

  function render() {
    shell.setStatement(chatStatement(store.messages, store.loaded.messages, store.errors.messages));
    if (clearing !== "busy") renderTools();
    const atBottom = scroller.scrollHeight - scroller.scrollTop - scroller.clientHeight < 60;
    if (!store.messages.length) {
      const lines = [h("li", { class: "chat-empty" }, store.loaded.messages ? "> sin registros." : "> cargando registros…")];
      if (store.loaded.messages) lines.push(h("li", { class: "chat-empty" }, "> lo que escribas desde la PC o desde el móvil se guarda aquí_"));
      log.replaceChildren(...lines);
      return;
    }
    log.replaceChildren(
      ...withDays(store.messages).map((item) =>
        item.type === "day" ? h("li", { class: "chat-day", "aria-hidden": "true" }, h("span", {}, item.label)) : messageEl(item.message),
      ),
    );
    if (atBottom) scroller.scrollTop = scroller.scrollHeight;
  }

  /** Al llegar arriba, pide los 50 anteriores sin mover lo que estás viendo. */
  async function loadOlder() {
    if (!hasOlder || loadingOlder || !store.conversationId) return;
    const oldest = store.messages.find((m) => !m.local);
    if (!oldest) return;
    loadingOlder = true;
    older.hidden = false;
    const before = scroller.scrollHeight;
    try {
      const fresh = await listMessages(client, store.conversationId, { before: oldest.sent_at, limit: PAGE });
      for (const m of fresh) baseline.add(m.id);
      hasOlder = fresh.length >= PAGE;
      if (fresh.length) {
        store.messages = mergeMessages(store.messages, fresh);
        store.emit("messages");
        scroller.scrollTop += scroller.scrollHeight - before;
      }
    } catch {
      hasOlder = true; // se reintenta al volver a subir
    } finally {
      loadingOlder = false;
      older.hidden = true;
    }
  }
  scroller.addEventListener("scroll", () => {
    if (scroller.scrollTop < 80) void loadOlder();
  });

  const text = h("textarea", { id: "chat-text", rows: 1, maxlength: 4000, placeholder: "escribe y pulsa ⏎", spellcheck: "true" });
  const send = h("button", { class: "chat-send", type: "submit", "aria-label": "Enviar" }, icon("enter"));
  // ----- archivos: el clip, arrastrar y soltar sobre el chat, y pegar una imagen
  const fileInput = h("input", { type: "file", multiple: true, hidden: true, id: "chat-files", "aria-label": "Elegir archivos para adjuntar" });
  const attach = h("button", { class: "chat-attach", type: "button", "aria-label": "Adjuntar archivos", title: "Adjuntar archivos (o suéltalos aquí)", onClick: () => fileInput.click() }, icon("paperclip"));
  const stagedList = h("ul", { class: "staged", "aria-label": "Archivos por enviar", hidden: true });
  const composer = h(
    "form",
    { class: "chat-composer" },
    stagedList,
    h("label", { for: "chat-text", class: "chat-prompt" }, h("span", { "aria-hidden": "true" }, ">"), h("span", { class: "sr-only" }, "Mensaje")),
    text,
    attach,
    send,
    fileInput,
  );
  const renderStaged = () => {
    stagedList.hidden = staged.length === 0;
    stagedList.replaceChildren(
      ...staged.map((f, i) =>
        h(
          "li",
          { class: "staged-item" },
          h("span", { class: "staged-name", title: f.name }, f.name),
          h("span", { class: "msg-size" }, formatSize(f.size)),
          h("button", { class: "btn-quiet", type: "button", "aria-label": `Quitar ${f.name}`, onClick: () => { staged = staged.filter((_, j) => j !== i); renderStaged(); grow(); text.focus(); } }, "Quitar"),
        ),
      ),
    );
  };
  function stage(files: File[]) {
    if (!files.length) return;
    const { accepted, errors } = checkFiles(files, staged);
    staged = [...staged, ...accepted];
    problem.textContent = errors.join(" ");
    renderStaged();
    grow();
    text.focus();
  }
  fileInput.addEventListener("change", () => {
    stage([...(fileInput.files ?? [])]);
    fileInput.value = "";
  });
  const hasFiles = (e: DragEvent) => !!e.dataTransfer && [...e.dataTransfer.types].includes("Files");
  const onDragOver = (e: DragEvent) => {
    if (!hasFiles(e)) return;
    e.preventDefault(); // sin esto el navegador abre el archivo en lugar de soltarlo
    shell.body.classList.add("is-dropping");
  };
  const onDragLeave = (e: DragEvent) => {
    if (e.relatedTarget === null || !(e.relatedTarget instanceof Node) || !shell.body.contains(e.relatedTarget)) shell.body.classList.remove("is-dropping");
  };
  const onDrop = (e: DragEvent) => {
    if (!hasFiles(e)) return;
    e.preventDefault();
    shell.body.classList.remove("is-dropping");
    stage([...(e.dataTransfer?.files ?? [])]);
  };
  shell.body.addEventListener("dragover", onDragOver);
  shell.body.addEventListener("dragleave", onDragLeave);
  shell.body.addEventListener("drop", onDrop);
  cleanups.push(() => {
    shell.body.removeEventListener("dragover", onDragOver);
    shell.body.removeEventListener("dragleave", onDragLeave);
    shell.body.removeEventListener("drop", onDrop);
    shell.body.classList.remove("is-dropping");
  });
  text.addEventListener("paste", (e) => {
    const files = [...(e.clipboardData?.files ?? [])];
    if (!files.length) return; // texto normal: se pega como siempre
    e.preventDefault();
    stage(files);
  });
  const grow = () => {
    send.disabled = !text.value.trim() && staged.length === 0;
    if (!text.isConnected) return; // sin estar en la página no se puede medir
    text.style.blockSize = "auto";
    if (text.scrollHeight) text.style.blockSize = `${Math.min(text.scrollHeight, 140)}px`; // hasta unas 5 líneas
  };
  grow();

  // ----- sugerencias al escribir «/»: una lista sobre el campo; el foco nunca sale del campo de texto
  const suggestList = h("ul", { class: "cmd-suggest", id: "chat-cmd-list", role: "listbox", "aria-label": "Comandos", hidden: true });
  composer.prepend(suggestList);
  text.setAttribute("role", "combobox");
  text.setAttribute("aria-autocomplete", "list");
  text.setAttribute("aria-controls", "chat-cmd-list");
  text.setAttribute("aria-expanded", "false");
  let suggestions: ChatCommand[] = [];
  let active = 0;
  let dismissed = ""; // el texto con el que se cerró con Esc: no se vuelve a abrir hasta que cambie

  function closeSuggest() {
    suggestions = [];
    suggestList.hidden = true;
    suggestList.replaceChildren();
    text.setAttribute("aria-expanded", "false");
    text.removeAttribute("aria-activedescendant");
  }
  function pick(c: ChatCommand) {
    text.value = `/${c.command} `;
    closeSuggest();
    grow();
    text.focus();
    text.setSelectionRange(text.value.length, text.value.length);
  }
  function renderSuggest() {
    suggestList.replaceChildren(
      ...suggestions.map((c, i) =>
        h(
          "li",
          {
            class: "cmd-option",
            role: "option",
            id: `chat-cmd-${c.command}`,
            "aria-selected": String(i === active),
            // mousedown + preventDefault: elegir con el ratón no le quita el foco al campo
            onMouseDown: (e: Event) => {
              e.preventDefault();
              pick(c);
            },
          },
          h("span", { class: "cmd-word" }, `/${c.command}`),
          h("span", { class: "cmd-name" }, c.name),
          h("span", { class: "cmd-url" }, c.url),
        ),
      ),
    );
    suggestList.hidden = false;
    text.setAttribute("aria-expanded", "true");
    text.setAttribute("aria-activedescendant", `chat-cmd-${suggestions[active].command}`);
  }
  function refreshSuggest() {
    const found = text.value === dismissed ? [] : suggestCommands(text.value, commands ?? []);
    if (!found.length) return closeSuggest();
    const keep = suggestions[active]?.id;
    suggestions = found;
    active = Math.max(0, found.findIndex((c) => c.id === keep));
    renderSuggest();
  }
  refreshSuggestHook = refreshSuggest;
  text.addEventListener("input", () => {
    grow();
    dismissed = "";
    refreshSuggest();
  });
  text.addEventListener("blur", closeSuggest);
  composer.addEventListener("submit", (e) => {
    e.preventDefault();
    const body = text.value.trim();
    if ((!body && !staged.length) || !store.conversationId) return;
    // con archivos elegidos, todo va como mensaje (un «/comando» con archivos es texto)
    if (staged.length) {
      const files = staged;
      staged = [];
      renderStaged();
      text.value = "";
      grow();
      problem.textContent = "";
      const placeholders = files.map((f) => ({ storage_path: "", file_name: f.name, mime_type: f.type || "application/octet-stream", size_bytes: f.size, width: null, height: null, duration_ms: null, thumb_path: null }));
      void deliver(sendPayload(store.conversationId, body, crypto.randomUUID(), new Date(), placeholders), files);
      return;
    }
    // «/comando»: abre la web que tiene configurada (Configuración → Comandos del chat) en lugar de mandar un mensaje
    const cmd = parseCommand(body, commands ?? []);
    if (cmd.kind !== "none") {
      if (commands === null) {
        problem.textContent = "Los comandos aún no se cargaron. Espera un momento y vuelve a intentarlo.";
        void loadCommands();
        return;
      }
      text.value = "";
      grow();
      if (cmd.kind === "unknown") {
        problem.textContent = `No existe el comando /${cmd.name}. Puedes crearlo en Configuración → Comandos del chat.`;
        return;
      }
      problem.textContent = "";
      window.open(cmd.command.url, "_blank", "noopener");
      return;
    }
    text.value = "";
    grow();
    void deliver(sendPayload(store.conversationId, body));
  });
  text.addEventListener("keydown", (e) => {
    if (suggestions.length && !e.isComposing) {
      const move = (by: number) => {
        e.preventDefault();
        active = (active + by + suggestions.length) % suggestions.length;
        renderSuggest();
      };
      if (e.key === "ArrowDown") return move(1);
      if (e.key === "ArrowUp") return move(-1);
      if (e.key === "Escape") {
        e.preventDefault();
        dismissed = text.value;
        return closeSuggest();
      }
      // Tab siempre completa; Enter completa salvo que ya esté escrito el comando entero (entonces lo ejecuta)
      if (e.key === "Tab" || (e.key === "Enter" && !e.shiftKey && text.value !== `/${suggestions[active].command}`)) {
        e.preventDefault();
        return pick(suggestions[active]);
      }
    }
    if (e.key === "Enter" && !e.shiftKey && !e.isComposing) {
      e.preventDefault();
      composer.requestSubmit();
    }
  });

  shell.body.append(h("div", { class: "chat" }, bar, scroller, composer));
  grow();
  render();
  scroller.scrollTop = scroller.scrollHeight;
  cleanups.push(store.on((area) => area === "messages" && render()));
  cleanups.push(
    status.on((st) => {
      liveBox.dataset.state = st.live;
      liveText.textContent = st.live === "connecting" ? "conectando…" : st.live === "live" ? "en línea" : LIVE_TEXT[st.live];
    }),
  );
  return () => {
    for (const fn of cleanups) fn();
  };
};
