"""Manda a Supabase cada canción que la PC acaba de bajar, para la persona que elegiste («Yo» o un pasante).

Cuando `MusicService` termina una descarga llama a `enqueue`. Aquí un hilo sube el MP3 a Storage (`chat-files`, en
`<usuario>/music/<id del vídeo>/<archivo>`, **una sola vez por vídeo**) y registra la canción para esa persona con la
función `add_music_track` (una fila por canción y destinatario). Cuando la canción ya está subida y la mandas a otra
persona, solo se registra la fila: no hace falta volver a bajarla ni a subirla. El MP3 bajado vive en una carpeta
temporal y se borra en cuanto termina el envío.

Usa la misma sesión que el chat (`ChatService.client_ready`). Si no hay internet o la sesión aún no está, la canción queda
pendiente (se guarda en `music_sync.json`) y se reintenta sola, también al volver a abrir Kyora.

Los avisos salen como `{"kind": "sync", id, state: uploading | synced | error, title, message, to}` por el mismo canal
que el resto de la música (`music_result`); además `on_sent(id, destinatario, lista)` y `on_failed(id, mensaje, lista)` le
dicen al servicio de música cómo terminó cada una. Se apaga con `music.sync = false` en config.json.
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
ME = "me"  # el destinatario «Yo» en las claves de la cola


def track_id(video_id, recipient=None):
    """El id de la canción en Supabase: siempre el mismo para el mismo vídeo y destinatario (mandarla otra vez no la
    duplica). Para «Yo» (`recipient` vacío) es el de siempre, así lo ya mandado antes sigue contando."""
    base = f"kyora-music:{video_id}"
    return str(uuid.uuid5(uuid.NAMESPACE_URL, f"{base}:{recipient}" if recipient else base))


REASONS = {  # lo que responde la base de datos (supabase/schema.sql) y qué significa
    "unknown_recipient": "Esa persona no existe en Supabase (¿ya se registró en la app?)",
    "not_admin": "Solo la cuenta de administrador puede mandar música",
    "track_id_taken": "Esa canción ya existe en otra cuenta",
    "not_authenticated": "La sesión de Supabase caducó: reinicia Kyora",
    "file_missing": "La canción ya se borró de la nube porque todos la recibieron: vuelve a mandarla",
}


def explain(err):
    """El motivo de un rechazo de Supabase en español (los códigos de la base de datos no se enseñan tal cual)."""
    for code, text in REASONS.items():
        if code in err.message or code == err.code:
            return text
    return err.message


def cover_url(video_id):
    """La carátula de un vídeo de YouTube (no se sube nada: la app del móvil la pide directamente)."""
    return f"https://i.ytimg.com/vi/{video_id}/hqdefault.jpg"


def key_of(video_id, recipient=None):
    return f"{video_id}:{recipient or ME}"


class MusicSync:
    def __init__(self, data_dir, chat, emit, config=dict, retry_s=RETRY_S):
        """`chat`: el `ChatService` (su sesión de Supabase). `config()`: la sección "music" de config.json."""
        self._path = Path(data_dir) / "music_sync.json"
        self._chat, self._emit, self._config, self._retry = chat, emit, config, retry_s
        self._lock = threading.Lock()
        self._wake = threading.Event()
        self._stop = threading.Event()
        self._thread = None
        self.on_sent = None  # `on_sent(id, destinatario o None, lista)`
        self.on_failed = None  # `on_failed(id, mensaje, lista)`
        self._synced, self._pending, self._uploaded = self._load()

    # ---------- estado guardado ----------

    def _load(self):
        """({clave: id}, {clave: datos}, {vídeo: archivo ya subido}). Lo guardado por la versión de una sola cuenta
        (claves sin destinatario) pasa a ser «Yo»."""
        try:
            data = json.loads(self._path.read_text(encoding="utf-8"))
        except (OSError, ValueError, AttributeError):
            return {}, {}, {}
        synced = {(k if ":" in k else f"{k}:{ME}"): v for k, v in dict(data.get("synced", {})).items()}
        pending = {}
        for k, info in dict(data.get("pending", {})).items():
            info = dict(info)
            info.setdefault("video", k.split(":")[0])
            info.setdefault("recipient", None)
            info.setdefault("temp", False)
            pending[k if ":" in k else f"{k}:{ME}"] = info
        return synced, pending, dict(data.get("uploaded", {}))

    def _save(self):
        try:
            self._path.write_text(json.dumps({"synced": self._synced, "pending": self._pending, "uploaded": self._uploaded},
                                             ensure_ascii=False, indent=1), encoding="utf-8")
        except OSError:
            log.warning("No se pudo guardar music_sync.json", exc_info=True)

    def enabled(self):
        return bool((self._config() or {}).get("sync", True)) and self._chat.configured()

    def is_synced(self, video_id, recipient=None):
        return key_of(video_id, recipient) in self._synced

    def is_uploaded(self, video_id):
        """¿El MP3 de ese vídeo ya está en Storage? Entonces mandarlo a otra persona no necesita bajarlo otra vez."""
        return video_id in self._uploaded

    # ---------- a quién ----------

    def recipients(self):
        """A quién se le puede mandar música: `[{id, name, me}]`, tú primero como «Yo» (`id` vacío). Lanza `ChatError`."""
        if not self.enabled():
            raise ChatError("sync_off", "El envío a otras personas está apagado (music.sync) o falta configurar el chat")
        client = self._chat.client_ready()
        if client is None:
            raise ChatError("no_session", "Aún no hay sesión con Supabase: revisa el chat", retryable=True)
        rows = client.rpc("list_recipients") or []
        people = [{"id": None if row.get("me") else row["id"], "name": "Yo" if row.get("me") else row.get("username") or "?",
                   "me": bool(row.get("me"))} for row in rows]
        return sorted(people, key=lambda p: (not p["me"], p["name"].lower()))

    # ---------- entrar y salir ----------

    def start(self):
        """Al abrir Kyora: lo que quedó pendiente de la vez anterior se retoma."""
        if self._pending and self.enabled():
            self._ensure_thread()

    def stop(self):
        self._stop.set()
        self._wake.set()

    def enqueue(self, video_id, path, title="", playlist="", recipient=None, recipient_name="Yo"):
        """Una canción para una persona (`recipient` = su id, o vacío para «Yo»). `path`: el MP3 bajado (se borra al
        terminar) o `None` si ya estaba subido y solo falta registrarla para esa persona."""
        key = key_of(video_id, recipient)
        if not self.enabled():
            self._discard(path)
            self._fail(video_id, title, playlist, "El envío al móvil está apagado", recipient_name)
            return
        if key in self._synced:
            self._discard(path)
            self._finish(video_id, title, playlist, recipient, recipient_name)
            return
        with self._lock:
            if key in self._pending:
                return
            self._pending[key] = {"video": video_id, "recipient": recipient, "name": recipient_name or "Yo",
                                  "path": str(path) if path else None, "title": title or "", "playlist": playlist or "",
                                  "temp": path is not None}
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

    def _done(self, key, track=None):
        """La canción sale de la cola (enviada o descartada) y su MP3 temporal se borra si nadie más lo espera."""
        with self._lock:
            info = self._pending.pop(key, None)
            if track:
                self._synced[key] = track
            self._save()
            still_needed = {i.get("path") for i in self._pending.values()}
        path = (info or {}).get("path")
        if path and (info or {}).get("temp") and path not in still_needed:
            self._discard(path)

    @staticmethod
    def _discard(path):
        if not path:
            return
        try:
            Path(path).unlink(missing_ok=True)
        except OSError:
            log.info("No se pudo borrar el temporal %s", path)

    def _say(self, video_id, state, title, message="", to="Yo"):
        self._emit({"kind": "sync", "id": video_id, "state": state, "title": title, "message": message, "to": to})

    def _finish(self, video_id, title, playlist, recipient, to):
        self._say(video_id, "synced", title, to=to)
        if self.on_sent:
            self.on_sent(video_id, recipient, playlist)

    def _fail(self, video_id, title, playlist, message, to="Yo"):
        self._say(video_id, "error", title, message, to)
        if self.on_failed:
            self.on_failed(video_id, message, playlist)

    def _upload_one(self, key, info):
        """«ok» (enviada), «drop» (no tiene arreglo: se descarta) o «retry» (sin conexión o sin sesión: se vuelve a intentar)."""
        video, recipient, to = info["video"], info.get("recipient"), info.get("name") or "Yo"
        playlist = info.get("playlist") or ""
        path = Path(info["path"]) if info.get("path") else None
        title = info.get("title") or (path.stem if path else video)
        uploaded = self._uploaded.get(video)
        if uploaded is None:
            if path is None or not path.is_file():
                self._done(key)
                self._fail(video, title, playlist, "La canción ya no está en el disco: vuelve a mandarla", to)
                return "drop"
            size = path.stat().st_size
            if size > self._chat.max_bytes():
                self._done(key)
                self._fail(video, title, playlist,
                           f"«{path.name}» pesa {size / 1e6:.0f} MB y no cabe en la nube ({self._chat.max_bytes() // 1_000_000} MB)",
                           to)
                return "drop"
        client = self._chat.client_ready()
        if client is None:
            return "retry"
        self._say(video, "uploading", title, to=to)
        try:
            if uploaded is None:
                storage_path = f"{client.user_id}/music/{track_id(video)}/{safe_name(path.name)}"
                client.upload(storage_path, path.read_bytes(), MIME)
                uploaded = {"path": storage_path, "file_name": path.name, "size": size}
                with self._lock:
                    self._uploaded[video] = uploaded
                    self._save()
            client.rpc("add_music_track", {"p_id": track_id(video, recipient), "p_title": title,
                                           "p_file_name": uploaded["file_name"], "p_storage_path": uploaded["path"],
                                           "p_mime_type": MIME, "p_size_bytes": uploaded["size"],
                                           "p_playlist": playlist or None, "p_recipient_id": recipient,
                                           "p_cover_url": cover_url(video)})
        except ChatError as err:
            if err.retryable:
                self._say(video, "error", title, "Sin conexión: se mandará cuando vuelva", to)
                return "retry"
            if "file_missing" in err.message or err.code == "file_missing":
                # la limpieza automática de Supabase borró el MP3 tras recibirse: la próxima vez hay que bajarlo y subirlo otra vez
                with self._lock:
                    self._uploaded.pop(video, None)
                    self._save()
            self._done(key)
            self._fail(video, title, playlist, explain(err), to)
            return "drop"
        except OSError:
            self._done(key)
            self._fail(video, title, playlist, f"No se pudo leer «{path.name if path else title}»", to)
            return "drop"
        self._done(key, track_id(video, recipient))
        self._finish(video, title, playlist, recipient, to)
        return "ok"
