"""La cápsula de lo que suena en el panel de abajo: ondas, botones y el alto del panel (Qt fuera de pantalla)."""
import struct
import time
from itertools import pairwise

from PySide6.QtCore import QByteArray, QEvent, QPointF, Qt
from PySide6.QtGui import QImage, QMouseEvent
from PySide6.QtMultimedia import QAudioBuffer, QAudioFormat
from PySide6.QtWidgets import QApplication

from kyora.ui import musicpill, quickdock
from kyora.ui.musicpage import level_of
from kyora.ui.theme import THEME
from kyora.ui.win import ScreenMap

app = QApplication.instance() or QApplication([])


def buffer(samples, kind, code):
    fmt = QAudioFormat()
    fmt.setSampleRate(44100)
    fmt.setChannelCount(1)
    fmt.setSampleFormat(kind)
    return QAudioBuffer(QByteArray(struct.pack(f"<{len(samples)}{code}", *samples)), fmt)


def make():
    return quickdock.QuickDock(THEME, ScreenMap(app.primaryScreen()), lambda *a, **k: None, lambda: {"hotkeys": {}})


def click(widget, point):
    event = QMouseEvent(QEvent.MouseButtonRelease, QPointF(point), QPointF(point), Qt.LeftButton, Qt.NoButton, Qt.NoModifier)
    widget.mouseReleaseEvent(event)


def pump(ms):
    end = time.monotonic() + ms / 1000
    while time.monotonic() < end:
        app.processEvents()


# ---------- el nivel del audio ----------

def test_level_of_measures_how_loud_a_chunk_is():
    fmt = QAudioFormat.SampleFormat
    assert level_of(buffer([0] * 64, fmt.Int16, "h")) == 0.0
    half = level_of(buffer([16384, -16384] * 32, fmt.Int16, "h"))
    assert abs(half - 0.5) < 0.01
    assert abs(level_of(buffer([0.25, -0.25] * 32, fmt.Float, "f")) - 0.25) < 0.01
    assert level_of(buffer([32767] * 64, fmt.Int16, "h")) <= 1.0


# ---------- las ondas ----------

def test_wave_averages_each_part_of_the_song_and_marks_where_it_is():
    wave = musicpill.Wave()
    assert wave.index() == 0 and wave.level(0) is None
    wave.moved(0, 100_000)                       # sin datos de duración aún no se guarda nada, con ella sí
    wave.add(0.2)
    wave.add(0.4)
    assert abs(wave.level(0) - 0.3) < 1e-9
    wave.moved(50_000, 100_000)
    assert wave.index() == musicpill.BARS // 2
    wave.add(0.1)
    assert wave.level(wave.index()) == 0.1
    assert abs(wave.reference() - 0.3) < 1e-9
    wave.reset()
    assert wave.level(0) is None and wave.dur == 0


def test_wave_ignores_levels_until_the_duration_is_known():
    wave = musicpill.Wave()
    wave.add(0.5)
    assert all(c == 0 for c in wave.count)


def test_clock_text():
    assert musicpill.clock(3_200) == "00:03" and musicpill.clock(25_900) == "00:25"
    assert musicpill.clock(605_000) == "10:05" and musicpill.clock(-5) == "00:00"


# ---------- la cápsula en el panel ----------

def test_the_panel_grows_with_music_and_has_its_buttons():
    dock = make()
    main = dock.main
    base = main.size[0]
    assert main.set_music({"title": "Una canción", "playing": True}) is True
    assert main.size[0] == base + musicpill.PILL_H + quickdock.GAP
    assert main.set_music({"title": "Una canción", "playing": False}) is False       # pausa: mismo alto
    main.setFixedSize(380, main.size[0] - 2 * quickdock.PAD)
    main.grab()
    names = {name for name, _ in main._hits}
    assert {"music_toggle", "music_stop", "clock", "wifi"} <= names
    sent = []
    main.music_control.connect(sent.append)
    hits = dict(main._hits)
    click(main, hits["music_toggle"].center())
    click(main, hits["music_stop"].center())
    assert sent == ["toggle", "stop"]


