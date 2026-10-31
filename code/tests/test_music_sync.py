"""Las canciones que la PC baja suben a Supabase para que las vea el móvil (cliente y chat falsos, sin red)."""
import threading
import time

from kyora.chat.client import ChatError
from kyora.music import sync as music_sync
from kyora.music.sync import MusicSync, track_id


class FakeClient:
    user_id = "user-1"

    def __init__(self):
        self.uploads, self.rpcs, self.fail = [], [], []

    def upload(self, path, data, mime):
        if self.fail:
            raise self.fail.pop(0)
        self.uploads.append((path, data, mime))

    def rpc(self, name, payload=None):
        self.rpcs.append((name, payload))
        return {}


class FakeChat:
    def __init__(self, client=None, state="online", max_mb=50):
        self.client, self.state, self._max = client, state, max_mb * 1_000_000

    def client_ready(self):
        return self.client

    def configured(self):
        return self.state != "unconfigured"

    def max_bytes(self):
        return self._max


def mp3(tmp_path, name="cancion.mp3", data=b"ID3audio"):
    path = tmp_path / name
    path.write_bytes(data)
    return path


def wait(condition, seconds=3):
    end = time.time() + seconds
    while time.time() < end:
        if condition():
            return True
        time.sleep(0.01)
    return condition()


def make(tmp_path, chat, config=dict, retry_s=0.05):
    events = []
    sync = MusicSync(tmp_path, chat, events.append, config, retry_s=retry_s)
    return sync, events


def test_a_downloaded_song_is_uploaded_and_registered_for_the_phone(tmp_path):
    client = FakeClient()
    sync, events = make(tmp_path, FakeChat(client))
    song = mp3(tmp_path)
    sync.enqueue("vid1", song, "Mi canción", "Favoritas")
    assert wait(lambda: sync.is_synced("vid1"))
    track = track_id("vid1")
    assert client.uploads == [(f"user-1/music/{track}/cancion.mp3", b"ID3audio", "audio/mpeg")]
    name, payload = client.rpcs[0]
    assert name == "add_music_track" and payload["p_id"] == track and payload["p_title"] == "Mi canción"
    assert payload["p_playlist"] == "Favoritas" and payload["p_size_bytes"] == len(b"ID3audio")
    assert [e["state"] for e in events] == ["uploading", "synced"]
    assert track_id("vid1") == track_id("vid1") != track_id("vid2")                        # mismo vídeo, mismo id


def test_a_song_is_not_sent_twice(tmp_path):
    client = FakeClient()
    sync, _ = make(tmp_path, FakeChat(client))
    song = mp3(tmp_path)
    sync.enqueue("vid1", song, "uno")
    assert wait(lambda: sync.is_synced("vid1"))
    sync.enqueue("vid1", song, "uno otra vez")
    time.sleep(0.1)
    assert len(client.uploads) == 1
    reopened, _ = make(tmp_path, FakeChat(client))                                          # tampoco tras reiniciar Kyora
    reopened.enqueue("vid1", song, "uno")
    time.sleep(0.1)
    assert len(client.uploads) == 1


def test_without_connection_the_song_waits_and_goes_when_it_comes_back(tmp_path):
    client = FakeClient()
    client.fail = [ChatError("offline", "Sin conexión con Supabase", retryable=True)]
    sync, events = make(tmp_path, FakeChat(client))
    sync.enqueue("vid1", mp3(tmp_path), "uno")
    assert wait(lambda: sync.is_synced("vid1"))
    assert [e["state"] for e in events if e["state"] != "uploading"] == ["error", "synced"]
    assert "Sin conexión" in next(e["message"] for e in events if e["state"] == "error")


def test_without_a_session_yet_it_keeps_the_song_pending_across_restarts(tmp_path):
    chat = FakeChat(client=None)
    sync, _ = make(tmp_path, chat)
    song = mp3(tmp_path)
    sync.enqueue("vid1", song, "uno")
    time.sleep(0.15)
    assert not sync.is_synced("vid1") and "vid1" in sync._pending
    sync.stop()
    client = FakeClient()
    reopened, _ = make(tmp_path, FakeChat(client))                                          # al abrir Kyora otra vez
    assert "vid1" in reopened._pending
    reopened.start()
    assert wait(lambda: reopened.is_synced("vid1")) and len(client.uploads) == 1


def test_a_refused_upload_is_dropped_with_the_reason(tmp_path):
    client = FakeClient()
    client.fail = [ChatError("403", "Supabase rechazó el archivo", retryable=False)]
    sync, events = make(tmp_path, FakeChat(client))
    sync.enqueue("vid1", mp3(tmp_path), "uno")
    assert wait(lambda: events and events[-1]["state"] == "error")
    assert "rechazó" in events[-1]["message"] and "vid1" not in sync._pending and not sync.is_synced("vid1")


def test_a_song_bigger_than_the_cloud_limit_is_not_uploaded(tmp_path):
    client = FakeClient()
    sync, events = make(tmp_path, FakeChat(client, max_mb=1))
    sync.enqueue("vid1", mp3(tmp_path, data=b"x" * 1_500_000), "grande")
    assert wait(lambda: events and events[-1]["state"] == "error")
    assert client.uploads == [] and "no cabe" in events[-1]["message"]


def test_it_does_nothing_when_off_or_when_the_chat_is_not_configured(tmp_path):
    client = FakeClient()
    off, _ = make(tmp_path, FakeChat(client), config=lambda: {"sync": False})
    off.enqueue("vid1", mp3(tmp_path), "uno")
    bare, _ = make(tmp_path, FakeChat(client, state="unconfigured"))
    bare.enqueue("vid2", mp3(tmp_path), "dos")
    time.sleep(0.1)
    assert client.uploads == [] and not off._pending and not bare._pending


def test_the_worker_thread_ends_when_the_queue_is_empty_and_restarts_for_the_next_song(tmp_path):
    client = FakeClient()
    sync, _ = make(tmp_path, FakeChat(client))
    song = mp3(tmp_path)
    sync.enqueue("vid1", song, "uno")
    assert wait(lambda: sync._thread is None and sync.is_synced("vid1"))
    sync.enqueue("vid2", song, "dos")
    assert wait(lambda: sync.is_synced("vid2"))
    assert not any(t.name == "kyora-music-sync" and t.is_alive() for t in threading.enumerate()) or wait(
        lambda: sync._thread is None)
