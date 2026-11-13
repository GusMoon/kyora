// Vista previa del diseño SIN Supabase: monta el tablero y las secciones con datos de ejemplo.
// Solo existe en desarrollo (http://127.0.0.1:5180/preview.html#/tareas); no entra en `npm run build`
// ni toca Supabase: el cliente de aquí es un sustituto que no hace nada. «Mis listas» sí usa el servicio local de
// música si está abierto (solo lee; descargar sigue pidiendo confirmar el destino).
import "@fontsource-variable/space-grotesk/wght.css";
import "@fontsource/ibm-plex-mono/400.css";
import "@fontsource/ibm-plex-mono/500.css";
import "@fontsource/ibm-plex-mono/700.css";
import "./styles/tokens.css";
import "./styles/base.css";
import "./styles/sections.css";
import "./styles/board.css";
import "./styles/settings.css";
import "./styles/fx.css";

import type { SupabaseClient } from "@supabase/supabase-js";
import { Store } from "./store";
import { Status } from "./status";
import { PrefsStore, applyAccent } from "./prefs";
import { Library } from "./data/library";
import { Backdrop } from "./backdrop";
import "./styles/backdrop.css";
import "./styles/cloud.css";
import { mergeCloud } from "./data/cloud";
import { cloudSection, cloudStatement } from "./sections/cloud";
import { fxConfig, hideBlocks, resetHidden, revealBlocks } from "./ui/fx";
import { settingsSection, settingsStatement } from "./sections/settings";
import { Shell, ROUTES, type RouteId } from "./ui/shell";
import { newTask, type Task } from "./data/tasks";
import type { Track } from "./data/music";
import type { Message } from "./data/chat";
import { tasksSection, tasksStatement } from "./sections/tasks";
import { musicSection, musicStatement } from "./sections/music";
import { chatSection, chatStatement } from "./sections/chat";
import type { Ctx, Section } from "./sections/context";
import type { Player } from "./player";

const ok = async () => ({ data: null, error: null });
const stub = {
  rpc: ok,
  from: () => ({ upsert: ok, select: () => ({ is: () => ({ limit: ok }) }) }),
  storage: { from: () => ({ createSignedUrl: async () => ({ data: null, error: { message: "Vista previa sin servidor" } }) }) },
} as unknown as SupabaseClient;

const now = new Date();
const at = (h: number, d = 0) => new Date(now.getFullYear(), now.getMonth(), now.getDate() + d, h).toISOString();
const t = (name: string, patch: Partial<Task> = {}) => ({ ...newTask(name, { id: name }), ...patch });

const tasks: Task[] = [
  t("Revisar el contrato de la casa", { due: at(18), position: 0 }),
  t("Comprar filtros para la cafetera", { position: 1 }),
  t("Llamar al dentista", { due: at(10, -1), position: 2 }),
  t("Migrar el chat a Merida", { status: "doing", expected_min: 90, position: 0 }),
  t("Probar la sincronización", { parent_id: "Migrar el chat a Merida", status: "done" }),
  t("Pantalla de música", { parent_id: "Migrar el chat a Merida" }),
  t("Leer el capítulo 4", { status: "review", position: 0 }),
  t("Pagar la luz", { status: "done", finished: at(9) }),
  t("Backup del NAS", { status: "done", finished: at(8, -1) }),
];

const track = (id: string, title: string, playlist: string | null, mb: number, d: number): Track => ({
  id, title, file_name: `${id}.mp3`, storage_path: `x/music/${id}.mp3`, mime_type: "audio/mpeg",
  size_bytes: mb * 1024 * 1024, playlist, cover_url: null, created_at: at(12, d), received_at: null,
});
const tracks = [
  track("a", "Midnight City", "Synthwave", 7.8, 0),
  track("b", "Nightcall", "Synthwave", 6.1, 0),
  track("c", "Teardrop", "Trip-hop", 8.9, -1),
  track("d", "Svefn-g-englar", null, 14.2, -3),
  track("e", "Intro", "The xx", 3.0, -4),
];

const msg = (id: string, device: string, body: string, h: number, extra: Partial<Message> = {}): Message => ({
  id, conversation_id: "c", sender_device: device, kind: "text", body, status: "sent",
  sent_at: at(h), created_at: at(h), deleted_at: null, attachments: [], ...extra,
});
const messages = [
  msg("1", "pc", "Te mandé las canciones de la lista Synthwave.", 9),
  msg("2", "movil", "Ya llegaron, gracias.", 10),
  msg("3", "pc", "Foto del pizarrón de la reunión", 11, { kind: "image", attachments: [{ id: "f", storage_path: "x", file_name: "pizarron.jpg", mime_type: "image/jpeg", size_bytes: 482113 }] }),
  msg("4", "web", "Probando Merida desde el navegador.", 12),
  { ...msg("5", "web", "Este se está enviando.", 13), local: "sending" as const },
];

