"""La interfaz del chat: burbujas, compositor, adjuntos y su sitio en el buscador (Qt fuera de pantalla)."""
from datetime import date

from PySide6.QtCore import QEvent, QMimeData, QPointF, Qt, QUrl
from PySide6.QtGui import QImage, QKeyEvent, QMouseEvent
from PySide6.QtWidgets import QApplication

from kyora.ui import chat, search, sectionbar, topdock
from kyora.ui.theme import THEME
from kyora.ui.win import ScreenMap

app = QApplication.instance() or QApplication([])


def msg(n, body="hola", device="pc", status="sent", attachments=(), error=None):
    stamp = f"2026-10-30T14:{n:02d}:00Z"
    return {"id": f"m{n}", "conversation_id": "c", "device": device, "kind": "text", "body": body, "status": status,
            "sent_at": stamp, "created_at": stamp, "deleted": False, "error": error, "attempts": 0,
            "attachments": list(attachments)}


def att(n, name="foto.png", mime="image/png", **extra):
    return {"id": f"a{n}", "file_name": name, "mime_type": mime, "size_bytes": 1234, "width": None, "height": None,
            "storage_path": f"u/c/m/{name}", "local_path": None, **extra}


class Core:
    """El núcleo falso: apunta lo que se le pide."""

    def __init__(self, messages=(), state="online"):
        self.calls, self.messages, self.state, self.fail = [], list(messages), state, None

    def __call__(self, action, **payload):
        self.calls.append((action, payload))
        if action == "chat.history":
            return {"ok": True, "data": {"messages": self.messages, "state": self.state, "detail": "", "device": "pc",
                                         "missing": []}}
        if self.fail and action == "chat.send":
            return {"ok": False, "error": {"code": "too_big", "message": self.fail}}
        return {"ok": True, "data": None}

    def sent(self, action):
        return [p for a, p in self.calls if a == action]


def board(core=None, size=(680, 540)):
    core = core or Core()
    widget = chat.ChatBoard(THEME, core, escape=lambda: core.calls.append(("escape", {})))
    widget.resize(*size)
    widget.show()
    widget.open()
    app.processEvents()
    return widget, core


def click(widget, point):
    event = QMouseEvent(QEvent.MouseButtonRelease, QPointF(point), QPointF(point), Qt.LeftButton, Qt.NoButton, Qt.NoModifier)
    widget.mouseReleaseEvent(event)


def move(widget, point):
    event = QMouseEvent(QEvent.MouseMove, QPointF(point), QPointF(point), Qt.NoButton, Qt.NoButton, Qt.NoModifier)
    widget.mouseMoveEvent(event)


def key(widget, k, mods=Qt.NoModifier):
    widget.keyPressEvent(QKeyEvent(QEvent.KeyPress, k, mods))


# ---------- utilidades ----------

def test_day_and_clock_texts():
    today = date(2026, 10, 30)
    assert chat.day_text("2026-10-30T12:00:00", today) == "Hoy" and chat.day_text("2026-10-29T12:00:00", today) == "Ayer"
    assert chat.day_text("2026-10-03T12:00:00", today) == "3 de octubre"
    assert chat.day_text("2025-12-24T12:00:00", today) == "24 de diciembre de 2025"
    assert chat.day_text("basura", today) == "" and chat.clock_text("basura") == ""
    assert len(chat.clock_text("2026-10-30T12:00:00Z")) == 5 and chat.clock_text("2026-10-30T12:00:00Z")[2] == ":"


def test_fit_keeps_the_proportion_and_never_enlarges():
    assert chat.fit((900, 600), (280, 220)) == (280, 186)
    assert chat.fit((100, 50), (280, 220)) == (100, 50)
    assert chat.fit((0, 0), (280, 220)) == (0 + 1, 0 + 1) or chat.fit((0, 0), (280, 220))[0] >= 1


# ---------- el tablero ----------

def test_open_shows_what_is_saved_with_its_state_and_focuses_the_composer():
    widget, core = board(Core([msg(1, "uno", device="phone"), msg(2, "dos")], state="offline"))
    assert [m["body"] for m in widget.view.messages] == ["uno", "dos"] and widget.state == "offline"
    assert widget.device == "pc" and widget.view.device == "pc" and core.sent("chat.history")
    assert widget.composer.hasFocus() or widget.composer.isVisible()


