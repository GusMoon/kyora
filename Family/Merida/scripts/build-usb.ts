// Prepara la carpeta usb/: la deja lista para copiarla a un USB (o para abrirla desde aquí con `npm run usb`).
//   web/             el build de Merida
//   app/kyora/       solo los módulos de Python que usa el servicio de música
//   runtime/         Python (embeddable), Node y FFmpeg propios: la PC de destino no necesita instalar nada
// Nunca copia credenciales (.env, chat.env, cookies.txt) y se detiene si encuentra la contraseña o el correo del .env dentro de lo copiado.
// Uso: npm run build:usb [-- --force] [-- --skip-build]
//   --force       vuelve a armar runtime/ aunque ya exista
//   --skip-build  reutiliza dist/ sin volver a compilar
import { execFileSync, execSync } from "node:child_process";
import { copyFileSync, createWriteStream, existsSync, mkdirSync, readFileSync, readdirSync, renameSync, rmSync, statSync, writeFileSync } from "node:fs";
import { basename, dirname, join, resolve } from "node:path";
import { Readable } from "node:stream";
import { pipeline } from "node:stream/promises";
import type { ReadableStream as WebStream } from "node:stream/web";
import { fileURLToPath } from "node:url";
import { parseEnv } from "../src/env-file.ts";

const here = dirname(fileURLToPath(import.meta.url));
const merida = resolve(here, "..");
const repo = resolve(merida, "..", "..");
const kyora = join(repo, "Family", "Kyora");
const usb = join(merida, "usb");
const cache = join(usb, ".cache");
const force = process.argv.includes("--force");

/** Los módulos de Python que importa `kyora.merida.server` (el cierre de imports; nada de la interfaz de Kyora). */
const KYORA_FILES = [
  "__init__.py",
  "config.py",
  "chat/__init__.py",
  "chat/client.py",
  "chat/env.py",
  "chat/realtime.py",
  "chat/service.py",
  "chat/store.py",
  "core/__init__.py",
  "core/actions.py",
  "merida/__init__.py",
  "merida/__main__.py",
  "merida/server.py",
  "music/__init__.py",
  "music/proxy.py",
  "music/service.py",
  "music/sync.py",
  "music/ytdlp.py",
  "system/__init__.py",
  "system/audio.py",
  "system/shell.py",
];
/** Paquetes de Python de requirements.txt que lleva el servicio (se instalan con la versión fijada allí). */
const PY_PACKAGES = ["websockets", "yt-dlp", "yt-dlp-ejs"];
const FFMPEG_URL = "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip";
const SYSTEM_TAR = join(process.env.SystemRoot ?? "C:\\Windows", "System32", "tar.exe"); // bsdtar: sabe abrir .zip (el tar de Git no)

const step = (text: string) => console.log(`\n▸ ${text}`);
const fail = (text: string): never => {
  console.error(`\n✗ ${text}`);
  process.exit(1);
};

function emptyDir(path: string) {
  rmSync(path, { recursive: true, force: true });
  mkdirSync(path, { recursive: true });
}

function copyDir(from: string, to: string) {
  mkdirSync(to, { recursive: true });
  for (const entry of readdirSync(from, { withFileTypes: true })) {
    const src = join(from, entry.name);
    const dst = join(to, entry.name);
    if (entry.isDirectory()) copyDir(src, dst);
    else copyFileSync(src, dst);
  }
}

async function download(url: string, file: string) {
  if (existsSync(file)) return console.log(`  (ya descargado: ${file.slice(usb.length + 1)})`);
  console.log(`  descargando ${url}`);
  const res = await fetch(url, { redirect: "follow" });
  if (!res.ok || !res.body) throw new Error(`${url} respondió ${res.status}`);
  mkdirSync(dirname(file), { recursive: true });
  await pipeline(Readable.fromWeb(res.body as unknown as WebStream), createWriteStream(`${file}.part`));
  renameSync(`${file}.part`, file);
}

function unzip(zip: string, to: string) {
  mkdirSync(to, { recursive: true });
  execFileSync(SYSTEM_TAR, ["-xf", zip, "-C", to], { stdio: "inherit" });
}

