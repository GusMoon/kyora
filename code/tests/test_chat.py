"""El chat: .env, almacén local, cliente HTTP, Realtime y el servicio (con un Supabase falso, como test_music con yt-dlp)."""
import io
import json
import queue
import threading
import time
import urllib.error
from pathlib import Path
from typing import ClassVar

import pytest

from kyora.chat import env as chat_env
from kyora.chat import realtime
from kyora.chat.client import ChatError, SupabaseClient
from kyora.chat.service import ChatService, safe_name
from kyora.chat.store import ChatStore, kind_of
from kyora.core.actions import ActionError

ENV = chat_env.ChatEnv(url="https://abc.supabase.co", anon_key="anon", email="yo@correo.com", password="secreta", device="pc")


def wait_until(check, timeout=3.0):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        value = check()
        if value:
            return value
        time.sleep(0.01)
    raise AssertionError("no llegó a tiempo")


def wait_for(events, kind, timeout=3.0, **match):
    def find():
        return next((e for e in list(events) if e["kind"] == kind and all(e.get(k) == v for k, v in match.items())), None)

    return wait_until(find, timeout)


# ---------- .env ----------

def test_parse_reads_variables_comments_quotes_and_export():
    text = '# comentario\n\nSUPABASE_URL=https://a.supabase.co/\nCHAT_EMAIL = "yo@x.com"\nexport CHAT_DEVICE=\'pc\'\nVACIA=\nCHAT_PASSWORD=abc # nota\n'
    values = chat_env.parse(text)
    assert values == {"SUPABASE_URL": "https://a.supabase.co/", "CHAT_EMAIL": "yo@x.com", "CHAT_DEVICE": "pc",
                      "VACIA": "", "CHAT_PASSWORD": "abc"}


def test_empty_env_file_is_not_ready_and_names_what_is_missing(tmp_path):
    repo = tmp_path / ".env"
    repo.write_text("SUPABASE_URL=\nSUPABASE_ANON_KEY=\nCHAT_EMAIL=\nCHAT_PASSWORD=\nCHAT_DEVICE=pc\n", encoding="utf-8")
    env = chat_env.load(tmp_path / "datos", repo_path=repo)
    assert not env.ready and env.missing() == list(chat_env.REQUIRED) and env.device == "pc"
    assert not chat_env.load(tmp_path / "no-hay", repo_path=tmp_path / "tampoco").ready       # sin archivo


def test_appdata_env_wins_over_the_repo_one(tmp_path):
    data = tmp_path / "datos"
    data.mkdir()
    full = "SUPABASE_URL=https://a.supabase.co/\nSUPABASE_ANON_KEY=k\nCHAT_EMAIL=a@b.c\nCHAT_PASSWORD=p\nCHAT_DEVICE=laptop\n"
    (data / "chat.env").write_text(full, encoding="utf-8")
    repo = tmp_path / ".env"
    repo.write_text("SUPABASE_URL=https://otro.supabase.co\n", encoding="utf-8")
    env = chat_env.load(data, repo_path=repo)
    assert env.ready and env.url == "https://a.supabase.co" and env.device == "laptop"        # sin la barra final
    (data / "chat.env").write_text("# vacío\n", encoding="utf-8")                              # vacío: sirve el del repo
    assert chat_env.load(data, repo_path=repo).url == "https://otro.supabase.co"


# ---------- almacén ----------

def pending(store, mid, sent_at, body="x", **extra):
    return store.add_pending({"id": mid, "conversation_id": None, "device": "pc", "body": body, "sent_at": sent_at},
                             extra.get("attachments", ()))


def test_store_keeps_order_and_the_outbox():
    store = ChatStore(":memory:")
    pending(store, "b", "2026-10-30T10:00:02Z", "segundo")
    pending(store, "a", "2026-10-30T10:00:01Z", "primero")
    assert [m["body"] for m in store.history()] == ["primero", "segundo"]
    assert [m["id"] for m in store.outbox()] == ["a", "b"] and store.get("a")["status"] == "pending"
    store.fail("a", "no hay red", retryable=True)
    assert store.get("a")["attempts"] == 1 and store.get("a")["error"] is None and len(store.outbox()) == 2
    store.fail("a", "archivo roto", retryable=False)
    assert [m["id"] for m in store.outbox()] == ["b"]                     # con error sin remedio sale de la bandeja
    store.retry("a")
    assert [m["id"] for m in store.outbox()] == ["a", "b"]