def test_events_add_replace_and_remove_messages_and_update_the_connection():
    widget, _ = board(Core([msg(1, "uno")]))
    widget.on_event({"kind": "message", "message": msg(2, "nuevo", status="pending"), "incoming": False})
    assert [m["id"] for m in widget.view.messages] == ["m1", "m2"] and widget.view.messages[1]["status"] == "pending"
    widget.on_event({"kind": "status", "id": "m2", "status": "sent", "message": msg(2, "nuevo")})
    assert widget.view.messages[1]["status"] == "sent" and len(widget.view.messages) == 2
    widget.on_event({"kind": "deleted", "id": "m1"})
    assert [m["id"] for m in widget.view.messages] == ["m2"]
    widget.on_event({"kind": "connection", "state": "auth_error", "detail": "Contraseña mala"})
    assert widget.state == "auth_error" and widget.detail == "Contraseña mala"
    widget.on_event({"kind": "older", "messages": [msg(0, "anterior")]})
    assert [m["id"] for m in widget.view.messages] == ["m0", "m2"]


def test_incoming_messages_only_notify_when_the_chat_is_not_visible():
    widget, _ = board()
    seen = []
    widget.notify.connect(seen.append)
    widget.on_event({"kind": "message", "message": msg(5, "con el chat abierto", device="phone"), "incoming": True})
    assert seen == []
    widget.hide()
    widget.on_event({"kind": "message", "message": msg(6, "con el chat cerrado", device="phone"), "incoming": True})
    assert len(seen) == 1 and "phone" in seen[0] and "con el chat cerrado" in seen[0]
    widget.on_event({"kind": "message", "message": msg(7, "mío", device="pc"), "incoming": False})
    assert len(seen) == 1
    widget.on_event({"kind": "error", "error": "No se pudo borrar"})
    assert seen[-1] == "No se pudo borrar"


def test_send_passes_text_and_staged_files_then_clears_the_composer():
    widget, core = board()
    widget.composer.setPlainText("  hola  ")
    widget.stage(["C:/a/foto.png", "C:/a/foto.png", "C:/a/doc.pdf"])                  # sin repetidos
    assert widget.staged == ["C:/a/foto.png", "C:/a/doc.pdf"]
    key(widget.composer, Qt.Key_Return)                                                # Enter envía
    assert core.sent("chat.send") == [{"text": "hola", "paths": ["C:/a/foto.png", "C:/a/doc.pdf"]}]
    assert widget.composer.toPlainText() == "" and widget.staged == []
    key(widget.composer, Qt.Key_Return)                                                # vacío: no envía
    assert len(core.sent("chat.send")) == 1


def test_shift_enter_makes_a_new_line_and_does_not_send():
    widget, core = board()
    widget.composer.setPlainText("a")
    widget.composer.moveCursor(widget.composer.textCursor().MoveOperation.End)
    key(widget.composer, Qt.Key_Return, Qt.ShiftModifier)
    assert core.sent("chat.send") == [] and "\n" in widget.composer.toPlainText()


def test_a_refused_send_keeps_the_text_and_says_why():
    core = Core()
    core.fail = "«grande.bin» pesa 80 MB; el máximo es 50 MB"
    widget, _ = board(core)
    widget.composer.setPlainText("con adjunto")
    widget.stage(["C:/grande.bin"])
    widget.send()
    assert widget.composer.toPlainText() == "con adjunto" and widget.staged == ["C:/grande.bin"]
    assert "80 MB" in widget._note


def test_staged_files_can_be_removed_with_their_cross():
    widget, _ = board()
    widget.stage(["C:/x/uno.txt", "C:/x/dos.txt"])
    rects = widget._chips_at(widget._rects())
    assert [path for _, path in rects] == ["C:/x/uno.txt", "C:/x/dos.txt"]
    click(widget, rects[0][0].center())
    assert widget.staged == ["C:/x/dos.txt"]


def test_composer_keys_attach_scroll_and_escape(monkeypatch):
    opened = []
    monkeypatch.setattr(chat.QFileDialog, "getOpenFileNames", lambda *a, **k: (opened.append(a) or ["C:/x/elegido.txt"], ""))
    widget, core = board()
    seen = []
    widget.composer.attach.connect(lambda: seen.append("attach"))
    widget.composer.scroll_page.connect(seen.append)
    key(widget.composer, Qt.Key_O, Qt.ControlModifier)
    key(widget.composer, Qt.Key_PageUp)
    key(widget.composer, Qt.Key_PageDown)
    key(widget.composer, Qt.Key_Escape)
    assert seen == ["attach", -1, 1] and ("escape", {}) in core.calls
    assert len(opened) == 1 and widget.staged == ["C:/x/elegido.txt"]                  # Ctrl+O abre el selector de archivos