function find(dir: string, name: string): string | null {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const path = join(dir, entry.name);
    if (entry.isDirectory()) {
      const hit = find(path, name);
      if (hit) return hit;
    } else if (entry.name.toLowerCase() === name) return path;
  }
  return null;
}

/** Todos los archivos de una carpeta (y sus subcarpetas), salvo las carpetas con esos nombres. */
function filesIn(dir: string, skip: string[] = []): string[] {
  return readdirSync(dir, { withFileTypes: true }).flatMap((e) => (skip.includes(e.name) ? [] : e.isDirectory() ? filesIn(join(dir, e.name), skip) : [join(dir, e.name)]));
}

function size(dir: string): number {
  return readdirSync(dir, { withFileTypes: true }).reduce((sum, e) => sum + (e.isDirectory() ? size(join(dir, e.name)) : statSync(join(dir, e.name)).size), 0);
}

// ---------------------------------------------------------------- 1. la web
if (process.argv.includes("--skip-build")) {
  if (!existsSync(join(merida, "dist", "index.html"))) fail("No hay dist/: quita --skip-build para compilar.");
} else {
  step("Compilando Merida (npm run build)");
  execSync("npm run build", { cwd: merida, stdio: "inherit" });
}
step("Copiando la web a usb/web");
emptyDir(join(usb, "web"));
copyDir(join(merida, "dist"), join(usb, "web"));

// ---------------------------------------------------------------- 2. el servicio de música (Python)
step("Copiando el servicio de música a usb/app/kyora");
emptyDir(join(usb, "app"));
for (const rel of KYORA_FILES) {
  const from = join(kyora, "kyora", rel);
  if (!existsSync(from)) fail(`Falta ${from}`);
  const to = join(usb, "app", "kyora", rel);
  mkdirSync(dirname(to), { recursive: true });
  copyFileSync(from, to);
}

// ---------------------------------------------------------------- 3. runtime/ (Python, Node, FFmpeg)
const pyDir = join(usb, "runtime", "python");
const nodeExe = join(usb, "runtime", "node", "node.exe");
const ffmpegDir = join(usb, "runtime", "ffmpeg");
const pyExe = join(pyDir, "python.exe");

