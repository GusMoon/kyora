import type { SupabaseClient } from "@supabase/supabase-js";
import { BUCKET, formatSize } from "./music";

/** Adjuntar archivos al chat desde Merida. Mismo camino que la PC (Family/Kyora/kyora/chat/service.py):
 *  1. cada archivo se sube a Storage en `<id de tu cuenta>/<conversación>/<id del mensaje>/<nombre seguro>`;
 *  2. el mensaje se envía con `send_message` y la lista de adjuntos (el servidor decide la clase por el primer adjunto).
 * El id del mensaje lo crea esta pestaña: reintentar un envío fallido repite las mismas rutas (se sobrescriben) y el
 * mismo id (no se duplica). */

export const MAX_BYTES = 50 * 1024 * 1024; // el límite del bucket chat-files
export const MAX_FILES = 10; // por mensaje

/** El descriptor que pide `send_message` (p_attachments). */
export interface AttachmentInput {
  storage_path: string;
  file_name: string;
  mime_type: string;
  size_bytes: number;
  width: number | null;
  height: number | null;
  duration_ms: number | null;
  thumb_path: string | null;
}

/** Deja solo `[A-Za-z0-9._-]` (lo demás, «_») y recorta a 120, como `safe_name` de Kyora. Nunca devuelve vacío ni «..». */
export function safeName(name: string): string {
  const base = name.replace(/[^A-Za-z0-9._-]/g, "_").slice(0, 120).replace(/^\.+/, "_");
  return base || "archivo";
}

/** Nombres seguros y únicos dentro de un mensaje: «foto.jpg», «foto-2.jpg»… (dos archivos con el mismo nombre no se pisan). */
export function uniqueNames(names: string[]): string[] {
  const used = new Set<string>();
  return names.map((raw) => {
    const safe = safeName(raw);
    let candidate = safe;
    for (let n = 2; used.has(candidate.toLowerCase()); n++) {
      const dot = safe.lastIndexOf(".");
      candidate = dot > 0 ? `${safe.slice(0, dot)}-${n}${safe.slice(dot)}` : `${safe}-${n}`;
    }
    used.add(candidate.toLowerCase());
    return candidate;
  });
}

export function storagePath(userId: string, conversationId: string, messageId: string, fileName: string): string {
  return `${userId}/${conversationId}/${messageId}/${fileName}`;
}

/** Revisa lo que se quiere añadir. Devuelve lo que vale y los motivos (en español) de lo que no. */
export function checkFiles(adding: File[], already: File[] = []): { accepted: File[]; errors: string[] } {
  const accepted: File[] = [];
  const errors: string[] = [];
  for (const f of adding) {
    if (already.length + accepted.length >= MAX_FILES) {
      errors.push(`Solo se pueden adjuntar ${MAX_FILES} archivos por mensaje.`);
      break;
    }
    if (f.size === 0) errors.push(`«${f.name}» está vacío.`);
    else if (f.size > MAX_BYTES) errors.push(`«${f.name}» pesa ${formatSize(f.size)}: el límite es ${formatSize(MAX_BYTES)}.`);
    else accepted.push(f);
  }
  return { accepted, errors };
}

/** El ancho y el alto de una imagen (o null si no se puede leer). Solo para imágenes: no sube nada. */
export async function imageSize(file: File): Promise<{ width: number; height: number } | null> {
  if (!file.type.startsWith("image/") || typeof createImageBitmap !== "function") return null;
  try {
    const bmp = await createImageBitmap(file);
    const size = { width: bmp.width, height: bmp.height };
    bmp.close();
    return size;
  } catch {
    return null;
  }
}

/** Sube los archivos y devuelve sus descriptores. Si uno falla, lanza el error (lo ya subido se sobrescribe al reintentar). */
export async function uploadAttachments(
  client: SupabaseClient,
  userId: string,
  conversationId: string,
  messageId: string,
  files: File[],
  onProgress: (done: number, total: number) => void = () => {},
): Promise<AttachmentInput[]> {
  const names = uniqueNames(files.map((f) => f.name));
  const out: AttachmentInput[] = [];
  for (let i = 0; i < files.length; i++) {
    onProgress(i, files.length);
    const file = files[i];
    const path = storagePath(userId, conversationId, messageId, names[i]);
    const mime = file.type || "application/octet-stream";
    const { error } = await client.storage.from(BUCKET).upload(path, file, { contentType: mime, upsert: true });
    if (error) throw error;
    const size = await imageSize(file);
    out.push({ storage_path: path, file_name: file.name || names[i], mime_type: mime, size_bytes: file.size, width: size?.width ?? null, height: size?.height ?? null, duration_ms: null, thumb_path: null });
  }
  onProgress(files.length, files.length);
  return out;
}

/** Quita de Storage lo que se subió para un mensaje que no llegó a enviarse (al cancelar). No lanza: es limpieza. */
export async function discardUploads(client: SupabaseClient, inputs: AttachmentInput[]): Promise<void> {
  const paths = inputs.map((a) => a.storage_path);
  if (!paths.length) return;
  try {
    await client.storage.from(BUCKET).remove(paths);
  } catch {
    /* se queda en el servidor; no afecta al chat */
  }
}