def test_store_remote_messages_are_sent_keep_local_files_and_only_advance_when_asked():
    store = ChatStore(":memory:")
    att = {"id": "x1", "file_name": "foto.png", "mime_type": "image/png", "size_bytes": 3, "local_path": "C:/foto.png",
           "storage_path": "u/c/m/foto.png"}
    pending(store, "m", "2026-10-30T10:00:00Z", "", attachments=[att])
    assert store.get("m")["kind"] == "image"
    remote = {"id": "m", "conversation_id": "c", "sender_device": "pc", "kind": "image", "body": None,
              "sent_at": "2026-10-30T10:00:00Z", "created_at": "2026-10-30T10:00:01Z", "deleted_at": None,
              "attachments": [{"id": "serv-1", "storage_path": "u/c/m/foto.png", "file_name": "foto.png",
                               "mime_type": "image/png", "size_bytes": 3}]}
    assert store.upsert_remote(remote, advance=False) is False                  # ya existía
    saved = store.get("m")
    assert saved["status"] == "sent" and saved["attachments"][0]["id"] == "serv-1"
    assert saved["attachments"][0]["local_path"] == "C:/foto.png"             # no se vuelve a bajar
    assert store.meta("last_created_at") == ""                                 # lo propio no mueve el punto de partida
    assert store.upsert_remote({**remote, "id": "n", "created_at": "2026-10-30T10:00:05Z", "attachments": []}) is True
    assert store.meta("last_created_at") == "2026-10-30T10:00:05Z"


def test_store_conversation_fills_the_messages_written_offline_and_survives_restart(tmp_path):
    path = tmp_path / "chat.sqlite"
    store = ChatStore(path)
    pending(store, "a", "2026-10-30T10:00:00Z")
    store.set_conversation("conv-9")
    store.close()
    again = ChatStore(path)
    assert again.get("a")["conversation_id"] == "conv-9" and again.meta("conversation_id") == "conv-9"
    again.mark_deleted("a")
    assert again.history() == []


def test_kind_of_matches_the_sql_rule():
    assert [kind_of(m) for m in ("image/png", "audio/mpeg", "video/mp4", "application/pdf", "", None)] == \
        ["image", "audio", "video", "file", "other", "other"]


def test_safe_name_keeps_extension_and_drops_odd_characters():
    assert safe_name("Mi foto (1).jpg") == "Mi_foto_1_.jpg" and safe_name("???") == "archivo"


# ---------- cliente HTTP ----------

class Reply:
    def __init__(self, data):
        self._data = data if isinstance(data, bytes) else json.dumps(data).encode("utf-8")

    def read(self):
        return self._data

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False


class FakeNet:
    def __init__(self, *answers):
        self.answers = list(answers)
        self.requests = []

    def __call__(self, request, timeout):
        self.requests.append(request)
        answer = self.answers.pop(0)
        if isinstance(answer, Exception):
            raise answer
        return Reply(answer)


def http_error(code, body):
    return urllib.error.HTTPError("https://x", code, "x", {}, io.BytesIO(json.dumps(body).encode("utf-8")))


SESSION = {"access_token": "tok1", "refresh_token": "ref1", "expires_in": 3600, "user": {"id": "user-1"}}


def test_client_signs_in_and_calls_functions_with_the_token():
    net = FakeNet(SESSION, {"ok": True})
    client = SupabaseClient(ENV, opener=net)
    assert client.rpc("send_message", {"p_id": "1"}) == {"ok": True} and client.user_id == "user-1"
    login, call = net.requests
    assert login.full_url.endswith("/auth/v1/token?grant_type=password") and json.loads(login.data)["email"] == "yo@correo.com"
    assert call.full_url == "https://abc.supabase.co/rest/v1/rpc/send_message" and json.loads(call.data) == {"p_id": "1"}
    assert call.get_header("Authorization") == "Bearer tok1" and call.get_header("Apikey") == "anon"


