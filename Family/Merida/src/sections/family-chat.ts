import { h } from "../ui/dom";
import { icon } from "../ui/icons";
import { explainError } from "../supabase";
import { formatSize } from "../data/music";
import { latestCreatedAt, type LiveState } from "../data/chat";
import { checkFiles, uploadAttachments } from "../data/attachments";
import {
  FAMILY_BUCKET,
  FAMILY_CONVERSATION,
  familyAttachmentUrl,
  familyDraft,
  familyMembers,
  familyPayload,
  familyStatement,
  listFamilyMessages,
  mergeFamily,
  nextExpiryIn,
  senderLabel,
  sendFamilyMessage,
  visibleMessages,
  watchFamily,
  type FamilyMember,
  type FamilyMessage,
  type FamilyPayload,
} from "../data/family-chat";
import { LIVE_TEXT } from "../status";
import { timeLabel, withDays } from "./chat";
import type { Ctx } from "./context";

const IMAGE_PREVIEW_MAX = 10 * 1024 * 1024; // las fotos de más de 10 MB no se descargan solas para la vista previa
const MIN_PRUNE_MS = 1000;
const MAX_PRUNE_MS = 60_000;

/** La vista del chat de la familia (mamá, papá y quien el administrador agregue): mensajes, imágenes, videos y documentos, que se
 * borran a las 24 horas, y los botones para llamar. Vive dentro de la sección Chat (pestaña «Familia»). */
