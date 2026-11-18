// Servidor local de Merida para el USB: sirve web/ (el build) en http://127.0.0.1:5180 y hace de puente /__music, igual que el
// servidor de desarrollo de Vite (vite.config.ts) pero sin instalar nada: solo usa módulos de Node.
// El puerto es el 5180 a propósito: el servicio de música (kyora.merida) solo acepta peticiones de ese origen.
// Uso: node server.mjs [--open]
import { spawn } from "node:child_process";
import { createReadStream, readFileSync } from "node:fs";
import { stat } from "node:fs/promises";
import { createServer as createHttpServer } from "node:http";
import { dirname, extname, join, resolve, sep } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

export const PORT = 5180;

const MIME = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".mjs": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".map": "application/json; charset=utf-8",
  ".txt": "text/plain; charset=utf-8",
  ".svg": "image/svg+xml",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".webp": "image/webp",
  ".gif": "image/gif",
  ".ico": "image/x-icon",
  ".woff": "font/woff",
  ".woff2": "font/woff2",
  ".ttf": "font/ttf",
};

function send(res, status, body, type = "text/plain; charset=utf-8") {
  res.writeHead(status, { "Content-Type": type, "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff" });
  res.end(body);
}

/** Dónde dejó el servicio de música su dirección y su token (el mismo archivo que lee vite.config.ts). */
function serviceFile(appData) {
  return appData ? join(appData, "Kyora", "merida_service.json") : "";
}

/** Responde /__music: `{ url, token }` del servicio de música, o 503 si no está abierto. Solo a la propia página (same-origin). */
function music(req, res, appData) {
  const site = req.headers["sec-fetch-site"];
  if (site && site !== "same-origin") return send(res, 403, JSON.stringify({ error: "forbidden" }), "application/json; charset=utf-8");
  try {
    const info = JSON.parse(readFileSync(serviceFile(appData), "utf-8"));
    send(res, 200, JSON.stringify({ url: String(info.url ?? ""), token: String(info.token ?? "") }), "application/json; charset=utf-8");
  } catch {
    send(res, 503, JSON.stringify({ error: "El servicio de música no está abierto" }), "application/json; charset=utf-8");
  }
}

/** El servidor (sin arrancar). `webDir` es la carpeta del build y `appData` el %APPDATA% donde escribe el servicio de música. */
export function createServer({ webDir, appData = process.env.APPDATA }) {
  const root = resolve(webDir);
  return createHttpServer(async (req, res) => {
    // Solo responde a su propia dirección: así una web ajena no puede usarlo (DNS rebinding).
    const port = req.socket.localPort;
    if (!["127.0.0.1", "localhost"].some((h) => req.headers.host === `${h}:${port}`)) return send(res, 403, "Host no permitido");
    if (req.method !== "GET" && req.method !== "HEAD") return send(res, 405, "Método no permitido");

    let pathname;
    try {
      pathname = decodeURIComponent(new URL(req.url ?? "/", "http://x").pathname);
    } catch {
      return send(res, 400, "Dirección no válida");
    }
    if (pathname.includes("\0")) return send(res, 400, "Dirección no válida");
    if (pathname === "/__music") return music(req, res, appData);

    let file = resolve(root, "." + pathname);
    if (file !== root && !file.startsWith(root + sep)) return send(res, 403, "Fuera de la carpeta");
    try {
      let info = await stat(file);
      if (info.isDirectory()) {
        file = join(file, "index.html");
        info = await stat(file);
      }
      const hashed = pathname.startsWith("/assets/"); // el build les pone un hash en el nombre: pueden guardarse siempre
      res.writeHead(200, {
        "Content-Type": MIME[extname(file).toLowerCase()] ?? "application/octet-stream",
        "Content-Length": info.size,
        "Cache-Control": hashed ? "public, max-age=31536000, immutable" : "no-cache",
        "X-Content-Type-Options": "nosniff",
      });
      if (req.method === "HEAD") return res.end();
      createReadStream(file).on("error", () => res.destroy()).pipe(res);
    } catch {
      send(res, 404, "No encontrado");
    }
  });
}

const isMain = process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href;
if (isMain) {
  const here = dirname(fileURLToPath(import.meta.url));
  const server = createServer({ webDir: join(here, "web") });
  server.on("error", (err) => {
    console.error(err.code === "EADDRINUSE" ? `El puerto ${PORT} está ocupado: Merida ya está abierta en otra ventana.` : `No se pudo arrancar: ${err.message}`);
    process.exit(1);
  });
  server.listen(PORT, "127.0.0.1", () => {
    const url = `http://127.0.0.1:${PORT}`;
    console.log(`Merida en ${url} (ciérrala con Ctrl+C o cerrando la ventana)`);
    if (process.argv.includes("--open")) spawn("cmd", ["/c", "start", "", url], { stdio: "ignore", windowsHide: true, detached: true }).unref();
  });
}