def test_client_renews_the_token_before_it_expires():
    now = [1000.0]
    net = FakeNet(SESSION, {"a": 1}, {**SESSION, "access_token": "tok2"}, {"a": 2})
    client = SupabaseClient(ENV, opener=net, clock=lambda: now[0])
    client.rpc("x")
    now[0] += 3600 - 30                                             # faltan 30 s: toca renovar
    client.rpc("x")
    assert "grant_type=refresh_token" in net.requests[2].full_url and net.requests[3].get_header("Authorization") == "Bearer tok2"


def test_client_maps_errors_to_retryable_or_not():
    client = SupabaseClient(ENV, opener=FakeNet(http_error(400, {"code": "invalid_credentials", "message": "Contraseña mala"})))
    with pytest.raises(ChatError) as bad:
        client.sign_in()
    assert bad.value.code == "invalid_credentials" and bad.value.message == "Contraseña mala" and not bad.value.retryable
    client = SupabaseClient(ENV, opener=FakeNet(http_error(503, {"message": "caído"})))
    with pytest.raises(ChatError) as down:
        client.sign_in()
    assert down.value.retryable
    client = SupabaseClient(ENV, opener=FakeNet(urllib.error.URLError("sin red")))
    with pytest.raises(ChatError) as offline:
        client.sign_in()
    assert offline.value.code == "offline" and offline.value.retryable


def test_client_uploads_and_downloads_files_by_path():
    net = FakeNet(SESSION, b"", b"BYTES")
    client = SupabaseClient(ENV, opener=net)
    client.upload("user-1/c/m/Mi foto.png", b"PNG", "image/png")
    assert client.download("user-1/c/m/Mi foto.png") == b"BYTES"
    up, down = net.requests[1], net.requests[2]
    assert up.full_url.endswith("/storage/v1/object/chat-files/user-1/c/m/Mi%20foto.png") and up.data == b"PNG"
    assert up.get_header("Content-type") == "image/png" and up.get_header("X-upsert") == "true"
    assert "/object/authenticated/chat-files/" in down.full_url


# ---------- Realtime ----------

class FakeWS:
    def __init__(self):
        self.incoming = queue.Queue()
        self.sent = []

    def send(self, text):
        self.sent.append(json.loads(text))

    def recv(self, timeout=None):
        try:
            return self.incoming.get(timeout=min(timeout or 0.01, 0.01))
        except queue.Empty:
            raise TimeoutError from None

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False


def test_realtime_url_joins_the_channel_forwards_changes_and_sends_heartbeats():
    ws, stop = FakeWS(), threading.Event()
    now = [0.0]
    seen = {"state": [], "change": [], "joined": 0}
    client = realtime.RealtimeClient(ENV, lambda: "tok", connect=lambda url, **kw: ws, clock=lambda: now[0])
    assert client.url() == "wss://abc.supabase.co/realtime/v1/websocket?apikey=anon&vsn=1.0.0"

    def tick():
        if seen["state"] and seen["change"] and now[0] < 30:
            now[0] += 26                                              # pasa el tiempo del latido
        elif now[0] >= 30:
            stop.set()

    ws.incoming.put(json.dumps({"topic": realtime.TOPIC, "event": "phx_reply", "ref": "1", "payload": {"status": "ok"}}))
    ws.incoming.put(json.dumps({"topic": realtime.TOPIC, "event": "postgres_changes",
                                "payload": {"data": {"type": "INSERT", "table": "messages", "record": {"id": "1"}}}}))
    client.run(stop, seen["change"].append, lambda s, d: seen["state"].append(s),
               on_joined=lambda: seen.__setitem__("joined", seen["joined"] + 1), tick=tick)
    join = ws.sent[0]
    assert join["event"] == "phx_join" and join["payload"]["access_token"] == "tok"
    assert [c["table"] for c in join["payload"]["config"]["postgres_changes"]] == ["messages", "attachments"]
    assert seen["state"][0] == "online" and seen["joined"] == 1 and seen["change"][0]["record"] == {"id": "1"}
    assert any(m["event"] == "heartbeat" and m["topic"] == "phoenix" for m in ws.sent)


