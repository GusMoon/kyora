"""El módulo Música como acciones con nombre (music.*): las listas de YouTube del usuario (con las cookies de su
navegador) y el envío de sus canciones en MP3 a la persona que elija («Yo» o un pasante).

«Descargar» no guarda nada en la PC: baja el MP3 a una carpeta temporal, se lo pasa a `on_done` (la sincronización con
Supabase lo sube para esa persona y borra el temporal) y la canción pasa a «enviada» cuando `mark_sent` lo confirma.
Sin sincronización (`on_done` vacío) se comporta como antes: el MP3 se queda en la carpeta que se le dio.

Todo corre en hilos y las respuestas salen por `emit` (la señal music_result de la interfaz) como diccionarios con
`kind`: ffmpeg, playlists, songs, progress, recipients, finished o error. Los estados de una canción son pending, queued,
doing (bajando), sending (subiéndose) y done (enviada, anotada en music.json con a quién); «descargar» solo toma las que
no están hechas, así que repetirlo reintenta las que faltan.
"""
import json
import logging
import subprocess
import threading
import time
from collections import deque
from pathlib import Path

from kyora.chat.client import ChatError
from kyora.core.actions import ActionError
from kyora.music import ytdlp
from kyora.music.proxy import StreamProxy

log = logging.getLogger("kyora.music")
CREATE_NO_WINDOW = 0x08000000
STREAM_TTL = 3600  # los enlaces de audio de YouTube duran horas; una se guarda para no pedirla dos veces


def _default_runner(opts):
    import yt_dlp

    return yt_dlp.YoutubeDL(opts)