def test_the_pill_stays_painted_until_the_panel_has_shrunk():
    dock = make()
    main = dock.main
    main.set_music({"title": "x", "playing": True})
    assert main.set_music(None) is True and main._shown       # el panel aún se está encogiendo
    assert main.size[0] == quickdock.INFO_H + quickdock.DOCK_H + quickdock.GAP + 2 * quickdock.PAD
    main.release_music()
    assert not main._shown


def test_closed_panel_is_resized_at_once_and_open_one_animates():
    dock = make()
    base = dock.pages["main"].size[0]
    dock.on_playing({"title": "x", "playing": True})
    assert dock._target("main")[2] == base + dock.main.pill_h + quickdock.GAP and not dock._grow.running()
    dock.on_playing(None)
    assert not dock.main._shown                                # cerrado: no hay nada que animar
    dock.opened, dock.name = True, "main"                      # como si estuviera abierto
    dock._piece = dock._target("main")
    dock.on_playing({"title": "x", "playing": True})
    assert dock._grow.running()
    pump(quickdock.GROW_MS + 150)
    assert dock._piece == dock._target("main") and dock._piece[2] == base + dock.main.pill_h + quickdock.GAP
    dock.on_playing(None)
    pump(quickdock.GROW_MS + 150)
    assert dock._piece[2] == base and not dock.main._shown
    dock.opened = False


def test_the_title_slides_only_when_it_does_not_fit_and_plays():
    pill = musicpill.MusicPill(THEME)
    assert pill.set_state("Corta", True) is True and not pill.scrolling()
    assert pill.set_state("Corta", True) is False
    pill.set_state("Un nombre larguísimo de canción que no cabe en la cápsula ni de broma", True)
    assert pill.scrolling()
    pill.step()
    assert pill.offset == musicpill.STEP_PX
    pill.set_state(pill.title, False)
    assert not pill.scrolling()
    pill.set_state("Otra", True)
    assert pill.offset == 0 and pill.wave.dur == 0             # canción nueva: empieza de cero


def test_the_pill_follows_the_theme_when_the_wallpaper_changes():
    from kyora.ui.app import apply_theme

    dock = make()
    dock.main.set_music({"title": "x", "playing": True})
    before = dock.main.pill._stops()[0].name()
    new = THEME.with_palette({"gold": "#3366ff", "second": "#2244cc", "third": "#5588ff", "fourth": "#99bbff"})
    apply_theme(app, [dock], new)
    assert dock.main.pill.theme is new and dock.main.pill._stops()[0].name() != before


def test_stopping_the_music_keeps_a_hover_opened_panel_open():
    dock = make()
    dock.opened, dock.hover, dock.name = True, True, "main"        # abierto con el ratón, en la página principal
    dock._leave.start()
    dock.main.music_control.emit("toggle")                          # pausar no cambia el alto: sigue como estaba
    assert dock.hover
    dock.main.music_control.emit("stop")
    assert not dock.hover and not dock._leave.isActive()           # ya no se cierra al quitar el cursor
    dock.opened = False


# ---------- carátula, anterior y siguiente ----------

class FakeReply:
    def __init__(self, data, ok=True):
        self._data, self._ok = data, ok
        self.deleted = False

    def error(self):
        from PySide6.QtNetwork import QNetworkReply
        return QNetworkReply.NetworkError.NoError if self._ok else QNetworkReply.NetworkError.HostNotFoundError

    def readAll(self):
        return self._data

    def deleteLater(self):
        self.deleted = True


def jpeg_bytes(width, height):
    from PySide6.QtCore import QBuffer, QIODevice
    from PySide6.QtGui import QColor

    image = QImage(width, height, QImage.Format_RGB32)
    image.fill(QColor("#336699"))
    buf = QBuffer()
    buf.open(QIODevice.WriteOnly)
    image.save(buf, "PNG")
    return buf.data()


