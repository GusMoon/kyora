// Vista previa del diseño SIN Supabase: monta el tablero y las secciones con datos de ejemplo.
// Solo existe en desarrollo (http://127.0.0.1:5180/preview.html#/tareas); no entra en `npm run build`
// ni toca Supabase: el cliente de aquí es una base de datos en memoria (se pierde al recargar). «Mis listas» sí usa el
// servicio local de música si está abierto (solo lee; descargar sigue pidiendo confirmar el destino).
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
import "./styles/forms.css";
import "./styles/modules.css";
import "./styles/calendar.css";

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
import { Shell } from "./ui/shell";
import { ROUTES, type RouteId } from "./routes";
import { routeForKey } from "./hotkeys";
import { isTyping } from "./ui/dom";
import { Palette } from "./ui/palette";
import { buildPaletteItems } from "./paletteItems";
import { VaultSession } from "./vault/session";
import { newTask, newTag, type Tag, type Task, type TaskTag } from "./data/tasks";
import { newEvent, type CalendarEvent } from "./data/events";
import { newReminder, type Reminder } from "./data/reminders";
import { newHabit, type Habit, type HabitCheck } from "./data/habits";
import { MB, overQuota, percent, type ServerStats } from "./data/server";
import { newCategory, newEntry, DEFAULT_CATEGORIES, type FinanceCategory, type FinanceEntry } from "./data/finance";
import type { Track } from "./data/music";
import type { Message } from "./data/chat";
import { tasksSection, tasksStatement } from "./sections/tasks";
import { calendarSection } from "./sections/calendar";
import { musicSection, musicStatement } from "./sections/music";
import { chatSection, chatStatement } from "./sections/chat";
import { vaultSection } from "./sections/vault";
import { financeSection } from "./sections/finance";
import { improvementsSection } from "./sections/improvements";
import type { Improvement } from "./data/improvements";
import type { Ctx, Section } from "./sections/context";
import type { Player } from "./player";

// ----- una «base de datos» en memoria con lo justo del cliente de Supabase (select/insert/upsert/update y filtros simples)
type Row = Record<string, unknown>;
const db: Record<string, Row[]> = {};
function table(name: string) {
  const rows = (db[name] ??= []);
  let op: "select" | "insert" | "upsert" | "update" = "select";
  let payload: unknown;
  const filters: ((r: Row) => boolean)[] = [];
  let maybe = false;
  const run = () => {
    if (op === "insert" || op === "upsert") {
      for (const r of (Array.isArray(payload) ? payload : [payload]) as Row[]) {
        const key = name === "task_tags" ? (x: Row) => x.task_id === r.task_id && x.tag_id === r.tag_id : (x: Row) => x.id !== undefined && x.id === r.id;
        const i = rows.findIndex(key);
        if (i >= 0) rows[i] = { ...rows[i], ...r };
        else rows.push({ ...r });
      }
      return { data: null, error: null };
    }
    const hit = rows.filter((r) => filters.every((f) => f(r)));
    if (op === "update") {
      for (const r of hit) Object.assign(r, payload as Row);
      return { data: null, error: null };
    }
    return { data: maybe ? (hit[0] ?? null) : hit.map((r) => ({ ...r })), error: null };
  };
  const b: Record<string, unknown> = {
    select: () => b,
    order: () => b,
    limit: () => b,
    range: () => b,
    in: () => b,
    is: (col: string, val: unknown) => (filters.push((r) => (r[col] ?? null) === val), b),
    eq: (col: string, val: unknown) => (filters.push((r) => r[col] === val), b),
    maybeSingle: () => ((maybe = true), b),
    insert: (p: unknown) => ((op = "insert"), (payload = p), b),
    upsert: (p: unknown) => ((op = "upsert"), (payload = p), b),
    update: (p: unknown) => ((op = "update"), (payload = p), b),
    then: (resolve: (v: unknown) => unknown) => Promise.resolve(run()).then(resolve),
  };
  return b;
}

