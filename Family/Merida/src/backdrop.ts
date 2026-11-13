/** El fondo de pantalla de Merida, como en Kyra (Family/Kyra/lib/ui/widgets/app_backdrop.dart y state/wallpaper_controller.dart):
 * una imagen a pantalla completa, oscurecida de forma plana (0,42) y con las líneas de barrido encima; mientras suena una canción,
 * su portada pasa a ser el fondo; y los colores de la app (el acento) salen del fondo o de la portada.
 *
 * En la web el fondo es **temporal**: dura lo que dure la sesión. Se guarda reducido en `sessionStorage` (se va al cerrar la pestaña)
 * y se borra al cerrar sesión. La imagen nunca sale del navegador. */

/** Lo que se oscurece el fondo: plano, igual en toda la pantalla (kBackdropDim de Kyra). */
export const BACKDROP_DIM = 0.42;
const KEY = "merida-wallpaper";
const MAX_SIDE = 1600; // lado mayor al que se reduce la imagen para guardarla
const MAX_BYTES = 30 * 1024 * 1024;
const COVER_FADE_MS = 600;

type StorageLike = Pick<Storage, "getItem" | "setItem" | "removeItem">;

function sessionStore(): StorageLike | null {
  try {
    return window.sessionStorage;
  } catch {
    return null;
  }
}

function hex(n: number): string {
  return Math.round(n).toString(16).padStart(2, "0");
}

/** HSV (tono 0–360, saturación y brillo 0–1) a «#rrggbb». */
export function hsvToHex(h: number, s: number, v: number): string {
  const f = (n: number) => {
    const k = (n + h / 60) % 6;
    return (v - v * s * Math.max(0, Math.min(k, 4 - k, 1))) * 255;
  };
  return `#${hex(f(5))}${hex(f(3))}${hex(f(1))}`;
}

/** El acento de unos píxeles RGBA, como `accentOf` de Kyra: agrupa por tono (24 grupos), elige el que más pesa (saturación × brillo)
 * y devuelve su tono medio con saturación 0,78 y brillo de neón. `null` si apenas hay color (una foto gris, negra o blanca). */
export function accentOf(rgba: ArrayLike<number>): string | null {
  const buckets = 24;
  const weight = new Array<number>(buckets).fill(0);
  const sinSum = new Array<number>(buckets).fill(0);
  const cosSum = new Array<number>(buckets).fill(0);
  let colorful = 0;
  let total = 0;
  for (let i = 0; i + 3 < rgba.length; i += 4) {
    if (rgba[i + 3] < 128) continue;
    total++;
    const r = rgba[i] / 255;
    const g = rgba[i + 1] / 255;
    const b = rgba[i + 2] / 255;
    const max = Math.max(r, g, b);
    const min = Math.min(r, g, b);
    const d = max - min;
    const sat = max === 0 ? 0 : d / max;
    if (sat < 0.25 || max < 0.2) continue; // lo gris y lo casi negro no dan color
    colorful++;
    let hue = 0;
    if (d > 0) {
      if (max === r) hue = ((g - b) / d) % 6;
      else if (max === g) hue = (b - r) / d + 2;
      else hue = (r - g) / d + 4;
      hue *= 60;
      if (hue < 0) hue += 360;
    }
    const w = sat * max;
    const bucket = Math.floor((hue / 360) * buckets) % buckets;
    const rad = (hue * Math.PI) / 180;
    weight[bucket] += w;
    sinSum[bucket] += w * Math.sin(rad);
    cosSum[bucket] += w * Math.cos(rad);
  }
  if (total === 0 || colorful / total < 0.02) return null;
  let best = 0;
  for (let b = 1; b < buckets; b++) if (weight[b] > weight[best]) best = b;
  if (weight[best] <= 0) return null;
  let hue = (Math.atan2(sinSum[best], cosSum[best]) * 180) / Math.PI;
  if (hue < 0) hue += 360;
  return hsvToHex(hue, 0.78, 1);
}