def test_realtime_reconnects_after_a_failure_and_reports_offline(monkeypatch):
    monkeypatch.setattr(realtime, "FIRST_BACKOFF", 0.01)
    ws, stop, states = FakeWS(), threading.Event(), []
    attempts = []

    def connect(url, **kw):
        attempts.append(1)
        if len(attempts) == 1:
            raise OSError("sin red")
        return ws

    ws.incoming.put(json.dumps({"topic": realtime.TOPIC, "event": "phx_reply", "ref": "1", "payload": {"status": "ok"}}))
    client = realtime.RealtimeClient(ENV, lambda: "tok", connect=connect)
    client.run(stop, lambda d: None, lambda s, d: (states.append(s), stop.set() if s == "online" else None))
    assert states == ["offline", "online"] and len(attempts) == 2


def test_realtime_join_refused_is_an_error():
    ws = FakeWS()
    ws.incoming.put(json.dumps({"topic": realtime.TOPIC, "event": "phx_reply", "ref": "1",
                                "payload": {"status": "error", "response": {"reason": "token caducado"}}}))
    client = realtime.RealtimeClient(ENV, lambda: "tok", connect=lambda url, **kw: ws)
    with pytest.raises(ConnectionError, match="token caducado"):
        list(client._session(ws, threading.Event(), lambda d: None, lambda: None))


# ---------- servicio ----------

class FakeSupabase:
    """El servidor: guarda mensajes, repite sin duplicar y se puede dejar sin red."""

    def __init__(self, env):
        self.env = env
        self.user_id = "user-1"
        self.offline = False
        self.lose_reply_once = False
        self.remote = {}
        self.uploads = {}
        self.calls = []
        self.sign_in_error = None
        self._n = 0

    def sign_in(self):
        if self.sign_in_error:
            raise self.sign_in_error

    def ensure_token(self):
        return "tok"

    def upload(self, path, data, mime):
        if self.offline:
            raise ChatError("offline", "Sin conexión con Supabase", retryable=True)
        self.uploads[path] = (data, mime)

    def download(self, path):
        return self.uploads[path][0]

    def _stamp(self):
        self._n += 1
        return f"2026-10-30T10:00:{self._n:02d}Z"

    def add_remote(self, mid, body, device="phone", kind="text", attachments=()):
        message = {"id": mid, "conversation_id": "conv-1", "owner_id": "user-1", "sender_device": device, "kind": kind,
                   "body": body, "status": "sent", "sent_at": self._stamp(), "created_at": self._stamp(),
                   "deleted_at": None, "attachments": list(attachments)}
        self.remote[mid] = message
        return message

    def rpc(self, name, payload=None):
        payload = payload or {}
        self.calls.append((name, payload))
        if name == "ensure_default_conversation":
            return "conv-1"
        if self.offline:
            raise ChatError("offline", "Sin conexión con Supabase", retryable=True)
        if name == "send_message":
            if payload["p_id"] not in self.remote:
                atts = [{"id": f"att-{i}", **a} for i, a in enumerate(payload["p_attachments"])]
                mime = atts[0]["mime_type"] if atts else ""
                kind = "text" if not atts else ("image" if mime.startswith("image/") else "file")
                message = self.add_remote(payload["p_id"], payload["p_body"], payload["p_device"], kind, atts)
                message["sent_at"] = payload["p_sent_at"]
            if self.lose_reply_once:
                self.lose_reply_once = False
                raise ChatError("offline", "Se cortó la respuesta", retryable=True)
            return self.remote[payload["p_id"]]
        if name == "list_messages":
            rows = sorted(self.remote.values(), key=lambda m: m["created_at"])
            if payload.get("p_after"):
                rows = [m for m in rows if m["created_at"] > payload["p_after"]]
            if payload.get("p_before"):
                rows = [m for m in rows if m["sent_at"] < payload["p_before"]]
            return [m for m in rows if not m["deleted_at"]][-payload.get("p_limit", 50):]
        if name == "delete_message":
            self.remote[payload["p_id"]]["deleted_at"] = "2026-10-30T11:00:00Z"
            return self.remote[payload["p_id"]]
        raise AssertionError(name)


