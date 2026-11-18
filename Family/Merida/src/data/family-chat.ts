import type { RealtimeChannel, SupabaseClient } from "@supabase/supabase-js";
import { DEVICE } from "../config";
import type { AttachmentInput } from "./attachments";
import { draftMessage, mergeMessages, type LiveState, type Message } from "./chat";

/** El chat familiar (Server/supabase/schema.sql §18): un solo chat para la familia, aparte del «General» de una cuenta.
 * Mismo modelo de mensaje que el chat General (así se reutilizan `mergeMessages`, `draftMessage` y la lista), con `sender_id`
 * para saber de quién es cada uno. Todo se borra a las 24 horas desde que llegó al servidor. */

export const FAMILY_BUCKET = "family-files";
/** El «id de conversación» del chat familiar: solo existe para reutilizar el modelo de mensaje y para la ruta de los archivos. */
export const FAMILY_CONVERSATION = "family";
export const FAMILY_TTL_MS = 24 * 3600 * 1000;

export interface FamilyMessage extends Message {
  sender_id: string;
}

export interface FamilyMember {
  id: string;
  username: string;
}

/** Lo que devuelve el servidor (family_message_json): una fila de family_messages con sus adjuntos. */
type FamilyRow = Omit<FamilyMessage, "conversation_id" | "status" | "deleted_at" | "attachments"> & { attachments?: FamilyMessage["attachments"] | null };

/** Del formato del servidor al del chat (rellena lo que el chat General sí tiene y este no). */
export function fromRow(row: FamilyRow): FamilyMessage {
  return { ...row, conversation_id: FAMILY_CONVERSATION, status: "sent", deleted_at: null, attachments: row.attachments ?? [] };
}

/** ¿Ya pasaron 24 horas desde que llegó al servidor? El servidor ya no lo enseña; esto lo quita de la pantalla sin esperar. */
export function isExpired(message: Pick<Message, "created_at">, now: number = Date.now()): boolean {
  return now - new Date(message.created_at).getTime() >= FAMILY_TTL_MS;
}

/** Lo que se ve: sin lo caducado. */
export function visibleMessages<T extends Pick<Message, "created_at">>(messages: T[], now: number = Date.now()): T[] {
  return messages.filter((m) => !isExpired(m, now));
}

/** Cuánto falta para que caduque el mensaje más antiguo que se ve (para volver a filtrar justo entonces). null si no hay ninguno. */
export function nextExpiryIn(messages: Pick<Message, "created_at">[], now: number = Date.now()): number | null {
  let soonest: number | null = null;
  for (const m of messages) {
    const left = new Date(m.created_at).getTime() + FAMILY_TTL_MS - now;
    if (left > 0 && (soonest === null || left < soonest)) soonest = left;
  }
  return soonest;
}

/** «Tú» para los propios; si no, el nombre de usuario del miembro (o «alguien» si ya no está en la familia). */
export function senderLabel(message: Pick<FamilyMessage, "sender_id">, members: FamilyMember[], userId: string): string {
  if (message.sender_id === userId) return "Tú";
  return members.find((m) => m.id === message.sender_id)?.username ?? "alguien";
}

/** El texto del indicador de arriba. */
export function familyStatement(messages: Pick<Message, "created_at">[], loaded: boolean, error?: string): string {
  if (error) return error;
  if (!loaded) return "Abriendo el chat de la familia.";
  const n = visibleMessages(messages).length;
  return n ? `Chat de la familia: ${n === 1 ? "1 mensaje" : `${n} mensajes`} (se borran a las 24 horas).` : "El chat de la familia está vacío. Los mensajes se borran a las 24 horas.";
}

export function familyPayload(body: string, id: string = crypto.randomUUID(), now = new Date(), attachments: AttachmentInput[] = []) {
  return { p_id: id, p_body: body, p_sent_at: now.toISOString(), p_device: DEVICE, p_attachments: attachments };
}
export type FamilyPayload = ReturnType<typeof familyPayload>;

/** El mensaje que se ve mientras se envía. */
export function familyDraft(payload: FamilyPayload, userId: string): FamilyMessage {
  return { ...draftMessage({ ...payload, p_conversation_id: FAMILY_CONVERSATION }), sender_id: userId };
}

/** Junta lo nuevo con lo que ya había (un mensaje por id, del más antiguo al más nuevo) y quita lo caducado. */
export function mergeFamily(current: FamilyMessage[], incoming: FamilyMessage[], now: number = Date.now()): FamilyMessage[] {
  return visibleMessages(mergeMessages(current, incoming), now);
}

export async function familyMembers(client: SupabaseClient): Promise<FamilyMember[]> {
  const { data, error } = await client.rpc("family_members");
  if (error) throw error;
  return (data ?? []) as FamilyMember[];
}

/** Los mensajes de las últimas 24 horas (el servidor ya los filtra), del más antiguo al más nuevo. */
export async function listFamilyMessages(client: SupabaseClient, opts: { after?: string | null; before?: string | null; limit?: number } = {}): Promise<FamilyMessage[]> {
  const { data, error } = await client.rpc("family_list_messages", { p_before: opts.before ?? null, p_after: opts.after ?? null, p_limit: opts.limit ?? 100 });
  if (error) throw error;
  return ((data ?? []) as FamilyRow[]).map(fromRow);
}

/** Envía (se puede reintentar con el mismo id sin duplicar). */
export async function sendFamilyMessage(client: SupabaseClient, payload: FamilyPayload): Promise<FamilyMessage> {
  const { data, error } = await client.rpc("family_send_message", payload);
  if (error) throw error;
  return fromRow(data as FamilyRow);
}

export async function familyAttachmentUrl(client: SupabaseClient, path: string): Promise<string> {
  const { data, error } = await client.storage.from(FAMILY_BUCKET).createSignedUrl(path, 3600);
  if (error || !data) throw error ?? new Error("Sin URL");
  return data.signedUrl;
}

/** Escucha los mensajes de la familia. `onChange` recibe el id y si se borró; `onState`, el estado de la conexión. */
export function watchFamily(
  client: SupabaseClient,
  onChange: (change: { id: string; deleted: boolean }) => void,
  onState: (state: LiveState) => void,
): () => void {
  onState("connecting");
  const channel: RealtimeChannel = client
    .channel(`merida-family-${Date.now()}`)
    .on("postgres_changes", { event: "*", schema: "public", table: "family_messages" }, (payload) => {
      const row = (payload.new ?? {}) as Partial<FamilyMessage>;
      const old = (payload.old ?? {}) as Partial<FamilyMessage>;
      const id = row.id ?? old.id;
      if (id) onChange({ id, deleted: payload.eventType === "DELETE" });
    })
    .subscribe((status) => {
      if (status === "SUBSCRIBED") onState("live");
      else if (status === "CHANNEL_ERROR" || status === "TIMED_OUT" || status === "CLOSED") onState("offline");
    });
  return () => {
    void client.removeChannel(channel);
  };
}
