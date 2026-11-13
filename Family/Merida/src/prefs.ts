/** Las preferencias de Merida en este navegador (Configuración): efectos, sección al abrir y color de acento.
 * Se guardan en localStorage; si el navegador no deja (modo privado, datos bloqueados) se usan las de siempre. */

export type StartRoute = "inicio" | "tareas" | "musica" | "chat";
export type AccentId = "lima" | "naranja" | "cian" | "magenta" | "salvia";

export interface Prefs {
  hack: boolean; // efecto hacking en los textos
  holo: boolean; // holograma al abrir y cerrar
  start: StartRoute;
  accent: AccentId;
  tint: boolean; // vestir la app con los colores del fondo y de la portada que suena
  cover: boolean; // la portada de lo que suena, de fondo
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

export const DEFAULT_PREFS: Prefs = { hack: true, holo: true, start: "inicio", accent: "lima", tint: true, cover: true };
const KEY = "merida-prefs";

type StorageLike = Pick<Storage, "getItem" | "setItem">;

function storage(): StorageLike | null {
  try {
    return window.localStorage;
  } catch {
    return null;
  }
}

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
