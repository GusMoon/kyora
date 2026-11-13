import type { SupabaseClient } from "@supabase/supabase-js";
import { trackUrl, type Track } from "./data/music";
import { explainError } from "./supabase";

export interface PlayerState {
  track: Track | null;
  playing: boolean;
  loading: boolean;
  time: number;
  duration: number;
  error: string | null;
}

/** Un solo reproductor para toda la app: sigue sonando aunque cambies de sección. */
export class Player {
  private readonly audio = new Audio();
  private queue: Track[] = [];
  private index = -1;
  private listeners = new Set<(s: PlayerState) => void>();
  state: PlayerState = { track: null, playing: false, loading: false, time: 0, duration: 0, error: null };

  constructor(private readonly client: SupabaseClient) {
    this.audio.preload = "metadata";
    this.audio.addEventListener("timeupdate", () => this.set({ time: this.audio.currentTime }));
    this.audio.addEventListener("durationchange", () => this.set({ duration: this.audio.duration || 0 }));
    this.audio.addEventListener("play", () => this.set({ playing: true, loading: false }));
    this.audio.addEventListener("pause", () => this.set({ playing: false }));
    this.audio.addEventListener("ended", () => this.next());
    this.audio.addEventListener("error", () => {
      if (this.state.track) this.set({ playing: false, loading: false, error: "No se pudo reproducir este archivo." });
    });
  }

  on(fn: (s: PlayerState) => void): () => void {
    this.listeners.add(fn);
    fn(this.state);
    return () => this.listeners.delete(fn);
  }

  private set(patch: Partial<PlayerState>) {
    this.state = { ...this.state, ...patch };
    for (const fn of this.listeners) fn(this.state);
  }

  async play(track: Track, queue: Track[]) {
    this.queue = queue;
    this.index = queue.findIndex((t) => t.id === track.id);
    this.set({ track, playing: false, loading: true, time: 0, duration: 0, error: null });
    try {
      this.audio.src = await trackUrl(this.client, track.storage_path);
      await this.audio.play();
    } catch (err) {
      if (this.state.track?.id === track.id) this.set({ loading: false, playing: false, error: explainError(err) });
    }
  }

  /** Escuchar algo que no está en Supabase: una canción de tus listas de YouTube, por el enlace que da el servicio local. */
  async playUrl(item: { id: string; title: string; playlist?: string | null }, url: string) {
    const track: Track = {
      id: `yt:${item.id}`,
      title: item.title,
      file_name: "",
      storage_path: "",
      mime_type: "audio/mpeg",
      size_bytes: 0,
      playlist: item.playlist ?? null,
      cover_url: `https://i.ytimg.com/vi/${encodeURIComponent(item.id)}/mqdefault.jpg`,
      created_at: new Date().toISOString(),
      received_at: null,
    };
    this.queue = [track];
    this.index = 0;
    this.set({ track, playing: false, loading: true, time: 0, duration: 0, error: null });
    try {
      this.audio.src = url;
      await this.audio.play();
    } catch (err) {
      if (this.state.track?.id === track.id) this.set({ loading: false, playing: false, error: explainError(err) });
    }
  }

  toggle() {
    if (!this.state.track) return;
    if (this.audio.paused) void this.audio.play().catch(() => undefined);
    else this.audio.pause();
  }

  next() {
    const t = this.queue[this.index + 1];
    if (t) void this.play(t, this.queue);
    else this.set({ playing: false });
  }

  previous() {
    if (this.audio.currentTime > 3 || this.index <= 0) {
      this.audio.currentTime = 0;
      return;
    }
    void this.play(this.queue[this.index - 1], this.queue);
  }

  /** Salta a una parte de la canción (0 a 1). */
  seek(fraction: number) {
    if (this.audio.duration) this.audio.currentTime = Math.min(1, Math.max(0, fraction)) * this.audio.duration;
  }

  stop() {
    this.audio.pause();
    this.audio.removeAttribute("src");
    this.audio.load();
    this.queue = [];
    this.index = -1;
    this.set({ track: null, playing: false, loading: false, time: 0, duration: 0, error: null });
  }
}