class FakeRealtime:
    """Realtime: avisa de que se unió y entrega los cambios que el test le va metiendo."""

    instances: ClassVar[list] = []  # las que se crean en cada prueba (el fixture las vacía)

    def __init__(self, env, token_provider):
        self.changes = queue.Queue()
        FakeRealtime.instances.append(self)

    def run(self, stop, on_change, on_state, on_joined=lambda: None, tick=lambda: None):
        on_state("online", "")
        on_joined()
        while not stop.is_set():
            try:
                on_change(self.changes.get(timeout=0.01))
            except queue.Empty:
                pass
            tick()


def settled(servers):
    """Espera a que la conexión inicial y su puesta al día (la de unirse a Realtime) hayan terminado."""
    wait_until(lambda: servers and sum(1 for n, _ in servers[0].calls if n == "list_messages") >= 2)


@pytest.fixture
def chat(tmp_path):
    FakeRealtime.instances.clear()
    events, servers = [], []

    def make(env=ENV, server_setup=None, **kwargs):
        def factory(e):
            server = FakeSupabase(e)
            if server_setup:
                server_setup(server)
            servers.append(server)
            return server

        opened = []
        service = ChatService(tmp_path, events.append, config=kwargs.pop("config", dict), env_loader=lambda: env,
                              client_factory=factory, realtime_factory=FakeRealtime, opener=opened.append,
                              store=ChatStore(":memory:"))
        service.opened = opened
        made.append(service)
        return service, events, servers

    made = []
    yield make
    for service in made:
        service.stop()


def test_a_message_is_saved_pending_at_once_and_becomes_sent(chat):
    service, events, servers = chat()
    service.start()
    wait_for(events, "connection", state="online")
    saved = service.send("hola")
    assert saved["status"] == "pending" and saved["body"] == "hola" and saved["device"] == "pc"
    assert saved["sent_at"].endswith("Z")
    sent = wait_for(events, "status", id=saved["id"], status="sent")
    assert sent["message"]["status"] == "sent"
    assert servers[0].remote[saved["id"]]["body"] == "hola" and service.store.get(saved["id"])["status"] == "sent"
    assert service.store.outbox() == []


def test_without_connection_it_stays_pending_and_goes_out_when_it_returns(chat):
    service, events, servers = chat()
    service.start()
    wait_for(events, "connection", state="online")
    settled(servers)
    servers[0].offline = True                                            # se cae la red después de conectar
    saved = service.send("sin red")
    wait_until(lambda: service.store.get(saved["id"])["attempts"] >= 1)
    assert service.store.get(saved["id"])["status"] == "pending" and saved["id"] not in servers[0].remote
    servers[0].offline = False
    service._wake_send.set()                                            # vuelve la red
    wait_for(events, "status", id=saved["id"], status="sent")
    assert servers[0].remote[saved["id"]]["body"] == "sin red"


def test_a_retry_after_a_lost_reply_does_not_duplicate_the_message(chat):
    service, events, servers = chat()
    service.start()
    wait_for(events, "connection", state="online")
    settled(servers)
    servers[0].lose_reply_once = True                                    # el servidor lo guardó pero la respuesta se perdió
    saved = service.send("una sola vez")
    wait_until(lambda: service.store.get(saved["id"])["attempts"] >= 1)
    service._wake_send.set()
    wait_for(events, "status", id=saved["id"], status="sent")
    assert len(servers[0].remote) == 1                                   # llegó una sola vez (aunque se intentara dos)
    assert service.store.get(saved["id"])["status"] == "sent" and service.store.outbox() == []


