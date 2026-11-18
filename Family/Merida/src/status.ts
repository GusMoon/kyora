import type { LiveState } from "./data/chat";

/** Lo que se lee del sistema: quién eres, cuánto tarda el servidor y si el chat está en vivo. Lo ven la franja de las
 * tesela y la sección de Configuración, así las dos dicen siempre lo mismo. */
export interface StatusData {
  account: string; // «usuario, rol» tal como se enseña
  username: string;
  role: string; // admin o visitante
  email: string;
  latency: number | null | undefined; // undefined = aún sin medir, null = sin respuesta
  live: LiveState;
}

export class Status {
  data: StatusData = { account: "…", username: "", role: "", email: "", latency: undefined, live: "connecting" };
  private listeners = new Set<(s: StatusData) => void>();

  on(fn: (s: StatusData) => void): () => void {
    this.listeners.add(fn);
    fn(this.data);
    return () => this.listeners.delete(fn);
  }

  set(patch: Partial<StatusData>) {
    this.data = { ...this.data, ...patch };
    for (const fn of this.listeners) fn(this.data);
  }
}

export const LIVE_TEXT: Record<LiveState, string> = { connecting: "conectando", live: "en vivo", offline: "sin conexión" };

export function latencyText(ms: number | null | undefined): string {
  if (ms === undefined) return "midiendo";
  return ms === null ? "sin respuesta" : `${Math.round(ms)} ms`;
}