def test_covers_are_cropped_to_a_square_cached_and_announced():
    covers = musicpill.Covers()
    seen = []
    covers.ready.connect(lambda vid, image: seen.append((vid, image.width(), image.height())))
    covers._asked.add("abc")
    covers._done(FakeReply(jpeg_bytes(320, 180)), "abc")
    assert seen == [("abc", musicpill.COVER_PX, musicpill.COVER_PX)]
    assert covers.get("abc").width() == musicpill.COVER_PX and "abc" not in covers._asked      # ya está: no vuelve a pedirla
    covers._done(FakeReply(b"", ok=False), "zzz")                                              # sin red: nada, sin fallar
    assert len(seen) == 1 and covers.get("") is None


def test_covers_cache_keeps_only_the_latest():
    covers = musicpill.Covers()
    for n in range(musicpill.COVER_CACHE + 3):
        covers._done(FakeReply(jpeg_bytes(40, 40)), f"v{n}")
    assert len(covers._cache) == musicpill.COVER_CACHE and "v0" not in covers._cache and "v14" in covers._cache


def test_a_cover_only_lands_on_the_song_that_asked_for_it(monkeypatch):
    dock = make()
    main = dock.main
    monkeypatch.setattr(main.covers, "get", lambda vid: None)
    main.set_music({"title": "A", "playing": True, "id": "a", "next": True})
    assert main.pill.cover is None
    image = QImage(20, 20, QImage.Format_RGB32)
    main._cover_ready("otra", image)
    assert main.pill.cover is None
    main._cover_ready("a", image)
    assert main.pill.cover is not None
    main.set_music({"title": "B", "playing": True, "id": "b", "next": False})      # otra canción: sin carátula hasta que llegue
    assert main.pill.cover is None


def test_the_whole_panel_fits_in_the_piece_with_music():
    """Con música, la página principal no puede pedir más alto que la pieza (si no, arriba se corta)."""
    dock = make()
    dock.main.pill_h = dock._pill_fit()
    base = quickdock.INFO_H + quickdock.DOCK_H + quickdock.GAP + 2 * quickdock.PAD
    assert dock.main.pill_h == musicpill.PILL_H                                    # en esta pantalla cabe con su alto normal
    assert base + dock.main.pill_h + quickdock.GAP <= dock.depth


def test_the_card_shrinks_when_the_piece_or_the_screen_is_short(monkeypatch):
    dock = make()
    base = quickdock.INFO_H + quickdock.DOCK_H + quickdock.GAP + 2 * quickdock.PAD
    monkeypatch.setattr(dock, "depth", base + quickdock.GAP + 300)
    assert dock._pill_fit() == 300
    monkeypatch.setattr(dock, "depth", base)                                       # ni de broma cabe: el mínimo
    assert dock._pill_fit() == musicpill.MIN_H
    dock.on_playing({"title": "x", "playing": True, "id": "i"})
    assert dock.main.pill_h == musicpill.MIN_H
    box = quickdock.QRectF(0, 0, 380, musicpill.MIN_H)                              # y con el mínimo todo sigue dentro de la pantalla
    pill = musicpill.MusicPill(THEME)
    pill.set_state("x", True, "id", has_next=True)
    rects = pill.layout(box)
    assert all(rects["screen"].contains(rects[n]) for n in ("title", "time", "wave"))
    assert rects["title"].bottom() <= rects["time"].top() and rects["screen"].bottom() <= musicpill.MIN_H


