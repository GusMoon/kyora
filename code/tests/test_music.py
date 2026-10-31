import threading
import time

from kyora.core.actions import ActionRegistry
from kyora.music import ytdlp
from kyora.music.service import MusicService

SONGS = [{"id": f"v{i}", "title": f"Cancion {i}", "duration": 100 + i} for i in range(3)]


class FakeYdl:
    """Un yt-dlp falso: lista canciones y, al descargar, crea el MP3 (o falla/espera según el escenario)."""

    def __init__(self, opts, script):
        self.opts, self.script = opts, script

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False

    def extract_info(self, url, download=False):
        if not download:
            if self.script.get("list_error"):
                raise RuntimeError("Could not copy Chrome cookie database")
            if "watch?v=" in url:
                if self.script.get("stream_error"):
                    raise RuntimeError("ERROR: Requested format is not available")
                self.script["resolved"] = self.script.get("resolved", 0) + 1
                return {"url": "https://stream/" + url.split("v=")[1]}
            if "feed/playlists" in url:
                return {"entries": [{"id": "PL1", "title": "Rock", "playlist_count": 3}]}
            return {"entries": SONGS}
        video_id = url.split("v=")[1]
        if video_id in self.script.get("fail", ()):
            raise RuntimeError("ERROR: Video unavailable")
        for hook in self.opts["progress_hooks"]:
            hook({"status": "downloading", "downloaded_bytes": 50, "total_bytes": 100})
        gate = self.script.get("gate")
        if gate and video_id == gate["id"]:
            gate["started"].set()
            for _ in range(200):  # espera a Detener: el hook lanza DownloadCancelled
                time.sleep(0.01)
                for hook in self.opts["progress_hooks"]:
                    hook({"status": "downloading", "downloaded_bytes": 60, "total_bytes": 100})
        path = self.script["dir"] / f"{video_id}.mp3"
        path.write_bytes(b"mp3")
        return {"title": f"Titulo {video_id}", "requested_downloads": [{"filepath": str(path)}]}


def make(tmp_path, **script):
    events = []
    script["dir"] = tmp_path
    service = MusicService(
        tmp_path, tmp_path, lambda: {"browser": "firefox"}, events.append,
        runner=lambda opts: FakeYdl(opts, script), find_ffmpeg=lambda: "ffmpeg-dir",
    )
    return service, events


def wait_for(events, kind, timeout=3):
    end = time.time() + timeout
    while time.time() < end:
        for e in events:
            if e["kind"] == kind:
                return e
        time.sleep(0.01)
    raise AssertionError(f"no llegó {kind}: {events}")


def states(events):
    last = {}
    for e in events:
        if e["kind"] == "progress":
            last[e["id"]] = e["state"]
    return last


def test_parsers():
    assert ytdlp.playlists_from({"entries": [{"id": "PL1", "title": "Rock"}, None, {"title": "sin id"}]})[1:] == [
        {"id": "PL1", "title": "Rock", "count": None}]
    assert ytdlp.playlists_from(None)[0]["id"] == "LL"
    assert ytdlp.songs_from({"entries": [{"id": "a", "title": "A", "duration": 61.4}, {"id": "b"}]}) == [
        {"id": "a", "title": "A", "duration": 61}, {"id": "b", "title": "b", "duration": None}]
    assert ytdlp.percent({"downloaded_bytes": 50, "total_bytes_estimate": 200}) == 25
    assert ytdlp.percent({}) == 0


def test_options(tmp_path):
    opts = ytdlp.download_opts(tmp_path, "firefox", "C:/ff", lambda d: None)
    assert opts["cookiesfrombrowser"] == ("firefox",) and opts["ffmpeg_location"] == "C:/ff"
    assert opts["postprocessors"][0]["preferredquality"] == "320" and opts["noplaylist"]
    assert "ffmpeg_location" not in ytdlp.download_opts(tmp_path, "edge", None, lambda d: None)


def test_friendly_errors():
    assert "firefox" in ytdlp.friendly_error(RuntimeError("Could not copy Chrome cookie database"), "firefox")
    assert ytdlp.friendly_error(RuntimeError("\x1b[0;31mERROR:\x1b[0m boom"), "chrome") == "boom"


def test_lists_playlists_and_songs(tmp_path):
    service, events = make(tmp_path)
    service.playlists()
    got = wait_for(events, "playlists")
    assert [p["id"] for p in got["playlists"]] == ["LL", "PL1"]
    service.songs("PL1")
    songs = wait_for(events, "songs")
    assert [s["state"] for s in songs["songs"]] == ["pending"] * 3


def test_list_error_is_reported(tmp_path):
    service, events = make(tmp_path, list_error=True)
    service.playlists()
    assert "cookies" in wait_for(events, "error")["error"]