if (force || !existsSync(pyExe)) {
  const cfg = join(kyora, ".venv", "pyvenv.cfg");
  const venvPython = join(kyora, ".venv", "Scripts", "python.exe");
  if (!existsSync(cfg) || !existsSync(venvPython)) fail("No encuentro Family/Kyora/.venv: hace falta para saber la versión de Python y para instalar yt-dlp.");
  const version = /^version\s*=\s*(\d+)\.(\d+)\.(\d+)/m.exec(readFileSync(cfg, "utf-8"));
  if (!version) fail("No se pudo leer la versión de Python de Family/Kyora/.venv/pyvenv.cfg.");
  const [, major, minor, patch] = version!;
  step(`Python ${major}.${minor}.${patch} (embeddable)`);
  const zip = join(cache, `python-${major}.${minor}.${patch}-embed-amd64.zip`);
  await download(`https://www.python.org/ftp/python/${major}.${minor}.${patch}/python-${major}.${minor}.${patch}-embed-amd64.zip`, zip);
  emptyDir(pyDir);
  unzip(zip, pyDir);
  // El archivo ._pth manda sobre sys.path: aquí van los paquetes de pip y el código del servicio (usb/app).
  writeFileSync(join(pyDir, `python${major}${minor}._pth`), [`python${major}${minor}.zip`, ".", "Lib/site-packages", "../../app", "import site", ""].join("\n"));

  const pins = readFileSync(join(kyora, "requirements.txt"), "utf-8")
    .split(/\r?\n/)
    .map((l) => /^([A-Za-z0-9._-]+)==([^\s#]+)/.exec(l))
    .filter((m): m is RegExpExecArray => !!m && PY_PACKAGES.includes(m[1].toLowerCase()))
    .map((m) => `${m[1]}==${m[2]}`);
  if (pins.length !== PY_PACKAGES.length) fail(`En Family/Kyora/requirements.txt faltan versiones fijadas de: ${PY_PACKAGES.join(", ")}.`);
  step(`Instalando ${pins.join(", ")}`);
  execFileSync(venvPython, ["-m", "pip", "install", "--no-deps", "--upgrade", "--target", join(pyDir, "Lib", "site-packages"), ...pins], { stdio: "inherit" });
}

if (force || !existsSync(nodeExe)) {
  step("Node.js (copia del que ejecuta este script)");
  mkdirSync(dirname(nodeExe), { recursive: true });
  copyFileSync(process.execPath, nodeExe);
}

if (force || !existsSync(join(ffmpegDir, "ffmpeg.exe"))) {
  step("FFmpeg (build essentials)");
  emptyDir(ffmpegDir);
  try {
    const zip = join(cache, "ffmpeg-release-essentials.zip");
    await download(FFMPEG_URL, zip);
    const extract = join(cache, "ffmpeg-extract");
    emptyDir(extract);
    unzip(zip, extract);
    for (const name of ["ffmpeg.exe", "ffprobe.exe"]) {
      const hit = find(extract, name);
      if (!hit) throw new Error(`el zip no trae ${name}`);
      copyFileSync(hit, join(ffmpegDir, name));
    }
    rmSync(extract, { recursive: true, force: true });
  } catch (err) {
    console.warn(`  No se pudo bajar FFmpeg (${(err as Error).message}); busco el que ya está instalado.`);
    const local = execFileSync("where", ["ffmpeg"], { encoding: "utf-8" }).split(/\r?\n/)[0]?.trim();
    if (!local || !existsSync(local)) fail("Tampoco hay un FFmpeg instalado: instálalo (winget install Gyan.FFmpeg) o revisa la conexión.");
    copyFileSync(local, join(ffmpegDir, "ffmpeg.exe"));
    const probe = join(dirname(local), "ffprobe.exe");
    if (existsSync(probe)) copyFileSync(probe, join(ffmpegDir, "ffprobe.exe"));
  }
}

// ---------------------------------------------------------------- 4. que no se cuele ningún secreto
step("Revisando que no haya credenciales");
const forbidden = filesIn(usb, [".cache"])
  .filter((path) => /(^|\.)env$/i.test(basename(path)) || basename(path).toLowerCase() === "cookies.txt")
  .map((path) => path.slice(usb.length + 1));
if (forbidden.length) fail(`Hay archivos de credenciales dentro de usb/: ${forbidden.join(", ")}`);

const envFile = [process.env.APPDATA ? join(process.env.APPDATA, "Kyora", "chat.env") : "", join(repo, "Server", "supabase", ".env")].find((p) => p && existsSync(p));
if (envFile) {
  const env = parseEnv(readFileSync(envFile, "utf-8"));
  const secrets = ["CHAT_PASSWORD", "CHAT_EMAIL"].map((k) => [k, env[k]] as const).filter(([, v]) => v && v.length >= 4);
  const leaks = new Set<string>();
  for (const path of [...filesIn(join(usb, "web")), ...filesIn(join(usb, "app"))]) {
    const data = readFileSync(path);
    for (const [key, value] of secrets) if (data.includes(value)) leaks.add(`${key} en ${path.slice(usb.length + 1)}`);
  }
  if (leaks.size) fail(`Una credencial del .env aparece dentro de lo copiado (${[...leaks].join("; ")}). No se debe copiar el USB.`);
  console.log("  Sin credenciales dentro de usb/.");
} else {
  console.log("  (no hay .env local con el que comparar; solo se comprobaron los nombres de archivo)");
}

// ---------------------------------------------------------------- 5. prueba de humo
step("Prueba de humo del servicio de música");
const smoke = execFileSync(pyExe, ["-c", "import kyora.merida.server, yt_dlp, websockets; print('imports ok')"], { cwd: usb, encoding: "utf-8" });
console.log(`  ${smoke.trim()}`);

console.log(`\n✓ usb/ listo (${(size(usb) / 1_000_000).toFixed(0)} MB con la caché de descargas; ${((size(usb) - (existsSync(cache) ? size(cache) : 0)) / 1_000_000).toFixed(0)} MB sin ella).`);
console.log("  Para el USB copia el contenido de usb/ sin la carpeta .cache. Para probar aquí: npm run usb");
