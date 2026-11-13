import { existsSync, readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import type { Plugin } from "vite";
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

// El servicio local de música (python -m kyora.merida) escribe al arrancar su dirección y su token en
// %APPDATA%\Kyora\merida_service.json. La página los pide aquí en cada conexión (si el servicio se reinicia, cambia
// el token). Solo responde a la propia página de Merida (Sec-Fetch-Site same-origin), no a otras webs.
function musicService(): Plugin {
  return {
    name: "merida-music-service",
    configureServer(server) {
      server.middlewares.use("/__music", (req, res) => {
        res.setHeader("Content-Type", "application/json; charset=utf-8");
        res.setHeader("Cache-Control", "no-store");
        const site = req.headers["sec-fetch-site"];
        if (site && site !== "same-origin") {
          res.statusCode = 403;
          res.end(JSON.stringify({ error: "forbidden" }));
          return;
        }
        const file = process.env.APPDATA ? join(process.env.APPDATA, "Kyora", "merida_service.json") : "";
        try {
          const info = JSON.parse(readFileSync(file, "utf-8"));
          res.end(JSON.stringify({ url: String(info.url ?? ""), token: String(info.token ?? "") }));
        } catch {
          res.statusCode = 503;
          res.end(JSON.stringify({ error: "El servicio de música no está abierto" }));
        }
      });
    },
  };
}

export default defineConfig({
  plugins: [musicService()],
  define: {
    __SUPABASE_URL__: JSON.stringify(env.values.SUPABASE_URL ?? ""),
    __SUPABASE_ANON_KEY__: JSON.stringify(env.values.SUPABASE_ANON_KEY ?? ""),
  },
  server: { port: 5180, strictPort: true, host: "127.0.0.1" },
  preview: { port: 5181, host: "127.0.0.1" },
  test: { environment: "jsdom", include: ["tests/**/*.test.ts"] },
});