const stub = {
  from: table,
  rpc: async (fn: string, args: Record<string, unknown> = {}) => {
    if (fn === "send_message") {
      const atts = (args.p_attachments as Row[]) ?? [];
      return {
        data: { id: args.p_id, conversation_id: args.p_conversation_id, sender_device: "web", kind: atts.length ? "file" : "text", body: args.p_body || null, status: "sent", sent_at: args.p_sent_at, created_at: args.p_sent_at, deleted_at: null, attachments: atts.map((a, i) => ({ id: `${args.p_id}:${i}`, ...a })) },
        error: null,
      };
    }
    if (fn === "list_messages") return { data: [], error: null };
    if (fn === "list_presence") {
      // cuentas de ejemplo para ver el panel «Usuarios» (quién está en línea) sin servidor
      const ago = (min: number) => new Date(Date.now() - min * 60000).toISOString();
      return {
        data: [
          { id: "me", username: "kyora1947", role: "admin", verified: true, last_seen: ago(0), online: true, code_pending: false, me: true },
          { id: "u1", username: "ana", role: "intern", verified: true, last_seen: ago(0), online: true, code_pending: false, me: false },
          { id: "u2", username: "luis", role: "intern", verified: true, last_seen: ago(190), online: false, code_pending: false, me: false },
          { id: "u3", username: "marta", role: "intern", verified: false, last_seen: null, online: false, code_pending: true, me: false },
        ],
        error: null,
      };
    }
    return { data: null, error: null };
  },
  storage: {
    from: () => ({
      createSignedUrl: async () => ({ data: null, error: { message: "Vista previa sin servidor" } }),
      upload: async () => ({ data: { path: "x" }, error: null }),
      remove: async () => ({ data: [], error: null }),
    }),
  },
} as unknown as SupabaseClient;

const now = new Date();
const at = (h: number, d = 0) => new Date(now.getFullYear(), now.getMonth(), now.getDate() + d, h).toISOString();
const t = (name: string, patch: Partial<Task> = {}) => ({ ...newTask(name, { id: name }), ...patch });

