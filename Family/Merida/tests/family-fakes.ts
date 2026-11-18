import type { SupabaseClient } from "@supabase/supabase-js";
import type { CallEnv } from "../src/data/webrtc";

/** Lo que comparten las pruebas del chat familiar y las llamadas: un cliente de Supabase falso (rpc, tablas, Storage y Realtime)
 * y un navegador falso con WebRTC y micrófono simulados (jsdom no trae ninguno de los dos). */

export interface TableCall {
  table: string;
  op: "select" | "insert" | "update" | "delete";
  payload?: unknown;
  filters: [string, string, unknown][];
}
export interface RpcCall {
  name: string;
  args: Record<string, unknown>;
}
type Reply = { data?: unknown; error?: unknown };

export interface FakeOptions {
  /** La respuesta de cada función rpc (si no hay, `data: null`). Puede lanzar o devolver `{ error }`. */
  rpc?: Record<string, (args: Record<string, unknown>) => unknown>;
  /** La respuesta de cada consulta a una tabla. */
  table?: (call: TableCall) => Reply | undefined;
  uploadError?: unknown;
}

export function fakeClient(opts: FakeOptions = {}) {
  const rpcCalls: RpcCall[] = [];
  const tableCalls: TableCall[] = [];
  const uploads: { bucket: string; path: string; type?: string }[] = [];
  const removed: { bucket: string; paths: string[] }[] = [];
  const handlers: { table: string; event: string; cb: (payload: unknown) => void }[] = [];
  const removedChannels: unknown[] = [];

  const rpc = (name: string, args: Record<string, unknown> = {}) => {
    rpcCalls.push({ name, args });
    try {
      const out = opts.rpc?.[name]?.(args);
      if (out && typeof out === "object" && "error" in (out as object)) return Promise.resolve({ data: null, error: (out as { error: unknown }).error });
      return Promise.resolve({ data: out ?? null, error: null });
    } catch (error) {
      return Promise.resolve({ data: null, error });
    }
  };

  const from = (table: string) => {
    const call: TableCall = { table, op: "select", filters: [] };
    const b = {
      select: () => b,
      insert: (payload: unknown) => ((call.op = "insert"), (call.payload = payload), b),
      update: (payload: unknown) => ((call.op = "update"), (call.payload = payload), b),
      delete: () => ((call.op = "delete"), b),
      eq: (k: string, v: unknown) => (call.filters.push([k, "eq", v]), b),
      in: (k: string, v: unknown) => (call.filters.push([k, "in", v]), b),
      order: () => b,
      single: () => b,
      then: (res: (r: unknown) => unknown, rej?: (e: unknown) => unknown) => {
        tableCalls.push(call);
        const reply = opts.table?.(call) ?? { data: call.op === "select" ? [] : null };
        return Promise.resolve({ data: reply.data ?? null, error: reply.error ?? null }).then(res, rej);
      },
    };
    return b;
  };

  const storage = {
    from: (bucket: string) => ({
      upload: async (path: string, _file: unknown, o?: { contentType?: string }) => {
        uploads.push({ bucket, path, type: o?.contentType });
        return { data: { path }, error: opts.uploadError ?? null };
      },
      createSignedUrl: async (path: string) => ({ data: { signedUrl: `https://files.test/${bucket}/${path}?token=t` }, error: null }),
      remove: async (paths: string[]) => {
        removed.push({ bucket, paths });
        return { data: [], error: null };
      },
    }),
  };

  const channel = (_name: string) => {
    const ch = {
      on: (_type: string, filter: { table: string; event: string }, cb: (payload: unknown) => void) => (handlers.push({ table: filter.table, event: filter.event, cb }), ch),
      subscribe: (cb?: (status: string) => void) => (queueMicrotask(() => cb?.("SUBSCRIBED")), ch),
    };
    return ch;
  };

  const client = { rpc, from, storage, channel, removeChannel: async (c: unknown) => void removedChannels.push(c) } as unknown as SupabaseClient;

  /** Simula un aviso de Realtime sobre una tabla. */
  const emit = (table: string, eventType: "INSERT" | "UPDATE" | "DELETE", row: unknown) => {
    for (const h of handlers) {
      if (h.table === table && (h.event === "*" || h.event === eventType)) h.cb({ eventType, new: eventType === "DELETE" ? {} : row, old: eventType === "DELETE" ? row : {} });
    }
  };

  return { client, rpcCalls, tableCalls, uploads, removed, removedChannels, emit, handlers };
}

// ---------------------------------------------------------------------------------------------------------------------
// WebRTC y micrófono falsos

export class FakeTrack {
  enabled = true;
  stopped = false;
  constructor(readonly kind: "audio" | "video") {}
  stop() {
    this.stopped = true;
  }
}

export class FakeStream {
  constructor(readonly tracks: FakeTrack[]) {}
  getTracks() {
    return this.tracks;
  }
  getAudioTracks() {
    return this.tracks.filter((t) => t.kind === "audio");
  }
  getVideoTracks() {
    return this.tracks.filter((t) => t.kind === "video");
  }
}

export class FakePeer {
  remoteDescription: unknown = null;
  localDescription: unknown = null;
  added: FakeTrack[] = [];
  candidates: unknown[] = [];
  closed = false;
  connectionState = "new";
  onicecandidate: ((e: { candidate: unknown }) => void) | null = null;
  ontrack: ((e: { streams: unknown[] }) => void) | null = null;
  onconnectionstatechange: (() => void) | null = null;
  constructor(readonly config: unknown) {}
  addTrack(t: FakeTrack) {
    this.added.push(t);
  }
  async createOffer() {
    return { type: "offer", sdp: "sdp-offer" };
  }
  async createAnswer() {
    return { type: "answer", sdp: "sdp-answer" };
  }
  async setLocalDescription(d: unknown) {
    this.localDescription = d;
  }
  async setRemoteDescription(d: unknown) {
    this.remoteDescription = d;
  }
  async addIceCandidate(c: unknown) {
    this.candidates.push(c);
  }
  close() {
    this.closed = true;
  }
  /** Simula que el navegador encontró un candidato ICE o que la conexión cambió de estado. */
  fireCandidate(c: unknown) {
    this.onicecandidate?.({ candidate: { toJSON: () => c } });
  }
  fireState(state: string) {
    this.connectionState = state;
    this.onconnectionstatechange?.();
  }
}

export function fakeEnv(opts: { denyMedia?: boolean } = {}) {
  const peers: FakePeer[] = [];
  const streams: FakeStream[] = [];
  const requested: MediaStreamConstraints[] = [];
  const env: CallEnv = {
    newPeer: (config) => {
      const p = new FakePeer(config);
      peers.push(p);
      return p as unknown as RTCPeerConnection;
    },
    getMedia: async (constraints) => {
      requested.push(constraints);
      if (opts.denyMedia) throw new Error("Permission denied");
      const s = new FakeStream([new FakeTrack("audio"), ...(constraints.video ? [new FakeTrack("video")] : [])]);
      streams.push(s);
      return s as unknown as MediaStream;
    },
  };
  return { env, peers, streams, requested };
}

export const flush = async (n = 6) => {
  for (let i = 0; i < n; i++) await new Promise((r) => setTimeout(r, 0));
};
