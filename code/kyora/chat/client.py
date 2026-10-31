"""El cliente HTTP de Supabase para el chat: sesión, funciones RPC y archivos (Storage). Solo `urllib`, como el clima.

Los endpoints están en `supabase/endpoints.md`. Todo error sale como `ChatError`; `retryable` dice si merece la pena
reintentar (sin red o error del servidor) o no (credenciales mal, archivo rechazado...).
"""
import json
import logging
import threading
import time
import urllib.error
import urllib.parse
import urllib.request

log = logging.getLogger("kyora.chat")
BUCKET = "chat-files"
TIMEOUT = 20  # segundos de espera por petición (las subidas grandes tienen más)
UPLOAD_TIMEOUT = 300
RENEW_BEFORE = 90  # el token se renueva cuando faltan menos segundos que estos


class ChatError(Exception):
    def __init__(self, code, message, retryable=False):
        super().__init__(message)
        self.code, self.message, self.retryable = code, message, retryable


def _urlopen(request, timeout):
    return urllib.request.urlopen(request, timeout=timeout)


def encode_path(path):
    """Una ruta de Storage lista para ir en la URL (las barras se conservan)."""
    return urllib.parse.quote(path, safe="/")


class SupabaseClient:
    def __init__(self, env, opener=_urlopen, clock=time.time):
        """`env`: un `ChatEnv`. `opener(request, timeout)`: lo que abre la red (los tests ponen uno falso)."""
        self.env = env
        self._open = opener
        self._clock = clock
        self._lock = threading.RLock()
        self.access_token = ""
        self._refresh_token = ""
        self._expires_at = 0.0
        self.user_id = ""

    # ---------- petición base ----------

    def _request(self, method, path, body=None, headers=None, timeout=TIMEOUT, token=True, raw=False):
        """Hace la petición y devuelve el JSON (o los bytes si `raw`). `body`: dict (se manda como JSON) o bytes."""
        head = {"apikey": self.env.anon_key}
        if token:
            head["Authorization"] = f"Bearer {self.access_token}"
        data = None
        if isinstance(body, (bytes, bytearray)):
            data = bytes(body)
        elif body is not None:
            data = json.dumps(body).encode("utf-8")
            head["Content-Type"] = "application/json"
        head.update(headers or {})
        request = urllib.request.Request(self.env.url + path, data=data, headers=head, method=method)
        try:
            with self._open(request, timeout) as response:
                payload = response.read()
        except urllib.error.HTTPError as err:
            raise self._http_error(err) from err
        except (urllib.error.URLError, TimeoutError, ConnectionError, OSError) as err:
            raise ChatError("offline", "Sin conexión con Supabase", retryable=True) from err
        if raw:
            return payload
        if not payload:
            return None
        try:
            return json.loads(payload.decode("utf-8"))
        except ValueError as err:
            raise ChatError("bad_response", "Supabase respondió algo que no se entiende", retryable=True) from err

    @staticmethod
    def _http_error(err):
        try:
            info = json.loads(err.read().decode("utf-8", errors="replace"))
        except (ValueError, OSError):
            info = {}
        message = (info.get("message") or info.get("msg") or info.get("error_description") or info.get("error")
                   or f"Error {err.code} de Supabase")
        code = str(info.get("code") or info.get("error_code") or err.code)
        return ChatError(code, str(message), retryable=err.code >= 500 or err.code in (408, 429))

    # ---------- sesión ----------

    def _store_session(self, data):
        self.access_token = data["access_token"]
        self._refresh_token = data.get("refresh_token", "")
        self._expires_at = self._clock() + float(data.get("expires_in", 3600))
        self.user_id = (data.get("user") or {}).get("id") or self.user_id

    def sign_in(self):
        """Entra con el correo y la contraseña del .env."""
        with self._lock:
            data = self._request("POST", "/auth/v1/token?grant_type=password",
                                 {"email": self.env.email, "password": self.env.password}, token=False)
            self._store_session(data)

    def ensure_token(self):
        """Un token que no caduca ya: renueva (o vuelve a entrar) si hace falta."""
        with self._lock:
            if self.access_token and self._clock() < self._expires_at - RENEW_BEFORE:
                return self.access_token
            if self._refresh_token:
                try:
                    data = self._request("POST", "/auth/v1/token?grant_type=refresh_token",
                                         {"refresh_token": self._refresh_token}, token=False)
                    self._store_session(data)
                    return self.access_token
                except ChatError as err:
                    if err.retryable:
                        raise
            self.sign_in()
            return self.access_token

    # ---------- funciones (RPC) ----------

    def rpc(self, name, payload=None):
        self.ensure_token()
        return self._request("POST", f"/rest/v1/rpc/{name}", payload or {})

    # ---------- archivos ----------

    def upload(self, storage_path, data, mime):
        """Sube los bytes a `chat-files/<storage_path>` (sobrescribe, para poder reintentar)."""
        self.ensure_token()
        self._request("POST", f"/storage/v1/object/{BUCKET}/{encode_path(storage_path)}", data,
                      {"Content-Type": mime or "application/octet-stream", "x-upsert": "true"},
                      timeout=UPLOAD_TIMEOUT, raw=True)

    def download(self, storage_path):
        """Los bytes de `chat-files/<storage_path>`."""
        self.ensure_token()
        return self._request("GET", f"/storage/v1/object/authenticated/{BUCKET}/{encode_path(storage_path)}",
                             timeout=UPLOAD_TIMEOUT, raw=True)
