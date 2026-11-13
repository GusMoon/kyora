"""El servicio local de música de Merida: `python -m kyora.merida` (lo arranca Scripts\\Merida\\iniciar_merida.bat).

Merida es una web y no puede leer las cookies del navegador ni bajar de YouTube; este proceso de Python hace por ella lo
mismo que la página Música de Kyora, con el mismo motor (`MusicService` + `MusicSync`, sin Qt):

- sus listas de YouTube con las cookies del navegador (o el cookies.txt que comparte con Kyora),
- bajar canciones en MP3 y mandarlas a quien elija («Yo», un pasante) o guardarlas en una carpeta de esta PC,
- escuchar sin bajar (el proxy de audio de Kyora).

Habla HTTP solo en 127.0.0.1 con la web de Merida: `POST /api/action/<music.*>` (una lista cerrada), `GET /api/events`
(los eventos de música como Server-Sent Events) y `GET/POST /api/settings`. Cada petición lleva un token aleatorio que
este proceso escribe al arrancar en %APPDATA%\\Kyora\\merida_service.json (Vite se lo pasa a la página), y se rechaza
cualquier Origin o Host que no sea el de Merida: así otra web abierta en el navegador no puede pedirle descargas.

La contraseña del .env la usa solo este proceso (para subir a Supabase); nunca sale de él.
"""
import json
import logging
import queue
import secrets
import shutil
import sys
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

from kyora import config as app_config
from kyora.chat import env as chat_env
from kyora.chat.client import ChatError, SupabaseClient
from kyora.core.actions import ActionRegistry
from kyora.music.service import MusicService
from kyora.music.sync import MusicSync

log = logging.getLogger("kyora.merida")

PORT = 5190
WEB_ORIGINS = ("http://127.0.0.1:5180", "http://localhost:5180")
FOLDER = "folder"  # el destino especial «Esta PC (carpeta)»
FOLDER_NAME = "Esta PC (carpeta)"
# lo único que la web puede pedir (nada de chat, notas, ventanas…)
ALLOWED = (
    "music.playlists", "music.songs", "music.download", "music.recipients", "music.cancel", "music.stream",
    "music.install_ffmpeg", "music.save_cookies",
)
BROWSERS = ("chrome", "edge", "brave", "firefox", "opera", "vivaldi", "chromium")
MAX_BODY = 1_000_000  # un cookies.txt pegado cabe de sobra
PING_S = 15  # latido de los eventos para que la conexión no se cierre sola
DEFAULT_MAX_MB = 50


# ---------------------------------------------------------------- ajustes de Merida

class Settings:
    """Los ajustes de música de Merida, en su propio archivo (no toca el config.json de Kyora aunque esté abierta)."""

    def __init__(self, path, default_folder=None):
        self._path = Path(path)
        self._defaults = {"browser": "chrome", "folder": str(default_folder or Path.home() / "Music"),
                          "default_recipient": None}
        self._lock = threading.Lock()

    def get(self):
        try:
            saved = json.loads(self._path.read_text(encoding="utf-8"))
            saved = saved if isinstance(saved, dict) else {}
        except (OSError, ValueError):
            saved = {}
        return {key: saved.get(key, value) for key, value in self._defaults.items()}

    def update(self, patch):
        """Cambia lo que venga en `patch` (validado). ValueError con el motivo si algo no vale."""
        if not isinstance(patch, dict):
            raise ValueError("Los ajustes deben ser un objeto")  # noqa: TRY004 - llega del JSON de la web: es un dato malo, no un fallo de tipos
        with self._lock:
            current = self.get()
            if "browser" in patch:
                browser = str(patch["browser"] or "").lower()
                if browser not in BROWSERS:
                    raise ValueError(f"Navegador no válido: usa uno de {', '.join(BROWSERS)}")
                current["browser"] = browser
            if "folder" in patch:
                folder = str(patch["folder"] or "").strip()
                if not folder or not Path(folder).is_absolute():
                    raise ValueError("La carpeta debe ser una ruta completa, por ejemplo C:\\Users\\tu\\Music")
                current["folder"] = folder
            if "default_recipient" in patch:
                value = patch["default_recipient"]
                current["default_recipient"] = None if value in (None, "", "me") else str(value)
            self._path.parent.mkdir(parents=True, exist_ok=True)
            self._path.write_text(json.dumps(current, ensure_ascii=False, indent=1), encoding="utf-8")
            return current