export interface Prepared {
  url: string; // la imagen reducida, como dirección de datos
  accent: string | null;
}

/** Reduce la imagen elegida (lado mayor 1600 px, JPEG) para guardarla, y saca su color de acento. */
export async function prepareWallpaper(file: Blob): Promise<Prepared> {
  if (!file.type.startsWith("image/")) throw new Error("Ese archivo no es una imagen.");
  if (file.size > MAX_BYTES) throw new Error("La imagen pesa demasiado (30 MB como máximo).");
  const bitmap = await createImageBitmap(file);
  try {
    const scale = Math.min(1, MAX_SIDE / Math.max(bitmap.width, bitmap.height));
    const canvas = document.createElement("canvas");
    canvas.width = Math.max(1, Math.round(bitmap.width * scale));
    canvas.height = Math.max(1, Math.round(bitmap.height * scale));
    const ctx = canvas.getContext("2d");
    if (!ctx) throw new Error("El navegador no pudo leer la imagen.");
    ctx.drawImage(bitmap, 0, 0, canvas.width, canvas.height);
    const url = canvas.toDataURL("image/jpeg", 0.82);
    return { url, accent: sampleAccent(bitmap) };
  } finally {
    bitmap.close?.();
  }
}

/** El acento de una imagen ya cargada (reducida a 64 px de ancho, como Kyra). `null` si no se puede leer. */
function sampleAccent(source: CanvasImageSource & { width: number; height: number }): string | null {
  try {
    const w = 64;
    const h = Math.max(1, Math.round((source.height / source.width) * w));
    const small = document.createElement("canvas");
    small.width = w;
    small.height = h;
    const ctx = small.getContext("2d", { willReadFrequently: true });
    if (!ctx) return null;
    ctx.drawImage(source, 0, 0, w, h);
    return accentOf(ctx.getImageData(0, 0, w, h).data);
  } catch {
    return null; // una imagen de otro sitio sin permiso para leerla: queda el acento elegido
  }
}

export interface BackdropOptions {
  storage?: StorageLike | null;
  prepare?: (file: Blob) => Promise<Prepared>;
  /** Saca el color de una portada (por su dirección). En las pruebas, uno falso. */
  coverAccent?: (url: string) => Promise<string | null>;
}

function loadCoverAccent(url: string): Promise<string | null> {
  return new Promise((resolve) => {
    const img = new Image();
    img.crossOrigin = "anonymous";
    img.onload = () => resolve(sampleAccent(img));
    img.onerror = () => resolve(null);
    img.src = url;
  });
}

/** El fondo vivo: la imagen elegida, la portada que suena y los colores que salen de ellas. Quien lo cambia avisa a quien escucha. */
export class Backdrop {
  /** La capa que va detrás de todo (se añade al `body`). */
  readonly el: HTMLElement;
  wallpaper: string | null = null;
  wallpaperAccent: string | null = null;
  cover: string | null = null;
  coverAccent: string | null = null;
  busy = false;
  error = "";

  private readonly wall = document.createElement("div");
  private readonly covers = document.createElement("div");
  private readonly dim = document.createElement("div");
  private readonly lines = document.createElement("div");
  private readonly storage: StorageLike | null;
  private readonly prepare: (file: Blob) => Promise<Prepared>;
  private readonly lookup: (url: string) => Promise<string | null>;
  private listeners = new Set<() => void>();

  constructor(opts: BackdropOptions = {}) {
    this.storage = opts.storage === undefined ? sessionStore() : opts.storage;
    this.prepare = opts.prepare ?? prepareWallpaper;
    this.lookup = opts.coverAccent ?? loadCoverAccent;
    this.el = document.createElement("div");
    this.el.className = "backdrop";
    this.el.setAttribute("aria-hidden", "true");
    this.wall.className = "backdrop-wall";
    this.covers.className = "backdrop-covers";
    this.dim.className = "backdrop-dim";
    this.lines.className = "backdrop-lines";
    this.el.append(this.wall, this.covers, this.dim, this.lines);
    this.restore();
    this.paint();
  }

