import type { SupabaseClient } from "@supabase/supabase-js";

/** Una canción que te mandaron desde la PC (`music_tracks`). Merida solo la escucha: nunca confirma «Recibido»,
 * porque eso deja que la limpieza automática borre el MP3 del servidor. */
export interface Track {
  id: string;
  title: string;
  file_name: string;
  storage_path: string;
  mime_type: string;
  size_bytes: number;
  playlist: string | null;
  cover_url: string | null;
  created_at: string;
  received_at: string | null;
}

export const BUCKET = "chat-files";

export async function listTracks(client: SupabaseClient, limit = 100): Promise<Track[]> {
  const { data, error } = await client.rpc("list_music_tracks", { p_limit: limit });
  if (error) throw error;
  return (data ?? []) as Track[];
}

/** Una URL temporal (1 h) para reproducir el archivo en el navegador. */
export async function trackUrl(client: SupabaseClient, path: string): Promise<string> {
  const { data, error } = await client.storage.from(BUCKET).createSignedUrl(path, 3600);
  if (error || !data) throw error ?? new Error("Sin URL");
  return data.signedUrl;
}

export function formatSize(bytes: number): string {
  if (!bytes) return "0 KB";
  if (bytes < 1024 * 1024) return `${Math.max(1, Math.round(bytes / 1024))} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

export function formatTime(seconds: number): string {
  if (!Number.isFinite(seconds) || seconds < 0) return "0:00";
  const s = Math.floor(seconds);
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
}

/** Las listas de reproducción distintas, en el orden en que aparecen. */
export function playlists(tracks: Track[]): string[] {
  return [...new Set(tracks.map((t) => t.playlist).filter((p): p is string => !!p))];
}