def test_files_are_uploaded_first_and_sent_with_their_data(chat, tmp_path):
    service, events, servers = chat()
    service.start()
    wait_for(events, "connection", state="online")
    photo = tmp_path / "Mi foto.png"
    photo.write_bytes(b"\x89PNG-datos")
    saved = service.send("mira", [photo])
    assert saved["kind"] == "image" and saved["attachments"][0]["mime_type"] == "image/png"
    wait_for(events, "status", id=saved["id"], status="sent")
    path = f"user-1/conv-1/{saved['id']}/Mi_foto.png"
    assert servers[0].uploads[path] == (b"\x89PNG-datos", "image/png")
    payload = next(p for n, p in servers[0].calls if n == "send_message")
    assert payload["p_attachments"][0]["storage_path"] == path and payload["p_attachments"][0]["file_name"] == "Mi foto.png"
    final = service.store.get(saved["id"])
    assert final["status"] == "sent" and final["attachments"][0]["local_path"] == str(photo.resolve())


def test_send_validates_its_input(chat, tmp_path):
    service, _, _ = chat()
    with pytest.raises(ActionError) as empty:
        service.send("   ")
    assert empty.value.code == "empty"
    with pytest.raises(ActionError) as missing:
        service.send("", [tmp_path / "no-existe.txt"])
    assert missing.value.code == "missing_file"
    big = tmp_path / "grande.bin"
    big.write_bytes(b"x" * 50)
    service._max_bytes = lambda: 10
    with pytest.raises(ActionError) as too_big:
        service.send("", [big])
    assert too_big.value.code == "too_big" and service.store.history() == []


def test_a_file_that_disappears_gets_an_error_and_can_be_retried(chat, tmp_path):
    service, events, _ = chat()
    doc = tmp_path / "doc.txt"
    doc.write_text("hola")
    saved = service.send("", [doc])                                      # se guarda en espera (aún sin hilos)
    doc.unlink()                                                         # y el archivo desaparece antes de que salga
    service.start()
    failed = wait_for(events, "status", id=saved["id"], status="pending")
    assert "doc.txt" in failed["error"] and service.store.outbox() == []
    doc.write_text("hola otra vez")
    service.retry(saved["id"])
    wait_for(events, "status", id=saved["id"], status="sent")


def test_messages_from_another_device_arrive_in_real_time(chat):
    service, events, servers = chat()
    service.start()
    wait_for(events, "history")
    settled(servers)
    wait_until(lambda: FakeRealtime.instances)
    message = servers[0].add_remote("remoto-1", "hola desde el móvil")
    FakeRealtime.instances[-1].changes.put({"type": "INSERT", "table": "messages", "record": {"id": "remoto-1"}})
    arrived = wait_for(events, "message", timeout=3)
    assert arrived["incoming"] is True and arrived["message"]["body"] == "hola desde el móvil"
    assert arrived["message"]["status"] == "sent" and arrived["message"]["device"] == "phone"
    assert service.store.meta("last_created_at") == message["created_at"]
    assert service.history()["messages"][-1]["id"] == "remoto-1"


def test_a_message_deleted_elsewhere_disappears(chat):
    service, events, servers = chat()
    service.start()
    wait_for(events, "connection", state="online")
    settled(servers)                                                     # la puesta al día inicial ya terminó
    saved = service.send("para borrar")
    wait_for(events, "status", id=saved["id"], status="sent")
    wait_until(lambda: FakeRealtime.instances)
    servers[0].remote[saved["id"]]["deleted_at"] = "2026-10-30T11:00:00Z"   # en el servidor ya está borrado
    FakeRealtime.instances[-1].changes.put({"type": "UPDATE", "table": "messages",
                                           "record": {"id": saved["id"], "deleted_at": "2026-10-30T11:00:00Z"}})
    wait_for(events, "deleted", id=saved["id"])
    assert service.history()["messages"] == []


