"""El tiempo real de Supabase (Realtime): un WebSocket con el protocolo de canales Phoenix. Ver `supabase/endpoints.md` §5.

`run` se queda conectado hasta que `stop` se activa: se une a los cambios de `messages` y `attachments`, manda el latido
cada 25 s, pasa el token nuevo cuando se renueva y, si se corta, vuelve a conectar con una espera que va creciendo (1, 2,
4... hasta 30 s). Los avisos vuelven por callbacks, siempre desde el mismo hilo que llama a `run`.
"""
import json
import logging
import time
import urllib.parse

log = logging.getLogger("kyora.chat")
TOPIC = "realtime:kyora-chat"
HEARTBEAT_S = 25
SILENCE_S = 70  # si el servidor no dice nada en tanto tiempo, la conexión está muerta
POLL_S = 1.0  # cada cuánto se mira si hay que parar, mandar el latido o hacer algo (`tick`)
FIRST_BACKOFF = 1  # la primera espera antes de reconectar
MAX_BACKOFF = 30
TABLES = ("messages", "attachments")


def _default_connect(uri, **kwargs):
    from websockets.sync.client import connect

    return connect(uri, **kwargs)


class RealtimeClient:
    def __init__(self, env, token_provider, connect=_default_connect, clock=time.monotonic):
        """`token_provider()` devuelve el token de acceso vigente (renovado si hace falta)."""
        self.env = env
        self._token = token_provider
        self._connect = connect
        self._clock = clock
        self._n = 0

    def url(self):
        base = self.env.url.replace("https://", "wss://", 1).replace("http://", "ws://", 1)
        query = urllib.parse.urlencode({"apikey": self.env.anon_key, "vsn": "1.0.0"})
        return f"{base}/realtime/v1/websocket?{query}"

    def _ref(self):
        self._n += 1
        return str(self._n)

    @staticmethod
    def _send(ws, topic, event, payload, ref, join_ref=None):
        message = {"topic": topic, "event": event, "payload": payload, "ref": ref}
        if join_ref is not None:
            message["join_ref"] = join_ref
        ws.send(json.dumps(message))

    def run(self, stop, on_change, on_state, on_joined=lambda: None, tick=lambda: None):
        """Bloquea mientras `stop` no esté activado. `on_change(data)`: un cambio de la base (`type`, `table`, `record`...).
        `on_state(estado, detalle)`: "online" al unirse, "offline" si se corta. `on_joined()`: cada vez que se une (para
        ponerse al día con lo que se perdió). `tick()`: se llama cada segundo desde este mismo hilo."""
        backoff = FIRST_BACKOFF
        while not stop.is_set():
            joined = False
            try:
                with self._connect(self.url(), open_timeout=15, max_size=None) as ws:
                    for event in self._session(ws, stop, on_change, tick):
                        if event == "joined":
                            joined = True
                            backoff = FIRST_BACKOFF
                            on_state("online", "")
                            on_joined()
            except Exception as err:  # noqa: BLE001 - cualquier corte (red, servidor, token) acaba en reconectar
                if stop.is_set():
                    break
                log.info("Realtime: %s", err)
                on_state("offline", str(err) or type(err).__name__)
            if stop.wait(backoff if not joined else FIRST_BACKOFF):
                break
            backoff = min(backoff * 2, MAX_BACKOFF)

    def _session(self, ws, stop, on_change, tick):
        """Una conexión: se une al canal y atiende mensajes. Produce "joined" al unirse; termina con una excepción si se
        corta, o sin ella si `stop` se activa."""
        token = self._token()
        join_ref = ref = self._ref()
        changes = [{"event": "*", "schema": "public", "table": table} for table in TABLES]
        self._send(ws, TOPIC, "phx_join", {"config": {"broadcast": {"self": False}, "presence": {"key": ""},
                                                       "postgres_changes": changes}, "access_token": token}, ref, join_ref)
        sent_token, last_beat, last_rx, joined = token, self._clock(), self._clock(), False
        while not stop.is_set():
            try:
                raw = ws.recv(timeout=POLL_S)
            except TimeoutError:
                raw = None
            now = self._clock()
            if raw is not None:
                last_rx = now
                message = json.loads(raw)
                event, payload = message.get("event"), message.get("payload") or {}
                if event == "phx_reply" and message.get("topic") == TOPIC and message.get("ref") == join_ref:
                    if payload.get("status") != "ok":
                        reason = (payload.get("response") or {}).get("reason") or "no se pudo unir al canal"
                        raise ConnectionError(str(reason))
                    joined = True
                    yield "joined"
                elif event == "postgres_changes":
                    data = payload.get("data")
                    if data:
                        on_change(data)
                elif event in ("phx_close", "phx_error") and message.get("topic") == TOPIC:
                    raise ConnectionError("el canal se cerró")
            elif now - last_rx > SILENCE_S:
                raise TimeoutError("el servidor no responde")
            if now - last_beat >= HEARTBEAT_S:
                self._send(ws, "phoenix", "heartbeat", {}, self._ref())
                last_beat = now
            if joined:
                fresh = self._token()
                if fresh != sent_token:
                    self._send(ws, TOPIC, "access_token", {"access_token": fresh}, self._ref())
                    sent_token = fresh
                tick()