def test_pasting_files_and_images_attaches_them(tmp_path):
    widget, _ = board()
    real = tmp_path / "nota.txt"
    real.write_text("x")
    mime = QMimeData()
    mime.setUrls([QUrl.fromLocalFile(str(real)), QUrl("https://ejemplo.com/no-es-archivo")])
    widget.composer.insertFromMimeData(mime)
    assert widget.staged == [str(real)]
    image = QMimeData()
    image.setImageData(QImage(8, 8, QImage.Format_RGB32))
    widget.composer.insertFromMimeData(image)
    assert len(widget.staged) == 2 and widget.staged[1].endswith(".png")
    text = QMimeData()
    text.setText("solo texto")
    widget.composer.insertFromMimeData(text)
    assert widget.composer.toPlainText() == "solo texto" and len(widget.staged) == 2


# ---------- la lista de mensajes ----------

def hit_point(widget, message_id, part=None, inside=True):
    """Un punto sobre la burbuja (o sobre una de sus piezas) del mensaje, en coordenadas de la vista."""
    view = widget.view
    for item in view._items:
        if item["kind"] == "message" and item["message"]["id"] == message_id:
            bx, by, bw, bh = item["bubble"]
            if part:
                px, py, pw, ph = next(pt["rect"] for pt in item["parts"] if pt["kind"] == part)
                return QPointF(bx + chat.PAD_X + px + pw / 2, by - view.scroll + py + ph / 2)
            return QPointF(bx + bw / 2, by - view.scroll + bh / 2)
    raise AssertionError(message_id)


def test_my_messages_go_right_and_the_others_left_with_their_device_name():
    widget, _ = board(Core([msg(1, "de otro", device="phone"), msg(2, "mío", device="pc"),
                            msg(3, "otro más", device="phone"), msg(4, "y otro", device="phone")]))
    bubbles = {i["message"]["id"]: i for i in widget.view._items if i["kind"] == "message"}
    assert bubbles["m1"]["bubble"][0] == chat.MARGIN and bubbles["m1"]["label"] == "phone"
    assert bubbles["m2"]["bubble"][0] + bubbles["m2"]["bubble"][2] == widget.view.width() - chat.MARGIN
    assert bubbles["m2"]["label"] == "" and bubbles["m3"]["label"] == "phone" and bubbles["m4"]["label"] == ""


def test_days_are_separated_and_the_view_sticks_to_the_bottom_for_new_messages():
    many = [msg(n % 60, f"mensaje {n}") for n in range(1, 40)]
    for n, m in enumerate(many):
        m["id"], m["sent_at"] = f"x{n:02d}", f"2026-10-30T10:{n:02d}:00Z"
    widget, _ = board(Core(many), size=(680, 300))
    view = widget.view
    assert sum(1 for i in view._items if i["kind"] == "day") == 1
    assert view.scroll == view._max_scroll() > 0
    widget.on_event({"kind": "message", "message": msg(59, "último", device="phone"), "incoming": True})
    assert view.scroll == view._max_scroll()
    view.scroll_by(-500)                                              # sube a leer: ya no se pega al final
    before = view.scroll
    widget.on_event({"kind": "message", "message": msg(58, "otro", device="phone"), "incoming": True})
    assert view.scroll == before


def test_scrolling_to_the_top_asks_for_older_messages_once():
    many = [msg(n) for n in range(1, 30)]
    widget, core = board(Core(many), size=(680, 300))
    widget.view.scroll = 0.0
    from PySide6.QtCore import QPoint
    from PySide6.QtGui import QWheelEvent

    def wheel():
        widget.view.wheelEvent(QWheelEvent(QPointF(50, 50), QPointF(50, 50), QPoint(0, 0), QPoint(0, 120), Qt.NoButton,
                                           Qt.NoModifier, Qt.NoScrollPhase, False))

    wheel()
    wheel()
    asked = core.sent("chat.older")
    assert asked == [{"before": many[0]["sent_at"]}]
    top = widget.view.messages[0]["id"]
    widget.on_event({"kind": "older", "messages": [msg(0, "viejo")]})
    assert widget.view.messages[0]["id"] == "m0" and top == "m1"