def test_every_button_is_on_the_screen_keys_in_the_middle_and_arrows_at_the_sides():
    pill = musicpill.MusicPill(THEME)
    pill.set_state("x", True, "id", has_next=True)
    for height in (musicpill.PILL_H, musicpill.MIN_H):
        box = quickdock.QRectF(0, 0, 380, height)
        assert [n for n, _ in pill.hits(box)] == ["music_toggle", "music_download", "music_stop", "music_prev", "music_next"]
        rects = dict(pill.hits(box))
        layout = pill.layout(box)
        screen = layout["screen"]
        assert all(screen.contains(r) for r in rects.values())                           # todo cae dentro de la carátula
        keys = [rects[n] for n in ("music_toggle", "music_download", "music_stop")]
        assert all(a.right() < b.left() for a, b in pairwise(keys))                      # en fila, de izquierda a derecha
        assert len({round(r.center().y(), 1) for r in keys}) == 1 and len({round(r.width(), 1) for r in keys}) == 1
        prev, nxt = rects["music_prev"], rects["music_next"]                             # las flechas, a cada lado de las teclas
        assert prev.right() < keys[0].left() and keys[-1].right() < nxt.left()
        assert abs(prev.center().y() - keys[0].center().y()) < 1
        for button in [*keys, prev, nxt]:                                                # y sin pisar el nombre, el tiempo ni las ondas
            assert not any(button.intersects(layout[n]) for n in ("title", "time", "wave")), height
    pill.set_state("x", True, "id", has_next=False)
    assert "music_next" not in [n for n, _ in pill.hits(box)]


def test_screen_holds_waves_time_and_title_with_no_frame_of_its_own():
    pill = musicpill.MusicPill(THEME)
    pill.set_state("Una canción", True, "id")
    rects = pill.layout(quickdock.QRectF(0, 0, 380, musicpill.PILL_H))
    for name in ("wave", "time", "title"):
        assert rects["screen"].contains(rects[name]), name
    assert rects["title"].top() < rects["time"].top() and rects["time"].bottom() <= rects["wave"].top()
    assert rects["title"].width() == musicpill.title_width()
    assert rects["screen"].left() == musicpill.SIDE                                      # pegada al borde del cuerpo: sin marco negro


def paint_pill(pill, over, hover=None):
    from PySide6.QtGui import QColor, QPainter, QPixmap

    image = QPixmap(380, musicpill.PILL_H)
    image.fill(QColor("#000000"))
    p = QPainter(image)
    pill.paint(p, quickdock.QRectF(0, 0, 380, musicpill.PILL_H), hover, over)
    p.end()
    return image.toImage()


def test_the_arrows_only_show_while_the_cursor_is_over_the_screen():
    pill = musicpill.MusicPill(THEME)
    pill.set_state("x", True, "id", has_next=True)
    layout = pill.layout(quickdock.QRectF(0, 0, 380, musicpill.PILL_H))
    left, right = layout["prev"].center().toPoint(), layout["next"].center().toPoint()
    hidden, shown = paint_pill(pill, over=False), paint_pill(pill, over=True)
    assert hidden.pixelColor(left) != shown.pixelColor(left) and hidden.pixelColor(right) != shown.pixelColor(right)
    assert paint_pill(pill, over=False, hover="music_next") != hidden                   # bajo una flecha siempre se ve
    pill.set_state("x", True, "id", has_next=False)
    assert paint_pill(pill, over=True).pixelColor(right) == hidden.pixelColor(right)    # sin siguiente, no hay flecha


def test_the_download_key_shows_how_the_download_goes():
    pill = musicpill.MusicPill(THEME)
    pill.set_state("x", True, "id", has_next=True)
    key = pill.layout(quickdock.QRectF(0, 0, 380, musicpill.PILL_H))["download"].center().toPoint()
    seen = {}
    for state in ("", "doing", "done", "error"):
        pill.set_state("x", True, "id", has_next=True, download=state)
        seen[state] = paint_pill(pill, over=True).copy(key.x() - 16, key.y() - 16, 32, 32)
    assert len({image for image in map(lambda i: i.constBits().tobytes(), seen.values())}) == 4     # los cuatro se ven distintos


