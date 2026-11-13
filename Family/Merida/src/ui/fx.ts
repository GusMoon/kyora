/** Los efectos de Kyra en la web: el texto que se escribe «hackeado» y el holograma al abrir y cerrar.
 * Las cifras son las de Kyra (Family/Kyra/lib/ui/widgets/hack_text.dart y section_motion.dart). */

/** Se encienden y apagan desde Configuración; con «reducir movimiento» del sistema, siempre apagados. */
export const fxConfig = { hack: true, holo: true };

function reducedMotion(): boolean {
  try {
    return window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  } catch {
    return false;
  }
}

export const hackEnabled = () => fxConfig.hack && !reducedMotion();
export const holoEnabled = () => fxConfig.holo && !reducedMotion();

/** El ruido determinista de Kyra (SectionMotion.noise): mismo resultado para la misma semilla y paso. */
export function noise(seed: number, tick: number): number {
  let x = (Math.imul(seed, 374761393) + Math.imul(tick, 668265263)) & 0x7fffffff;
  x = Math.imul(x ^ (x >> 13), 1274126177) & 0x7fffffff;
  return (x & 0xffff) / 0xffff;
}

// ---------------------------------------------------------------- texto hacking

export const GLYPHS = "░▒▓#@$%&*+=<>/\\01ｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄ";
const PER_CHAR = 14;
const WINDOW = 3;
const FLICKER = 30;
const MIN_MS = 180;
const MAX_MS = 560;
const EXIT_MS = 210;

export const hackDuration = (len: number) => Math.min(MAX_MS, Math.max(MIN_MS, PER_CHAR * (len + WINDOW)));

/** Un fotograma: lo ya escrito, el ruido (hasta 3 caracteres) y lo que falta (se pinta transparente). */
export function hackFrame(text: string, progress: number, tick: number): { done: string; noise: string; rest: string } {
  const len = text.length;
  const shown = Math.floor(Math.max(0, Math.min(1, progress)) * (len + WINDOW));
  const done = Math.max(0, Math.min(len, shown - WINDOW));
  const end = Math.max(0, Math.min(len, shown));
  let noisy = "";
  for (let i = done; i < end; i++) {
    const ch = text[i];
    noisy += ch === " " || ch === "\n" ? ch : GLYPHS[(i * 7 + tick * 13 + len) % GLYPHS.length];
  }
  return { done: text.slice(0, done), noise: noisy, rest: text.slice(end) };
}

const running = new WeakMap<Element, () => void>();

/** El texto de verdad de un elemento, aunque esté a medio escribir (entonces lleva dos copias: la de los lectores de
 * pantalla y la animada, y `textContent` las juntaría: «MÚSICAMÚSICA»). */
export function plainText(el: Element): string {
  const sr = el.querySelector(":scope > .sr-only");
  return sr ? (sr.textContent ?? "") : (el.textContent ?? "");
}

function paint(el: HTMLElement, text: string, frame: ReturnType<typeof hackFrame>) {
  const sr = document.createElement("span");
  sr.className = "sr-only";
  sr.textContent = text;
  const shown = document.createElement("span");
  shown.setAttribute("aria-hidden", "true");
  shown.append(frame.done);
  if (frame.noise) {
    const n = document.createElement("span");
    n.className = "hack-noise";
    n.textContent = frame.noise;
    shown.append(n);
  }
  if (frame.rest) {
    const r = document.createElement("span");
    r.className = "hack-rest";
    r.textContent = frame.rest;
    shown.append(r);
  }
  el.replaceChildren(sr, shown);
}

/** Escribe `text` en `el` con el efecto (de izquierda a derecha, con una ventana de ruido delante). Devuelve una
 * promesa que se cumple al terminar. Sin efecto, lo pone de golpe. */
export function hackText(el: HTMLElement, text = plainText(el), opts: { delay?: number } = {}): Promise<void> {
  running.get(el)?.();
  if (!hackEnabled() || !text.trim()) {
    el.textContent = text;
    return Promise.resolve();
  }
  const duration = hackDuration(text.length);
  const delay = opts.delay ?? 0;
  return new Promise((resolve) => {
    let frameId = 0;
    const start = performance.now();
    const stop = () => {
      cancelAnimationFrame(frameId);
      el.textContent = text;
      running.delete(el);
      resolve();
    };
    running.set(el, stop);
    paint(el, text, hackFrame(text, 0, 0));
    const step = (now: number) => {
      const elapsed = now - start;
      const progress = (elapsed - delay) / duration;
      if (progress >= 1) return stop();
      paint(el, text, hackFrame(text, progress, Math.floor(elapsed / FLICKER)));
      frameId = requestAnimationFrame(step);
    };
    frameId = requestAnimationFrame(step);
  });
}

/** Lo des-escribe (de derecha a izquierda) en 210 ms, como al cerrar en Kyra. */
export function hackOut(el: HTMLElement): Promise<void> {
  const text = plainText(el);
  running.get(el)?.();
  if (!hackEnabled() || !text.trim()) return Promise.resolve();
  return new Promise((resolve) => {
    let frameId = 0;
    const start = performance.now();
    const stop = () => {
      cancelAnimationFrame(frameId);
      el.textContent = text;
      running.delete(el);
      resolve();
    };
    running.set(el, stop);
    const step = (now: number) => {
      const t = Math.min(1, (now - start) / EXIT_MS);
      if (t >= 1) {
        cancelAnimationFrame(frameId);
        running.delete(el);
        resolve();
        return;
      }
      paint(el, text, hackFrame(text, 1 - t, Math.floor((1 - t) * 33)));
      frameId = requestAnimationFrame(step);
    };
    frameId = requestAnimationFrame(step);
  });
}

