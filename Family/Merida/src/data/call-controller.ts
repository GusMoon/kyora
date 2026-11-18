import type { SupabaseClient } from "@supabase/supabase-js";
import { explainError } from "../supabase";
import {
  RING_TIMEOUT_MS,
  answerCall,
  finishCall,
  listSignals,
  nextCallState,
  phaseOf,
  sendSignal,
  startCall,
  watchCalls,
  type CallKind,
  type CallPhase,
  type CallRow,
  type SignalRow,
} from "./calls";
import type { FamilyMember } from "./family-chat";
import { CallSession, type CallEnv, type Connection } from "./webrtc";

/** Lo que el panel de la llamada necesita para dibujarse. */
export interface CallView {
  phase: CallPhase;
  kind: CallKind;
  callId: string | null;
  /** El nombre de la otra persona (null si no se sabe). */
  peer: string | null;
  muted: boolean;
  cameraOff: boolean;
  connection: Connection | null;
  /** Cuándo pasó a «en curso» (ms), para el cronómetro. */
  startedAt: number | null;
  error: string;
}

export const idleView = (): CallView => ({ phase: "idle", kind: "audio", callId: null, peer: null, muted: false, cameraOff: false, connection: null, startedAt: null, error: "" });

export interface ControllerDeps {
  client: SupabaseClient;
  userId: string;
  /** El navegador (null si no soporta llamadas). */
  env: CallEnv | null;
  members: () => FamilyMember[];
  now?: () => number;
  ringMs?: number;
}

/** Junta la base de datos (calls.ts) y WebRTC (webrtc.ts) en una llamada a la vez, y avisa a quien escuche de cada cambio.
 * Una llamada es entre dos personas: quien llama y la primera que contesta. */
export class CallController {
  view: CallView = idleView();
  remote: MediaStream | null = null;
  private call: CallRow | null = null;
  private session: CallSession | null = null;
  private seen = new Set<string>(); // señales ya aplicadas (la lista y Realtime pueden traer la misma)
  private ringTimer: ReturnType<typeof setTimeout> | null = null;
  private readonly listeners = new Set<() => void>();
  private readonly now: () => number;
  private readonly ringMs: number;

  constructor(private readonly deps: ControllerDeps) {
    this.now = deps.now ?? Date.now;
    this.ringMs = deps.ringMs ?? RING_TIMEOUT_MS;
  }

  /** El flujo del micrófono y la cámara propios (para el recuadro pequeño). */
  get local(): MediaStream | null {
    return this.session?.localStream ?? null;
  }

  on(fn: () => void): () => void {
    this.listeners.add(fn);
    return () => this.listeners.delete(fn);
  }

  private emit() {
    for (const fn of [...this.listeners]) fn();
  }

  private set(patch: Partial<CallView>) {
    this.view = { ...this.view, ...patch };
    this.emit();
  }

  private busy(): boolean {
    return this.view.phase === "calling" || this.view.phase === "incoming" || this.view.phase === "active";
  }

  private nameOf(id: string | undefined): string | null {
    return id ? (this.deps.members().find((m) => m.id === id)?.username ?? null) : null;
  }

  /** Empieza a escuchar las llamadas de la familia. Devuelve la función que deja de escuchar y cuelga lo que haya. */
  attach(): () => void {
    const stop = watchCalls(this.deps.client, { onCall: (row) => this.handleCall(row), onSignal: (s) => this.handleSignal(s) });
    return () => {
      stop();
      this.teardown();
      this.view = idleView();
    };
  }

  private newSession(role: "caller" | "callee", kind: CallKind, callId: string): CallSession {
    const { client, userId, env } = this.deps;
    return new CallSession({
      env: env!,
      kind,
      role,
      send: (k, p) => sendSignal(client, callId, userId, k, p),
      onRemote: (stream) => {
        this.remote = stream;
        this.emit();
      },
      onConnection: (connection) => {
        this.view = { ...this.view, connection, error: connection === "failed" ? "No se pudo conectar la llamada: la red de alguno la impide." : this.view.error };
        this.emit();
      },
    });
  }

  private clearRing() {
    if (this.ringTimer) clearTimeout(this.ringTimer);
    this.ringTimer = null;
  }

  private teardown() {
    this.clearRing();
    this.session?.close();
    this.session = null;
    this.remote = null;
    this.call = null;
    this.seen.clear();
  }

  /** Llama a la familia. Pide primero el micrófono (y la cámara): si no hay permiso, no suena nada en las otras casas. */
  async start(kind: CallKind): Promise<void> {
    if (this.busy()) return;
    if (!this.deps.env) {
      this.set({ ...idleView(), error: "Este navegador no permite llamadas (hace falta HTTPS o localhost, micrófono y WebRTC)." });
      return;
    }
    const id = crypto.randomUUID();
    const session = this.newSession("caller", kind, id);
    this.teardown();
    this.session = session;
    this.set({ ...idleView(), phase: nextCallState("idle", "start"), kind, callId: id, connection: "connecting" });
    try {
      await session.start();
      this.call = await startCall(this.deps.client, this.deps.userId, kind, id);
      await session.offer();
    } catch (err) {
      this.fail(`No se pudo llamar. ${explainError(err)}`, id);
      return;
    }
    this.ringTimer = setTimeout(() => void this.giveUp(id), this.ringMs);
  }