# ---------------------------------------------------------------- la sesión de Supabase para subir

class SessionChat:
    """Lo mínimo que `MusicSync` necesita del chat: una sesión de Supabase con las credenciales del .env."""

    def __init__(self, env, client_factory=SupabaseClient, max_mb=DEFAULT_MAX_MB):
        self._env, self._factory, self._max = env, client_factory, max_mb * 1_000_000
        self._client = None
        self._lock = threading.Lock()

    def configured(self):
        return bool(self._env.ready)

    def max_bytes(self):
        return self._max

    def client_ready(self):
        """El cliente con sesión, o None si no se puede entrar ahora (MusicSync lo reintenta)."""
        if not self._env.ready:
            return None
        with self._lock:
            if self._client is None:
                client = self._factory(self._env)
                try:
                    client.sign_in()
                except ChatError as err:
                    log.warning("No se pudo entrar a Supabase: %s", err.message)
                    return None
                self._client = client
            return self._client


# ---------------------------------------------------------------- eventos para la web

class EventHub:
    """Reparte cada evento de música a todas las páginas de Merida conectadas."""

    def __init__(self):
        self._queues = set()
        self._lock = threading.Lock()

    def subscribe(self):
        q = queue.Queue(maxsize=500)
        with self._lock:
            self._queues.add(q)
        return q

    def unsubscribe(self, q):
        with self._lock:
            self._queues.discard(q)

    def publish(self, event):
        with self._lock:
            targets = list(self._queues)
        for q in targets:
            try:
                q.put_nowait(event)
            except queue.Full:  # una página que no lee no frena a las demás
                pass


# ---------------------------------------------------------------- el motor de música, como en Kyora

class MeridaMusic:
    """`MusicService` + `MusicSync` conectados igual que en Kyora (kyora/app.py), más el destino «Esta PC (carpeta)»."""

    def __init__(self, data_dir, music_dir, chat, settings, cookies_file, runner=None, find_ffmpeg=None):
        self.hub = EventHub()
        self.settings = settings
        self._cookies_file = str(cookies_file)
        self._folder_call = False
        self._call_lock = threading.Lock()
        extra = {}
        if runner is not None:
            extra["runner"] = runner
        if find_ffmpeg is not None:
            extra["find_ffmpeg"] = find_ffmpeg
        Path(data_dir).mkdir(parents=True, exist_ok=True)
        self.music = MusicService(data_dir, music_dir, self._music_config, self.hub.publish, **extra)
        self.sync = MusicSync(data_dir, chat, self.hub.publish, lambda: {"sync": True})
        m = self.music
        m.on_done = self._on_done
        # para la carpeta no hace falta Supabase, y aunque la canción ya esté en la nube hay que bajarla
        m.can_send = lambda: self._folder_call or self.sync.enabled()
        m.uploaded = lambda video_id: (not self._folder_call) and self.sync.is_uploaded(video_id)
        m.fetch_recipients = self._recipients
        self.sync.on_sent = m.mark_sent
        self.sync.on_failed = m.mark_failed
        self.registry = ActionRegistry()
        m.register(self.registry)
        self.registry.register("music.download", self.download)  # la versión que sabe del destino carpeta

    def _music_config(self):
        # el mismo cookies.txt que Kyora (leerlo y guardarlo); el navegador, el de los ajustes de Merida
        return {"browser": self.settings.get()["browser"], "cookies_file": self._cookies_file}

    def _recipients(self):
        try:
            people = self.sync.recipients()
        except ChatError as err:
            log.info("Sin destinatarios de Supabase: %s", err.message)
            people = []
        return people + [{"id": FOLDER, "name": FOLDER_NAME, "me": False}]

    def download(self, playlist, ids=None, recipient=None, recipient_name="Yo"):
        folder = recipient == FOLDER
        with self._call_lock:
            self._folder_call = folder
            try:
                return self.music.download(playlist, ids=ids, recipient=recipient,
                                           recipient_name=FOLDER_NAME if folder else recipient_name)
            finally:
                self._folder_call = False

    def _on_done(self, video_id, path, title="", playlist="", recipient=None, recipient_name="Yo"):
        if recipient != FOLDER:
            self.sync.enqueue(video_id, path, title, playlist, recipient, recipient_name)
            return
        if not path or not Path(path).is_file():
            self.music.mark_failed(video_id, "No se encontró el MP3 recién bajado", playlist)
            return
        folder = Path(self.settings.get()["folder"])
        try:
            folder.mkdir(parents=True, exist_ok=True)
            target = _free_name(folder / Path(path).name)
            shutil.move(path, target)
        except OSError as err:
            log.warning("No se pudo guardar %s en %s: %s", video_id, folder, err)
            self.music.mark_failed(video_id, f"No se pudo guardar en {folder}", playlist)
            return
        self.hub.publish({"kind": "saved", "id": video_id, "title": title or target.stem, "path": str(target)})
        self.music.mark_sent(video_id, FOLDER, playlist)

    def local_file(self, video_id):
        """El MP3 de esa canción si está guardado (para escucharlo desde la web), o None."""
        path = self.music._local(str(video_id))
        return Path(path) if path else None

    def start(self):
        self.sync.start()

    def stop(self):
        self.sync.stop()


