"""Manda a tu cuenta de Supabase cada canción que la PC acaba de bajar, para que la app del móvil la vea y la guarde.

Cuando `MusicService` termina una descarga llama a `enqueue`. Aquí un hilo sube el MP3 a Storage (`chat-files`, en
`<usuario>/music/<id>/<archivo>`) y registra la canción con la función `add_music_track`. Usa la misma sesión que el chat
(`ChatService.client_ready`), así que no pide nada nuevo. Si no hay internet o la sesión aún no está, la canción queda
pendiente (se guarda en `music_sync.json`) y se reintenta sola, también al volver a abrir Kyora.

Los avisos salen como `{"kind": "sync", id, state: uploading | synced | error, title, message}` por el mismo canal que
el resto de la música (`music_result`). Se apaga con `music.sync = false` en config.json.
"""
import json
import logging
import threading
import uuid
from pathlib import Path

from kyora.chat.client import ChatError
from kyora.chat.service import safe_name

log = logging.getLogger("kyora.music")
RETRY_S = 30  # espera entre intentos cuando no hay conexión
MIME = "audio/mpeg"


def track_id(video_id):
    """El id de la canción en Supabase: siempre el mismo para el mismo vídeo (bajarla otra vez no la duplica)."""
    return str(uuid.uuid5(uuid.NAMESPACE_URL, f"kyora-music:{video_id}"))


class MusicSync:
    def __init__(self, data_dir, chat, emit, config=dict, retry_s=RETRY_S):
        """`chat`: el `ChatService` (su sesión de Supabase). `config()`: la sección "music" de config.json."""
        self._path = Path(data_dir) / "music_sync.json"
        self._chat, self._emit, self._config, self._retry = chat, emit, config, retry_s
        self._lock = threading.Lock()
        self._wake = threading.Event()
        self._stop = threading.Event()
        self._thread = None
        self._synced, self._pending = self._load()

    # ---------- estado guardado ----------

    def _load(self):
        try:
            data = json.loads(self._path.read_text(encoding="utf-8"))
            return dict(data.get("synced", {})), dict(data.get("pending", {}))
        except (OSError, ValueError, AttributeError):
            return {}, {}

    def _save(self):
        try:
            self._path.write_text(json.dumps({"synced": self._synced, "pending": self._pending}, ensure_ascii=False, indent=1),
                                  encoding="utf-8")
        except OSError:
            log.warning("No se pudo guardar music_sync.json", exc_info=True)

    def enabled(self):
        return bool((self._config() or {}).get("sync", True)) and self._chat.configured()

    def is_synced(self, video_id):
        return video_id in self._synced

    # ---------- entrar y salir ----------

    def start(self):
        """Al abrir Kyora: lo que quedó pendiente de la vez anterior se retoma."""
        if self._pending and self.enabled():
            self._ensure_thread()

    def stop(self):
        self._stop.set()
        self._wake.set()

    def enqueue(self, video_id, path, title="", playlist=""):
        """Una canción recién bajada (o una que se pide mandar otra vez): se pone en la cola de subida."""
        if not self.enabled() or video_id in self._synced:
            return
        with self._lock:
            if video_id in self._pending:
                return
            self._pending[video_id] = {"path": str(path), "title": title or "", "playlist": playlist or ""}
            self._save()
        self._ensure_thread()

    # ---------- el hilo de subida ----------

    def _ensure_thread(self):
        with self._lock:
            if self._thread is None:
                self._stop.clear()
                self._thread = threading.Thread(target=self._run, daemon=True, name="kyora-music-sync")
                self._thread.start()

    def _run(self):
        while not self._stop.is_set():
            with self._lock:
                item = next(iter(self._pending.items()), None)
                if item is None:
                    self._thread = None  # nada que subir: el hilo termina; el próximo `enqueue` lo vuelve a arrancar
                    return
            if self._upload_one(*item) == "retry":
                self._wake.wait(self._retry)
                self._wake.clear()
        with self._lock:
            self._thread = None

    def _done(self, video_id, track=None):
        with self._lock:
            self._pending.pop(video_id, None)
            if track:
                self._synced[video_id] = track
            self._save()

    def _say(self, video_id, state, title, message=""):
        self._emit({"kind": "sync", "id": video_id, "state": state, "title": title, "message": message})

    def _upload_one(self, video_id, info):
        """«ok» (subida), «drop» (no tiene arreglo: se descarta) o «retry» (sin conexión o sin sesión: se vuelve a intentar)."""
        path, title = Path(info["path"]), info.get("title") or Path(info["path"]).stem
        if not path.is_file():
            self._done(video_id)
            return "drop"
        size = path.stat().st_size
        if size > self._chat.max_bytes():
            self._done(video_id)
            self._say(video_id, "error", title,
                      f"«{path.name}» pesa {size / 1e6:.0f} MB y no cabe en la nube ({self._chat.max_bytes() // 1_000_000} MB)")
            return "drop"
        client = self._chat.client_ready()
        if client is None:
            return "retry"
        self._say(video_id, "uploading", title)
        track = track_id(video_id)
        try:
            storage_path = f"{client.user_id}/music/{track}/{safe_name(path.name)}"
            client.upload(storage_path, path.read_bytes(), MIME)
            client.rpc("add_music_track", {"p_id": track, "p_title": title, "p_file_name": path.name,
                                           "p_storage_path": storage_path, "p_mime_type": MIME, "p_size_bytes": size,
                                           "p_playlist": info.get("playlist") or None})
        except ChatError as err:
            if err.retryable:
                self._say(video_id, "error", title, "Sin conexión: se mandará al móvil cuando vuelva")
                return "retry"
            self._done(video_id)
            self._say(video_id, "error", title, err.message)
            return "drop"
        except OSError:
            self._done(video_id)
            self._say(video_id, "error", title, f"No se pudo leer «{path.name}»")
            return "drop"
        self._done(video_id, track)
        self._say(video_id, "synced", title)
        return "ok"
