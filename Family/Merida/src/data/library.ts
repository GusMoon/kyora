/** Tus listas de YouTube: el cliente del servicio local de música (Family/Kyora/kyora/merida/server.py).
 * Merida no puede leer cookies ni bajar de YouTube; el servicio sí, con el mismo motor que Kyora. Vite le dice a la
 * página dónde está y su token en /__music (lo lee del archivo que escribe el servicio al arrancar). */

export interface ServiceInfo {
  url: string;
  token: string;
}

export interface Playlist {
  id: string;
  title: string;
  count: number | null;
}

export type SongState = "pending" | "queued" | "doing" | "sending" | "done" | "error";

export interface Song {
  id: string;
  title: string;
  duration: number | null;
  state: SongState;
}

export interface Recipient {
  id: string | null; // null = «Yo»; "folder" = esta PC
  name: string;
  me: boolean;
}

export interface Progress {
  state: SongState;
  percent: number;
  error?: string;
}

export interface MusicEvent {
  kind: string;
  [key: string]: unknown;
}

export interface LibraryState {
  playlists: Playlist[] | null;
  songs: Record<string, Song[]>;
  progress: Record<string, Progress>;
  recipients: Recipient[] | null;
  ffmpeg: { available: boolean; message: string } | null;
  error: { where: string; message: string } | null;
  busy: boolean;
  lastSaved: string | null; // dónde quedó el último MP3 guardado en la carpeta
  stream: { id: string; source: string; local: boolean } | null;
}

export const FOLDER = "folder";
export const COOKIE_HINT =
  "Exporta las cookies de youtube.com con una extensión como «Get cookies.txt LOCALLY» (con la sesión de YouTube abierta) y pega aquí todo el archivo.";

export function emptyLibrary(): LibraryState {
  return { playlists: null, songs: {}, progress: {}, recipients: null, ffmpeg: null, error: null, busy: false, lastSaved: null, stream: null };
}

/** Aplica un evento del servicio al estado de la pantalla (sin efectos: fácil de probar). */
export function applyEvent(state: LibraryState, ev: MusicEvent): LibraryState {
  switch (ev.kind) {
    case "ffmpeg":
      return { ...state, ffmpeg: { available: Boolean(ev.available), message: String(ev.message ?? "") } };
    case "playlists":
      return { ...state, playlists: (ev.playlists as Playlist[]) ?? [], error: state.error?.where === "playlists" ? null : state.error };
    case "songs": {
      const songs = (ev.songs as Song[]) ?? [];
      const progress = { ...state.progress };
      for (const song of songs) if (!progress[song.id] || song.state === "done") progress[song.id] = { state: song.state, percent: song.state === "done" ? 100 : 0 };
      return { ...state, songs: { ...state.songs, [String(ev.playlist)]: songs }, progress, error: state.error?.where === "songs" ? null : state.error };
    }
    case "progress": {
      const id = String(ev.id);
      const entry: Progress = { state: ev.state as SongState, percent: Number(ev.percent ?? 0) };
      if (ev.error) entry.error = String(ev.error);
      const busy = state.busy || entry.state === "queued" || entry.state === "doing";
      return { ...state, progress: { ...state.progress, [id]: entry }, busy };
    }
    case "finished":
      return { ...state, busy: false };
    case "recipients":
      return { ...state, recipients: (ev.recipients as Recipient[]) ?? [] };
    case "saved":
      return { ...state, lastSaved: String(ev.path ?? "") };
    case "stream":
      return { ...state, stream: { id: String(ev.id), source: String(ev.source), local: Boolean(ev.local) } };
    case "error":
      return { ...state, error: { where: String(ev.where ?? ""), message: String(ev.error ?? "Algo falló en el servicio de música") } };
    default:
      return state;
  }
}

/** ¿El error pide cookies nuevas? Entonces se ofrece pegar el cookies.txt. */
export function needsCookies(error: LibraryState["error"]): boolean {
  return !!error && error.where === "playlists" && /cookie|sesi[oó]n|sign in|401|403/i.test(error.message);
}

export interface ActionResult {
  ok: boolean;
  data?: unknown;
  error?: { code: string; message: string };
}

export const SERVICE_DOWN = "El servicio de música no está abierto: abre Merida con su .bat (iniciar_merida.bat o Abrir Merida.bat).";

/** El cliente HTTP del servicio. */
export class Library {
  info: ServiceInfo | null = null;
  constructor(
    private readonly fetchImpl: typeof fetch = (...args) => fetch(...args),
    private readonly infoUrl = "/__music",
  ) {}

  /** Pregunta a Vite dónde está el servicio y comprueba que responde. False si no está abierto. */
  async connect(): Promise<boolean> {
    try {
      const res = await this.fetchImpl(this.infoUrl, { cache: "no-store" });
      if (!res.ok) return false;
      const info = (await res.json()) as Partial<ServiceInfo>;
      if (!info.url || !info.token) return false;
      this.info = { url: info.url, token: info.token };
      const health = await this.request("GET", "/api/health");
      return health.ok;
    } catch {
      this.info = null;
      return false;
    }
  }

  private async request(method: "GET" | "POST", path: string, body?: unknown): Promise<ActionResult> {
    if (!this.info) return { ok: false, error: { code: "offline", message: SERVICE_DOWN } };
    try {
      const res = await this.fetchImpl(this.info.url + path, {
        method,
        headers: { "X-Merida-Token": this.info.token, ...(body === undefined ? {} : { "Content-Type": "application/json" }) },
        body: body === undefined ? undefined : JSON.stringify(body),
      });
      const data = (await res.json()) as ActionResult;
      return data && typeof data.ok === "boolean" ? data : { ok: false, error: { code: "bad_response", message: "Respuesta rara del servicio" } };
    } catch {
      return { ok: false, error: { code: "offline", message: SERVICE_DOWN } };
    }
  }

  act(name: string, payload: Record<string, unknown> = {}): Promise<ActionResult> {
    return this.request("POST", `/api/action/${name}`, payload);
  }

  settings(): Promise<ActionResult> {
    return this.request("GET", "/api/settings");
  }

  saveSettings(patch: Record<string, unknown>): Promise<ActionResult> {
    return this.request("POST", "/api/settings", patch);
  }

  /** La URL para escuchar un MP3 que ya está en esta PC. */
  fileUrl(id: string): string {
    return this.info ? `${this.info.url}/api/file?id=${encodeURIComponent(id)}&token=${encodeURIComponent(this.info.token)}` : "";
  }

  /** Escucha los eventos del servicio. Devuelve cómo dejar de escuchar. */
  events(onEvent: (ev: MusicEvent) => void, onState: (live: boolean) => void = () => {}): () => void {
    if (!this.info || typeof EventSource === "undefined") return () => {};
    const source = new EventSource(`${this.info.url}/api/events?token=${encodeURIComponent(this.info.token)}`);
    source.onopen = () => onState(true);
    source.onerror = () => onState(false);
    source.onmessage = (msg) => {
      try {
        onEvent(JSON.parse(msg.data) as MusicEvent);
      } catch {
        /* un evento roto no rompe la página */
      }
    };
    return () => source.close();
  }
}
