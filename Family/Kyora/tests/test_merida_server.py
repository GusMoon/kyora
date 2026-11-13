"""El servicio local de música de Merida: el mismo motor que Kyora, el destino «Esta PC (carpeta)» y un HTTP que solo
atiende a la web de Merida con su token (yt-dlp, cliente y chat falsos, sin red)."""
import json
import threading
import time
import urllib.error
import urllib.request

import pytest
from test_music import FakeYdl
from test_music_sync import FakeChat, FakeClient

from kyora.merida.server import (
    FOLDER,
    MeridaMusic,
    Settings,
    make_server,
    write_service_file,
)

TOKEN = "t0ken-de-prueba"
ORIGIN = "http://127.0.0.1:5180"


def wait_for(events, predicate, seconds=3):
    end = time.time() + seconds
    while time.time() < end:
        for event in list(events):
            if predicate(event):
                return event
        time.sleep(0.01)
    raise AssertionError(f"No llegó el evento esperado: {events[-5:]}")


def make_engine(tmp_path, client=None, chat_state="online"):
    script = {"dir": tmp_path / "dl"}
    script["dir"].mkdir()
    settings = Settings(tmp_path / "merida.json", default_folder=tmp_path / "Music")
    chat = FakeChat(client if client is not None else FakeClient(), state=chat_state)
    engine = MeridaMusic(tmp_path / "state", tmp_path / "dl", chat, settings, tmp_path / "cookies.txt",
                         runner=lambda opts: FakeYdl(opts, script), find_ffmpeg=lambda: "ffmpeg-dir")
    events = []
    q = engine.hub.subscribe()

    def collect():
        while True:
            events.append(q.get())

    threading.Thread(target=collect, daemon=True).start()
    return engine, events


def load_songs(engine, events):
    assert engine.registry.invoke("music.songs", {"playlist": "PL1"})["ok"]
    wait_for(events, lambda e: e["kind"] == "songs")


# ---------------------------------------------------------------- el motor

def test_guardar_en_la_carpeta_mueve_el_mp3_y_no_toca_supabase(tmp_path):
    client = FakeClient()
    engine, events = make_engine(tmp_path, client)
    load_songs(engine, events)
    result = engine.registry.invoke("music.download", {"playlist": "PL1", "ids": ["v0"], "recipient": FOLDER})
    assert result["ok"], result
    saved = wait_for(events, lambda e: e["kind"] == "saved")
    wait_for(events, lambda e: e["kind"] == "progress" and e["id"] == "v0" and e["state"] == "done")
    assert (tmp_path / "Music" / "v0.mp3").is_file()
    assert saved["path"].endswith("v0.mp3")
    assert not (tmp_path / "dl" / "v0.mp3").exists()  # se movió, no se copió
    assert client.uploads == [] and not any(name == "add_music_track" for name, _ in client.rpcs)


def test_la_carpeta_funciona_aunque_supabase_no_este_configurado(tmp_path):
    engine, events = make_engine(tmp_path, chat_state="unconfigured")
    load_songs(engine, events)
    assert engine.registry.invoke("music.download", {"playlist": "PL1", "ids": ["v1"], "recipient": FOLDER})["ok"]
    wait_for(events, lambda e: e["kind"] == "saved")
    # mandar a una persona sí necesita Supabase
    blocked = engine.registry.invoke("music.download", {"playlist": "PL1", "ids": ["v2"]})
    assert blocked["error"]["code"] == "no_sync"


def test_si_el_nombre_existe_no_pisa_el_archivo(tmp_path):
    engine, events = make_engine(tmp_path)
    (tmp_path / "Music").mkdir()
    (tmp_path / "Music" / "v0.mp3").write_bytes(b"otro")
    load_songs(engine, events)
    engine.registry.invoke("music.download", {"playlist": "PL1", "ids": ["v0"], "recipient": FOLDER})
    saved = wait_for(events, lambda e: e["kind"] == "saved")
    assert saved["path"].endswith("v0 (2).mp3")
    assert (tmp_path / "Music" / "v0.mp3").read_bytes() == b"otro"


def test_mandar_a_una_persona_sube_a_supabase_como_kyora(tmp_path):
    client = FakeClient()
    engine, events = make_engine(tmp_path, client)
    load_songs(engine, events)
    assert engine.registry.invoke("music.download", {"playlist": "PL1", "ids": ["v0"]})["ok"]
    wait_for(events, lambda e: e["kind"] == "sync" and e["state"] == "synced")
    assert client.uploads and client.uploads[0][0].startswith("user-1/music/")
    assert any(name == "add_music_track" for name, _ in client.rpcs)


def test_los_destinatarios_terminan_con_la_carpeta_aunque_falle_supabase(tmp_path):
    client = FakeClient()
    client.people = [{"id": "me-id", "username": "kyora", "me": True}, {"id": "p1", "username": "Ana", "me": False}]
    engine, events = make_engine(tmp_path, client)
    engine.registry.invoke("music.recipients", {})
    got = wait_for(events, lambda e: e["kind"] == "recipients")["recipients"]
    assert [p["name"] for p in got] == ["Yo", "Ana", "Esta PC (carpeta)"]
    assert got[-1]["id"] == FOLDER

    other = tmp_path / "otro"
    other.mkdir()
    offline, events2 = make_engine(other, chat_state="unconfigured")
    offline.registry.invoke("music.recipients", {})
    only = wait_for(events2, lambda e: e["kind"] == "recipients")["recipients"]
    assert [p["id"] for p in only] == [FOLDER]


