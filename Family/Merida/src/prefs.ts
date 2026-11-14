/** Las preferencias de Merida en este navegador (Configuración): efectos, sección al abrir y color de acento.
 * Se guardan en localStorage; si el navegador no deja (modo privado, datos bloqueados) se usan las de siempre. */

import { DEFAULT_KEYS, type KeyMap } from "./routes";
import { resolveKeys } from "./hotkeys";
import type { View } from "./data/agenda";
import { FREE_DB_MB, FREE_FILES_MB } from "./data/server";

export type StartRoute = "inicio" | "tareas" | "musica" | "chat";
export type AccentId = "lima" | "naranja" | "cian" | "magenta" | "salvia";

export interface Prefs {
  hack: boolean; // efecto hacking en los textos
  holo: boolean; // holograma al abrir y cerrar
  start: StartRoute;
  accent: AccentId;
  tint: boolean; // vestir la app con los colores del fondo y de la portada que suena
  cover: boolean; // la portada de lo que suena, de fondo
  keys: KeyMap; // las teclas que abren cada sección
  notify: boolean; // avisar con una notificación del navegador cuando llega un mensaje
  sound: boolean; // con un sonido corto
  preview: boolean; // mostrar el texto del mensaje en el aviso (apagado: solo «Mensaje nuevo»)
  currency: string; // la moneda de Finanzas, código ISO de tres letras
  calendarView: View; // la vista del Calendario: día, semana o mes
  quotaDbMb: number; // el límite de la base de datos de tu plan de Supabase, en MB (gratuito: 500)
  quotaFilesMb: number; // el de los archivos (Storage), en MB (gratuito: 1024)
}

/** Las paletas de acento de Kyra (Family/Kyra/lib/state/palette_controller.dart). Lima es la de Merida. */
export const ACCENTS: { id: AccentId; name: string; color: string }[] = [
  { id: "lima", name: "Lima", color: "#c8f73a" },
  { id: "naranja", name: "Naranja", color: "#ff5a1f" },
  { id: "cian", name: "Cian", color: "#35d4ff" },
  { id: "magenta", name: "Magenta", color: "#ff4fd8" },
  { id: "salvia", name: "Salvia", color: "#c9cebc" },
];

export const START_OPTIONS: { id: StartRoute; name: string }[] = [
  { id: "inicio", name: "El mosaico" },
  { id: "tareas", name: "Tareas" },
  { id: "musica", name: "Música" },
  { id: "chat", name: "Chat" },
];

export const DEFAULT_PREFS: Prefs = {
  hack: true,
  holo: true,
  start: "inicio",
  accent: "lima",
  tint: true,
  cover: true,
  keys: DEFAULT_KEYS,
  notify: false,
  sound: true,
  preview: true,
  currency: "MXN",
  calendarView: "week",
  quotaDbMb: FREE_DB_MB,
  quotaFilesMb: FREE_FILES_MB,
};
const KEY = "merida-prefs";

type StorageLike = Pick<Storage, "getItem" | "setItem">;

function storage(): StorageLike | null {
  try {
    return window.localStorage;
  } catch {
    return null;
  }
}

/** Un límite en MB: un entero entre 1 y 10 millones; lo demás vuelve al de siempre. */
export const validMb = (v: unknown, fallback: number): number => (typeof v === "number" && Number.isInteger(v) && v >= 1 && v <= 10_000_000 ? v : fallback);

/** Las guardadas, validadas campo a campo (lo que no valga vuelve a su valor de siempre). */
export function loadPrefs(store: StorageLike | null = storage()): Prefs {
  let raw: Partial<Prefs> = {};
  try {
    raw = JSON.parse(store?.getItem(KEY) ?? "{}") ?? {};
  } catch {
    raw = {};
  }
  return {
    hack: typeof raw.hack === "boolean" ? raw.hack : DEFAULT_PREFS.hack,
    holo: typeof raw.holo === "boolean" ? raw.holo : DEFAULT_PREFS.holo,
    start: START_OPTIONS.some((o) => o.id === raw.start) ? (raw.start as StartRoute) : DEFAULT_PREFS.start,
    accent: ACCENTS.some((a) => a.id === raw.accent) ? (raw.accent as AccentId) : DEFAULT_PREFS.accent,
    tint: typeof raw.tint === "boolean" ? raw.tint : DEFAULT_PREFS.tint,
    cover: typeof raw.cover === "boolean" ? raw.cover : DEFAULT_PREFS.cover,
    keys: resolveKeys(raw.keys),
    notify: typeof raw.notify === "boolean" ? raw.notify : DEFAULT_PREFS.notify,
    sound: typeof raw.sound === "boolean" ? raw.sound : DEFAULT_PREFS.sound,
    preview: typeof raw.preview === "boolean" ? raw.preview : DEFAULT_PREFS.preview,
    calendarView: raw.calendarView === "day" || raw.calendarView === "week" || raw.calendarView === "month" ? raw.calendarView : DEFAULT_PREFS.calendarView,
    quotaDbMb: validMb(raw.quotaDbMb, DEFAULT_PREFS.quotaDbMb),
    quotaFilesMb: validMb(raw.quotaFilesMb, DEFAULT_PREFS.quotaFilesMb),
    currency: typeof raw.currency === "string" && /^[A-Z]{3}$/.test(raw.currency) ? raw.currency : DEFAULT_PREFS.currency,
  };
}

export function savePrefs(prefs: Prefs, store: StorageLike | null = storage()): void {
  try {
    store?.setItem(KEY, JSON.stringify(prefs));
  } catch {
    /* sin almacenamiento: vale solo para esta visita */
  }
}

/** El texto que va sobre un color: casi negro, o blanco si el color es muy oscuro (como AppPalette.onAccent de Kyra). */
export function onAccent(hex: string): string {
  const n = parseInt(hex.replace("#", ""), 16);
  const lin = (c: number) => {
    const v = c / 255;
    return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4;
  };
  const lum = 0.2126 * lin((n >> 16) & 255) + 0.7152 * lin((n >> 8) & 255) + 0.0722 * lin(n & 255);
  return lum > 0.18 ? "#0a0b0d" : "#ffffff";
}

/** Pone el acento en toda la página (las variables CSS que usa todo): una paleta elegida o un color suelto («#rrggbb»), como el que sale del fondo. */
export function applyAccent(choice: AccentId | `#${string}`, root: HTMLElement = document.documentElement): void {
  const color = choice.startsWith("#") ? choice : (ACCENTS.find((a) => a.id === choice) ?? ACCENTS[0]).color;
  const n = parseInt(color.slice(1), 16);
  root.style.setProperty("--accent", color);
  root.style.setProperty("--on-accent", onAccent(color));
  root.style.setProperty("--accent-soft", `rgba(${(n >> 16) & 255}, ${(n >> 8) & 255}, ${n & 255}, 0.14)`);
}

/** Las preferencias vivas: quien las cambia avisa a quien escucha (el acento y los efectos se aplican al momento). */
export class PrefsStore {
  value: Prefs;
  private listeners = new Set<(p: Prefs) => void>();

  constructor(initial: Prefs = loadPrefs()) {
    this.value = initial;
  }

  on(fn: (p: Prefs) => void): () => void {
    this.listeners.add(fn);
    return () => this.listeners.delete(fn);
  }

  set(patch: Partial<Prefs>) {
    this.value = { ...this.value, ...patch };
    savePrefs(this.value);
    for (const fn of this.listeners) fn(this.value);
  }
}
