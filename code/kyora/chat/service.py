"""El chat como acciones con nombre (chat.*): mensajes de texto, fotos y archivos entre tus dispositivos, con Supabase.

Todo corre en hilos y las novedades salen por `emit` (la señal chat_event de la interfaz) como diccionarios con `kind`:
- `connection`: {state, detail, missing}; state = unconfigured | connecting | online | offline | auth_error.
- `message`: {message, incoming}: un mensaje nuevo (propio al escribirlo, o de otro dispositivo al llegar).
- `status`: {id, status, message?, error?}: pasó de «en espera» (pending) a «enviado» (sent), o falló sin remedio.
- `history` / `older`: {messages}: lo guardado, del más antiguo al más nuevo.
- `deleted`: {id}. `attachment`: {message_id, attachment_id, path, open}. `saved`: {message_id, attachment_id, path, name}
  (la copia que dejó «Descargar» en Descargas). `error`: {error}.

Un mensaje se guarda al instante en `chat.sqlite` como **en espera** y el hilo de envío lo sube cuando hay conexión (los
archivos primero, a Storage; luego la función `send_message`). Sin internet queda en espera y se reintenta solo; como su
`id` lo crea este dispositivo, un reintento nunca lo duplica. Lo que llega de otros dispositivos entra por Realtime: cada
aviso provoca una puesta al día con `list_messages(p_after=…)`, que también recupera lo perdido tras una desconexión.
"""
import logging
import mimetypes
import os
import re
import threading
import uuid
from datetime import UTC, datetime
from pathlib import Path

from kyora.chat import env as chat_env
from kyora.chat.client import ChatError, SupabaseClient
from kyora.chat.realtime import RealtimeClient
from kyora.chat.store import ChatStore
from kyora.core.actions import ActionError

log = logging.getLogger("kyora.chat")
AUTH_CODES = {"invalid_credentials", "not_authenticated", "28000", "401", "bad_jwt", "user_not_found"}
PAGE = 50  # mensajes que se piden de golpe
MAX_BACKOFF = 60
DEFAULT_MAX_MB = 50  # el límite por archivo del plan gratuito de Supabase


def now_iso():
    return datetime.now(UTC).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def safe_name(name):
    """Un nombre de archivo apto para las rutas de Storage (letras, números, punto, guion y guion bajo)."""
    cleaned = re.sub(r"[^A-Za-z0-9._-]+", "_", name).strip("._") or "archivo"
    return cleaned[-120:]


def downloads_folder():
    """La carpeta Descargas de Windows (o `~/Downloads` si no se puede saber)."""
    try:
        from kyora.system import shell

        found = shell.known_folder("downloads")
    except Exception:  # noqa: BLE001 - sin Windows (las pruebas)
        found = None
    return Path(found) if found else Path.home() / "Downloads"


def unique_path(folder, name):
    """`folder/name`, o `folder/name (1).ext`, `(2)`… si ya existe: bajar un archivo nunca pisa otro."""
    target = Path(folder) / name
    stem, suffix, n = target.stem, target.suffix, 1
    while target.exists():
        target = Path(folder) / f"{stem} ({n}){suffix}"
        n += 1
    return target


