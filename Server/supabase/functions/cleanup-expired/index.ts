// Limpieza automática de Supabase para que la base de datos y el almacenamiento no se saturen.
//
//  1. Mensajes: 24 horas después de que el dispositivo de destino confirmó que los recibió (messages.received_at), se borran
//     sus archivos de Storage (adjuntos y miniaturas) y luego el mensaje (los adjuntos caen en cascada).
//  2. Canciones: en cuanto quien las recibió pulsó «Recibido» (music_tracks.received_at, que la app solo manda cuando la
//     canción ya está guardada en su teléfono) se borra el MP3 de Storage y la fila. El MP3 se sube una sola vez y lo comparten
//     todas las filas de esa canción: no se borra hasta que TODOS los destinatarios lo confirmaron.
//
//  3. Chat familiar: 24 horas después de llegar al servidor (created_at, sin esperar a ninguna confirmación) se borran los
//     archivos de family-files, los mensajes (family_messages; los adjuntos caen en cascada) y las llamadas (family_calls; sus
//     señales caen en cascada). La RLS ya los oculta pasadas las 24 h: esto libera el espacio de verdad.
//
// En los puntos 1 y 2 nunca se borra nada con received_at vacío. Los archivos se borran antes que las filas: si algo falla a medias,
// la siguiente pasada lo termina (borrar un archivo que ya no está no da error).
//
// La llama pg_cron cada hora (ver Server/supabase/cleanup.sql) con la cabecera x-cleanup-secret. Se despliega con
//   supabase functions deploy cleanup-expired --no-verify-jwt
// y necesita el secreto CLEANUP_SECRET (supabase secrets set CLEANUP_SECRET=...). SUPABASE_URL y SUPABASE_SERVICE_ROLE_KEY
// los pone Supabase solo.
import { createClient } from "npm:@supabase/supabase-js@2.45.4";
import { expiryCutoff, filesOf } from "./cutoff.ts";

const BUCKET = "chat-files";
const FAMILY_BUCKET = "family-files";
const HOURS = 24;
const BATCH = 200;

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  const secret = Deno.env.get("CLEANUP_SECRET");
  if (!secret || req.headers.get("x-cleanup-secret") !== secret) return json({ error: "unauthorized" }, 401);

  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false },
  });

  try {
    const messages = await purgeMessages(db);
    const tracks = await purgeTracks(db);
    const family = await purgeFamily(db);
    return json({ ok: true, messages, tracks, family });
  } catch (error) {
    console.error("cleanup-expired", error);
    return json({ ok: false, error: String((error as Error)?.message ?? error) }, 500);
  }
});

type Db = ReturnType<typeof createClient>;

async function removeFiles(db: Db, paths: string[], bucket: string = BUCKET) {
  for (let i = 0; i < paths.length; i += 100) {
    const { error } = await db.storage.from(bucket).remove(paths.slice(i, i + 100));
    if (error) throw new Error(`Storage: ${error.message}`);
  }
}

/** Chat familiar: mensajes y llamadas de hace más de 24 horas (archivos primero y luego filas). Devuelve cuántos se borraron. */
async function purgeFamily(db: Db): Promise<{ messages: number; calls: number }> {
  const cutoff = expiryCutoff(Date.now());

  const { data, error } = await db
    .from("family_messages")
    .select("id, attachments:family_attachments(storage_path, thumb_path)")
    .lt("created_at", cutoff)
    .limit(BATCH);
  if (error) throw new Error(`family_messages: ${error.message}`);
  let messages = 0;
  if (data && data.length > 0) {
    await removeFiles(db, filesOf(data as any), FAMILY_BUCKET);
    const { error: deleteError } = await db.from("family_messages").delete().in("id", data.map((m) => m.id));
    if (deleteError) throw new Error(`family_messages (borrar): ${deleteError.message}`);
    messages = data.length;
  }

  const { data: calls, error: callsError } = await db.from("family_calls").delete().lt("created_at", cutoff).select("id");
  if (callsError) throw new Error(`family_calls (borrar): ${callsError.message}`);
  return { messages, calls: calls?.length ?? 0 };
}

/** Mensajes recibidos hace más de 24 horas: archivos y luego filas. Devuelve cuántos se borraron. */
async function purgeMessages(db: Db): Promise<number> {
  const cutoff = new Date(Date.now() - HOURS * 3600 * 1000).toISOString();
  const { data, error } = await db
    .from("messages")
    .select("id, attachments(storage_path, thumb_path)")
    .not("received_at", "is", null)
    .lt("received_at", cutoff)
    .limit(BATCH);
  if (error) throw new Error(`messages: ${error.message}`);
  if (!data || data.length === 0) return 0;

  const paths = new Set<string>();
  for (const message of data) {
    for (const a of (message as any).attachments ?? []) {
      if (a.storage_path) paths.add(a.storage_path);
      if (a.thumb_path) paths.add(a.thumb_path);
    }
  }
  await removeFiles(db, [...paths]);

  const { error: deleteError } = await db.from("messages").delete().in("id", data.map((m) => m.id));
  if (deleteError) throw new Error(`messages (borrar): ${deleteError.message}`);
  return data.length;
}

/** Canciones confirmadas por todos sus destinatarios: el MP3 y sus filas. Devuelve cuántas filas se borraron. */
async function purgeTracks(db: Db): Promise<number> {
  const { data, error } = await db
    .from("music_tracks")
    .select("storage_path")
    .not("received_at", "is", null)
    .limit(BATCH);
  if (error) throw new Error(`music_tracks: ${error.message}`);
  const confirmed = [...new Set((data ?? []).map((t) => t.storage_path as string))];
  if (confirmed.length === 0) return 0;

  // Los archivos que aún tienen algún destinatario sin confirmar no se tocan.
  const { data: open, error: openError } = await db
    .from("music_tracks")
    .select("storage_path")
    .in("storage_path", confirmed)
    .is("received_at", null);
  if (openError) throw new Error(`music_tracks (pendientes): ${openError.message}`);
  const blocked = new Set((open ?? []).map((t) => t.storage_path as string));
  const removable = confirmed.filter((p) => !blocked.has(p));
  if (removable.length === 0) return 0;

  await removeFiles(db, removable);
  const { data: gone, error: deleteError } = await db
    .from("music_tracks")
    .delete()
    .in("storage_path", removable)
    .not("received_at", "is", null)
    .select("id");
  if (deleteError) throw new Error(`music_tracks (borrar): ${deleteError.message}`);
  return gone?.length ?? 0;
}