export function familyChatView(ctx: Ctx): { el: HTMLElement; destroy: () => void } {
  const { client, shell } = ctx;
  const userId = ctx.userId;
  const cleanups: (() => void)[] = [];
  let alive = true;
  cleanups.push(() => (alive = false));

  let messages: FamilyMessage[] = [];
  let members: FamilyMember[] = [];
  let loaded = false;
  let error = "";
  let staged: File[] = [];
  const pendingFiles = new Map<string, File[]>(); // los archivos de un mensaje que se está enviando o falló: para reintentar
  const progress = new Map<string, string>();
  const urls = new Map<string, string>(); // las URL firmadas ya pedidas (por ruta)
  const asking = new Set<string>();

  const liveText = h("span", { class: "chat-live-text" });
  const liveBox = h("p", { class: "chat-live", role: "status" }, h("span", { class: "chat-live-dot", "aria-hidden": "true" }), liveText);
  const callTools = h("div", { class: "fam-call-tools" });
  const problem = h("p", { class: "form-error", role: "alert" });
  const note = h("p", { class: "fam-note" }, "Los mensajes, los archivos y las llamadas se borran a las 24 horas.");
  const bar = h("div", { class: "chat-bar fam-bar" }, liveBox, callTools, note, problem);
  const log = h("ol", { class: "chat-log", "aria-label": "Mensajes de la familia", "aria-live": "polite" });
  const scroller = h("div", { class: "chat-scroll", tabindex: 0 }, log);

  const isMember = () => members.length > 0;

  // ----- las llamadas (el panel flotante vive en main.ts; aquí solo los botones)
  function renderCallTools() {
    const calls = ctx.calls;
    const busy = !!calls && (calls.view.phase === "calling" || calls.view.phase === "incoming" || calls.view.phase === "active");
    const disabled = !calls || !isMember() || busy;
    callTools.replaceChildren(
      h("button", { class: "btn-edge", type: "button", "data-call-start": "audio", disabled, onClick: () => void calls?.start("audio") }, icon("call", "icon"), "Llamar"),
      h("button", { class: "btn-edge", type: "button", "data-call-start": "video", disabled, onClick: () => void calls?.start("video") }, icon("video", "icon"), "Videollamada"),
    );
  }
  if (ctx.calls) cleanups.push(ctx.calls.on(renderCallTools));

  // ----- los mensajes
  async function load() {
    try {
      members = await familyMembers(client);
      const fresh = await listFamilyMessages(client);
      messages = mergeFamily([], fresh);
      error = "";
    } catch (err) {
      error = `No se pudo abrir el chat de la familia. ${explainError(err)}`;
    }
    if (!alive) return;
    loaded = true;
    render();
    renderCallTools();
    scroller.scrollTop = scroller.scrollHeight;
  }

  async function catchUp() {
    try {
      const fresh = await listFamilyMessages(client, { after: latestCreatedAt(messages) });
      if (!alive || !fresh.length) return;
      messages = mergeFamily(messages, fresh);
      render();
    } catch {
      /* se vuelve a intentar con el siguiente aviso */
    }
  }

  /** Quita de la pantalla lo que ya cumplió 24 horas, justo cuando los cumple. */
  let pruneTimer: ReturnType<typeof setTimeout> | null = null;
  function schedulePrune() {
    if (pruneTimer) clearTimeout(pruneTimer);
    pruneTimer = null;
    const wait = nextExpiryIn(messages);
    if (wait === null) return;
    pruneTimer = setTimeout(() => {
      if (!alive) return;
      messages = visibleMessages(messages);
      render();
    }, Math.min(MAX_PRUNE_MS, Math.max(MIN_PRUNE_MS, wait)));
  }
  cleanups.push(() => {
    if (pruneTimer) clearTimeout(pruneTimer);
  });

  async function deliver(payload: FamilyPayload, files: File[] = [], retry = false) {
    const id = payload.p_id;
    if (retry) messages = messages.map((m) => (m.id === id ? { ...m, local: "sending" as const } : m));
    else messages = mergeFamily(messages, [familyDraft(payload, userId)]);
    if (files.length) pendingFiles.set(id, files);
    render();
    scroller.scrollTop = scroller.scrollHeight;
    try {
      let toSend = payload;
      if (files.length) {
        const uploaded = await uploadAttachments(
          client,
          userId,
          FAMILY_CONVERSATION,
          id,
          files,
          (done, total) => {
            progress.set(id, done >= total ? "enviando…" : `subiendo ${done + 1}/${total}`);
            render();
          },
          FAMILY_BUCKET,
        );
        toSend = { ...payload, p_attachments: uploaded };
      }
      const sent = await sendFamilyMessage(client, toSend);
      messages = mergeFamily(messages, [sent]);
      pendingFiles.delete(id);
    } catch (err) {
      problem.textContent = `No se envió el mensaje. ${explainError(err)}`;
      messages = messages.map((m) => (m.id === id ? { ...m, local: "failed" as const } : m));
    } finally {
      progress.delete(id);
    }
    if (alive) render();
  }

  /** La URL firmada de un archivo (una sola vez por ruta). */
  async function urlFor(path: string): Promise<string> {
    const known = urls.get(path);
    if (known) return known;
    const url = await familyAttachmentUrl(client, path);
    urls.set(path, url);
    return url;
  }

  /** Carga en un elemento (foto, video o audio) la URL de su archivo, sin pedirla dos veces a la vez. */
  function fill(path: string, target: HTMLImageElement | HTMLVideoElement | HTMLAudioElement, size: number, limit = Infinity) {
    const cached = urls.get(path);
    if (cached) {
      target.src = cached;
      return;
    }
    if (asking.has(path) || size > limit) return;
    asking.add(path);
    void urlFor(path)
      .then((url) => {
        if (alive && target.isConnected) target.src = url;
      })
      .catch(() => {
        /* sin vista previa: queda el nombre del archivo */
      })
      .finally(() => asking.delete(path));
  }

  async function open(path: string) {
    try {
      window.open(await urlFor(path), "_blank", "noopener");
    } catch (err) {
      problem.textContent = explainError(err);
    }
  }

  /** Un adjunto: foto en pequeño, video o audio con controles, o un enlace con nombre y tamaño para los documentos. */
  function attachmentEl(m: FamilyMessage, a: FamilyMessage["attachments"][number]): HTMLElement {
    const mime = (a.mime_type ?? "").toLowerCase();
    const link = h("button", { class: "msg-file", type: "button", disabled: !!m.local, onClick: () => void open(a.storage_path) }, h("strong", {}, ":: "), a.file_name, h("span", { class: "msg-size" }, formatSize(a.size_bytes)));
    if (m.local) return h("li", {}, link);
    if (mime.startsWith("image/")) {
      const img = h("img", { class: "msg-img", alt: a.file_name, loading: "lazy" });
      fill(a.storage_path, img, a.size_bytes, IMAGE_PREVIEW_MAX);
      return h("li", {}, h("button", { class: "msg-thumb", type: "button", "aria-label": `Abrir ${a.file_name}`, onClick: () => void open(a.storage_path) }, img), link);
    }
    if (mime.startsWith("video/")) {
      const video = h("video", { class: "msg-video", controls: true, preload: "metadata", "aria-label": a.file_name });
      fill(a.storage_path, video, a.size_bytes);
      return h("li", {}, video, link);
    }
    if (mime.startsWith("audio/")) {
      const audio = h("audio", { class: "msg-audio", controls: true, preload: "metadata", "aria-label": a.file_name });
      fill(a.storage_path, audio, a.size_bytes);
      return h("li", {}, audio, link);
    }
    return h("li", {}, link);
  }

  function footer(m: FamilyMessage, mine: boolean): HTMLElement {
    const foot = h("p", { class: "msg-foot" }, h("time", { datetime: m.sent_at }, timeLabel(m.sent_at)));
    if (m.local === "sending") foot.append(h("span", { class: "msg-state" }, progress.get(m.id) ?? "en cola"));
    else if (m.local === "failed") {
      const files = pendingFiles.get(m.id) ?? [];
      foot.append(
        h("span", { class: "msg-error" }, "ERR: no se envió"),
        h("button", { class: "btn-edge", type: "button", "data-retry": m.id, onClick: () => void deliver({ p_id: m.id, p_body: m.body ?? "", p_sent_at: m.sent_at, p_device: m.sender_device, p_attachments: [] }, files, true) }, "Reintentar"),
      );
    } else if (mine) foot.append(h("span", { class: "msg-check", "aria-label": "enviado" }, "✓"));
    return foot;
  }

  function messageEl(m: FamilyMessage): HTMLElement {
    const mine = m.sender_id === userId;
    return h(
      "li",
      { class: `msg fam-msg${mine ? " is-mine" : ""}`, "data-sender": m.sender_id },
      h(
        "div",
        { class: "msg-main" },
        h("p", { class: "fam-sender" }, senderLabel(m, members, userId)),
        m.body ? h("p", { class: "msg-text" }, m.body) : null,
        m.attachments?.length ? h("ul", { class: "msg-files" }, m.attachments.map((a) => attachmentEl(m, a))) : null,
        footer(m, mine),
      ),
    );
  }

  function render() {
    shell.setStatement(familyStatement(messages, loaded, error || undefined));
    messages = visibleMessages(messages);
    const atBottom = scroller.scrollHeight - scroller.scrollTop - scroller.clientHeight < 60;
    if (!messages.length) {
      const lines = [h("li", { class: "chat-empty" }, loaded ? (isMember() ? "> sin mensajes de las últimas 24 horas." : "> no estás en la familia: pídele al administrador que te agregue.") : "> cargando registros…")];
      log.replaceChildren(...lines);
    } else {
      log.replaceChildren(
        ...withDays(messages).map((item) => (item.type === "day" ? h("li", { class: "chat-day", "aria-hidden": "true" }, h("span", {}, item.label)) : messageEl(item.message as FamilyMessage))),
      );
      if (atBottom) scroller.scrollTop = scroller.scrollHeight;
    }
    if (error) problem.textContent = error;
    text.disabled = loaded && !isMember();
    schedulePrune();
  }

  // ----- el compositor: texto, archivos (clip, arrastrar y pegar)
  const text = h("textarea", { id: "fam-text", rows: 1, maxlength: 4000, placeholder: "escribe a la familia y pulsa ⏎", spellcheck: "true" });
  const send = h("button", { class: "chat-send", type: "submit", "aria-label": "Enviar" }, icon("enter"));
  const fileInput = h("input", { type: "file", multiple: true, hidden: true, id: "fam-files", "aria-label": "Elegir archivos para adjuntar" });
  const attach = h("button", { class: "chat-attach", type: "button", "aria-label": "Adjuntar imágenes, videos o documentos", title: "Adjuntar (o suelta los archivos aquí)", onClick: () => fileInput.click() }, icon("paperclip"));
  const stagedList = h("ul", { class: "staged", "aria-label": "Archivos por enviar", hidden: true });
  const composer = h(
    "form",
    { class: "chat-composer" },
    stagedList,
    h("label", { for: "fam-text", class: "chat-prompt" }, h("span", { "aria-hidden": "true" }, ">"), h("span", { class: "sr-only" }, "Mensaje para la familia")),
    text,
    attach,
    send,
    fileInput,
  );
  const grow = () => {
    send.disabled = !text.value.trim() && staged.length === 0;
    if (!text.isConnected) return;
    text.style.blockSize = "auto";
    if (text.scrollHeight) text.style.blockSize = `${Math.min(text.scrollHeight, 140)}px`;
  };
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
  text.addEventListener("paste", (e) => {
    const files = [...(e.clipboardData?.files ?? [])];
    if (!files.length) return;
    e.preventDefault();
    stage(files);
  });
  text.addEventListener("input", grow);
  text.addEventListener("keydown", (e) => {
    if (e.key === "Enter" && !e.shiftKey && !e.isComposing) {
      e.preventDefault();
      composer.requestSubmit();
    }
  });
  composer.addEventListener("submit", (e) => {
    e.preventDefault();
    const body = text.value.trim();
    if ((!body && !staged.length) || !isMember()) return;
    const files = staged;
    staged = [];
    renderStaged();
    text.value = "";
    grow();
    problem.textContent = "";
    // con archivos, el borrador ya lleva sus nombres (los descriptores reales se calculan al subirlos)
    const placeholders = files.map((f) => ({ storage_path: "", file_name: f.name, mime_type: f.type || "application/octet-stream", size_bytes: f.size, width: null, height: null, duration_ms: null, thumb_path: null }));
    void deliver(familyPayload(body, crypto.randomUUID(), new Date(), placeholders), files);
  });

  const el = h("div", { class: "chat fam" }, bar, scroller, composer);
  const hasFiles = (e: DragEvent) => !!e.dataTransfer && [...e.dataTransfer.types].includes("Files");
  el.addEventListener("dragover", (e) => {
    if (!hasFiles(e)) return;
    e.preventDefault();
    el.classList.add("is-dropping");
  });
  el.addEventListener("dragleave", () => el.classList.remove("is-dropping"));
  el.addEventListener("drop", (e) => {
    if (!hasFiles(e)) return;
    e.preventDefault();
    el.classList.remove("is-dropping");
    stage([...(e.dataTransfer?.files ?? [])]);
  });

  // ----- en vivo
  const setLive = (live: LiveState) => {
    liveBox.dataset.state = live;
    liveText.textContent = live === "connecting" ? "conectando…" : live === "live" ? "en línea" : LIVE_TEXT[live];
  };
  cleanups.push(
    watchFamily(
      client,
      ({ id, deleted }) => {
        if (!alive) return;
        if (deleted) {
          messages = messages.filter((m) => m.id !== id);
          render();
        } else void catchUp();
      },
      (state) => {
        setLive(state);
        if (state === "live" && loaded) void catchUp(); // al volver tras un corte, ponerse al día
      },
    ),
  );
  grow();
  renderCallTools();
  render();
  void load();

  return {
    el,
    destroy() {
      for (const fn of cleanups) fn();
    },
  };
}