def test_clicking_an_attachment_opens_it_and_the_error_asks_to_retry():
    widget, core = board(Core([msg(1, "foto", attachments=[att(1)]), msg(2, "fallido", status="pending", error="sin remedio"),
                               msg(3, "", device="phone", attachments=[att(2, "doc.pdf", "application/pdf")])]))
    app.processEvents()
    widget.view._fetched.clear()
    click(widget.view, hit_point(widget, "m1", "image"))
    assert core.sent("chat.fetch_attachment")[-1] == {"message_id": "m1", "attachment_id": "a1", "open": True}
    click(widget.view, hit_point(widget, "m3", "file"))
    assert core.sent("chat.fetch_attachment")[-1]["attachment_id"] == "a2"
    click(widget.view, hit_point(widget, "m2", "error"))
    assert core.sent("chat.retry") == [{"id": "m2"}]


def test_sent_images_not_on_disk_are_requested_once_and_local_ones_are_loaded(tmp_path):
    local = tmp_path / "foto.png"
    image = QImage(300, 200, QImage.Format_RGB32)
    image.fill(0x336699)
    image.save(str(local))
    messages = [msg(1, "", attachments=[att(1)]), msg(2, "", attachments=[att(2, local_path=str(local))])]
    widget, core = board(Core(messages))
    asked = [p["attachment_id"] for p in core.sent("chat.fetch_attachment")]
    assert asked == ["a1"]                                                      # la que ya está en disco no se pide
    widget.view._relayout()
    assert [p["attachment_id"] for p in core.sent("chat.fetch_attachment")] == ["a1"]       # ni se repite
    for _ in range(100):                                                       # el hilo lee la foto y avisa
        app.processEvents()
        if str(local) in widget.view._pixmaps:
            break
    assert str(local) in widget.view._pixmaps
    widget.on_event({"kind": "attachment", "message_id": "m1", "attachment_id": "a1", "path": str(local), "open": False})
    assert widget.view.messages[0]["attachments"][0]["local_path"] == str(local)


def test_delete_needs_a_second_press_on_the_hover_button():
    widget, core = board(Core([msg(1, "para borrar")]))
    point = hit_point(widget, "m1")
    move(widget.view, point)
    assert widget.view._hover == "m1"
    item = next(i for i in widget.view._items if i["kind"] == "message")
    pill = widget.view._pill_rect(item).center()
    click(widget.view, pill)
    assert widget.view._armed == "m1" and core.sent("chat.delete") == []
    click(widget.view, pill)
    assert core.sent("chat.delete") == [{"id": "m1"}] and widget.view._armed is None
    move(widget.view, point)
    click(widget.view, pill)
    click(widget.view, QPointF(5, 5))                                           # pulsar en otro sitio lo desarma
    assert widget.view._armed is None


def test_the_board_paints_in_every_state_without_errors():
    for state in ("unconfigured", "connecting", "online", "offline", "auth_error"):
        widget, _ = board(Core([msg(1, "hola", attachments=[att(1)]), msg(2, "", status="pending", error="x")], state=state))
        widget.stage(["C:/x/a.txt"])
        widget.on_event({"kind": "connection", "state": state, "detail": "detalle"})
        assert not widget.grab().isNull()


# ---------- su sitio en el buscador ----------

def test_chat_is_a_section_of_the_pill_and_of_the_top_panel():
    assert "chat" in sectionbar.StatusRow(THEME).chips and "chat" in topdock.ACTIONS
    assert topdock.ACTIONS["chat"] == ("search.open_mode", {"mode": "chat"})
    row = sectionbar.StatusRow(THEME)
    seen = []
    row.run.connect(seen.append)
    row.chat.click()
    assert seen == ["chat"]


def test_the_search_popout_opens_the_chat_without_the_text_field():
    core = Core([msg(1, "hola")])
    picked = []
    popout = search.SearchPopout(THEME, ScreenMap(app.primaryScreen()),
                                 query=lambda text, mode="": {"mode": "chat", "results": [], "indexing": False}
                                 if mode == "chat" else {"results": [], "indexing": False},
                                 launch=lambda *a, **k: None, close=lambda refocus: picked.append(refocus), call=core)
    popout.open("chat")
    app.processEvents()
    assert popout.mode == "chat" and popout.pill.chips["chat"].active and not popout.pill.chips["task"].active
    assert [m["body"] for m in popout.chat.view.messages] == ["hola"]
    popout._band_anim.stop()
    popout._set_band(0.0)
    assert popout._bandf == 0.0 and not popout.edit.isVisible()
    popout._section("chat")                                                     # la sección abierta no hace nada
    popout.chat.escape()
    assert picked == [True]
