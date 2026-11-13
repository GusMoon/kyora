// Comprueba Merida contra el servidor real SIN cambiar nada: entra con la cuenta del .env y solo lee
// (perfil y cuántas tareas, canciones y mensajes hay). Nunca imprime el correo, la contraseña ni las claves.
// Uso: npm run check:live
import { existsSync, readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { parseEnv } from "../src/env-file.ts";

const here = dirname(fileURLToPath(import.meta.url));
const candidates = [
  process.env.APPDATA ? join(process.env.APPDATA, "Kyora", "chat.env") : "",
  resolve(here, "..", "..", "..", "Server", "supabase", ".env"),
].filter(Boolean);
const source = candidates.find((p) => existsSync(p));
if (!source) {
  console.error("No encuentro Server/supabase/.env ni %APPDATA%\\Kyora\\chat.env.");
  process.exit(2);
}
const env = parseEnv(readFileSync(source, "utf-8"));
const missing = ["SUPABASE_URL", "SUPABASE_ANON_KEY", "CHAT_EMAIL", "CHAT_PASSWORD"].filter((k) => !env[k]);
if (missing.length) {
  console.error(`Faltan datos en el .env: ${missing.join(", ")}.`);
  process.exit(2);
}

const base = env.SUPABASE_URL.replace(/\/$/, "");
const headers: Record<string, string> = { apikey: env.SUPABASE_ANON_KEY, "Content-Type": "application/json" };

async function call(method: string, path: string, body?: unknown, extra: Record<string, string> = {}) {
  const res = await fetch(`${base}${path}`, { method, headers: { ...headers, ...extra }, body: body === undefined ? undefined : JSON.stringify(body) });
  const text = await res.text();
  if (!res.ok) throw new Error(`${method} ${path.split("?")[0]} respondió ${res.status}: ${text.slice(0, 200)}`);
  return { data: text ? JSON.parse(text) : null, headers: res.headers };
}

try {
  const login = await call("POST", "/auth/v1/token?grant_type=password", { email: env.CHAT_EMAIL, password: env.CHAT_PASSWORD });
  headers.Authorization = `Bearer ${login.data.access_token}`;
  console.log("Sesión: abierta");

  const t0 = performance.now();
  const profile = (await call("POST", "/rest/v1/rpc/my_profile", {})).data;
  console.log(`Perfil: ${profile ? `${profile.username} (${profile.role})` : "sin perfil"}, ${Math.round(performance.now() - t0)} ms`);

  const tasks = await call("GET", "/rest/v1/tasks?select=id&deleted_at=is.null&limit=1", undefined, { Prefer: "count=exact" });
  console.log(`Tareas: ${tasks.headers.get("content-range")?.split("/")[1] ?? "?"}`);

  const tracks = (await call("POST", "/rest/v1/rpc/list_music_tracks", { p_limit: 500 })).data;
  console.log(`Canciones: ${tracks.length}`);

  // la nube: los archivos que hay ahora en el servidor (adjuntos del chat y canciones), solo conteo y tamaño
  const atts = (await call("GET", "/rest/v1/attachments?select=id,storage_path,file_name,mime_type,size_bytes,created_at,message:messages(sender_device,deleted_at)&order=created_at.desc&limit=500")).data as { size_bytes: number; mime_type: string; message: { sender_device: string | null } | null }[];
  const songs = (await call("GET", "/rest/v1/music_tracks?select=storage_path,size_bytes&limit=500")).data as { storage_path: string; size_bytes: number }[];
  const byDevice = atts.reduce<Record<string, number>>((m, a) => ((m[a.message?.sender_device ?? "?"] = (m[a.message?.sender_device ?? "?"] ?? 0) + 1), m), {});
  console.log(`Adjuntos por dispositivo: ${JSON.stringify(byDevice)}`);
  const paths = new Set(songs.map((s) => s.storage_path));
  const mb = (n: number) => `${(n / 1048576).toFixed(1)} MB`;
  console.log(`Nube: ${atts.length} adjuntos del chat (${mb(atts.reduce((a, x) => a + Number(x.size_bytes || 0), 0))}) y ${paths.size} canciones (${mb(songs.reduce((a, x) => a + Number(x.size_bytes || 0), 0))} contando repetidas)`);

  const conv = (await call("POST", "/rest/v1/rpc/ensure_default_conversation", {})).data;
  const messages = (await call("POST", "/rest/v1/rpc/list_messages", { p_conversation_id: conv, p_before: null, p_after: null, p_limit: 100 })).data;
  console.log(`Mensajes (últimos 100): ${messages.length}`);
  console.log("Todo bien: Merida puede leer tareas, música, chat y la nube.");
} catch (err) {
  console.error(`Falló: ${(err as Error).message}`);
  process.exit(1);
}