const tasks: Task[] = [
  t("Revisar el contrato de la casa", { due: at(18), position: 0, expected_min: 45, description: "Leer las cláusulas de renovación y subrayar lo del depósito." }),
  t("Comprar filtros para la cafetera", { position: 1 }),
  t("Llamar al dentista", { due: at(10, -1), position: 2 }),
  t("Migrar el chat a Merida", { status: "doing", expected_min: 90, real_s: 3725, position: 0 }),
  t("Probar la sincronización", { parent_id: "Migrar el chat a Merida", status: "done" }),
  t("Pantalla de música", { parent_id: "Migrar el chat a Merida" }),
  t("Leer el capítulo 4", { status: "review", position: 0, due: at(12, 3) }),
  t("Pagar la luz", { status: "done", finished: at(9) }),
  t("Backup del NAS", { status: "done", finished: at(8, -1) }),
];
const tags: Tag[] = [newTag("casa", "#ff5a1f", now, "tag-casa"), newTag("trabajo", "#35d4ff", now, "tag-trabajo"), newTag("urgente", "#ff4fd8", now, "tag-urgente")];
const taskTags: TaskTag[] = [
  { task_id: "Revisar el contrato de la casa", tag_id: "tag-casa", updated_at: now.toISOString(), deleted_at: null },
  { task_id: "Migrar el chat a Merida", tag_id: "tag-trabajo", updated_at: now.toISOString(), deleted_at: null },
  { task_id: "Llamar al dentista", tag_id: "tag-urgente", updated_at: now.toISOString(), deleted_at: null },
];
const events: CalendarEvent[] = [
  newEvent("Reunión con el equipo", new Date(now.getFullYear(), now.getMonth(), now.getDate(), 11, 0), { end: new Date(now.getFullYear(), now.getMonth(), now.getDate(), 12, 0), color: "#35d4ff", id: "ev1", description: "Revisar el avance de Merida." }),
  newEvent("Cumpleaños de Ana", new Date(now.getFullYear(), now.getMonth(), now.getDate() + 2), { allDay: true, color: "#ff4fd8", id: "ev2" }),
  newEvent("Entrega del informe", new Date(now.getFullYear(), now.getMonth(), now.getDate() + 5, 17, 30), { color: "#ffd23f", id: "ev3" }),
];
const reminders: Reminder[] = [
  newReminder("Llamar a la aseguradora", new Date(now.getFullYear(), now.getMonth(), now.getDate(), 16, 30), { id: "rm1", notes: "Preguntar por la póliza de la casa." }),
  newReminder("Sacar la basura", new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1, 20, 0), { id: "rm2" }),
  newReminder("Renovar el dominio", new Date(now.getFullYear(), now.getMonth(), now.getDate() + 4, 9, 0), { id: "rm3" }),
];
// los hábitos son los de Kyra: creados hace dos semanas para que haya historial
const habitStart = new Date(now.getFullYear(), now.getMonth(), now.getDate() - 14);
const habits: Habit[] = [
  newHabit("Beber agua", { id: "hb1", now: habitStart, remindAt: 9 * 60 }),
  newHabit("Leer 20 minutos", { id: "hb2", now: habitStart, weekdays: 0b0011111, remindAt: 21 * 60, position: 1 }),
  newHabit("Estirar", { id: "hb3", now: habitStart, position: 2 }),
];
const habitChecks: HabitCheck[] = [-1, -2, -3, -5].flatMap((d) => {
  const key = new Date(now.getFullYear(), now.getMonth(), now.getDate() + d);
  const day = `${key.getFullYear()}-${String(key.getMonth() + 1).padStart(2, "0")}-${String(key.getDate()).padStart(2, "0")}`;
  return ["hb1", "hb3"].map((id) => ({ habit_id: id, day, done: true, updated_at: now.toISOString() }));
});
// el servidor de ejemplo: la base de datos al 84 % para que se vea la advertencia
const serverStats: ServerStats = {
  db_bytes: 420 * MB, storage_bytes: 318 * MB, storage_objects: 57, at: new Date(Date.now() - 4 * 60_000).toISOString(),
  buckets: [{ bucket: "chat-files", objects: 41, bytes: 244 * MB }, { bucket: "music", objects: 16, bytes: 74 * MB }],
  tables: [{ name: "messages", bytes: 38 * MB, rows: 12840 }, { name: "tasks", bytes: 9 * MB, rows: 640 }, { name: "attachments", bytes: 6 * MB, rows: 410 }, { name: "finance_entries", bytes: 2 * MB, rows: 380 }, { name: "habit_checks", bytes: 1 * MB, rows: 900 }],
};
const financeCategories: FinanceCategory[] = DEFAULT_CATEGORIES.map((c, i) => newCategory(c.name, c.kind, c.color, now, `cat${i}`));
const cat = (name: string) => financeCategories.find((c) => c.name === name)!.id;
const day = (d: number) => `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}-${String(Math.max(1, Math.min(28, d))).padStart(2, "0")}`;
const financeEntries: FinanceEntry[] = [
  newEntry({ kind: "income", amount_cents: 1850000, category_id: cat("Sueldo"), description: "Quincena", occurred_on: day(1) }, now, "fe1"),
  newEntry({ kind: "expense", amount_cents: 420000, category_id: cat("Casa"), description: "Renta", occurred_on: day(2) }, now, "fe2"),
  newEntry({ kind: "expense", amount_cents: 86550, category_id: cat("Comida"), description: "Súper", occurred_on: day(5) }, now, "fe3"),
  newEntry({ kind: "expense", amount_cents: 32000, category_id: cat("Transporte"), description: "Gasolina", occurred_on: day(8) }, now, "fe4"),
  newEntry({ kind: "expense", amount_cents: 17900, category_id: cat("Ocio"), description: "Cine", occurred_on: day(10) }, now, "fe5"),
  newEntry({ kind: "income", amount_cents: 250000, category_id: cat("Otros ingresos"), description: "Venta de la bici", occurred_on: day(11) }, now, "fe6"),
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

const improvements: Improvement[] = [
  { id: "m1", section: "Calendario", functions: "Vista de agenda\nArrastrar eventos entre días", description: "Que se pueda reordenar sin abrir cada evento.", created_at: now.toISOString() },
  { id: "m2", section: "Música", functions: "Cola de reproducción", description: "", created_at: new Date(now.getTime() - 86_400_000).toISOString() },
];
const store = new Store();
Object.assign(store, {
  tasks, tags, taskTags, tracks, messages, files, events, reminders, habits, habitChecks, serverStats, financeEntries, financeCategories, conversationId: "c", improvements,
  loaded: { tasks: true, tags: true, tracks: true, messages: true, files: true, events: true, finance: true, reminders: true, habits: true, improvements: true, server: true },
});

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
const prefs = new PrefsStore();
const vault = new VaultSession(stub);
const shell = new Shell({ store, vault, prefs });
const over = overQuota(serverStats, { db: prefs.value.quotaDbMb, files: prefs.value.quotaFilesMb });
if (over.length) shell.setAlert("nube", percent(Math.max(...over.map((q) => q.ratio))), "El servidor está casi lleno");
status.set({ account: "gustavo, admin", username: "gustavo", role: "admin", email: "gustavo@ejemplo.com", latency: 84, live: "live" });
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
void vault.refresh();

// la portada de lo que suena es el fondo (en la vista previa, una portada de ejemplo dibujada aquí)
const demoCover = "data:image/svg+xml," + encodeURIComponent("<svg xmlns='http://www.w3.org/2000/svg' width='320' height='180'><rect width='320' height='180' fill='#d4237a'/><circle cx='230' cy='60' r='70' fill='#ff8a3d'/><rect x='0' y='120' width='320' height='60' fill='#401060'/></svg>");
const syncCover = () => backdrop.setCover(prefs.value.cover && state.playing && state.track ? demoCover : null);
player.on(syncCover);
prefs.on(syncCover);

const ctx: Ctx = { client: stub, shell, store, player, status, prefs, backdrop, library: new Library(), vault, userId: "me", signOut, reload: async () => {} };
const SECTIONS: Record<RouteId, [Section, () => string]> = {
  inicio: [() => () => {}, () => ""],
  configuracion: [settingsSection, () => settingsStatement(status.data)],
  tareas: [tasksSection, () => tasksStatement(tasks, true)],
  calendario: [calendarSection, () => ""],
  musica: [musicSection, () => musicStatement(tracks, true)],
  nube: [cloudSection, () => cloudStatement(files, true)],
  chat: [chatSection, () => chatStatement(messages, true)],
  contrasenas: [vaultSection, () => ""],
  finanzas: [financeSection, () => ""],
  mejoras: [improvementsSection, () => ""],
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
const palette = new Palette(() => buildPaletteItems({ client: stub, store, prefs, vault, go: (hash) => { location.hash = hash; } }));
window.addEventListener("hashchange", route);
window.addEventListener("keydown", (e) => {
  if ((e.ctrlKey || e.metaKey) && !e.altKey && !e.shiftKey && e.key.toLowerCase() === "k") {
    e.preventDefault();
    palette.toggle();
    return;
  }
  if (e.key === "Escape") {
    if (e.defaultPrevented || palette.isOpen || document.querySelector('[aria-modal="true"]')) return;
    if (isTyping(e.target)) return void (e.target as HTMLElement).blur();
    if (shell.route !== "inicio") location.hash = "#/inicio";
    return;
  }
  if (e.ctrlKey || e.metaKey || e.altKey || isTyping(e.target)) return;
  const id = routeForKey(prefs.value.keys, e.key);
  if (id) location.hash = `#/${id}`;
});
document.getElementById("app")!.replaceChildren(shell.root);
route();