  /** Hay algo de fondo (imagen o portada): las superficies dejan ver lo de detrás y se oscurece. */
  get active(): boolean {
    return !!(this.wallpaper || this.cover);
  }

  on(fn: () => void): () => void {
    this.listeners.add(fn);
    return () => this.listeners.delete(fn);
  }

  private emit() {
    this.paint();
    for (const fn of this.listeners) fn();
  }

  private restore() {
    try {
      const saved = JSON.parse(this.storage?.getItem(KEY) ?? "null") as { url?: unknown; accent?: unknown } | null;
      if (saved && typeof saved.url === "string" && saved.url.startsWith("data:image/")) {
        this.wallpaper = saved.url;
        this.wallpaperAccent = typeof saved.accent === "string" ? saved.accent : null;
      }
    } catch {
      /* nada guardado, o roto: sin fondo */
    }
  }

  private persist() {
    try {
      if (this.wallpaper) this.storage?.setItem(KEY, JSON.stringify({ url: this.wallpaper, accent: this.wallpaperAccent }));
      else this.storage?.removeItem(KEY);
    } catch {
      /* no cabe: el fondo vale solo hasta recargar la página */
    }
  }

  /** Pone una imagen de fondo. Devuelve `false` (y `error` dice por qué) si no se pudo; el fondo que había se queda. */
  async setWallpaper(file: Blob): Promise<boolean> {
    this.busy = true;
    this.error = "";
    this.emit();
    try {
      const done = await this.prepare(file);
      this.wallpaper = done.url;
      this.wallpaperAccent = done.accent;
      this.persist();
      return true;
    } catch (err) {
      this.error = err instanceof Error && err.message ? err.message : "No se pudo poner esa imagen de fondo.";
      return false;
    } finally {
      this.busy = false;
      this.emit();
    }
  }

  /** Quita la imagen: vuelven el fondo liso y el acento elegido. */
  clearWallpaper() {
    this.wallpaper = null;
    this.wallpaperAccent = null;
    this.error = "";
    this.persist();
    this.emit();
  }

  /** La portada de lo que suena (o `null` si no suena nada): pasa a ser el fondo, con su color. */
  setCover(url: string | null) {
    if (url === this.cover) return;
    this.cover = url;
    this.coverAccent = null;
    this.emit();
    if (url) {
      void this.lookup(url).then((accent) => {
        if (this.cover !== url) return; // ya cambió la canción
        this.coverAccent = accent;
        this.emit();
      });
    }
  }

  /** Cierra la sesión del fondo: se borra todo (la imagen y la portada). */
  reset() {
    this.cover = null;
    this.coverAccent = null;
    this.clearWallpaper();
  }

  /** El color de la app que sale del fondo (primero la portada que suena, luego la imagen), o `null` si no hay o es casi gris. */
  get accent(): string | null {
    return this.cover ? (this.coverAccent ?? this.wallpaperAccent) : this.wallpaperAccent;
  }

  private paint() {
    this.wall.style.backgroundImage = this.wallpaper ? `url("${this.wallpaper}")` : "";
    this.wall.hidden = !this.wallpaper;
    this.dim.hidden = !this.active;
    document.documentElement.toggleAttribute("data-backdrop", this.active);
    // la portada: la nueva entra fundiéndose encima y la vieja se va después
    const current = this.covers.lastElementChild as HTMLElement | null;
    if (current?.dataset.src === (this.cover ?? "")) return;
    for (const old of [...this.covers.children]) {
      old.classList.remove("in");
      window.setTimeout(() => old.remove(), COVER_FADE_MS);
    }
    if (this.cover) {
      const layer = document.createElement("div");
      layer.className = "backdrop-cover";
      layer.dataset.src = this.cover;
      layer.style.backgroundImage = `url("${this.cover.replace(/"/g, "%22")}")`;
      this.covers.append(layer);
      requestAnimationFrame(() => layer.classList.add("in"));
    }
  }
}