def test_download_all_then_only_missing(tmp_path):
    service, events = make(tmp_path, fail={"v1"})
    service.songs("PL1")
    wait_for(events, "songs")
    service.download("PL1")
    done = wait_for(events, "finished")
    assert (done["done"], done["failed"]) == (2, 1)
    assert states(events) == {"v0": "done", "v1": "error", "v2": "done"}
    assert (tmp_path / "v0.mp3").exists() and not (tmp_path / "v1.mp3").exists()
    # segundo intento: solo la que faltó (ahora sin fallo)
    events.clear()
    service2, events2 = make(tmp_path)
    service2.songs("PL1")
    wait_for(events2, "songs")
    service2.download("PL1")
    again = wait_for(events2, "finished")
    assert (again["done"], again["failed"]) == (1, 0)
    assert set(states(events2)) == {"v1"}


def test_single_download(tmp_path):
    service, events = make(tmp_path)
    service.songs("PL1")
    wait_for(events, "songs")
    service.download("PL1", ids=["v2"])
    wait_for(events, "finished")
    assert states(events) == {"v2": "done"}


def test_deleted_mp3_is_pending_again(tmp_path):
    service, events = make(tmp_path)
    service.songs("PL1")
    wait_for(events, "songs")
    service.download("PL1", ids=["v0"])
    wait_for(events, "finished")
    assert service.is_done("v0")
    (tmp_path / "v0.mp3").unlink()
    assert not service.is_done("v0")


def test_done_survives_restart(tmp_path):
    service, events = make(tmp_path)
    service.songs("PL1")
    wait_for(events, "songs")
    service.download("PL1", ids=["v0"])
    wait_for(events, "finished")
    other, _ = make(tmp_path)
    assert other.is_done("v0") and not other.is_done("v1")


def test_cancel_stops_current_and_queue(tmp_path):
    gate = {"id": "v0", "started": threading.Event()}
    service, events = make(tmp_path, gate=gate)
    service.songs("PL1")
    wait_for(events, "songs")
    service.download("PL1")
    assert gate["started"].wait(3)
    service.cancel()
    done = wait_for(events, "finished")
    assert done["cancelled"] and done["done"] == 0
    assert states(events) == {"v0": "pending", "v1": "pending", "v2": "pending"}
    assert not any(tmp_path.glob("*.mp3"))


def test_missing_ffmpeg_raises(tmp_path):
    service, _ = make(tmp_path)
    service._find_ffmpeg = lambda: None
    service._songs["PL1"] = SONGS
    registry = ActionRegistry()
    service.register(registry)
    result = registry.invoke("music.download", {"playlist": "PL1"})
    assert not result["ok"] and "FFmpeg" in result["error"]["message"]


def test_cookies_file_takes_over_browser(tmp_path):
    assert ytdlp.list_opts("chrome", "c.txt")["cookiefile"] == "c.txt"
    assert "cookiesfrombrowser" not in ytdlp.download_opts(tmp_path, "chrome", None, lambda d: None, "c.txt")
    service, _ = make(tmp_path)
    assert service._cookies_file() is None
    (tmp_path / "cookies.txt").write_text("# Netscape HTTP Cookie File\n")
    assert service._cookies_file() == tmp_path / "cookies.txt"


def test_js_runtime_is_passed_when_found(monkeypatch, tmp_path):
    monkeypatch.setattr(ytdlp.shutil, "which", lambda name: "C:/node.exe" if name == "node" else None)
    assert ytdlp.list_opts("chrome")["js_runtimes"] == {"node": {"path": "C:/node.exe"}}
    assert ytdlp.download_opts(tmp_path, "chrome", None, lambda d: None)["js_runtimes"]
    monkeypatch.setattr(ytdlp.shutil, "which", lambda name: None)
    assert "js_runtimes" not in ytdlp.list_opts("chrome")
    assert "Node.js" in ytdlp.friendly_error(RuntimeError("Requested format is not available"), "chrome")


def test_stream_resolves_url_and_prefetches_next(tmp_path):
    script = {}
    service, events = make(tmp_path, **script)
    service.stream("v0", "v1")
    got = wait_for(events, "stream")
    assert got["source"].startswith("http://127.0.0.1:") and got["source"].endswith("/s/v0") and not got["local"]
    deadline = time.time() + 3
    while "v1" not in service._urls and time.time() < deadline:
        time.sleep(0.01)
    assert "v1" in service._urls  # la siguiente ya está lista


def test_stream_uses_local_file_and_cached_url(tmp_path):
    service, events = make(tmp_path)
    service.songs("PL1")
    wait_for(events, "songs")
    service.download("PL1", ids=["v0"])
    wait_for(events, "finished")
    events.clear()
    service.stream("v0")
    got = wait_for(events, "stream")
    assert got["local"] and got["source"].endswith("v0.mp3")
    events.clear()
    service.stream("v2")
    wait_for(events, "stream")
    events.clear()
    service._runner = None  # ya no debe pedir nada a yt-dlp
    service.stream("v2")
    assert wait_for(events, "stream")["source"].endswith("/s/v2")


