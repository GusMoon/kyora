"""Las canciones que la PC baja suben a Supabase para quien elijas, «Yo» o un pasante (cliente y chat falsos, sin red)."""
import json
import threading
import time

import pytest

from kyora.chat.client import ChatError
from kyora.music.sync import MusicSync, cover_url, explain, track_id


class FakeClient:
    user_id = "user-1"

    def __init__(self):
        self.uploads, self.rpcs, self.fail, self.people, self.rpc_fail = [], [], [], [], []

    def upload(self, path, data, mime):
        if self.fail:
            raise self.fail.pop(0)
        self.uploads.append((path, data, mime))

    def rpc(self, name, payload=None):
        self.rpcs.append((name, payload))
        if name == "add_music_track" and self.rpc_fail:
            raise self.rpc_fail.pop(0)
        return self.people if name == "list_recipients" else {}


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
    events, sent, failed = [], [], []
    sync = MusicSync(tmp_path, chat, events.append, config, retry_s=retry_s)
    sync.on_sent = lambda *args: sent.append(args)
    sync.on_failed = lambda *args: failed.append(args)
    sync.sent, sync.failed = sent, failed
    return sync, events


def test_a_downloaded_song_is_uploaded_registered_for_me_and_the_temp_file_is_deleted(tmp_path):
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
    assert payload["p_recipient_id"] is None and payload["p_cover_url"] == cover_url("vid1")
    assert [e["state"] for e in events] == ["uploading", "synced"] and events[-1]["to"] == "Yo"
    assert sync.sent == [("vid1", None, "Favoritas")]
    assert wait(lambda: not song.exists())                                                  # el temporal se borra
    assert track_id("vid1") == track_id("vid1") != track_id("vid2")                        # mismo vídeo, mismo id
    assert track_id("vid1", "ana") != track_id("vid1") and track_id("vid1", "ana") != track_id("vid1", "luis")


def test_a_song_for_a_pasante_is_registered_for_them_and_named_in_the_events(tmp_path):
    client = FakeClient()
    sync, events = make(tmp_path, FakeChat(client))
    sync.enqueue("vid1", mp3(tmp_path), "uno", "", "ana-id", "ana")
    assert wait(lambda: sync.is_synced("vid1", "ana-id"))
    payload = client.rpcs[0][1]
    assert payload["p_recipient_id"] == "ana-id" and payload["p_id"] == track_id("vid1", "ana-id")
    assert not sync.is_synced("vid1")                                                       # a «Yo» no se le mandó
    assert events[-1]["to"] == "ana" and sync.sent == [("vid1", "ana-id", "")]


def test_the_same_song_for_two_people_is_uploaded_once(tmp_path):
    client = FakeClient()
    sync, _ = make(tmp_path, FakeChat(client))
    song = mp3(tmp_path)
    sync.enqueue("vid1", song, "uno", "", None, "Yo")
    sync.enqueue("vid1", song, "uno", "", "ana-id", "ana")
    assert wait(lambda: sync.is_synced("vid1") and sync.is_synced("vid1", "ana-id"))
    assert len(client.uploads) == 1 and [r[1]["p_recipient_id"] for r in client.rpcs] == [None, "ana-id"]
    assert wait(lambda: not song.exists())
    # más tarde, a otra persona: ya está en la nube, no hace falta archivo
    assert sync.is_uploaded("vid1") and not sync.is_uploaded("vid2")
    sync.enqueue("vid1", None, "uno", "", "luis-id", "luis")
    assert wait(lambda: sync.is_synced("vid1", "luis-id"))
    assert len(client.uploads) == 1
    last = client.rpcs[-1][1]
    assert last["p_storage_path"] == f"user-1/music/{track_id('vid1')}/cancion.mp3" and last["p_file_name"] == "cancion.mp3"
    reopened, _ = make(tmp_path, FakeChat(client))                                          # y se recuerda tras reiniciar
    assert reopened.is_uploaded("vid1")


