"""«Descargar» pregunta a quién mandar la canción: el panel de destinatarios de la página de Música (Qt fuera de pantalla)."""
from PySide6.QtCore import QEvent, QPointF, Qt
from PySide6.QtGui import QKeyEvent, QMouseEvent
from PySide6.QtWidgets import QApplication

from kyora.ui import musicpage
from kyora.ui.musicpage import MusicPage
from kyora.ui.theme import THEME

app = QApplication.instance() or QApplication([])

PEOPLE = [{"id": None, "name": "Yo", "me": True}, {"id": "ana-id", "name": "ana", "me": False},
          {"id": "luis-id", "name": "Luis", "me": False}]


def make(states=("pending", "pending", "done")):
    calls = []
    page = MusicPage(THEME, lambda action, **payload: calls.append((action, payload)))
    page.resize(440, 400)
    page.playlist = {"id": "PL1", "title": "Rock"}
    page.songs = [{"id": f"v{i}", "title": f"Canción {i}", "state": state, "percent": 0} for i, state in enumerate(states)]
    page.list.set_items("songs", [{**s, "sub": ""} for s in page.songs])
    page._sync()
    page.show()
    calls.clear()
    return page, calls


def press(widget, key):
    widget.keyPressEvent(QKeyEvent(QEvent.KeyPress, key, Qt.NoModifier))


def downloads(calls):
    return [(payload.get("ids"), payload.get("recipient"), payload.get("recipient_name"))
            for action, payload in calls if action == "music.download"]


def test_the_download_button_asks_who_before_sending_anything():
    page, calls = make()
    page.download.click()
    assert [a for a, _ in calls] == ["music.recipients"]                          # solo pide la lista de personas
    assert page.recipients.isVisible() and not page.list.isVisible()
    assert page.recipients.prompt == "¿A quién se las mando? (2)"


def test_choosing_a_person_sends_to_them_and_goes_back_to_the_list():
    page, calls = make()
    page.download.click()
    page.on_result({"kind": "recipients", "recipients": PEOPLE})
    assert [p["name"] for p in page.recipients.items] == ["Yo", "ana", "Luis"]
    press(page.recipients, Qt.Key_Down)
    press(page.recipients, Qt.Key_Return)
    assert downloads(calls) == [(None, "ana-id", "ana")]                          # todas las pendientes (sin ids), a ana
    assert not page.recipients.isVisible() and page.list.isVisible()
    assert page.last_recipient["name"] == "ana"


def test_yo_is_first_and_goes_with_an_empty_recipient():
    page, calls = make()
    page.list.download.emit(1)                                                    # el botón de bajar de una fila
    page.on_result({"kind": "recipients", "recipients": PEOPLE})
    assert page.recipients.prompt == "¿A quién se la mando?"
    press(page.recipients, Qt.Key_Return)
    assert downloads(calls) == [(["v1"], None, "Yo")]


def test_clicking_a_name_chooses_it():
    page, calls = make()
    page.list.download.emit(0)
    page.on_result({"kind": "recipients", "recipients": PEOPLE})
    row = musicpage.ROW_H
    point = QPointF(100, page.recipients._top() + 2 * row + row / 2)
    page.recipients.mousePressEvent(QMouseEvent(QEvent.MouseButtonPress, point, point, Qt.LeftButton, Qt.LeftButton, Qt.NoModifier))
    assert downloads(calls) == [(["v0"], "luis-id", "Luis")]


def test_escape_cancels_without_sending():
    page, calls = make()
    page.download.click()
    page.on_result({"kind": "recipients", "recipients": PEOPLE})
    press(page.recipients, Qt.Key_Escape)
    assert downloads(calls) == [] and page.list.isVisible() and page.asking is None


def test_if_the_list_of_people_fails_the_reason_is_shown_and_nothing_is_sent():
    page, calls = make()
    page.download.click()
    page.on_result({"kind": "error", "where": "recipients", "error": "Aún no hay sesión con Supabase: revisa el chat"})
    assert page.recipients.items == [] and "sesión" in page.recipients.message and page.recipients.warn
    press(page.recipients, Qt.Key_Return)                                         # sin personas, Enter no hace nada
    assert downloads(calls) == [] and page.recipients.isVisible()
    press(page.recipients, Qt.Key_Escape)
    assert page.list.isVisible()


def test_an_answer_that_arrives_after_cancelling_is_ignored():
    page, _ = make()
    page.download.click()
    press(page.recipients, Qt.Key_Escape)
    page.on_result({"kind": "recipients", "recipients": PEOPLE})
    assert page.recipients.items == []


def test_a_song_already_sent_can_be_sent_to_someone_else_but_one_being_sent_cannot():
    page, calls = make(states=("done", "sending", "doing"))
    page.list.keyPressEvent(QKeyEvent(QEvent.KeyPress, Qt.Key_D, Qt.NoModifier))     # D sobre la primera (ya enviada)
    assert [a for a, _ in calls] == ["music.recipients"]
    page._close_recipients()
    calls.clear()
    for index in (1, 2):
        page.list.selected = index
        page.list.keyPressEvent(QKeyEvent(QEvent.KeyPress, Qt.Key_D, Qt.NoModifier))
    assert calls == []


def test_the_capsule_key_sends_the_playing_song_to_the_last_person_chosen():
    page, calls = make()
    page.queue, page.at, page.sound, page.queue_playlist = list(page.songs), 1, "playing", "PL1"
    page.download_current()
    assert downloads(calls) == [(["v1"], None, "Yo")]                              # por defecto, yo
    page.last_recipient = PEOPLE[1]
    calls.clear()
    page.download_current()
    assert downloads(calls) == [(["v1"], "ana-id", "ana")]


def test_the_notes_name_who_the_song_goes_to():
    page, _ = make()
    page.on_result({"kind": "sync", "id": "v0", "state": "uploading", "title": "Canción 0", "to": "ana"})
    assert page.note.text() == "Mandando «Canción 0» a ana…"
    page.on_result({"kind": "sync", "id": "v0", "state": "synced", "title": "Canción 0", "to": "ana"})
    assert page.note.text() == "Enviada a ana: «Canción 0»"
    page.on_result({"kind": "sync", "id": "v0", "state": "synced", "title": "Canción 0", "to": "Yo"})
    assert page.note.text() == "En tu móvil: «Canción 0»"


def test_a_sending_row_is_busy_and_a_failed_one_shows_the_reason():
    page, _ = make(states=("pending", "pending", "pending"))
    page.on_result({"kind": "progress", "playlist": "PL1", "id": "v0", "state": "sending", "percent": 100})
    assert page.songs[0]["state"] == "sending" and page.list.items[0]["state"] == "sending"
    page.on_result({"kind": "progress", "playlist": "PL1", "id": "v0", "state": "error", "percent": 0,
                    "error": "Supabase rechazó el archivo"})
    assert page.songs[0]["state"] == "error" and page.note.text() == "Supabase rechazó el archivo"