def _free_name(path):
    """`path`, o `nombre (2).mp3`, `nombre (3).mp3`… si ya existe."""
    if not path.exists():
        return path
    for n in range(2, 1000):
        candidate = path.with_name(f"{path.stem} ({n}){path.suffix}")
        if not candidate.exists():
            return candidate
    raise OSError("Demasiados archivos con el mismo nombre")


# ---------------------------------------------------------------- HTTP

def make_server(engine, token, port=PORT, host="127.0.0.1", origins=WEB_ORIGINS):
    """El servidor HTTP (aún sin arrancar). `port=0` elige uno libre (para las pruebas)."""

    class Handler(BaseHTTPRequestHandler):
        server_version = "MeridaMusic/1"

        def log_message(self, fmt, *args):  # sin ruido en la consola por cada petición
            log.debug("%s %s", self.address_string(), fmt % args)

        # ----- comprobaciones

        def _origin_ok(self):
            origin = self.headers.get("Origin")
            return origin is None or origin in origins

        def _host_ok(self):
            port_now = self.server.server_address[1]
            return self.headers.get("Host", "") in (f"127.0.0.1:{port_now}", f"localhost:{port_now}")

        def _token_ok(self, query):
            given = self.headers.get("X-Merida-Token") or (query.get("token") or [""])[0]
            return bool(given) and secrets.compare_digest(given, token)

        def _cors(self):
            origin = self.headers.get("Origin")
            if origin in origins:
                self.send_header("Access-Control-Allow-Origin", origin)
                self.send_header("Vary", "Origin")

        def _json(self, status, body):
            data = json.dumps(body, ensure_ascii=False).encode("utf-8")
            self.send_response(status)
            self._cors()
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(data)

        def _fail(self, status, code, message):
            self._json(status, {"ok": False, "error": {"code": code, "message": message}})

        def _guard(self):
            """(ruta, query) si la petición puede seguir; si no, responde el error y devuelve None."""
            parts = urlsplit(self.path)
            query = parse_qs(parts.query)
            if not self._host_ok() or not self._origin_ok():
                self._fail(403, "forbidden", "Solo la web de Merida puede usar este servicio")
                return None
            if not self._token_ok(query):
                self._fail(401, "bad_token", "Falta el token del servicio: recarga Merida")
                return None
            return parts.path, query

        def _body(self):
            length = int(self.headers.get("Content-Length") or 0)
            if length > MAX_BODY:
                raise ValueError("La petición es demasiado grande")
            raw = self.rfile.read(length) if length else b""
            return json.loads(raw.decode("utf-8")) if raw else {}

        # ----- métodos

        def do_OPTIONS(self):
            if not self._host_ok() or self.headers.get("Origin") not in origins:
                self.send_response(403)
                self.end_headers()
                return
            self.send_response(204)
            self._cors()
            self.send_header("Access-Control-Allow-Methods", "GET, POST")
            self.send_header("Access-Control-Allow-Headers", "Content-Type, X-Merida-Token")
            self.send_header("Access-Control-Max-Age", "600")
            self.end_headers()

        def do_GET(self):
            guarded = self._guard()
            if guarded is None:
                return
            path, query = guarded
            if path == "/api/health":
                self._json(200, {"ok": True, "data": {"service": "merida-music"}})
            elif path == "/api/settings":
                self._json(200, {"ok": True, "data": engine.settings.get()})
            elif path == "/api/events":
                self._events()
            elif path == "/api/file":
                self._file((query.get("id") or [""])[0])
            else:
                self._fail(404, "not_found", "No existe esa ruta")

        def do_POST(self):
            guarded = self._guard()
            if guarded is None:
                return
            path, _ = guarded
            try:
                body = self._body()
            except (ValueError, UnicodeDecodeError) as err:
                self._fail(400, "bad_payload", f"JSON no válido: {err}")
                return
            if path == "/api/settings":
                try:
                    self._json(200, {"ok": True, "data": engine.settings.update(body)})
                except ValueError as err:
                    self._fail(400, "bad_settings", str(err))
                return
            if path.startswith("/api/action/"):
                name = path.removeprefix("/api/action/")
                if name not in ALLOWED:
                    self._fail(404, "unknown_action", f"Merida no puede pedir {name}")
                    return
                if not isinstance(body, dict):
                    self._fail(400, "bad_payload", "El cuerpo debe ser un objeto JSON")
                    return
                self._json(200, engine.registry.invoke(name, body))
                return
            self._fail(404, "not_found", "No existe esa ruta")

        # ----- eventos y archivos

        def _events(self):
            q = engine.hub.subscribe()
            try:
                self.send_response(200)
                self._cors()
                self.send_header("Content-Type", "text/event-stream; charset=utf-8")
                self.send_header("Cache-Control", "no-store")
                self.send_header("Connection", "keep-alive")
                self.end_headers()
                self.wfile.write(b": hola\n\n")
                self.wfile.flush()
                while not getattr(self.server, "closing", False):
                    try:
                        event = q.get(timeout=PING_S)
                        chunk = f"data: {json.dumps(event, ensure_ascii=False)}\n\n"
                    except queue.Empty:
                        chunk = ": ping\n\n"
                    self.wfile.write(chunk.encode("utf-8"))
                    self.wfile.flush()
            except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError, OSError):
                pass  # la página se cerró
            finally:
                engine.hub.unsubscribe(q)

        def _file(self, video_id):
            path = engine.local_file(video_id) if video_id else None
            if path is None or not path.is_file():
                self._fail(404, "not_found", "Esa canción no está guardada en esta PC")
                return
            data = path.read_bytes()
            self.send_response(200)
            self._cors()
            self.send_header("Content-Type", "audio/mpeg")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

    server = _QuietServer((host, port), Handler)
    server.daemon_threads = True
    server.closing = False
    return server


