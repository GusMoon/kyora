import { h, shortWhen } from "../ui/dom";
import { explainError } from "../supabase";
import { formatSize } from "../data/music";
import { attachmentUrl, deviceLabel, draftMessage, mergeMessages, sendMessage, sendPayload, type Message } from "../data/chat";
import type { Ctx, Section } from "./context";

export function chatStatement(messages: Message[], loaded: boolean, error?: string): string {
  if (error) return error;
  if (!loaded) return "Abriendo la conversación General.";
  if (!messages.length) return "La conversación General está vacía. Escribe el primer mensaje.";
  return `Conversación General: ${messages.length === 1 ? "1 mensaje" : `${messages.length} mensajes`} con la PC y el móvil.`;
}

export const chatSection: Section = (ctx: Ctx) => {
  const { store, shell, client } = ctx;
  const log = h("ol", { class: "ledger", "aria-live": "polite", "aria-label": "Mensajes" });
  const scroller = h("div", { class: "ledger-wrap", tabindex: 0 }, log);

  async function deliver(payload: ReturnType<typeof sendPayload>) {
    store.messages = mergeMessages(store.messages, [draftMessage(payload)]);
    store.emit("messages");
    try {
      const sent = await sendMessage(client, payload);
      store.messages = mergeMessages(store.messages, [sent]);
    } catch {
      store.messages = store.messages.map((m) => (m.id === payload.p_id ? { ...m, local: "failed" as const } : m));
    }
    store.emit("messages");
  }

  async function openAttachment(path: string) {
    try {
      window.open(await attachmentUrl(client, path), "_blank", "noopener");
    } catch (err) {
      alert(explainError(err));
    }
  }

  function row(m: Message): HTMLElement {
    const mine = m.sender_device === "web";
    let state: Node | string = shortWhen(m.sent_at);
    if (m.local === "sending") state = "enviando";
    if (m.local === "failed") {
      state = h("button", {
        class: "btn-quiet danger",
        type: "button",
        onClick: () => void deliver({ p_id: m.id, p_conversation_id: m.conversation_id, p_body: m.body ?? "", p_sent_at: m.sent_at, p_device: "web", p_attachments: [] }),
      }, "No se envió. Reintentar");
    }
    return h(
      "li",
      { class: `entry${mine ? " is-mine" : ""}`, "data-device": m.sender_device },
      h("span", { class: "entry-device readout" }, deviceLabel(m.sender_device)),
      h(
        "div",
        { class: "entry-body" },
        m.body ? h("p", {}, m.body) : null,
        m.attachments?.length
          ? h("ul", { class: "files" }, m.attachments.map((a) => h("li", {}, h("button", { class: "file", type: "button", onClick: () => void openAttachment(a.storage_path) }, a.file_name, h("span", { class: "readout" }, formatSize(a.size_bytes))))))
          : null,
      ),
      h("span", { class: "entry-time readout" }, state),
    );
  }

  function render() {
    shell.setStatement(chatStatement(store.messages, store.loaded.messages, store.errors.messages));
    const atBottom = scroller.scrollHeight - scroller.scrollTop - scroller.clientHeight < 40;
    log.replaceChildren(...store.messages.map(row));
    if (atBottom) scroller.scrollTop = scroller.scrollHeight;
  }

  const text = h("textarea", { id: "chat-text", rows: 2, maxlength: 4000, placeholder: "Escribe un mensaje. Enter envía, Mayús+Enter salta de línea." });
  const send = h("button", { class: "btn-solid", type: "submit" }, "Enviar");
  const composer = h("form", { class: "composer composer-chat" }, h("label", { for: "chat-text", class: "sr-only" }, "Mensaje"), text, send);
  composer.addEventListener("submit", (e) => {
    e.preventDefault();
    const body = text.value.trim();
    if (!body || !store.conversationId) return;
    text.value = "";
    void deliver(sendPayload(store.conversationId, body));
  });
  text.addEventListener("keydown", (e) => {
    if (e.key === "Enter" && !e.shiftKey && !e.isComposing) {
      e.preventDefault();
      composer.requestSubmit();
    }
  });

  shell.body.append(h("div", { class: "chat" }, scroller, composer));
  render();
  scroller.scrollTop = scroller.scrollHeight;
  const off = store.on((area) => area === "messages" && render());
  return off;
};