def test_start_catches_up_with_history_and_a_restart_only_asks_for_what_is_new(chat):
    service, events, servers = chat(server_setup=lambda s: (s.add_remote("a", "uno"), s.add_remote("b", "dos")))
    service.start()
    history = wait_for(events, "history")
    assert [m["body"] for m in history["messages"]] == ["uno", "dos"]
    first = next(p for n, p in servers[0].calls if n == "list_messages")
    assert first["p_after"] is None
    service.reload()                                                    # se vuelve a conectar (nuevo "servidor")
    wait_until(lambda: len(servers) == 2)
    wait_until(lambda: any(n == "list_messages" for n, _ in servers[1].calls))
    assert next(p for n, p in servers[1].calls if n == "list_messages")["p_after"] == service.store.meta("last_created_at") != ""


def test_without_credentials_it_says_what_is_missing_but_still_keeps_messages(chat):
    service, events, _ = chat(env=chat_env.ChatEnv())
    service.start()
    info = wait_for(events, "connection", state="unconfigured")
    assert info["missing"] == list(chat_env.REQUIRED) and "SUPABASE_URL" in info["detail"]
    saved = service.send("lo guardo para después")
    assert service.history()["state"] == "unconfigured" and service.history()["messages"][0]["id"] == saved["id"]
    assert saved["status"] == "pending"


def test_wrong_credentials_are_reported_not_retried_forever(chat):
    bad = ChatError("invalid_credentials", "Correo o contraseña incorrectos")
    service, events, servers = chat(server_setup=lambda s: setattr(s, "sign_in_error", bad))
    service.start()
    info = wait_for(events, "connection", state="auth_error")
    assert info["detail"] == "Correo o contraseña incorrectos"
    time.sleep(0.1)
    assert len(servers) == 1                                             # espera a que arregles el .env (chat.reload)


def test_delete_pending_forgets_it_and_delete_sent_asks_the_server(chat):
    service, events, _ = chat(env=chat_env.ChatEnv())
    local = service.send("nunca salió")
    service.delete(local["id"])
    assert service.store.get(local["id"]) is None
    wait_for(events, "deleted", id=local["id"])

    service2, events2, servers2 = chat(server_setup=lambda s: s.add_remote("viejo", "enviado"))
    service2.start()
    wait_for(events2, "history")
    service2.delete("viejo")
    wait_until(lambda: servers2[0].remote["viejo"]["deleted_at"])
    assert service2.history()["messages"] == []


def test_attachments_are_downloaded_once_and_opened(chat):
    att = {"id": "att-9", "storage_path": "user-1/conv-1/m/doc.pdf", "file_name": "doc.pdf", "mime_type": "application/pdf",
           "size_bytes": 4}
    service, events, servers = chat(server_setup=lambda s: (s.add_remote("m", None, kind="file", attachments=[att]),
                                                            s.uploads.__setitem__(att["storage_path"], (b"%PDF", "x"))))
    service.start()
    wait_for(events, "history")
    service.fetch_attachment("m", "att-9", open=True)
    got = wait_for(events, "attachment", attachment_id="att-9")
    assert got["open"] is True and Path(got["path"]).read_bytes() == b"%PDF"
    wait_until(lambda: service.opened == [got["path"]])
    assert service.store.attachment("att-9")["local_path"] == got["path"]
    downloads = len(servers[0].uploads)
    service.fetch_attachment("m", "att-9")                              # ya está en disco: no se baja otra vez
    wait_until(lambda: sum(1 for e in events if e["kind"] == "attachment") == 2)
    assert len(servers[0].uploads) == downloads


def test_older_messages_are_requested_with_the_cutoff_time(chat):
    service, events, _ = chat(server_setup=lambda s: [s.add_remote(f"m{n}", f"mensaje {n}") for n in range(4)])
    service.start()
    wait_for(events, "history")
    cutoff = service.store.history()[2]["sent_at"]
    service.older(cutoff)
    older = wait_for(events, "older")
    assert [m["body"] for m in older["messages"]] == ["mensaje 0", "mensaje 1"]