class _QuietServer(ThreadingHTTPServer):
    """Como ThreadingHTTPServer, pero sin la traza de error cuando el navegador cierra una conexión (pasa a menudo)."""

    def handle_error(self, request, client_address):
        if isinstance(sys.exc_info()[1], (ConnectionAbortedError, ConnectionResetError, BrokenPipeError)):
            return
        super().handle_error(request, client_address)


def write_service_file(path, port, token):
    """Deja el puerto y el token donde Vite los lee para pasárselos a la página de Merida."""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps({"url": f"http://127.0.0.1:{port}", "token": token}), encoding="utf-8")


def build(data_root=None):
    """El motor con las rutas de siempre: estado propio en %APPDATA%\\Kyora\\merida, cookies.txt compartido con Kyora."""
    root = Path(data_root or app_config.data_dir())
    settings = Settings(root / "merida.json")
    chat = SessionChat(chat_env.load(root))
    music_dir = Path(tempfile.gettempdir()) / "Kyora" / "merida-music"
    return MeridaMusic(root / "merida", music_dir, chat, settings, root / "cookies.txt"), root


def main(argv=None):
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(name)s %(levelname)s %(message)s")
    engine, root = build()
    token = secrets.token_urlsafe(32)
    try:
        server = make_server(engine, token)
    except OSError:
        print(f"El puerto {PORT} está ocupado: el servicio de música de Merida ya está abierto en otra ventana.")
        return 1
    write_service_file(root / "merida_service.json", PORT, token)
    engine.start()
    print(f"Servicio de música de Merida en http://127.0.0.1:{PORT} (ciérralo con Ctrl+C o cerrando la ventana)")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.closing = True
        engine.stop()
        server.server_close()
    return 0