def test_las_cookies_pegadas_van_al_cookies_txt_que_comparte_con_kyora(tmp_path):
    engine, _ = make_engine(tmp_path)
    text = ".youtube.com\tTRUE\t/\tTRUE\t0\tSID\tabc"
    assert engine.registry.invoke("music.save_cookies", {"text": text})["ok"]
    assert "SID" in (tmp_path / "cookies.txt").read_text(encoding="utf-8")


# ---------------------------------------------------------------- ajustes

def test_ajustes_por_defecto_y_validacion(tmp_path):
    settings = Settings(tmp_path / "merida.json", default_folder=tmp_path / "Music")
    assert settings.get() == {"browser": "chrome", "folder": str(tmp_path / "Music"), "default_recipient": None}
    assert settings.update({"browser": "Edge", "default_recipient": "p1"})["browser"] == "edge"
    assert settings.get()["default_recipient"] == "p1"
    with pytest.raises(ValueError):
        settings.update({"browser": "netscape"})
    with pytest.raises(ValueError):
        settings.update({"folder": "relativa/no"})
    assert settings.update({"default_recipient": "me"})["default_recipient"] is None


# ---------------------------------------------------------------- HTTP

@pytest.fixture
def server(tmp_path):
    engine, _ = make_engine(tmp_path)
    srv = make_server(engine, TOKEN, port=0)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    yield srv, engine
    srv.closing = True
    srv.shutdown()
    srv.server_close()


def call(srv, method, path, body=None, token=TOKEN, origin=ORIGIN, host=None):
    port = srv.server_address[1]
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(f"http://127.0.0.1:{port}{path}", data=data, method=method)
    if token:
        req.add_header("X-Merida-Token", token)
    if origin:
        req.add_header("Origin", origin)
    if host:
        req.add_header("Host", host)
    if data is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=3) as res:
            return res.status, json.loads(res.read()), res.headers
    except urllib.error.HTTPError as err:
        return err.code, json.loads(err.read()), err.headers


def test_sin_token_o_con_otro_origen_se_rechaza(server):
    srv, _ = server
    assert call(srv, "GET", "/api/health", token=None)[0] == 401
    assert call(srv, "GET", "/api/health", token="otro")[0] == 401
    assert call(srv, "GET", "/api/health", origin="https://malicioso.example")[0] == 403
    assert call(srv, "GET", "/api/health", host="evil.example:5190")[0] == 403
    status, body, headers = call(srv, "GET", "/api/health")
    assert status == 200 and body["ok"]
    assert headers["Access-Control-Allow-Origin"] == ORIGIN


def test_solo_acepta_las_acciones_de_musica_de_la_lista(server):
    srv, _ = server
    assert call(srv, "POST", "/api/action/chat.send", {"text": "x"})[0] == 404
    assert call(srv, "POST", "/api/action/music.panel", {})[0] == 404
    status, body, _ = call(srv, "POST", "/api/action/music.playlists", {})
    assert status == 200 and body == {"ok": True, "data": None}
    status, body, _ = call(srv, "POST", "/api/action/music.songs", {"nada": 1})
    assert body["ok"] is False and body["error"]["code"] == "bad_payload"


def test_ajustes_por_http(server):
    srv, _ = server
    status, body, _ = call(srv, "POST", "/api/settings", {"browser": "firefox"})
    assert status == 200 and body["data"]["browser"] == "firefox"
    assert call(srv, "POST", "/api/settings", {"browser": "x"})[0] == 400
    assert call(srv, "GET", "/api/settings")[1]["data"]["browser"] == "firefox"


def test_los_eventos_llegan_por_sse(server):
    srv, _ = server
    port = srv.server_address[1]
    req = urllib.request.Request(f"http://127.0.0.1:{port}/api/events?token={TOKEN}", headers={"Origin": ORIGIN})
    res = urllib.request.urlopen(req, timeout=5)
    assert res.headers["Content-Type"].startswith("text/event-stream")
    call(srv, "POST", "/api/action/music.playlists", {})
    got = None
    for _ in range(40):
        line = res.readline().decode("utf-8").strip()
        if line.startswith("data: "):
            event = json.loads(line[6:])
            if event["kind"] == "playlists":
                got = event
                break
    res.close()
    assert got and got["playlists"][0]["id"] == "LL"


def test_preflight_cors_solo_para_merida(server):
    srv, _ = server
    port = srv.server_address[1]
    ok = urllib.request.Request(f"http://127.0.0.1:{port}/api/action/music.songs", method="OPTIONS",
                                headers={"Origin": ORIGIN, "Access-Control-Request-Method": "POST"})
    with urllib.request.urlopen(ok, timeout=3) as res:
        assert res.status == 204
        assert "X-Merida-Token" in res.headers["Access-Control-Allow-Headers"]
    bad = urllib.request.Request(f"http://127.0.0.1:{port}/api/action/music.songs", method="OPTIONS",
                                 headers={"Origin": "https://malicioso.example"})
    with pytest.raises(urllib.error.HTTPError) as err:
        urllib.request.urlopen(bad, timeout=3)
    assert err.value.code == 403


def test_el_archivo_del_servicio_guarda_url_y_token(tmp_path):
    write_service_file(tmp_path / "merida_service.json", 5190, "abc")
    assert json.loads((tmp_path / "merida_service.json").read_text()) == {"url": "http://127.0.0.1:5190", "token": "abc"}