class ChatService:
    def __init__(self, data_dir, emit, config=dict, env_loader=None, client_factory=SupabaseClient,
                 realtime_factory=RealtimeClient, opener=None, store=None, downloads=None):
        """`config()`: la sección "chat" de config.json. `env_loader()`: devuelve un `ChatEnv` (los tests ponen el suyo).
        `opener(ruta)`: abre un archivo con su programa (os.startfile). `downloads()`: la carpeta Descargas."""
        self._dir = Path(data_dir)
        self._downloads = downloads or downloads_folder
        self._emit = emit
        self._config = config
        self._env_loader = env_loader or (lambda: chat_env.load(self._dir))
        self._client_factory = client_factory
        self._realtime_factory = realtime_factory
        self._opener = opener or os.startfile
        self.store = store or ChatStore(self._dir / "chat.sqlite")
        self.env = chat_env.ChatEnv()
        self.client = None
        self.state, self.detail = "unconfigured", ""
        self._conversation = self.store.meta("conversation_id") or ""
        self._stop = threading.Event()
        self._reload = threading.Event()
        self._session_stop = threading.Event()
        self._wake_send = threading.Event()
        self._catch_up_wanted = threading.Event()
        self._ready = threading.Event()  # hay sesión y conversación: se puede enviar
        self._threads = []

    def register(self, registry):
        r = registry
        r.register("chat.history", self.history)
        r.register("chat.older", self.older)
        r.register("chat.send", self.send)
        r.register("chat.retry", self.retry)
        r.register("chat.delete", self.delete)
        r.register("chat.fetch_attachment", self.fetch_attachment)
        r.register("chat.save_attachment", self.save_attachment)
        r.register("chat.reload", self.reload)

    # ---------- para otros servicios (la música sube sus canciones con esta misma sesión) ----------

    def client_ready(self):
        """El cliente de Supabase si ya hay sesión y conversación; si no, None."""
        return self.client if self._ready.is_set() and self.client is not None else None

    def configured(self):
        """¿Hay credenciales en supabase/.env? Sin ellas el chat (y lo que cuelga de él) no funciona nunca."""
        return self.state != "unconfigured"

    def max_bytes(self):
        return self._max_bytes()

    # ---------- ajustes ----------

    def _max_bytes(self):
        return int((self._config() or {}).get("max_mb") or DEFAULT_MAX_MB) * 1_000_000

    def _page(self):
        return int((self._config() or {}).get("history") or PAGE)

    def _cache_dir(self):
        path = self._dir / "chat_cache"
        path.mkdir(parents=True, exist_ok=True)
        return path

    # ---------- arrancar y parar ----------

    def start(self):
        """Lanza los hilos de sincronización y de envío (los dos paran con `stop`)."""
        for target, name in ((self._sync_loop, "kyora-chat-sync"), (self._send_loop, "kyora-chat-send")):
            thread = threading.Thread(target=target, daemon=True, name=name)
            thread.start()
            self._threads.append(thread)

    def stop(self):
        self._stop.set()
        self._session_stop.set()
        self._reload.set()
        self._wake_send.set()

    def reload(self):
        """Vuelve a leer el .env (por ejemplo, después de rellenarlo) y se reconecta."""
        self._session_stop.set()
        self._reload.set()

    def _set_state(self, state, detail=""):
        if (state, detail) == (self.state, self.detail):
            return
        self.state, self.detail = state, detail
        self._emit({"kind": "connection", "state": state, "detail": detail, "missing": self.env.missing()})

    def _fail_event(self, text):
        self._emit({"kind": "error", "error": text})

    # ---------- sincronización: sesión, historial y tiempo real ----------

    def _sync_loop(self):
        backoff = 2
        while not self._stop.is_set():
            self._reload.clear()
            self._session_stop = threading.Event()
            self.env = self._env_loader()
            self._ready.clear()
            if not self.env.ready:
                self._set_state("unconfigured", "Faltan: " + ", ".join(self.env.missing()))
                self._reload.wait()
                continue
            self.client = self._client_factory(self.env)
            self._set_state("connecting")
            try:
                self._connect_and_listen()
                backoff = 2
            except ChatError as err:
                self._ready.clear()
                if err.code in AUTH_CODES:
                    self._set_state("auth_error", err.message)
                    self._reload.wait()
                    continue
                self._set_state("offline", err.message)
            except Exception as err:
                log.exception("Chat: fallo inesperado")
                self._ready.clear()
                self._set_state("offline", str(err) or type(err).__name__)
            if self._stop.is_set():
                break
            if not self._reload.is_set() and self._reload.wait(backoff):
                continue
            backoff = min(backoff * 2, MAX_BACKOFF)

    def _connect_and_listen(self):
        client = self.client
        client.sign_in()
        self._conversation = str(client.rpc("ensure_default_conversation"))
        self.store.set_conversation(self._conversation)
        self._catch_up(first=True)
        self._ready.set()
        self._wake_send.set()
        realtime = self._realtime_factory(self.env, client.ensure_token)
        realtime.run(self._session_stop, self._on_change, self._on_realtime_state, on_joined=self._on_joined,
                     tick=self._tick)

    def _on_realtime_state(self, state, detail):
        self._set_state(state, detail)
        if state == "online":
            self._wake_send.set()

    def _on_joined(self):
        self._catch_up_wanted.set()  # lo que llegó mientras no se estaba unido

    def _on_change(self, data):
        table, kind = data.get("table"), data.get("type")
        if table == "messages":
            record = data.get("record") or {}
            old = data.get("old_record") or {}
            if kind == "DELETE" or (kind == "UPDATE" and record.get("deleted_at")):
                message_id = record.get("id") or old.get("id")
                if message_id and (self.store.get(message_id) or {}).get("deleted") is False:
                    self.store.mark_deleted(message_id)
                    self._emit({"kind": "deleted", "id": message_id})
                return
        self._catch_up_wanted.set()

    def _tick(self):
        if self._catch_up_wanted.is_set():
            self._catch_up_wanted.clear()
            self._catch_up()

    def _catch_up(self, first=False):
        """Pide al servidor lo que aún no se tiene (todo lo posterior a la última llegada) y lo avisa a la interfaz."""
        for _ in range(20):  # por si se acumularon más de una página
            after = self.store.meta("last_created_at") or None
            page = 200 if after else self._page()  # la primera vez, solo lo último; después, todo lo que falte
            remote = self.client.rpc("list_messages", {"p_conversation_id": self._conversation, "p_after": after,
                                                       "p_limit": page}) or []
            waiting = {m["id"] for m in self.store.outbox()}  # en espera aquí, pero el servidor ya lo tiene
            fresh = [m for m in remote if self.store.upsert_remote(m)]
            for message in remote:
                if message["id"] in waiting:  # se envió aunque la respuesta se perdió: ahora sí consta como enviado
                    self._emit({"kind": "status", "id": message["id"], "status": "sent",
                                "message": self.store.get(message["id"])})
            if not first:
                for message in fresh:
                    saved = self.store.get(message["id"])
                    self._emit({"kind": "message", "message": saved,
                                "incoming": saved["device"] != self.env.device})
            if len(remote) < page:
                break
        if first:
            self._emit({"kind": "history", "messages": self.store.history(self._page())})

    # ---------- envío ----------

    def _send_loop(self):
        backoff = 2
        while not self._stop.is_set():
            self._wake_send.wait()
            self._wake_send.clear()
            while not self._stop.is_set() and self._ready.is_set():
                pending = self.store.outbox()
                if not pending:
                    break
                result = self._send_one(pending[0])
                if result is None:  # sin conexión o sin sesión: se reintenta más tarde
                    if self._wake_send.wait(backoff):
                        self._wake_send.clear()
                    backoff = min(backoff * 2, MAX_BACKOFF)
                    continue
                backoff = 2

    def _send_one(self, message):
        """Sube los archivos y envía el mensaje. True: enviado. False: no se puede enviar nunca (queda con su error).
        None: reintentar luego."""
        client = self.client
        conversation = message["conversation_id"] or self._conversation
        if not conversation or client is None:
            return None
        try:
            payload = []
            if message["attachments"]:
                client.ensure_token()
            for att in message["attachments"]:
                payload.append(self._upload(client, conversation, message["id"], att))
            remote = client.rpc("send_message", {
                "p_id": message["id"], "p_conversation_id": conversation, "p_body": message["body"],
                "p_sent_at": message["sent_at"], "p_device": message["device"] or self.env.device,
                "p_attachments": payload})
        except ChatError as err:
            if err.code in AUTH_CODES:
                self._set_state("auth_error", err.message)
                return None
            if err.retryable:
                self.store.fail(message["id"], err.message, retryable=True)
                self._set_state("offline", err.message)
                return None
            self.store.fail(message["id"], err.message, retryable=False)
            self._emit({"kind": "status", "id": message["id"], "status": "pending", "error": err.message,
                        "message": self.store.get(message["id"])})
            return False
        self.store.upsert_remote(remote, advance=False)
        if self.state == "offline":  # si ha salido, hay conexión
            self._set_state("online")
        self._emit({"kind": "status", "id": message["id"], "status": "sent", "message": self.store.get(message["id"])})
        return True

    def _upload(self, client, conversation, message_id, att):
        """Sube un adjunto a Storage (si no estaba ya) y devuelve su descripción para `send_message`."""
        path = att.get("storage_path") or f"{client.user_id}/{conversation}/{message_id}/{safe_name(att['file_name'])}"
        source = att.get("local_path")
        if not source or not Path(source).is_file():
            raise ChatError("missing_file", f"No encuentro el archivo «{att['file_name']}»")
        data = Path(source).read_bytes()
        if len(data) > self._max_bytes():
            raise ChatError("too_big", f"«{att['file_name']}» pesa demasiado (máximo {self._max_bytes() // 1_000_000} MB)")
        self.store.set_attachment(att["id"], storage_path=path)
        client.upload(path, data, att["mime_type"])
        return {"storage_path": path, "file_name": att["file_name"], "mime_type": att["mime_type"],
                "size_bytes": len(data), "width": att.get("width"), "height": att.get("height"),
                "duration_ms": att.get("duration_ms"), "thumb_path": att.get("thumb_path")}

    # ---------- acciones ----------

    def history(self, limit=None):
        """Lo guardado en este equipo (rápido, sin red) y cómo está la conexión: {messages, state, detail, device, missing}."""
        return {"messages": self.store.history(int(limit or self._page())), "state": self.state, "detail": self.detail,
                "device": self.env.device, "missing": self.env.missing()}

    def send(self, text="", paths=()):
        """Escribe un mensaje: se guarda al instante en espera y sale en cuanto hay conexión. `paths`: archivos del disco."""
        text = (text or "").strip()
        paths = [str(p) for p in (paths or [])]
        if not text and not paths:
            raise ActionError("empty", "Escribe algo o adjunta un archivo")
        attachments = []
        for raw in paths:
            path = Path(raw)
            if not path.is_file():
                raise ActionError("missing_file", f"No encuentro el archivo «{path.name}»")
            size = path.stat().st_size
            if size > self._max_bytes():
                raise ActionError("too_big", f"«{path.name}» pesa {size / 1e6:.0f} MB; el máximo es "
                                              f"{self._max_bytes() // 1_000_000} MB")
            mime = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
            attachments.append({"id": str(uuid.uuid4()), "file_name": path.name, "mime_type": mime, "size_bytes": size,
                                "local_path": str(path.resolve())})
        saved = self.store.add_pending(
            {"id": str(uuid.uuid4()), "conversation_id": self._conversation, "device": self.env.device, "body": text,
             "sent_at": now_iso()}, attachments)
        self._emit({"kind": "message", "message": saved, "incoming": False})
        self._wake_send.set()
        return saved

    def retry(self, id):
        """Vuelve a intentar un mensaje que se quedó con error."""
        self.store.retry(id)
        self._emit({"kind": "status", "id": id, "status": "pending", "message": self.store.get(id)})
        self._wake_send.set()

    def delete(self, id):
        message = self.store.get(id)
        if message is None:
            return
        if message["status"] == "pending":
            self.store.forget(id)  # no llegó a salir
        else:
            self.store.mark_deleted(id)
            self._spawn(self._delete_remote, id)
        self._emit({"kind": "deleted", "id": id})

    def _delete_remote(self, message_id):
        try:
            self.client.rpc("delete_message", {"p_id": message_id})
        except (ChatError, AttributeError) as err:
            self._fail_event(getattr(err, "message", "No se pudo borrar en Supabase"))

    def older(self, before):
        """Mensajes anteriores a la hora `before` (para el scroll hacia arriba): primero lo guardado y, si hay conexión, lo
        que falte del servidor."""
        self._spawn(self._older, str(before))

    def _older(self, before):
        try:
            if self._ready.is_set():
                remote = self.client.rpc("list_messages", {"p_conversation_id": self._conversation, "p_before": before,
                                                           "p_limit": self._page()}) or []
                for message in remote:
                    self.store.upsert_remote(message, advance=False)
        except ChatError as err:
            self._fail_event(err.message)
        self._emit({"kind": "older", "messages": self.store.history(self._page(), before=before)})

    def fetch_attachment(self, message_id, attachment_id, open=False):
        """Deja un adjunto en el disco (lo baja si hace falta) y avisa de dónde está; con `open`, lo abre además."""
        self._spawn(self._fetch, message_id, attachment_id, bool(open))

    def save_attachment(self, message_id, attachment_id):
        """El botón «Descargar»: deja una copia del adjunto en Descargas (lo baja antes si hace falta) y avisa con `saved`."""
        self._spawn(self._save, message_id, attachment_id)

    def _save(self, message_id, attachment_id):
        if not self._fetch(message_id, attachment_id, False):
            return
        att = self.store.attachment(attachment_id)
        try:
            folder = Path(self._downloads())
            folder.mkdir(parents=True, exist_ok=True)
            target = unique_path(folder, att["file_name"] or Path(att["local_path"]).name)
            target.write_bytes(Path(att["local_path"]).read_bytes())
        except OSError:
            self._fail_event("No se pudo guardar en Descargas")
            return
        self._emit({"kind": "saved", "message_id": message_id, "attachment_id": attachment_id, "path": str(target),
                    "name": target.name})

    def _fetch(self, message_id, attachment_id, open_it):
        """Deja el adjunto en el disco y avisa. True si quedó (con su ruta en el almacén), False si no se pudo."""
        att = self.store.attachment(attachment_id)
        if att is None:
            return False
        path = att.get("local_path")
        try:
            if not path or not Path(path).is_file():
                if not att.get("storage_path") or self.client is None:
                    raise ChatError("offline", "El archivo aún no está disponible", retryable=True)
                data = self.client.download(att["storage_path"])
                target = self._cache_dir() / f"{attachment_id[:8]}_{safe_name(att['file_name'])}"
                target.write_bytes(data)
                path = str(target)
                self.store.set_attachment(attachment_id, local_path=path)
        except ChatError as err:
            self._fail_event(err.message)
            return False
        except OSError:
            self._fail_event("No se pudo guardar el archivo")
            return False
        self._emit({"kind": "attachment", "message_id": message_id, "attachment_id": attachment_id, "path": path,
                    "open": open_it})
        if open_it:
            try:
                self._opener(path)
            except OSError:
                self._fail_event("No se pudo abrir el archivo")
        return True

    def _spawn(self, target, *args):
        threading.Thread(target=target, args=args, daemon=True, name="kyora-chat").start()