class MusicService:
    def __init__(self, data_dir, music_dir, config, emit, runner=_default_runner, find_ffmpeg=ytdlp.find_ffmpeg):
        self._path = Path(data_dir) / "music.json"
        self._music_dir = Path(music_dir)
        self._config = config  # función que devuelve la sección "music" de config.json
        self._emit = emit
        self._runner = runner
        self._find_ffmpeg = find_ffmpeg
        self._lock = threading.Lock()
        self._cancel = threading.Event()
        self._queue = deque()  # [(playlist, id)] por bajar
        self._worker = None
        self._songs = {}  # playlist -> canciones de la última vez que se abrió
        self._urls = {}  # id -> (cuándo, enlace local del proxy)
        self._proxy = StreamProxy()  # QtMultimedia no manda las cabeceras de YouTube: este las manda por él
        # `on_done(id, ruta o None, título, lista, destinatario, nombre)`: cada canción recién bajada (sube a Supabase)
        self.on_done = None
        self.can_send = None  # `can_send()`: ¿se puede mandar al móvil ahora? (la sincronización está activa)
        self.uploaded = None  # `uploaded(id)`: ¿ese MP3 ya está en la nube? Entonces mandarlo a otro no necesita bajarlo
        self.fetch_recipients = None  # `fetch_recipients()` -> [{id, name, me}]; lanza ChatError
        self._targets = {}  # id -> (destinatario, nombre) de lo que está en cola o bajándose
        self._sending = set()  # ids que se están subiendo
        self._done, self._sent = self._load()

    def register(self, registry):
        r = registry
        r.register("music.playlists", self.playlists)
        r.register("music.songs", self.songs)
        r.register("music.download", self.download)
        r.register("music.recipients", self.recipients)
        r.register("music.cancel", self.cancel)
        r.register("music.stream", self.stream)
        r.register("music.install_ffmpeg", self.install_ffmpeg)
        r.register("music.save_cookies", self.save_cookies)

    # ---------- estado guardado ----------

    def _load(self):
        """(`done`: MP3 guardados en una carpeta, de antes o sin sincronización; `sent`: a quién se mandó cada canción)."""
        try:
            data = json.loads(self._path.read_text(encoding="utf-8"))
            sent = {str(k): [str(r) for r in v] for k, v in data.get("sent", {}).items()}
            return {str(k): str(v) for k, v in data.get("done", {}).items()}, sent
        except (OSError, ValueError, AttributeError):
            return {}, {}

    def _save(self):
        try:
            self._path.write_text(json.dumps({"done": self._done, "sent": self._sent}, ensure_ascii=False, indent=1),
                                  encoding="utf-8")
        except OSError:
            log.warning("No se pudo guardar music.json", exc_info=True)

    def _local(self, video_id):
        """La ruta del MP3 si está guardado en una carpeta y sigue ahí, o None."""
        path = self._done.get(video_id)
        return path if path and Path(path).exists() else None

    def is_done(self, video_id):
        return self._local(video_id) is not None or bool(self._sent.get(video_id))

    def _browser(self):
        return (self._config() or {}).get("browser") or "chrome"

    def _cookies_file(self):
        r"""cookies.txt exportado: music.cookies_file, o %APPDATA%\Kyora\cookies.txt si existe."""
        chosen = (self._config() or {}).get("cookies_file")
        path = Path(chosen) if chosen else self._path.with_name("cookies.txt")
        return path if path.is_file() else None

    def _state(self, video_id):
        if self.is_done(video_id):
            return "done"
        if video_id in self._sending:
            return "sending"
        return "queued" if any(i == video_id for _, i in self._queue) else "pending"

    def _spawn(self, target, *args):
        threading.Thread(target=target, args=args, daemon=True, name="kyora-music").start()

    # ---------- FFmpeg ----------

    def _ffmpeg_message(self, message=""):
        self._emit({"kind": "ffmpeg", "available": self._find_ffmpeg() is not None, "message": message})

    def install_ffmpeg(self):
        self._spawn(self._install_ffmpeg)

    def _install_ffmpeg(self):
        self._ffmpeg_message("Instalando FFmpeg con winget…")
        try:
            run = subprocess.run(
                ["winget", "install", "--id", "Gyan.FFmpeg", "-e", "--accept-source-agreements",
                 "--accept-package-agreements"],
                check=False, capture_output=True, timeout=600, creationflags=CREATE_NO_WINDOW,
            )
            failed = run.returncode != 0 and self._find_ffmpeg() is None
        except (OSError, subprocess.TimeoutExpired):
            failed = True
        self._ffmpeg_message("No se pudo instalar FFmpeg (instálalo con: winget install Gyan.FFmpeg)" if failed else "")

    # ---------- listas y canciones ----------

    def save_cookies(self, text):
        """Guarda las cookies que el usuario pegó (el contenido de un cookies.txt) y vuelve a pedir sus listas."""
        lines = []
        for raw in str(text).splitlines():
            line = raw.strip()
            if not line or (line.startswith("#") and not line.startswith("#HttpOnly_")):
                continue
            fields = line.split("\t") if line.count("\t") >= 6 else line.split(None, 6)  # al pegar, los tabuladores a veces se vuelven espacios
            if len(fields) == 7:
                lines.append("\t".join(fields))
        if not any(("youtube.com" in line or "google.com" in line) for line in lines):
            raise ActionError("bad_cookies", "No parece un cookies.txt de YouTube: pega todo su contenido")
        chosen = (self._config() or {}).get("cookies_file")
        path = Path(chosen) if chosen else self._path.with_name("cookies.txt")
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("# Netscape HTTP Cookie File\n" + "\n".join(lines) + "\n", encoding="utf-8")
        self.playlists()

    def playlists(self):
        self._ffmpeg_message()
        self._spawn(self._playlists)

    def _playlists(self):
        try:
            with self._runner(ytdlp.list_opts(self._browser(), self._cookies_file())) as ydl:
                info = ydl.extract_info(ytdlp.PLAYLISTS_URL, download=False)
            self._emit({"kind": "playlists", "playlists": ytdlp.playlists_from(info)})
        except Exception as exc:  # noqa: BLE001 - yt-dlp lanza muchos tipos de error: todos van al panel
            log.warning("Listas de YouTube: %s", exc)
            self._emit({"kind": "error", "where": "playlists", "error": ytdlp.friendly_error(exc, self._browser())})

    def songs(self, playlist):
        self._spawn(self._songs_of, str(playlist))

    def _songs_of(self, playlist):
        try:
            with self._runner(ytdlp.list_opts(self._browser(), self._cookies_file())) as ydl:
                info = ydl.extract_info(ytdlp.playlist_url(playlist), download=False)
            songs = ytdlp.songs_from(info)
        except Exception as exc:  # noqa: BLE001
            log.warning("Canciones de %s: %s", playlist, exc)
            self._emit({"kind": "error", "where": "songs", "error": ytdlp.friendly_error(exc, self._browser())})
            return
        self._songs[playlist] = songs
        self._emit({"kind": "songs", "playlist": playlist,
                    "songs": [{**s, "state": self._state(s["id"])} for s in songs]})

    # ---------- escuchar sin descargar ----------

    def stream(self, id, next_id=None):
        """Resuelve de dónde reproducir `id` (su MP3 si ya está bajada, o el enlace de YouTube) y avisa con
        {"kind": "stream", "id", "source", "local"}. Mientras tanto deja lista `next_id` para que el salto sea inmediato."""
        self._spawn(self._stream, str(id), str(next_id) if next_id else None)

    def _source(self, video_id):
        local = self._local(video_id)
        if local:
            return local
        when, link = self._urls.get(video_id, (0, None))
        if link and time.time() - when < STREAM_TTL:
            return link
        with self._runner(ytdlp.stream_opts(self._browser(), self._cookies_file())) as ydl:
            url, headers = ytdlp.stream_url(ydl.extract_info(ytdlp.video_url(video_id), download=False))
        link = self._proxy.add(video_id, url, headers)
        self._urls[video_id] = (time.time(), link)
        return link

    def _stream(self, video_id, next_id):
        try:
            source = self._source(video_id)
        except Exception as exc:  # noqa: BLE001 - yt-dlp lanza muchos tipos de error: todos van al panel
            log.warning("Reproducir %s: %s", video_id, exc)
            self._emit({"kind": "error", "where": "stream", "id": video_id,
                        "error": ytdlp.friendly_error(exc, self._browser())})
            return
        self._emit({"kind": "stream", "id": video_id, "source": source, "local": self._local(video_id) is not None})
        if next_id:
            try:
                self._source(next_id)
            except Exception:  # noqa: BLE001 - es solo adelantar trabajo: si falla, se pedirá al llegar su turno
                log.info("No se pudo adelantar %s", next_id)

    # ---------- descargar ----------

    def recipients(self):
        """A quién se le puede mandar música: responde {"kind": "recipients", recipients: [{id, name, me}]} (tú primero)."""
        self._spawn(self._recipients)

    def _recipients(self):
        try:
            if self.fetch_recipients is None:
                raise ChatError("sync_off", "El envío a otras personas no está disponible")
            people = self.fetch_recipients()
        except ChatError as err:
            self._emit({"kind": "error", "where": "recipients", "error": err.message})
            return
        except Exception:  # noqa: BLE001 - el panel de destinatarios nunca debe quedarse esperando
            log.warning("Destinatarios", exc_info=True)
            self._emit({"kind": "error", "where": "recipients", "error": "No se pudo pedir la lista de personas"})
            return
        self._emit({"kind": "recipients", "recipients": people})

    def download(self, playlist, ids=None, recipient=None, recipient_name="Yo"):
        """Pone en cola las canciones `ids` de la lista (todas las que falten si no se dan) para mandárselas a
        `recipient` (su id; vacío = «Yo»). Las que ya están en la nube se registran para esa persona sin bajarlas otra vez."""
        playlist = str(playlist)
        if ids is None:
            ids = [s["id"] for s in self._songs.get(playlist, [])]
        sends = self.on_done is not None
        if sends and self.can_send is not None and not self.can_send():
            raise ActionError("no_sync", "No se puede mandar al móvil: falta configurar el chat (Supabase) o music.sync está apagado")
        who = recipient or "me"
        titles = {s["id"]: s.get("title") for s in self._songs.get(playlist, [])}
        wanted, resend = [], []
        for video_id in ids:
            if sends:
                if who in self._sent.get(video_id, []) or video_id in self._sending:
                    continue  # ya se le mandó a esa persona (o va en camino)
                if self.uploaded is not None and self.uploaded(video_id):
                    resend.append(video_id)
                    continue
            elif self.is_done(video_id):
                continue
            wanted.append(video_id)
        if wanted and self._find_ffmpeg() is None:
            raise ActionError("no_ffmpeg", "Falta FFmpeg: instálalo desde la página de Música")
        for video_id in resend:
            self._hand_over(playlist, video_id, None, titles.get(video_id), recipient, recipient_name)
        if not wanted:
            self._emit({"kind": "finished", "playlist": playlist, "done": 0, "failed": 0, "cancelled": False})
            return
        with self._lock:
            queued = {i for _, i in self._queue}
            for video_id in wanted:
                if video_id not in queued:
                    self._targets[video_id] = (recipient, recipient_name)
                    self._queue.append((playlist, video_id))
                    self._emit({"kind": "progress", "playlist": playlist, "id": video_id, "state": "queued",
                                "percent": 0})
            if self._worker is None:
                self._cancel.clear()
                self._worker = threading.Thread(target=self._work, daemon=True, name="kyora-music-dl")
                self._worker.start()

    def _hand_over(self, playlist, video_id, path, title, recipient, recipient_name):
        """Le pasa la canción a la sincronización (que la sube). False si no pudo ponerla en cola."""
        self._sending.add(video_id)
        self._emit({"kind": "progress", "playlist": playlist, "id": video_id, "state": "sending", "percent": 100})
        try:
            self.on_done(video_id, str(path) if path else None, title, playlist, recipient, recipient_name)
        except Exception:  # noqa: BLE001 - un fallo al encolar se enseña en la fila, no rompe el resto
            log.warning("No se pudo poner %s en la cola de envío", video_id, exc_info=True)
            self.mark_failed(video_id, "No se pudo preparar el envío", playlist)
            return False
        return True

    def mark_sent(self, video_id, recipient, playlist):
        """La sincronización terminó: la canción ya está para esa persona."""
        with self._lock:
            self._sending.discard(video_id)
            sent = self._sent.setdefault(video_id, [])
            if (recipient or "me") not in sent:
                sent.append(recipient or "me")
            self._save()
        self._emit({"kind": "progress", "playlist": playlist, "id": video_id, "state": "done", "percent": 100})

    def mark_failed(self, video_id, message, playlist):
        """La sincronización no pudo mandarla: la fila vuelve a poder reintentarse, con el motivo."""
        self._sending.discard(video_id)
        self._emit({"kind": "progress", "playlist": playlist, "id": video_id, "state": "error", "percent": 0,
                    "error": message})

    def cancel(self):
        """Detener: se corta la descarga en curso y la cola vuelve a «pendiente»."""
        self._cancel.set()
        with self._lock:
            dropped = list(self._queue)
            self._queue.clear()
            for _, video_id in dropped:
                self._targets.pop(video_id, None)
        for playlist, video_id in dropped:
            self._emit({"kind": "progress", "playlist": playlist, "id": video_id, "state": "pending", "percent": 0})

    def _work(self):
        done = failed = 0
        cancelled = False
        last = ""
        while True:
            with self._lock:
                if not self._queue:
                    self._worker = None
                    break
                playlist, video_id = self._queue.popleft()
            last = playlist
            ok = self._download_one(playlist, video_id)
            if ok is None:  # Detener: la cola ya se vació; si llegó algo nuevo después, se sigue con ello
                cancelled = True
                self._cancel.clear()
                continue
            done, failed = done + bool(ok), failed + (not ok)
        self._emit({"kind": "finished", "playlist": last, "done": done, "failed": failed, "cancelled": cancelled})

    def _download_one(self, playlist, video_id):
        """True si quedó bajada, False si falló, None si el usuario la detuvo."""

        def progress(percent, state="doing", **extra):
            self._emit({"kind": "progress", "playlist": playlist, "id": video_id, "state": state,
                        "percent": percent, **extra})

        def hook(d):
            if self._cancel.is_set():
                raise ytdlp.DownloadCancelled()
            if d.get("status") == "downloading":
                progress(ytdlp.percent(d))

        progress(0)
        opts = ytdlp.download_opts(self._music_dir, self._browser(), self._find_ffmpeg(), hook, self._cookies_file())
        try:
            self._music_dir.mkdir(parents=True, exist_ok=True)
            with self._runner(opts) as ydl:
                info = ydl.extract_info(ytdlp.video_url(video_id), download=True)
                path = ytdlp.final_path(info, ydl)
                title = (info or {}).get("title") if isinstance(info, dict) else None
        except Exception as exc:  # noqa: BLE001
            if self._cancel.is_set():
                progress(0, "pending")
                return None
            log.warning("Descarga de %s: %s", video_id, exc)
            progress(0, "error", error=ytdlp.friendly_error(exc, self._browser()))
            return False
        recipient, name = self._targets.pop(video_id, (None, "Yo"))
        if self.on_done is None:  # sin sincronización: el MP3 se queda donde se bajó
            self._done[video_id] = str(path)
            self._save()
            progress(100, "done")
            return True
        return self._hand_over(playlist, video_id, path, title, recipient, name)