def test_a_song_whose_file_was_purged_from_the_cloud_is_reported_and_will_be_uploaded_again_next_time(tmp_path):
    client = FakeClient()
    sync, events = make(tmp_path, FakeChat(client))
    song = mp3(tmp_path)
    sync.enqueue("vid1", song, "uno", "", "ana-id", "ana")
    assert wait(lambda: sync.is_synced("vid1", "ana-id"))
    assert sync.is_uploaded("vid1") and len(client.uploads) == 1
    # la limpieza automática de Supabase borró el MP3 tras recibirse; mandarla a otra persona sin volver a subirla falla
    client.rpc_fail.append(ChatError("22023", "file_missing"))
    sync.enqueue("vid1", None, "uno", "", "luis-id", "luis")
    assert wait(lambda: sync.failed)
    assert "vuelve a mandarla" in sync.failed[-1][1] and not sync.is_synced("vid1", "luis-id")
    assert not sync.is_uploaded("vid1")                                                     # ya no se da por subida
    song2 = mp3(tmp_path, "otra.mp3")
    sync.enqueue("vid1", song2, "uno", "", "luis-id", "luis")                               # la PC vuelve a bajarla y mandarla
    assert wait(lambda: sync.is_synced("vid1", "luis-id"))
    assert len(client.uploads) == 2 and sync.is_uploaded("vid1")


def test_a_song_is_not_sent_twice_to_the_same_person(tmp_path):
    client = FakeClient()
    sync, _ = make(tmp_path, FakeChat(client))
    sync.enqueue("vid1", mp3(tmp_path), "uno")
    assert wait(lambda: sync.is_synced("vid1"))
    again = mp3(tmp_path, "otra.mp3")
    sync.enqueue("vid1", again, "uno otra vez")
    time.sleep(0.1)
    assert len(client.uploads) == 1 and len(client.rpcs) == 1
    assert not again.exists() and len(sync.sent) == 2                                       # se avisa de que ya estaba
    reopened, _ = make(tmp_path, FakeChat(client))                                          # tampoco tras reiniciar Kyora
    reopened.enqueue("vid1", mp3(tmp_path, "y-otra.mp3"), "uno")
    time.sleep(0.1)
    assert len(client.uploads) == 1


def test_without_connection_the_song_waits_and_goes_when_it_comes_back(tmp_path):
    client = FakeClient()
    client.fail = [ChatError("offline", "Sin conexión con Supabase", retryable=True)]
    sync, events = make(tmp_path, FakeChat(client))
    song = mp3(tmp_path)
    sync.enqueue("vid1", song, "uno")
    assert wait(lambda: any(e["state"] == "error" for e in events))
    assert song.exists()                                                                    # el temporal espera
    assert wait(lambda: sync.is_synced("vid1"))
    assert [e["state"] for e in events if e["state"] != "uploading"] == ["error", "synced"]
    assert "Sin conexión" in next(e["message"] for e in events if e["state"] == "error")
    assert sync.failed == [] and wait(lambda: not song.exists())


def test_without_a_session_yet_it_keeps_the_song_pending_across_restarts(tmp_path):
    chat = FakeChat(client=None)
    sync, _ = make(tmp_path, chat)
    song = mp3(tmp_path)
    sync.enqueue("vid1", song, "uno", "", "ana-id", "ana")
    time.sleep(0.15)
    assert not sync.is_synced("vid1", "ana-id") and "vid1:ana-id" in sync._pending and song.exists()
    sync.stop()
    client = FakeClient()
    reopened, _ = make(tmp_path, FakeChat(client))                                          # al abrir Kyora otra vez
    assert "vid1:ana-id" in reopened._pending
    reopened.start()
    assert wait(lambda: reopened.is_synced("vid1", "ana-id")) and len(client.uploads) == 1
    assert reopened.sent == [("vid1", "ana-id", "")]


def test_a_refused_upload_is_dropped_with_the_reason_and_the_temp_file_goes(tmp_path):
    client = FakeClient()
    client.fail = [ChatError("403", "Supabase rechazó el archivo", retryable=False)]
    sync, events = make(tmp_path, FakeChat(client))
    song = mp3(tmp_path)
    sync.enqueue("vid1", song, "uno", "Lista")
    assert wait(lambda: events and events[-1]["state"] == "error")
    assert "rechazó" in events[-1]["message"] and not sync._pending and not sync.is_synced("vid1")
    assert sync.failed == [("vid1", "Supabase rechazó el archivo", "Lista")] and wait(lambda: not song.exists())


def test_a_song_bigger_than_the_cloud_limit_is_not_uploaded(tmp_path):
    client = FakeClient()
    sync, events = make(tmp_path, FakeChat(client, max_mb=1))
    sync.enqueue("vid1", mp3(tmp_path, data=b"x" * 1_500_000), "grande")
    assert wait(lambda: events and events[-1]["state"] == "error")
    assert client.uploads == [] and "no cabe" in events[-1]["message"] and sync.failed