// ---------------------------------------------------------------- holograma

const STEPS = 9;
const ENTER_MS = 240;
const EXIT_HOLO_MS = 210;
const easeOut = (t: number) => 1 - (1 - t) * (1 - t);

export type Edge = "top" | "bottom" | "left" | "right";
const EDGE_INDEX: Record<Edge, number> = { top: 0, bottom: 1, left: 2, right: 3 };

/** El parpadeo de Kyra: en ~30 % de los pasos la opacidad cae a 0.3 de lo que toca. */
export function glitchOpacity(shown: number, seed: number, tick: number): number {
  if (shown <= 0) return 0;
  if (shown >= 1) return 1;
  return noise(seed, tick) < 0.3 ? shown * 0.3 : shown;
}

/** El salto: hasta ±14 px a los lados y una deriva de 10 px hacia su borde mientras no está del todo. */
export function glitchShift(shown: number, seed: number, tick: number, edge: Edge): { x: number; y: number } {
  if (shown >= 1) return { x: 0, y: 0 };
  const g = 1 - shown;
  let x = (noise(seed + 11, tick) - 0.5) * 2 * 14 * g;
  let y = 0;
  if (edge === "top") y -= 10 * g;
  if (edge === "bottom") y += 10 * g;
  if (edge === "left") x -= 10 * g;
  if (edge === "right") x += 10 * g;
  return { x, y };
}

/** Los fotogramas del holograma: de nada a entero (entrada) o al revés (salida), a saltos. */
export function hologramFrames(order: number, edge: Edge, mode: "in" | "out"): Keyframe[] {
  const seed = order * 7 + EDGE_INDEX[edge] * 3 + 1;
  const frames: Keyframe[] = [];
  for (let i = 0; i <= STEPS; i++) {
    const t = i / STEPS;
    const shown = mode === "in" ? easeOut(t) : 1 - t;
    const tick = Math.floor(shown * STEPS);
    const { x, y } = glitchShift(shown, seed, tick, edge);
    frames.push({ offset: t, opacity: glitchOpacity(shown, seed, tick), transform: `translate(${x.toFixed(1)}px, ${y.toFixed(1)}px)`, easing: "steps(1, end)" });
  }
  return frames;
}

/** Hace entrar (o salir) un bloque como un holograma: parpadeo, saltos y bandas de interferencia encima. */
export function hologram(el: HTMLElement, opts: { order?: number; edge?: Edge; mode?: "in" | "out" } = {}): Promise<void> {
  const order = Math.max(0, Math.min(5, opts.order ?? 0));
  const mode = opts.mode ?? "in";
  if (!holoEnabled() || typeof el.animate !== "function") return Promise.resolve();
  const duration = mode === "in" ? ENTER_MS : EXIT_HOLO_MS;
  const delay = mode === "in" ? 120 + 45 * order : 0;
  el.classList.add("holo", mode === "out" ? "holo-out" : "holo-in");
  el.style.setProperty("--holo-ms", `${duration}ms`);
  el.style.setProperty("--holo-delay", `${delay}ms`);
  const anim = el.animate(hologramFrames(order, opts.edge ?? "left", mode), { duration, delay, fill: "both" });
  if (mode === "out") hidden.add(anim); // se queda invisible hasta que cambie la sección (resetHidden)
  return anim.finished
    .catch(() => undefined)
    .then(() => {
      el.classList.remove("holo", "holo-out", "holo-in");
      if (mode === "in") anim.cancel(); // entero: sin estilos de animación pegados
    });
}

const hidden = new Set<Animation>();

/** Suelta las salidas: lo que se ocultó vuelve a verse (se llama justo después de cambiar de sección). */
export function resetHidden(): void {
  for (const anim of hidden) anim.cancel();
  hidden.clear();
}

/** Entrada de varios bloques en orden (cada uno 45 ms después del anterior) con sus textos escribiéndose a la vez. */
export function revealBlocks(blocks: HTMLElement[], texts: HTMLElement[] = []): Promise<void> {
  const all = blocks.map((el, i) => hologram(el, { order: i, edge: i % 2 ? "right" : "left" }));
  texts.forEach((el, i) => {
    const block = blocks.findIndex((b) => b.contains(el));
    const delay = holoEnabled() ? 120 + 45 * Math.max(0, Math.min(5, block < 0 ? i : block)) : 0;
    all.push(hackText(el, plainText(el), { delay }));
  });
  return Promise.all(all).then(() => undefined);
}

/** Salida de todos los bloques a la vez (210 ms), con sus textos des-escribiéndose. */
export function hideBlocks(blocks: HTMLElement[], texts: HTMLElement[] = []): Promise<void> {
  if (!holoEnabled() && !hackEnabled()) return Promise.resolve();
  return Promise.all([...blocks.map((el) => hologram(el, { mode: "out" })), ...texts.map((el) => hackOut(el))]).then(() => undefined);
}
