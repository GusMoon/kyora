import type { RealtimeChannel, SupabaseClient } from "@supabase/supabase-js";
import { DEVICE } from "../config";
import { BUCKET } from "./music";

export interface Attachment {
  id: string;
  storage_path: string;
  file_name: string;
  mime_type: string;
  size_bytes: number;
}

/** Un mensaje del chat General (Server/supabase/endpoints.md §2). `local` marca lo que esta pestaña aún está enviando. */
export interface Message {
  id: string;
  conversation_id: string;
  sender_device: string;
  kind: string;
  body: string | null;
  status: string;
  sent_at: string;
  created_at: string;
  deleted_at: string | null;
  received_at?: string | null;
  attachments: Attachment[];
  local?: "sending" | "failed";
}

const DEVICE_LABEL: Record<string, string> = { pc: "pc", movil: "móvil", phone: "móvil", web: "web" };

export function deviceLabel(device: string): string {
  return DEVICE_LABEL[device] ?? device;
}

/** Junta lo nuevo con lo que ya había: un mensaje por id (gana el del servidor), sin borrados, del más antiguo al
 * más nuevo. Así repetir una carga o recibir el mismo mensaje por el tiempo real no lo duplica. */
export function mergeMessages(current: Message[], incoming: Message[]): Message[] {
  const byId = new Map(current.map((m) => [m.id, m]));
  for (const m of incoming) byId.set(m.id, { ...m, attachments: m.attachments ?? byId.get(m.id)?.attachments ?? [] });
  return [...byId.values()]
    .filter((m) => !m.deleted_at)
    .sort((a, b) => (a.sent_at !== b.sent_at ? a.sent_at.localeCompare(b.sent_at) : a.id.localeCompare(b.id)));
}

/** La hora del último mensaje que llegó al servidor: desde ahí se pide lo nuevo al reconectar. */
export function latestCreatedAt(messages: Message[]): string | null {
  let latest: string | null = null;
  for (const m of messages) if (!m.local && (!latest || m.created_at > latest)) latest = m.created_at;
  return latest;
}

export function sendPayload(conversationId: string, body: string, id: string = crypto.randomUUID(), now = new Date()) {
  return {
    p_id: id,
    p_conversation_id: conversationId,
    p_body: body,
    p_sent_at: now.toISOString(),
    p_device: DEVICE,
    p_attachments: [],
  };
}

/** El mensaje que se ve mientras se envía. */
export function draftMessage(payload: ReturnType<typeof sendPayload>): Message {
  return {
    id: payload.p_id,
    conversation_id: payload.p_conversation_id,
    sender_device: DEVICE,
    kind: "text",
    body: payload.p_body,
    status: "sent",
    sent_at: payload.p_sent_at,
    created_at: payload.p_sent_at,
    deleted_at: null,
    attachments: [],
    local: "sending",
  };
}

export async function defaultConversation(client: SupabaseClient): Promise<string> {
  const { data, error } = await client.rpc("ensure_default_conversation");
  if (error) throw error;
  return data as string;
}

export async function listMessages(
  client: SupabaseClient,
  conversationId: string,
  opts: { after?: string | null; limit?: number } = {},
): Promise<Message[]> {
  const { data, error } = await client.rpc("list_messages", {
    p_conversation_id: conversationId,
    p_before: null,
    p_after: opts.after ?? null,
    p_limit: opts.limit ?? 50,
  });
  if (error) throw error;
  return (data ?? []) as Message[];
}

/** Envía (se puede reintentar con el mismo id sin duplicar). Merida no llama a confirm_messages_received: eso es de la PC. */
export async function sendMessage(client: SupabaseClient, payload: ReturnType<typeof sendPayload>): Promise<Message> {
  const { data, error } = await client.rpc("send_message", payload);
  if (error) throw error;
  return data as Message;
}

export async function attachmentUrl(client: SupabaseClient, path: string): Promise<string> {
  const { data, error } = await client.storage.from(BUCKET).createSignedUrl(path, 3600);
  if (error || !data) throw error ?? new Error("Sin URL");
  return data.signedUrl;
}

export type LiveState = "connecting" | "live" | "offline";

/** Escucha los cambios de la conversación. `onChange` recibe el id y si se borró; `onState`, el estado de la conexión. */
export function watchMessages(
  client: SupabaseClient,
  conversationId: string,
  onChange: (change: { id: string; deleted: boolean }) => void,
  onState: (state: LiveState) => void,
): () => void {
  onState("connecting");
  const channel: RealtimeChannel = client
    .channel(`merida-chat-${Date.now()}`)
    .on(
      "postgres_changes",
      { event: "*", schema: "public", table: "messages", filter: `conversation_id=eq.${conversationId}` },
      (payload) => {
        const row = (payload.new ?? {}) as Partial<Message>;
        const old = (payload.old ?? {}) as Partial<Message>;
        const id = row.id ?? old.id;
        if (id) onChange({ id, deleted: payload.eventType === "DELETE" || !!row.deleted_at });
      },
    )
    .subscribe((status) => {
      if (status === "SUBSCRIBED") onState("live");
      else if (status === "CHANNEL_ERROR" || status === "TIMED_OUT" || status === "CLOSED") onState("offline");
    });
  return () => {
    void client.removeChannel(channel);
  };
}
