import { ICE_SERVERS } from "../config";
import type { CallKind, SignalKind } from "./calls";

/** Una sesión de WebRTC entre dos navegadores: saca el micrófono (y la cámara en video), arma la conexión y pasa por `send` la
 * oferta, la respuesta y los candidatos ICE al otro lado. Quien llama manda la oferta (`offer`); quien contesta la recibe y responde.
 * El navegador se inyecta (`CallEnv`) para poder probarlo sin audio ni cámara reales (jsdom no trae WebRTC). */

export interface CallEnv {
  newPeer(config: RTCConfiguration): RTCPeerConnection;
  getMedia(constraints: MediaStreamConstraints): Promise<MediaStream>;
}

/** El navegador de verdad. `null` si no soporta llamadas (o la página no es segura: sin HTTPS no hay micrófono). */
export function browserEnv(): CallEnv | null {
  if (typeof RTCPeerConnection === "undefined" || typeof navigator === "undefined" || !navigator.mediaDevices?.getUserMedia) return null;
  return {
    newPeer: (config) => new RTCPeerConnection(config),
    getMedia: (constraints) => navigator.mediaDevices.getUserMedia(constraints),
  };
}

export type Connection = "connecting" | "connected" | "failed" | "closed";

export interface SessionOptions {
  env: CallEnv;
  kind: CallKind;
  role: "caller" | "callee";
  /** Manda una señal al otro lado (por family_call_signals). */
  send: (kind: SignalKind, payload: unknown) => Promise<void>;
  onRemote: (stream: MediaStream) => void;
  onConnection: (state: Connection) => void;
}

/** Lo que pide cada tipo de llamada. */
export function constraintsFor(kind: CallKind): MediaStreamConstraints {
  return { audio: { echoCancellation: true, noiseSuppression: true }, video: kind === "video" };
}

export class CallSession {
  private peer: RTCPeerConnection | null = null;
  private local: MediaStream | null = null;
  private queued: RTCIceCandidateInit[] = []; // candidatos que llegaron antes que la descripción remota
  private chain: Promise<void> = Promise.resolve(); // las señales se procesan de una en una y en orden
  private closed = false;
  private markReady: () => void = () => {};
  private readonly ready = new Promise<void>((resolve) => (this.markReady = resolve)); // las señales esperan a que `start` termine

  constructor(private readonly opts: SessionOptions) {}

  get localStream(): MediaStream | null {
    return this.local;
  }

  /** Saca los medios, arma la conexión y, si es quien llama, manda la oferta. Lanza si no hay permiso de micrófono o cámara. */
  async start(): Promise<void> {
    try {
      await this.setup();
    } finally {
      this.markReady();
    }
  }

  private async setup(): Promise<void> {
    const { env, kind, send, onRemote, onConnection } = this.opts;
    this.local = await env.getMedia(constraintsFor(kind));
    if (this.closed) return this.stopLocal();
    const peer = env.newPeer({ iceServers: ICE_SERVERS });
    this.peer = peer;
    for (const track of this.local.getTracks()) peer.addTrack(track, this.local);
    peer.onicecandidate = (e) => {
      if (e.candidate) void send("candidate", e.candidate.toJSON ? e.candidate.toJSON() : e.candidate).catch(() => {});
    };
    peer.ontrack = (e) => {
      if (e.streams[0]) onRemote(e.streams[0]);
    };
    peer.onconnectionstatechange = () => {
      const s = peer.connectionState;
      if (s === "connected") onConnection("connected");
      else if (s === "failed") onConnection("failed");
      else if (s === "closed" || s === "disconnected") onConnection("closed");
    };
    onConnection("connecting");
  }

  /** Quien llama manda la oferta. Va aparte de `start` para pedir primero el micrófono y solo entonces hacer sonar la llamada. */
  async offer(): Promise<void> {
    const peer = this.peer;
    if (!peer || this.closed) return;
    const offer = await peer.createOffer();
    await peer.setLocalDescription(offer);
    await this.opts.send("offer", { type: offer.type, sdp: offer.sdp });
  }

  /** Una señal del otro lado. Se encadenan: no se procesa una hasta terminar la anterior. */
  handleSignal(kind: SignalKind, payload: unknown): Promise<void> {
    this.chain = this.chain.then(() => this.apply(kind, payload)).catch(() => {});
    return this.chain;
  }

  private async apply(kind: SignalKind, payload: unknown): Promise<void> {
    await this.ready;
    const peer = this.peer;
    if (!peer || this.closed) return;
    if (kind === "offer" && this.opts.role === "callee") {
      await peer.setRemoteDescription(payload as RTCSessionDescriptionInit);
      await this.flush(peer);
      const answer = await peer.createAnswer();
      await peer.setLocalDescription(answer);
      await this.opts.send("answer", { type: answer.type, sdp: answer.sdp });
    } else if (kind === "answer" && this.opts.role === "caller") {
      await peer.setRemoteDescription(payload as RTCSessionDescriptionInit);
      await this.flush(peer);
    } else if (kind === "candidate") {
      if (peer.remoteDescription) await peer.addIceCandidate(payload as RTCIceCandidateInit);
      else this.queued.push(payload as RTCIceCandidateInit);
    }
  }

  private async flush(peer: RTCPeerConnection): Promise<void> {
    const pending = this.queued;
    this.queued = [];
    for (const c of pending) await peer.addIceCandidate(c);
  }

  /** Silencia o activa el micrófono. */
  setMuted(muted: boolean): void {
    for (const t of this.local?.getAudioTracks() ?? []) t.enabled = !muted;
  }

  /** Apaga o enciende la cámara (sin cortar la llamada). */
  setCameraOff(off: boolean): void {
    for (const t of this.local?.getVideoTracks() ?? []) t.enabled = !off;
  }

  private stopLocal(): void {
    for (const t of this.local?.getTracks() ?? []) t.stop();
    this.local = null;
  }

  /** Cuelga: para el micrófono y la cámara y cierra la conexión. Se puede llamar más de una vez. */
  close(): void {
    if (this.closed) return;
    this.closed = true;
    this.stopLocal();
    try {
      this.peer?.close();
    } catch {
      /* ya estaba cerrada */
    }
    this.peer = null;
  }
}
