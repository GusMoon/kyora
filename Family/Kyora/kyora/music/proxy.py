"""Un servidor local mínimo para escuchar sin bajar: QtMultimedia no puede mandar las cabeceras que YouTube exige en los
enlaces de audio (responde 403), así que le damos un enlace `http://127.0.0.1:<puerto>/s/<id>` y este servidor pide el
audio a YouTube como lo hace yt-dlp. Pasa el `Range` tal cual, para que la barra de tiempo pueda saltar.

Un enlace recién resuelto responde 403 durante 1 o 2 segundos y luego funciona: por eso se reintenta unos instantes
antes de rendirse. Solo escucha en 127.0.0.1."""
import logging
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

log = logging.getLogger("kyora.music")
CHUNK = 64 * 1024
TIMEOUT = 20
COPIED = ("Content-Type", "Content-Length", "Content-Range", "Accept-Ranges")
RETRIES = 14  # intentos ante un 403, espaciados RETRY_WAIT segundos (unos 7 s en total)
RETRY_WAIT = 0.5


def _open(url, headers):
    """Pide el audio a YouTube; un 403 de un enlace recién resuelto se reintenta unos segundos."""
    request = urllib.request.Request(url, headers=headers)
    for attempt in range(RETRIES):
        try:
            return urllib.request.urlopen(request, timeout=TIMEOUT)
        except urllib.error.HTTPError as exc:
            if exc.code != 403 or attempt == RETRIES - 1:
                raise
            time.sleep(RETRY_WAIT)
    raise AssertionError("inalcanzable")


class _Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_GET(self):
        self._serve(send_body=True)

    def do_HEAD(self):
        self._serve(send_body=False)

    def log_message(self, *args):
        """Sin ruido en la consola."""

    def _serve(self, send_body):
        entry = self.server.streams.get(self.path.rsplit("/", 1)[-1])
        if entry is None:
            self.send_error(404)
            return
        url, headers = entry
        wanted = {**headers, "Accept-Encoding": "identity", "Range": self.headers.get("Range") or "bytes=0-"}
        try:
            upstream = _open(url, wanted)
        except urllib.error.HTTPError as exc:
            log.warning("YouTube respondió %s al reproducir", exc.code)
            self.send_error(exc.code)
            return
        except OSError:
            self.send_error(502)
            return
        with upstream:
            self.send_response(upstream.status)
            for name in COPIED:
                if upstream.headers.get(name):
                    self.send_header(name, upstream.headers[name])
            self.end_headers()
            if not send_body:
                return
            try:
                while chunk := upstream.read(CHUNK):
                    self.wfile.write(chunk)
            except OSError:  # el reproductor cerró la conexión (saltó a otro punto o cambió de canción)
                return


class StreamProxy:
    def __init__(self):
        self._server = None
        self._lock = threading.Lock()
        self._streams = {}

    def add(self, key, url, headers):
        """Registra el audio de `key` y devuelve el enlace local para reproducirlo."""
        with self._lock:
            if self._server is None:
                self._server = ThreadingHTTPServer(("127.0.0.1", 0), _Handler)
                self._server.daemon_threads = True
                self._server.streams = self._streams
                threading.Thread(target=self._server.serve_forever, daemon=True, name="kyora-music-proxy").start()
        self._streams[str(key)] = (url, dict(headers or {}))
        return f"http://127.0.0.1:{self._server.server_address[1]}/s/{key}"

    def close(self):
        with self._lock:
            if self._server is not None:
                self._server.shutdown()
                self._server.server_close()
                self._server = None