// la nube de ejemplo: lo que se mandó por el chat y las canciones que subió la PC
const files = mergeCloud(
  [
    { id: "f1", storage_path: "u/c/m1/pizarron.jpg", file_name: "pizarron.jpg", mime_type: "image/jpeg", size_bytes: 482113, created_at: at(11), message: { sender_device: "pc", deleted_at: null } },
    { id: "f2", storage_path: "u/c/m2/contrato-casa.pdf", file_name: "contrato-casa.pdf", mime_type: "application/pdf", size_bytes: 1894400, created_at: at(10, -1), message: { sender_device: "movil", deleted_at: null } },
    { id: "f3", storage_path: "u/c/m3/captura.png", file_name: "captura.png", mime_type: "image/png", size_bytes: 920000, created_at: at(9, -3), message: { sender_device: "web", deleted_at: null } },
  ],
  tracks.map((tr) => ({ ...tr, owner_id: "me", recipient_id: "me", title: tr.title })),
  "me",
);

const store = new Store();
Object.assign(store, { tasks, tracks, messages, files, conversationId: "c", loaded: { tasks: true, tracks: true, messages: true, files: true } });

let listeners: ((s: Player["state"]) => void)[] = [];
let state: Player["state"] = { track: tracks[1], playing: true, loading: false, time: 74, duration: 258, error: null };
const player = {
  get state() { return state; },
  on(fn: (s: Player["state"]) => void) { listeners.push(fn); fn(state); return () => { listeners = listeners.filter((x) => x !== fn); }; },
  play(tr: Track) { state = { ...state, track: tr, time: 0 }; listeners.forEach((f) => f(state)); },
  toggle() { state = { ...state, playing: !state.playing }; listeners.forEach((f) => f(state)); },
  next() {}, previous() {}, seek() {}, stop() {},
} as unknown as Player;

const status = new Status();
const signOut = () => alert("Vista previa: no hay sesión que cerrar.");
const shell = new Shell({ store });
status.set({ account: "gustavo, admin", username: "gustavo", role: "admin", email: "gustavo@ejemplo.com", latency: 84, live: "live" });
const prefs = new PrefsStore();
const backdrop = new Backdrop();
document.body.prepend(backdrop.el);
const applyPrefs = () => {
  applyAccent((prefs.value.tint && backdrop.accent ? (backdrop.accent as `#${string}`) : null) ?? prefs.value.accent);
  fxConfig.hack = prefs.value.hack;
  fxConfig.holo = prefs.value.holo;
};
applyPrefs();
prefs.on(applyPrefs);
backdrop.on(applyPrefs);

// la portada de lo que suena es el fondo (en la vista previa, una portada de ejemplo dibujada aquí)
const demoCover = "data:image/svg+xml," + encodeURIComponent("<svg xmlns='http://www.w3.org/2000/svg' width='320' height='180'><rect width='320' height='180' fill='#d4237a'/><circle cx='230' cy='60' r='70' fill='#ff8a3d'/><rect x='0' y='120' width='320' height='60' fill='#401060'/></svg>");
const syncCover = () => backdrop.setCover(prefs.value.cover && state.playing && state.track ? demoCover : null);
player.on(syncCover);
prefs.on(syncCover);

const ctx: Ctx = { client: stub, shell, store, player, status, prefs, backdrop, library: new Library(), signOut, reload: async () => {} };
const SECTIONS: Record<RouteId, [Section, () => string]> = {
  inicio: [() => () => {}, () => ""],
  configuracion: [settingsSection, () => settingsStatement(status.data)],
  tareas: [tasksSection, () => tasksStatement(tasks, true)],
  musica: [musicSection, () => musicStatement(tracks, true)],
  nube: [cloudSection, () => cloudStatement(files, true)],
  chat: [chatSection, () => chatStatement(messages, true)],
};
let unmount: (() => void) | null = null;
let first = true;
let seq = 0;
// igual que main.ts: sale como holograma; la tesela crece (View Transitions) y a la vez lo nuevo entra como holograma
function route() {
  const id = (location.hash.replace(/^#\/?/, "") || "inicio") as RouteId;
  const key = ROUTES.some((r) => r.id === id) ? id : "inicio";
  if (!first && key === shell.route) return;
  const previous = shell.route;
  const token = ++seq;
  const firstTime = first;
  const swap = () => {
    unmount?.();
    shell.setSection(key, SECTIONS[key][1]());
    unmount = SECTIONS[key][0](ctx);
    shell.body.scrollTop = 0;
    resetHidden();
    const { blocks, texts } = shell.fxTargets(key);
    void revealBlocks(key === "inicio" && !firstTime ? [] : blocks, texts);
  };
  if (first) {
    first = false;
    swap();
    return;
  }
  const leaving = previous === "inicio" ? Promise.resolve() : hideBlocks(shell.fxTargets(previous).blocks, shell.fxTargets(previous).texts);
  void leaving.then(() => {
    if (token !== seq) return;
    const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    if (reduce || !("startViewTransition" in document)) swap();
    else document.startViewTransition(swap);
  });
}
window.addEventListener("hashchange", route);
window.addEventListener("keydown", (e) => {
  const target = e.target as HTMLElement | null;
  if (e.ctrlKey || e.metaKey || e.altKey || (target && ["INPUT", "TEXTAREA", "SELECT"].includes(target.tagName))) return;
  const r = e.key === "Escape" ? ROUTES[0] : ROUTES.find((x) => x.key.toLowerCase() === e.key.toLowerCase());
  if (r) location.hash = `#/${r.id}`;
});
document.getElementById("app")!.replaceChildren(shell.root);
route();
