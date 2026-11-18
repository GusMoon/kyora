import type { RealtimeChannel, SupabaseClient } from "@supabase/supabase-js";
import { DEVICE } from "../config";
import { BUCKET } from "./music";
import type { AttachmentInput } from "./attachments";

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
export function mergeMessages<T extends Message>(current: T[], incoming: T[]): T[] {
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

export function sendPayload(conversationId: string, body: string, id: string = crypto.randomUUID(), now = new Date(), attachments: AttachmentInput[] = []) {
  return {
    p_id: id,
    p_conversation_id: conversationId,
    p_body: body,
    p_sent_at: now.toISOString(),
    p_device: DEVICE,
    p_attachments: attachments,
  };
}

/** La clase de un mensaje por su primer adjunto, igual que lo decide `send_message` en el servidor. */
export function kindOfMime(mime: string | undefined): string {
  const m = (mime ?? "").toLowerCase();
  if (!m) return "text";
  if (m.startsWith("image/")) return "image";
  if (m.startsWith("audio/")) return "audio";
  if (m.startsWith("video/")) return "video";
  return "file";
}

/** El mensaje que se ve mientras se envía (con sus adjuntos, si los lleva). */
export function draftMessage(payload: ReturnType<typeof sendPayload>): Message {
  return {
    id: payload.p_id,
    conversation_id: payload.p_conversation_id,
    sender_device: DEVICE,
    kind: kindOfMime(payload.p_attachments[0]?.mime_type),
    body: payload.p_body || null,
    status: "sent",
    sent_at: payload.p_sent_at,
    created_at: payload.p_sent_at,
    deleted_at: null,
    attachments: payload.p_attachments.map((a, i) => ({ id: `${payload.p_id}:${i}`, storage_path: a.storage_path, file_name: a.file_name, mime_type: a.mime_type, size_bytes: a.size_bytes })),
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
  opts: { after?: string | null; before?: string | null; limit?: number } = {},
): Promise<Message[]> {
  const { data, error } = await client.rpc("list_messages", {
    p_conversation_id: conversationId,
    p_before: opts.before ?? null, // cargar más hacia atrás: los enviados antes de esa hora
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

const CHUNK = 100; // cuántos mensajes se borran por tanda (la dirección de la petición no puede crecer sin fin)

/** Borra mensajes del servidor **de verdad** (no «borrado suave»): primero los archivos de sus adjuntos en Storage (y
 * sus miniaturas) y luego las filas (los adjuntos caen en cascada). Si falla el almacenamiento no se toca la base, así se
 * puede reintentar. Devuelve los ids que se borraron. Las otras apps (Kyora y Kyra) quitan el mensaje al recibir el aviso. */
export async function deleteMessages(client: SupabaseClient, ids: string[]): Promise<string[]> {
  const deleted: string[] = [];
  for (let i = 0; i < ids.length; i += CHUNK) {
    const part = ids.slice(i, i + CHUNK);
    const atts = await client.from("attachments").select("storage_path, thumb_path").in("message_id", part);
    if (atts.error) throw atts.error;
    const paths = [...new Set((atts.data ?? []).flatMap((a: { storage_path: string | null; thumb_path: string | null }) => [a.storage_path, a.thumb_path]).filter((p): p is string => !!p))];
    if (paths.length) {
      const removed = await client.storage.from(BUCKET).remove(paths);
      if (removed.error) throw removed.error;
    }
    const gone = await client.from("messages").delete().in("id", part).select("id");
    if (gone.error) throw gone.error;
    deleted.push(...(gone.data ?? []).map((r: { id: string }) => r.id));
  }
  return deleted;
}

/** Los ids de todos los mensajes de una conversación (de mil en mil). */
export async function conversationMessageIds(client: SupabaseClient, conversationId: string): Promise<string[]> {
  const ids: string[] = [];
  for (let from = 0; ; from += 1000) {
    const { data, error } = await client.from("messages").select("id").eq("conversation_id", conversationId).order("created_at").range(from, from + 999);
    if (error) throw error;
    ids.push(...(data ?? []).map((r: { id: string }) => r.id));
    if ((data ?? []).length < 1000) return ids;
  }
}

/** Vacía la conversación: todos sus mensajes y los archivos de sus adjuntos. Devuelve cuántos se borraron y cuántos había. */
export async function clearConversation(client: SupabaseClient, conversationId: string): Promise<{ deleted: number; total: number }> {
  const ids = await conversationMessageIds(client, conversationId);
  const deleted = await deleteMessages(client, ids);
  return { deleted: deleted.length, total: ids.length };
}
