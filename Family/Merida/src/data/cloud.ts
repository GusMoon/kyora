import type { SupabaseClient } from "@supabase/supabase-js";
import { BUCKET, formatSize } from "./music";
import { deleteMessages, deviceLabel } from "./chat";

/** La nube: los archivos que se han compartido por medio de Supabase y están ahora mismo en el servidor (bucket `chat-files`).
 * Salen de dos tablas, que la limpieza automática borra junto con sus archivos:
 *  - `attachments`: lo que se mandó por el chat (fotos, documentos…), con el dispositivo que lo mandó;
 *  - `music_tracks`: las canciones que la PC subió (para ti o para un pasante).
 * Merida solo los lista y los abre: nunca confirma «Recibido» ni borra nada, así que no cambia lo que el servidor guarda. */

export type CloudKind = "image" | "audio" | "video" | "doc" | "other";

export interface CloudFile {
  id: string; // «chat:<id>» o «music:<id>»: el mismo archivo no se repite
  source: "chat" | "music";
  path: string;
  name: string;
  mime: string;
  size: number;
  at: string; // cuándo llegó al servidor
  from: string; // quién lo mandó o a quién va: «pc», «móvil», «web», «para ti»…
  kind: CloudKind;
  messageId?: string; // si vino por el chat: el mensaje al que pertenece
  thumbPath?: string | null; // y su miniatura, si tiene
}

export const KIND_LABEL: Record<CloudKind, string> = { image: "Fotos", audio: "Música", video: "Vídeos", doc: "Documentos", other: "Otros" };
export const KIND_ORDER: CloudKind[] = ["image", "audio", "video", "doc", "other"];

const DOC_EXT = /\.(pdf|docx?|xlsx?|pptx?|txt|md|csv|rtf|odt|zip|rar|7z)$/i;

export function kindOf(mime: string, name = ""): CloudKind {
  const m = (mime || "").toLowerCase();
  if (m.startsWith("image/")) return "image";
  if (m.startsWith("audio/")) return "audio";
  if (m.startsWith("video/")) return "video";
  if (m.startsWith("text/") || m === "application/pdf" || m.includes("officedocument") || m.includes("msword") || m.includes("zip") || DOC_EXT.test(name)) return "doc";
  return "other";
}

interface AttachmentRow {
  id: string;
  message_id?: string;
  thumb_path?: string | null;
  storage_path: string;
  file_name: string;
  mime_type: string;
  size_bytes: number;
  created_at: string;
  message: { sender_device: string | null; deleted_at: string | null } | { sender_device: string | null; deleted_at: string | null }[] | null;
}

interface TrackRow {
  id: string;
  title: string;
  file_name: string;
  storage_path: string;
  mime_type: string;
  size_bytes: number;
  created_at: string;
  owner_id: string;
  recipient_id: string;
}

/** Une las dos listas: un archivo por ruta (una canción para varios pasantes es un solo MP3), lo más nuevo primero. */
export function mergeCloud(chat: AttachmentRow[], tracks: TrackRow[], me: string | null, names: Record<string, string> = {}): CloudFile[] {
  const byPath = new Map<string, CloudFile>();
  for (const a of chat) {
    const msg = Array.isArray(a.message) ? a.message[0] : a.message;
    if (msg?.deleted_at) continue; // un mensaje borrado ya no cuenta
    byPath.set(a.storage_path, {
      id: `chat:${a.id}`,
      source: "chat",
      path: a.storage_path,
      name: a.file_name,
      mime: a.mime_type,
      size: Number(a.size_bytes) || 0,
      at: a.created_at,
      from: msg?.sender_device ? deviceLabel(msg.sender_device) : "chat",
      kind: kindOf(a.mime_type, a.file_name),
      messageId: a.message_id,
      thumbPath: a.thumb_path ?? null,
    });
  }
  for (const t of tracks) {
    const to = t.recipient_id === me ? "para ti" : names[t.recipient_id] ? `para ${names[t.recipient_id]}` : "para un pasante";
    const prev = byPath.get(t.storage_path);
    if (prev) {
      // el mismo MP3 para varios: se muestra una vez, a quién va se junta
      if (!prev.from.includes(to)) prev.from = `${prev.from}, ${to}`;
      continue;
    }
    byPath.set(t.storage_path, {
      id: `music:${t.id}`,
      source: "music",
      path: t.storage_path,
      name: t.file_name || `${t.title}.mp3`,
      mime: t.mime_type || "audio/mpeg",
      size: Number(t.size_bytes) || 0,
      at: t.created_at,
      from: to,
      kind: "audio",
    });
  }
  return [...byPath.values()].sort((a, b) => (a.at !== b.at ? b.at.localeCompare(a.at) : a.id.localeCompare(b.id)));
}