  private async giveUp(id: string) {
    if (this.call?.id !== id || this.view.phase !== "calling") return;
    this.set({ phase: nextCallState("calling", "timeout"), connection: null });
    this.teardownKeepView();
    try {
      await finishCall(this.deps.client, id, "missed");
    } catch {
      /* el otro lado la verá perder igualmente por su propio reloj */
    }
  }

  private teardownKeepView() {
    const view = this.view;
    this.teardown();
    this.view = view;
  }

  private fail(message: string, id: string) {
    const created = this.call?.id === id;
    this.teardown();
    this.view = { ...idleView(), error: message };
    this.emit();
    if (created) void finishCall(this.deps.client, id, "ended").catch(() => {});
  }

  /** Contesta la llamada que suena. */
  async accept(): Promise<void> {
    const call = this.call;
    if (!call || this.view.phase !== "incoming") return;
    if (!this.deps.env) {
      this.set({ error: "Este navegador no permite llamadas." });
      return;
    }
    this.clearRing();
    const session = this.newSession("callee", call.kind, call.id);
    this.session = session;
    this.set({ connection: "connecting", error: "" });
    try {
      await session.start();
      const won = await answerCall(this.deps.client, this.deps.userId, call.id);
      if (!won) {
        this.teardown();
        this.view = idleView();
        this.emit();
        return;
      }
      this.set({ phase: nextCallState("incoming", "accept"), startedAt: this.now() });
      for (const signal of await listSignals(this.deps.client, call.id)) this.handleSignal(signal);
    } catch (err) {
      this.fail(`No se pudo contestar. ${explainError(err)}`, call.id);
    }
  }

  /** Rechaza la llamada que suena. */
  async decline(): Promise<void> {
    const call = this.call;
    if (!call || this.view.phase !== "incoming") return;
    this.teardown();
    this.view = idleView();
    this.emit();
    try {
      await finishCall(this.deps.client, call.id, "declined");
    } catch {
      /* si no llega, a quien llamó le sonará hasta que se agote el tiempo */
    }
  }

  /** Cuelga (o cancela, si aún suena). */
  async hangup(): Promise<void> {
    const call = this.call;
    if (!call || !this.busy()) return;
    this.set({ phase: nextCallState(this.view.phase, "hangup"), connection: null });
    this.teardownKeepView();
    try {
      await finishCall(this.deps.client, call.id, "ended");
    } catch {
      /* el otro lado lo sabrá al cerrarse la conexión */
    }
  }

  /** Quita el aviso de una llamada terminada, rechazada o perdida. */
  dismiss(): void {
    if (this.busy()) return;
    this.view = { ...idleView(), kind: this.view.kind };
    this.emit();
  }

  toggleMute(): void {
    const muted = !this.view.muted;
    this.session?.setMuted(muted);
    this.set({ muted });
  }

  toggleCamera(): void {
    const cameraOff = !this.view.cameraOff;
    this.session?.setCameraOff(cameraOff);
    this.set({ cameraOff });
  }

  /** Cambió una fila de family_calls (la llegada de una llamada, que la contesten, la cuelguen...). */
  handleCall(row: CallRow): void {
    const me = this.deps.userId;
    if (!this.call || this.call.id !== row.id) {
      const fresh = this.now() - new Date(row.created_at).getTime() < this.ringMs;
      if (row.status === "ringing" && row.caller_id !== me && !this.busy() && fresh) {
        this.call = row;
        this.view = { ...idleView(), phase: nextCallState(this.view.phase, "incoming"), kind: row.kind, callId: row.id, peer: this.nameOf(row.caller_id) };
        this.ringTimer = setTimeout(() => {
          if (this.view.phase === "incoming" && this.call?.id === row.id) {
            this.view = { ...this.view, phase: nextCallState("incoming", "timeout") };
            this.teardownKeepView();
            this.emit();
          }
        }, this.ringMs + 5000);
        this.emit();
      }
      return;
    }
    this.call = row;
    let next = phaseOf(row, me);
    if (this.view.phase === "incoming" && next === "ended") next = "missed"; // colgó antes de que contestara: la perdí
    if (next === this.view.phase) return;
    if (this.view.phase === "calling" && next === "active") {
      this.clearRing();
      this.set({ phase: "active", startedAt: this.now(), peer: this.nameOf(row.answered_by ?? undefined) });
      return;
    }
    if (this.view.phase === "incoming" && next === "active") return; // la contesté yo: ya está en curso
    // terminó de una forma u otra (o la contestó otro miembro y a mí ya no me toca)
    if (next === "idle") {
      this.teardown();
      this.view = idleView();
    } else {
      this.set({ phase: next, connection: null });
      this.teardownKeepView();
    }
    this.emit();
  }

  /** Llegó una señal de WebRTC. Solo cuentan las de la llamada actual y las del otro lado. */
  handleSignal(signal: SignalRow): void {
    if (!this.session || !this.call || signal.call_id !== this.call.id || signal.sender_id === this.deps.userId) return;
    if (this.seen.has(signal.id)) return;
    this.seen.add(signal.id);
    void this.session.handleSignal(signal.kind, signal.payload);
  }
}