def test_the_screen_follows_the_cursor_and_forgets_it_on_leave():
    dock = make()
    main = dock.main
    main.set_music({"title": "x", "playing": True, "id": "i", "next": True})
    main.setFixedSize(380, main.size[0] - 2 * quickdock.PAD)
    main.grab()
    screen = main.pill.layout(main._pill_rect())["screen"]
    spot = QPointF(screen.center().x(), screen.top() + 20)                              # el nombre: en la pantalla, pero no es un botón
    move = QMouseEvent(QEvent.MouseMove, spot, spot, Qt.NoButton, Qt.NoButton, Qt.NoModifier)
    main.mouseMoveEvent(move)
    assert main._over_screen
    assert main._hover is None                                                           # el centro de la pantalla no es ningún botón
    key = dict(main._hits)["music_toggle"].center()                                      # sobre una tecla (que está en la pantalla)
    main.mouseMoveEvent(QMouseEvent(QEvent.MouseMove, QPointF(key), QPointF(key), Qt.NoButton, Qt.NoButton, Qt.NoModifier))
    assert main._over_screen and main._hover == "music_toggle"
    away = QPointF(5, main.height() - 5)                                                 # abajo: los iconos, no la tarjeta
    main.mouseMoveEvent(QMouseEvent(QEvent.MouseMove, away, away, Qt.NoButton, Qt.NoButton, Qt.NoModifier))
    assert not main._over_screen
    main.mouseMoveEvent(move)
    main.leaveEvent(None)
    assert not main._over_screen


def test_the_screen_is_painted_once_and_reused_until_something_changes():
    from PySide6.QtGui import QPixmap

    pill = musicpill.MusicPill(THEME)
    pill.set_state("x", True, "id", has_next=True)
    paint_pill(pill, over=False)
    first = pill._baked[1]
    paint_pill(pill, over=True)
    assert pill._baked[1] is first                                                       # solo cambió lo de encima
    pill.cover = QPixmap(40, 40)
    paint_pill(pill, over=False)
    assert pill._baked[1] is not first                                                   # llegó la carátula: se rehace


def test_main_page_sends_prev_and_next():
    dock = make()
    main = dock.main
    main.set_music({"title": "x", "playing": True, "id": "i", "next": True})
    main.setFixedSize(380, main.size[0] - 2 * quickdock.PAD)
    main.grab()
    sent = []
    main.music_control.connect(sent.append)
    hits = dict(main._hits)
    click(main, hits["music_prev"].center())
    click(main, hits["music_next"].center())
    assert sent == ["prev", "next"]


def make_page(count=3, at=1):
    from kyora.ui.musicpage import MusicPage

    page = MusicPage(THEME, lambda *a, **k: None)
    page.queue = [{"id": f"s{n}", "title": f"t{n}"} for n in range(count)]
    page.at, page.sound = at, "playing"
    started = []
    page._start = lambda: started.append(page.at)
    return page, started


class FakePlayer:
    def __init__(self, position):
        self.sought = []
        self.player = type("P", (), {"position": staticmethod(lambda: position)})()

    def seek(self, ms):
        self.sought.append(ms)


def test_next_and_previous_move_through_the_queue():
    page, started = make_page()
    page.next_track()
    assert page.at == 2 and started == [2]
    page.next_track()                                       # era la última: no pasa nada
    assert page.at == 2 and started == [2]
    page.previous_track()
    assert page.at == 1 and started == [2, 1]
    page.sound = ""
    page.next_track()
    page.previous_track()
    assert started == [2, 1]                                # sin nada sonando, tampoco


def test_previous_restarts_the_song_after_a_few_seconds_or_on_the_first_one():
    page, started = make_page(at=2)
    page.player = FakePlayer(position=9000)
    page.previous_track()
    assert page.player.sought == [0] and page.at == 2 and not started
    page.player = FakePlayer(position=500)
    page.previous_track()
    assert page.at == 1 and started == [1]
    page.at = 0
    page.player = FakePlayer(position=500)
    page.previous_track()
    assert page.player.sought == [0] and page.at == 0


def test_announce_carries_the_id_and_whether_there_is_a_next_song():
    page, _ = make_page(at=2)
    seen = []
    page.playing_changed.connect(seen.append)
    page._announce()
    assert seen[-1] == {"title": "t2", "playing": True, "id": "s2", "next": False, "download": ""}
    page.at = 0
    page._announce()
    assert seen[-1]["next"] is True
