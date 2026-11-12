import { existsSync, readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { defineConfig } from "vitest/config";
import { parseEnv } from "./src/env-file.ts";

const here = dirname(fileURLToPath(import.meta.url));

// Las credenciales salen del mismo sitio que en Kyora (Family/Kyora/kyora/chat/env.py): primero
// %APPDATA%\Kyora\chat.env y, si no existe, Server/supabase/.env. Al navegador solo llegan la URL y la clave
// pública (anon); el correo y la contraseña del .env NUNCA se exponen: se escriben en la pantalla de acceso.
function envSource(): { path: string | null; values: Record<string, string> } {
  const candidates = [
    process.env.APPDATA ? join(process.env.APPDATA, "Kyora", "chat.env") : null,
    resolve(here, "..", "..", "Server", "supabase", ".env"),
  ].filter((p): p is string => !!p);
  for (const path of candidates) {
    if (existsSync(path)) return { path, values: parseEnv(readFileSync(path, "utf-8")) };
  }
  return { path: null, values: {} };
}

const env = envSource();

export default defineConfig({
  define: {
    __SUPABASE_URL__: JSON.stringify(env.values.SUPABASE_URL ?? ""),
    __SUPABASE_ANON_KEY__: JSON.stringify(env.values.SUPABASE_ANON_KEY ?? ""),
  },
  server: { port: 5180, strictPort: true, host: "127.0.0.1" },
  preview: { port: 5181, host: "127.0.0.1" },
  test: { environment: "jsdom", include: ["tests/**/*.test.ts"] },
});