def test_a_missing_file_that_was_never_uploaded_is_reported(tmp_path):
    sync, events = make(tmp_path, FakeChat(FakeClient()))
    sync.enqueue("vid1", tmp_path / "no-existe.mp3", "uno")
    assert wait(lambda: events and events[-1]["state"] == "error")
    assert "ya no está" in events[-1]["message"] and sync.failed


def test_it_says_so_and_does_nothing_when_off_or_when_the_chat_is_not_configured(tmp_path):
    client = FakeClient()
    off, off_events = make(tmp_path, FakeChat(client), config=lambda: {"sync": False})
    off.enqueue("vid1", mp3(tmp_path), "uno")
    bare, _ = make(tmp_path, FakeChat(client, state="unconfigured"))
    bare.enqueue("vid2", mp3(tmp_path, "b.mp3"), "dos")
    time.sleep(0.1)
    assert client.uploads == [] and not off._pending and not bare._pending
    assert off.failed and off_events[-1]["state"] == "error"                                # la fila no se queda esperando


def test_the_worker_thread_ends_when_the_queue_is_empty_and_restarts_for_the_next_song(tmp_path):
    client = FakeClient()
    sync, _ = make(tmp_path, FakeChat(client))
    sync.enqueue("vid1", mp3(tmp_path, "a.mp3"), "uno")
    assert wait(lambda: sync._thread is None and sync.is_synced("vid1"))
    sync.enqueue("vid2", mp3(tmp_path, "b.mp3"), "dos")
    assert wait(lambda: sync.is_synced("vid2"))
    assert not any(t.name == "kyora-music-sync" and t.is_alive() for t in threading.enumerate()) or wait(
        lambda: sync._thread is None)


def test_the_list_of_people_has_me_first_as_yo_then_the_pasantes_by_name(tmp_path):
    client = FakeClient()
    client.people = [{"id": "me-id", "username": "kyora1947", "role": "admin", "me": True},
                     {"id": "luis-id", "username": "Luis", "role": "intern", "me": False},
                     {"id": "ana-id", "username": "ana", "role": "intern", "me": False}]
    sync, _ = make(tmp_path, FakeChat(client))
    assert sync.recipients() == [{"id": None, "name": "Yo", "me": True}, {"id": "ana-id", "name": "ana", "me": False},
                                 {"id": "luis-id", "name": "Luis", "me": False}]


def test_the_list_of_people_explains_why_it_is_not_available(tmp_path):
    with pytest.raises(ChatError) as off:
        make(tmp_path, FakeChat(FakeClient()), config=lambda: {"sync": False})[0].recipients()
    assert "apagado" in off.value.message
    with pytest.raises(ChatError) as waiting:
        make(tmp_path, FakeChat(client=None))[0].recipients()
    assert waiting.value.retryable and "sesión" in waiting.value.message


def test_what_the_single_account_version_saved_still_counts_as_sent_to_me(tmp_path):
    (tmp_path / "music_sync.json").write_text(json.dumps({"synced": {"vid1": "t1"}, "pending": {
        "vid2": {"path": str(mp3(tmp_path, "viejo.mp3")), "title": "viejo", "playlist": ""}}}), encoding="utf-8")
    client = FakeClient()
    sync, _ = make(tmp_path, FakeChat(client))
    assert sync.is_synced("vid1") and not sync.is_synced("vid1", "ana-id") and "vid2:me" in sync._pending
    sync.start()
    assert wait(lambda: sync.is_synced("vid2")) and client.rpcs[0][1]["p_recipient_id"] is None


def test_database_error_codes_are_shown_in_spanish(tmp_path):
    client = FakeClient()
    client.fail = []
    sync, events = make(tmp_path, FakeChat(client))

    def refuse(name, payload=None):
        raise ChatError("22023", "unknown_recipient", retryable=False)

    client.rpc = refuse
    sync.enqueue("vid1", mp3(tmp_path), "uno", "", "ana-id", "ana")
    assert wait(lambda: events and events[-1]["state"] == "error")
    assert "no existe en Supabase" in events[-1]["message"] and "unknown_recipient" not in events[-1]["message"]
    assert sync.is_uploaded("vid1")                                                         # el archivo ya estaba subido: reintentar no lo baja
    assert explain(ChatError("42501", "not_admin")).startswith("Solo la cuenta de administrador")
    assert explain(ChatError("500x", "otra cosa")) == "otra cosa"