/** Los archivos que hay ahora en el servidor. Solo lee. */
export async function listCloud(client: SupabaseClient, me: string | null): Promise<CloudFile[]> {
  const [chat, tracks] = await Promise.all([
    client
      .from("attachments")
      .select("id, message_id, thumb_path, storage_path, file_name, mime_type, size_bytes, created_at, message:messages(sender_device, deleted_at)")
      .order("created_at", { ascending: false })
      .limit(500),
    client.from("music_tracks").select("id, title, file_name, storage_path, mime_type, size_bytes, created_at, owner_id, recipient_id").order("created_at", { ascending: false }).limit(500),
  ]);
  if (chat.error) throw chat.error;
  if (tracks.error) throw tracks.error;
  // los nombres de los pasantes, solo para decir a quién va cada canción (si no se pueden leer, se dice «un pasante»)
  const names: Record<string, string> = {};
  try {
    const { data } = await client.rpc("list_recipients");
    for (const r of (data ?? []) as { id: string; username: string }[]) names[r.id] = r.username;
  } catch {
    /* no es administrador o no hay red: sin nombres */
  }
  return mergeCloud((chat.data ?? []) as unknown as AttachmentRow[], (tracks.data ?? []) as TrackRow[], me, names);
}

/** Una URL temporal (1 h): para abrir el archivo, o (con `download`) para que el navegador lo guarde con su nombre. */
export async function cloudUrl(client: SupabaseClient, path: string, download?: string): Promise<string> {
  const { data, error } = await client.storage.from(BUCKET).createSignedUrl(path, 3600, download ? { download } : undefined);
  if (error || !data) throw error ?? new Error("Sin URL");
  return data.signedUrl;
}

export interface CloudTotals {
  count: number;
  bytes: number;
  byKind: Record<CloudKind, number>;
}

export function cloudTotals(files: CloudFile[]): CloudTotals {
  const byKind: Record<CloudKind, number> = { image: 0, audio: 0, video: 0, doc: 0, other: 0 };
  let bytes = 0;
  for (const f of files) {
    byKind[f.kind]++;
    bytes += f.size;
  }
  return { count: files.length, bytes, byKind };
}

/** La frase de la nube (en la tesela y en la sección). */
export function cloudStatement(files: CloudFile[], loaded: boolean, error?: string): string {
  if (error) return error;
  if (!loaded) return "Leyendo el servidor…";
  if (!files.length) return "No hay archivos en el servidor.";
  const t = cloudTotals(files);
  return `${t.count} ${t.count === 1 ? "archivo" : "archivos"} en el servidor (${formatSize(t.bytes)}).`;
}

/** Cuánto hace que llegó, en palabras cortas: «ahora», «hace 5 min», «hace 3 h», «ayer», «12 nov». */
export function agoLabel(iso: string, now = new Date()): string {
  const t = new Date(iso).getTime();
  if (!Number.isFinite(t)) return "";
  const min = Math.floor((now.getTime() - t) / 60000);
  if (min < 1) return "ahora";
  if (min < 60) return `hace ${min} min`;
  if (min < 60 * 24) return `hace ${Math.floor(min / 60)} h`;
  if (min < 60 * 48) return "ayer";
  return new Date(iso).toLocaleDateString("es", { day: "numeric", month: "short" }).replace(".", "");
}

export interface DeleteResult {
  /** Si al quitar el archivo el mensaje se quedó vacío (sin texto ni más adjuntos), el mensaje también se borró. */
  messageDeleted?: string;
  /** Si el archivo seguía en un mensaje con texto: el mensaje se queda sin ese adjunto. */
  messageKept?: string;
}

/** Borra un archivo del servidor **de verdad**: primero el archivo en Storage y luego su fila (así, si algo falla a medias,
 * se puede volver a intentar). Una canción se quita para todos los que la tenían. */
export async function deleteCloudFile(client: SupabaseClient, file: CloudFile): Promise<DeleteResult> {
  const paths = [file.path, file.thumbPath].filter((p): p is string => !!p);
  const removed = await client.storage.from(BUCKET).remove(paths);
  if (removed.error) throw removed.error;

  if (file.source === "music") {
    const rows = await client.from("music_tracks").delete().eq("storage_path", file.path).select("id");
    if (rows.error) throw rows.error;
    if (!rows.data?.length) throw new Error("El servidor no dejó borrar esta canción (no es tuya).");
    return {};
  }

  const attId = file.id.slice("chat:".length);
  const row = await client.from("attachments").delete().eq("id", attId).select("id");
  if (row.error) throw row.error;
  if (!row.data?.length) throw new Error("El servidor no dejó borrar este archivo.");
  if (!file.messageId) return {};
  // ¿el mensaje se quedó sin nada? entonces se borra también (un mensaje vacío no sirve de nada)
  const msg = await client.from("messages").select("id, body, attachments(id)").eq("id", file.messageId).maybeSingle();
  if (msg.error) throw msg.error;
  const left = msg.data as { id: string; body: string | null; attachments: { id: string }[] } | null;
  if (!left) return {};
  if (!(left.body ?? "").trim() && !left.attachments?.length) {
    await deleteMessages(client, [left.id]);
    return { messageDeleted: left.id };
  }
  return { messageKept: left.id };
}