def test_stream_error_is_reported(tmp_path):
    service, events = make(tmp_path, stream_error=True)
    service.stream("v0")
    got = wait_for(events, "error")
    assert got["where"] == "stream" and got["id"] == "v0"


def test_proxy_forwards_range_and_retries_fresh_link_403(monkeypatch):
    import http.server
    import urllib.request

    from kyora.music import proxy as proxy_module
    from kyora.music.proxy import StreamProxy

    monkeypatch.setattr(proxy_module, "RETRY_WAIT", 0.01)
    seen = []
    data = bytes(range(256)) * 16  # 4096 bytes

    class Upstream(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            first, _, last = self.headers["Range"].split("=")[1].partition("-")
            first, last = int(first), min(int(last or len(data) - 1), len(data) - 1)
            seen.append((self.headers.get("User-Agent"), self.headers.get("Accept-Encoding"), first))
            if len(seen) <= 2:  # un enlace recién resuelto: los primeros instantes da 403
                self.send_response(403)
                self.send_header("Content-Length", "0")
                self.end_headers()
                return
            body = data[first:last + 1]
            self.send_response(206)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Content-Range", f"bytes {first}-{last}/{len(data)}")
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *args):
            pass

    upstream = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Upstream)
    threading.Thread(target=upstream.serve_forever, daemon=True).start()
    proxy = StreamProxy()

    def fetch(link, rng):
        with urllib.request.urlopen(urllib.request.Request(link, headers={"Range": rng}), timeout=5) as r:
            return r.status, r.headers.get("Content-Range"), r.read()

    try:
        link = proxy.add("abc", f"http://127.0.0.1:{upstream.server_address[1]}/audio", {"User-Agent": "Browser/1"})
        assert fetch(link, "bytes=100-") == (206, "bytes 100-4095/4096", data[100:])
        assert seen[0] == ("Browser/1", "identity", 100) and len(seen) == 3  # dos 403 y el tercero pasó
        assert fetch(link, "bytes=10-19") == (206, "bytes 10-19/4096", data[10:20])
        try:
            urllib.request.urlopen(link.replace("abc", "nope"), timeout=5)
            raise AssertionError("debía dar 404")
        except urllib.error.HTTPError as exc:
            assert exc.code == 404
    finally:
        proxy.close()
        upstream.shutdown()


def test_expired_cookies_say_to_update_them():
    for text in ("HTTP Error 401: Unauthorized", "HTTP Error 403: Forbidden", "Sign in to confirm"):
        assert "cookies" in ytdlp.friendly_error(RuntimeError(text), "chrome")


def test_pasted_cookies_are_saved_as_a_netscape_file(tmp_path):
    import pytest

    from kyora.core.actions import ActionError
    from kyora.music.service import MusicService

    events = []
    service = MusicService(tmp_path, tmp_path, dict, events.append, runner=lambda opts: (_ for _ in ()).throw(RuntimeError("x")))
    pasted = "# Netscape HTTP Cookie File\n.youtube.com TRUE / TRUE 1893456000 SID abc\n.google.com\tTRUE\t/\tTRUE\t0\tHSID\tdef\n"
    service.save_cookies(pasted)
    text = (tmp_path / "cookies.txt").read_text(encoding="utf-8")
    assert text.startswith("# Netscape HTTP Cookie File") and ".youtube.com\tTRUE\t/\tTRUE\t1893456000\tSID\tabc" in text
    with pytest.raises(ActionError):
        service.save_cookies("esto no son cookies")


def test_each_finished_song_is_handed_to_the_phone_sync(tmp_path):
    service, events = make(tmp_path)
    handed = []
    service.on_done = lambda *args: handed.append(args)
    service.songs("PL1")
    wait_for(events, "songs")
    service.download("PL1", ids=["v1"])
    wait_for(events, "finished")
    assert handed == [("v1", str(tmp_path / "v1.mp3"), "Titulo v1", "PL1")]


def test_a_failing_sync_never_spoils_a_finished_download(tmp_path):
    service, events = make(tmp_path)

    def broken(*args):
        raise RuntimeError("sin cola")

    service.on_done = broken
    service.songs("PL1")
    wait_for(events, "songs")
    service.download("PL1", ids=["v0"])
    done = wait_for(events, "finished")
    assert (done["done"], done["failed"]) == (1, 0) and service.is_done("v0")


def test_asking_again_for_an_already_downloaded_song_sends_it_to_the_phone_but_download_all_does_not(tmp_path):
    service, events = make(tmp_path)
    service.songs("PL1")
    wait_for(events, "songs")
    service.download("PL1", ids=["v0"])
    wait_for(events, "finished")
    handed = []
    service.on_done = lambda *args: handed.append(args[0])
    service.download("PL1", ids=["v0"])                                       # una canción concreta: se vuelve a mandar
    assert handed == ["v0"]
    handed.clear()
    service.download("PL1")                                                   # «Descargar» todo: lo ya bajado no se reenvía
    wait_for(events, "finished")
    assert "v0" not in handed
