"""Página de Música del panel de arriba (Win+M): tus listas de YouTube y, al abrir una, sus canciones para bajarlas en MP3.

Las listas y las descargas tardan: se piden al núcleo con `invoke` (fuera del hilo de Qt) y las respuestas llegan por
`on_result` (la señal music_result del puente). Enter abre una lista o reproduce la canción (en streaming, sin bajarla,
y al acabar sigue con la siguiente); D la manda (pregunta a quién: «Yo» o un pasante, y nada se guarda en la PC);
Espacio pausa; Esc / ← vuelve a las listas.
"""
import array
import math

from PySide6.QtCore import QObject, QPointF, QRectF, Qt, QUrl, Signal
from PySide6.QtGui import QColor, QPainter
from PySide6.QtWidgets import (
    QHBoxLayout,
    QLabel,
    QPlainTextEdit,
    QPushButton,
    QVBoxLayout,
    QWidget,
)

from kyora.ui import glyphs
from kyora.ui.bar import font
from kyora.ui.dock import DockPage
from kyora.ui.search import _css
from kyora.ui.status_icon import paint_status

ROW_H = 40
ICON_R = 9
ACTION_W = 44  # la zona de la derecha: el botón de bajar o el porcentaje
STATUS_OF = {"done": "done", "doing": "doing", "sending": "doing", "queued": "open", "error": "pending",
             "pending": "pending"}


def duration_text(seconds):
    if not seconds:
        return ""
    return f"{seconds // 60}:{seconds % 60:02d}"


class MusicList(QWidget):
    """Las listas (mode "playlists") o las canciones (mode "songs"), dibujadas a mano."""

    opened = Signal(int)  # una lista
    play = Signal(int)  # una canción: reproducirla
    download = Signal(int)  # una canción: bajarla
    toggle = Signal()  # Espacio: pausa o sigue
    back = Signal()

    def __init__(self, theme):
        super().__init__()
        self.theme = theme
        self.mode = "playlists"
        self.items = []
        self.empty = ""
        self.selected = -1
        self._hover = -1
        self._scroll = 0
        self.setMouseTracking(True)
        self.setFocusPolicy(Qt.StrongFocus)

    def set_items(self, mode, items, empty=""):
        keep = self.items[self.selected]["id"] if 0 <= self.selected < len(self.items) and mode == self.mode else None
        if mode != self.mode:
            self._scroll = 0
        self.mode, self.items, self.empty = mode, items, empty
        ids = [i["id"] for i in items]
        self.selected = ids.index(keep) if keep in ids else (0 if items else -1)
        self._scroll = min(self._scroll, self._max_scroll())
        self.update()

    def set_empty(self, text):
        self.items, self.empty, self.selected = [], text, -1
        self.update()

    def set_playing(self, video_id, state):
        """Marca la canción que suena ("loading", "playing" o "paused"); a las demás las desmarca."""
        for item in self.items:
            item["play"] = state if item["id"] == video_id else ""
        self.update()

    def update_song(self, video_id, **fields):
        for item in self.items:
            if item["id"] == video_id:
                item.update(fields)
                self.update()
                return

    def _max_scroll(self):
        return max(len(self.items) * ROW_H - self.height(), 0)

    def _row_at(self, y):
        i = int((y + self._scroll) // ROW_H)
        return i if 0 <= i < len(self.items) else -1

    def _follow(self):
        top = self.selected * ROW_H
        self._scroll = min(max(self._scroll, top + ROW_H - self.height()), top)
        self._scroll = min(max(self._scroll, 0), self._max_scroll())

    # ---------- teclado y ratón ----------

    def keyPressEvent(self, event):
        key = event.key()
        if key in (Qt.Key_Up, Qt.Key_Down) and self.items:
            self.selected = min(max(self.selected + (1 if key == Qt.Key_Down else -1), 0), len(self.items) - 1)
            self._follow()
            self.update()
        elif key in (Qt.Key_Return, Qt.Key_Enter) and self.selected >= 0:
            self._activate(self.selected)
        elif key == Qt.Key_D and self.mode == "songs" and self.selected >= 0:
            self._download(self.selected)
        elif key == Qt.Key_Space and self.mode == "songs":
            self.toggle.emit()
        elif self.mode == "songs" and key in (Qt.Key_Escape, Qt.Key_Left, Qt.Key_Backspace):
            self.back.emit()
        else:
            super().keyPressEvent(event)

    def _activate(self, index):
        if self.mode == "playlists":
            self.opened.emit(index)
        else:
            self.play.emit(index)

    def _download(self, index):
        if self.items[index]["state"] not in ("doing", "queued", "sending"):  # una ya enviada se puede mandar a otra persona
            self.download.emit(index)

    def mouseMoveEvent(self, event):
        hover = self._row_at(event.position().y())
        if hover != self._hover:
            self._hover = hover
            self.update()

    def leaveEvent(self, _):
        self._hover = -1
        self.update()

    def mousePressEvent(self, event):
        index = self._row_at(event.position().y())
        if event.button() != Qt.LeftButton or index < 0:
            return
        self.selected = index
        self.update()
        if self.mode == "playlists" or event.position().x() < self.width() - ACTION_W:
            self._activate(index)
        else:
            self._download(index)

    def wheelEvent(self, event):
        self._scroll = min(max(self._scroll - event.angleDelta().y() * 0.5, 0), self._max_scroll())
        self.update()

    def resizeEvent(self, _):
        self._scroll = min(self._scroll, self._max_scroll())

    # ---------- pintura ----------

    def paintEvent(self, _):
        t = self.theme
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        if not self.items:
            p.setPen(QColor(t.dim))
            p.setFont(font(t, t.font_px))
            p.drawText(QRectF(self.rect()).adjusted(8, 8, -8, -8), Qt.AlignTop | Qt.AlignHCenter | Qt.TextWordWrap,
                       self.empty)
            return
        p.setClipRect(self.rect())
        first = int(self._scroll // ROW_H)
        for i in range(first, min(len(self.items), first + self.height() // ROW_H + 2)):
            self._paint_row(p, i, QRectF(0, i * ROW_H - self._scroll, self.width(), ROW_H))

    def _paint_row(self, p, i, row):
        t, item = self.theme, self.items[i]
        if i in (self.selected, self._hover):
            p.setPen(Qt.NoPen)
            p.setBrush(QColor(t.gold_soft if i == self.selected and self.hasFocus() else t.hover))
            p.drawRoundedRect(row.adjusted(2, 1, -2, -1), 8, 8)
        mid = row.center().y()
        left = 14.0
        if self.mode == "songs":
            paint_status(p, QPointF(left + ICON_R, mid), ICON_R, STATUS_OF[item["state"]], t)
            left += 2 * ICON_R + 12
        right = self.width() - 12
        if self.mode == "songs":
            self._paint_action(p, item, QRectF(right - ACTION_W + 4, row.top(), ACTION_W, ROW_H))
            right -= ACTION_W
        sub = "…" if item.get("play") == "loading" else item.get("sub", "")
        if sub:
            p.setPen(QColor(t.dim))
            p.setFont(font(t, t.small_px))
            p.drawText(QRectF(right - 70, row.top(), 70, ROW_H), Qt.AlignVCenter | Qt.AlignRight, sub)
            right -= 76
        sound = item.get("play", "")
        color = QColor(t.warn) if item.get("state") == "error" else QColor(t.gold if sound else t.ink)
        p.setPen(color)
        p.setFont(font(t, t.font_px + 1, bold=item.get("state") == "doing" or bool(sound)))
        name = p.fontMetrics().elidedText(item["title"], Qt.ElideRight, int(right - left))
        p.drawText(QRectF(left, row.top(), right - left, ROW_H), Qt.AlignVCenter | Qt.AlignLeft, name)

    def _paint_action(self, p, item, box):
        t, state = self.theme, item["state"]
        if state == "doing":
            p.setPen(QColor(t.gold))
            p.setFont(font(t, t.small_px, bold=True))
            p.drawText(box, Qt.AlignVCenter | Qt.AlignRight, f"{item.get('percent', 0)}%")
        elif state == "sending":
            p.setPen(QColor(t.gold))
            p.setFont(font(t, t.small_px, bold=True))
            p.drawText(box, Qt.AlignVCenter | Qt.AlignRight, "…")
        elif state in ("pending", "error", "done"):
            p.setPen(glyphs.pen(QColor(t.warn if state == "error" else t.dim), 1.4))
            p.setBrush(Qt.NoBrush)
            glyphs.download(p, QRectF(box.right() - 24, box.center().y() - 9, 18, 18))


RESTART_MS = 3000  # "anterior" después de tanto tiempo vuelve al principio de la misma canción
LEVEL_STRIDE = 3  # del audio de cada trozo solo se mira una muestra de cada tantas: basta para saber lo fuerte que suena
SAMPLE_KINDS = {"Int16": ("h", 32768.0, 0), "Int32": ("i", 2147483648.0, 0), "Float": ("f", 1.0, 0), "UInt8": ("B", 128.0, 128)}


def level_of(buffer):
    """Lo fuerte que suena un trozo de audio de QtMultimedia: de 0 a 1 (valor cuadrático medio). 0 si no se sabe leer."""
    kind = SAMPLE_KINDS.get(buffer.format().sampleFormat().name)
    if kind is None or not buffer.isValid():
        return 0.0
    code, scale, zero = kind
    samples = array.array(code)
    raw = bytes(buffer.constData())
    samples.frombytes(raw[: len(raw) // samples.itemsize * samples.itemsize])
    picked = samples[::LEVEL_STRIDE]
    if not picked:
        return 0.0
    return min(math.sqrt(sum((s - zero) * (s - zero) for s in picked) / len(picked)) / scale, 1.0)


def _time(ms):
    s = max(ms, 0) // 1000
    return f"{s // 60}:{s % 60:02d}"


class Player(QObject):
    """El reproductor (QtMultimedia se carga la primera vez que suena algo: tarda en importarse)."""

    state_changed = Signal()
    finished = Signal()  # la canción llegó al final
    failed = Signal(str)
    moved = Signal(int, int)  # (posición, duración) en ms
    level = Signal(float)  # lo fuerte que suena lo que sale ahora (0 a 1): las ondas de la cápsula

    def __init__(self):
        super().__init__()
        from PySide6.QtMultimedia import (  # PySide6-Addons
            QAudioBufferOutput,
            QAudioOutput,
            QMediaPlayer,
        )

        self._qt = QMediaPlayer
        self.player = QMediaPlayer(self)
        self.audio = QAudioOutput(self)
        self.player.setAudioOutput(self.audio)
        self.tap = QAudioBufferOutput(self)  # copia del audio que se reproduce, solo para medirlo
        self.player.setAudioBufferOutput(self.tap)
        self.tap.audioBufferReceived.connect(lambda buffer: self.level.emit(level_of(buffer)))
        self.player.playbackStateChanged.connect(lambda _: self.state_changed.emit())
        self.player.positionChanged.connect(lambda ms: self.moved.emit(ms, self.player.duration()))
        self.player.durationChanged.connect(lambda ms: self.moved.emit(self.player.position(), ms))
        self.player.mediaStatusChanged.connect(self._status)
        self.player.errorOccurred.connect(lambda _, text: self.failed.emit(text))

    def _status(self, status):
        if status == self._qt.EndOfMedia:
            self.finished.emit()

    def play(self, source):
        self.player.setSource(QUrl(source) if "://" in source else QUrl.fromLocalFile(source))
        self.player.play()

    def toggle(self):
        if self.is_playing():
            self.player.pause()
        else:
            self.player.play()

    def is_playing(self):
        return self.player.playbackState() == self._qt.PlayingState

    def seek(self, ms):
        self.player.setPosition(ms)


class RecipientPanel(QWidget):
    """«¿A quién se la mando?»: tú («Yo») y los pasantes registrados. Enter o clic elige; Esc cancela. Sustituye a la lista
    mientras está abierto (el mismo patrón que CookiePanel)."""

    chosen = Signal(int)
    cancelled = Signal()

    def __init__(self, theme):
        super().__init__()
        self.theme = theme
        self.items = []  # [{id, name, me}]
        self.message = "Cargando…"
        self.warn = False
        self.selected = 0
        self._hover = -1
        self.prompt = ""
        self.setMouseTracking(True)
        self.setFocusPolicy(Qt.StrongFocus)

    def ask(self, prompt):
        self.prompt, self.items, self.message, self.warn, self.selected = prompt, [], "Cargando…", False, 0
        self.update()

    def set_people(self, people):
        self.items, self.message, self.warn = list(people), "", False
        self.selected = 0
        self.update()

    def set_error(self, text):
        self.items, self.message, self.warn = [], text, True
        self.update()

    def _top(self):
        return 30  # sitio para la pregunta

    def _row_at(self, y):
        i = int((y - self._top()) // ROW_H)
        return i if 0 <= i < len(self.items) else -1

    def keyPressEvent(self, event):
        key = event.key()
        if key in (Qt.Key_Up, Qt.Key_Down) and self.items:
            self.selected = min(max(self.selected + (1 if key == Qt.Key_Down else -1), 0), len(self.items) - 1)
            self.update()
        elif key in (Qt.Key_Return, Qt.Key_Enter) and 0 <= self.selected < len(self.items):
            self.chosen.emit(self.selected)
        elif key in (Qt.Key_Escape, Qt.Key_Left, Qt.Key_Backspace):
            self.cancelled.emit()
        else:
            super().keyPressEvent(event)

    def mouseMoveEvent(self, event):
        hover = self._row_at(event.position().y())
        if hover != self._hover:
            self._hover = hover
            self.update()

    def leaveEvent(self, _):
        self._hover = -1
        self.update()

    def mousePressEvent(self, event):
        index = self._row_at(event.position().y())
        if event.button() == Qt.LeftButton and index >= 0:
            self.selected = index
            self.chosen.emit(index)

    def paintEvent(self, _):
        t = self.theme
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        p.setPen(QColor(t.dim))
        p.setFont(font(t, t.font_px))
        p.drawText(QRectF(14, 0, self.width() - 28, self._top()), Qt.AlignVCenter | Qt.AlignLeft, self.prompt)
        if not self.items:
            p.setPen(QColor(t.warn if self.warn else t.dim))
            p.drawText(QRectF(self.rect()).adjusted(12, self._top() + 6, -12, -8), Qt.AlignTop | Qt.AlignHCenter | Qt.TextWordWrap,
                       self.message + ("\n\nEsc para volver" if self.warn else ""))
            return
        for i, person in enumerate(self.items):
            row = QRectF(0, self._top() + i * ROW_H, self.width(), ROW_H)
            if i in (self.selected, self._hover):
                p.setPen(Qt.NoPen)
                p.setBrush(QColor(t.gold_soft if i == self.selected and self.hasFocus() else t.hover))
                p.drawRoundedRect(row.adjusted(2, 1, -2, -1), 8, 8)
            p.setPen(QColor(t.gold if person.get("me") else t.ink))
            p.setFont(font(t, t.font_px + 1, bold=bool(person.get("me"))))
            p.drawText(row.adjusted(16, 0, -12, 0), Qt.AlignVCenter | Qt.AlignLeft, person["name"])


class CookiePanel(QWidget):
    """Cuando YouTube pide cookies: en el centro, un botón para agregarlas; al pulsarlo se pega ahí el contenido del
    cookies.txt y se guarda (sin abrir el archivo a mano)."""

    save = Signal(str)

    def __init__(self, theme):
        super().__init__()
        self.theme = theme
        t = theme
        self.message = QLabel("YouTube necesita cookies nuevas")
        self.message.setAlignment(Qt.AlignCenter)
        self.message.setFont(font(t, t.font_px))
        self.message.setStyleSheet(f"color: {t.dim};")
        self.add = QPushButton("Agregar cookies")
        self.paste = QPlainTextEdit()
        self.paste.setPlaceholderText("Pega aquí el contenido de tu cookies.txt")
        self.paste.setStyleSheet(
            f"QPlainTextEdit {{ background: {t.frame_dark}; color: {t.ink}; border: 1px solid {_css(t.line)};"
            f" border-radius: 10px; padding: 8px; font: {t.small_px}px '{t.mono_family}'; }}"
            f"QPlainTextEdit:focus {{ border-color: {t.gold}; }}")
        self.accept = QPushButton("Guardar")
        self.cancel = QPushButton("Cancelar")
        for button in (self.add, self.accept, self.cancel):
            button.setCursor(Qt.PointingHandCursor)
            button.setFocusPolicy(Qt.NoFocus)
        self.add.clicked.connect(self._open)
        self.cancel.clicked.connect(self._close)
        self.accept.clicked.connect(lambda: self.save.emit(self.paste.toPlainText()))
        row = QHBoxLayout()
        row.addStretch(1)
        row.addWidget(self.cancel)
        row.addWidget(self.accept)
        self.form = QWidget()
        form = QVBoxLayout(self.form)
        form.setContentsMargins(0, 0, 0, 0)
        form.addWidget(self.paste, 1)
        form.addLayout(row)
        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.addStretch(1)
        layout.addWidget(self.message)
        layout.addWidget(self.add, 0, Qt.AlignHCenter)
        layout.addWidget(self.form, 4)
        layout.addStretch(1)
        self._close()

    def say(self, text):
        self.message.setText(text)

    def _open(self):
        self.add.hide()
        self.form.show()
        self.paste.setFocus()

    def _close(self):
        self.paste.clear()
        self.form.hide()
        self.add.show()


class MusicPage(DockPage):
    size = (440, 400)
    playing_changed = Signal(object)  # {title, playing, id, next} de lo que suena, o None: la cápsula del panel de abajo lo enseña
    progress_changed = Signal(int, int)  # (posición, duración) en ms de lo que suena
    level_changed = Signal(float)  # lo fuerte que suena ahora (0 a 1)

    def __init__(self, theme, invoke):
        super().__init__()
        self.theme = theme
        self._invoke = invoke
        self.playlist = None  # la lista abierta: {id, title}
        self.playlists = []
        self.songs = []
        self.ffmpeg = True
        self.running = False
        self.player = None  # se crea al reproducir la primera canción
        self.queue = []  # las canciones de la lista que suena, en orden
        self.queue_playlist = None  # de qué lista son (puede que ya estés mirando otra)
        self.at = -1  # cuál de ellas
        self.want = None  # la que se está pidiendo (por si el usuario cambia antes de que llegue)
        self.last_recipient = {"id": None, "name": "Yo", "me": True}  # a quien se mandó la última vez (la cápsula usa este)
        self.asking = None  # las canciones por mandar mientras se elige a quién: lista de ids, o [] = todas las pendientes
        self.sound = ""  # "loading", "playing" o "paused" de la que va en `self.at`
        t = theme
        self.title = QLabel("Música")
        self.title.setFont(font(t, t.font_px + 3, bold=True))
        self.back = QPushButton("Listas")
        self.download = QPushButton("Descargar")
        self.stop = QPushButton("Detener")
        for button in (self.back, self.download, self.stop):
            button.setCursor(Qt.PointingHandCursor)
            button.setFocusPolicy(Qt.NoFocus)
        self.back.clicked.connect(self._back)
        self.download.clicked.connect(lambda: self._download(None))
        self.stop.clicked.connect(lambda: self._invoke("music.cancel"))
        head = QHBoxLayout()
        head.addWidget(self.title, 1)
        head.addWidget(self.back)
        head.addWidget(self.download)
        head.addWidget(self.stop)
        self.note = QLabel("")
        self.note.setWordWrap(True)
        self.note.setFont(font(t, t.font_px))
        self.note.setStyleSheet(f"color: {t.dim};")
        self.install = QPushButton("Instalar FFmpeg")
        self.install.setCursor(Qt.PointingHandCursor)
        self.install.setFocusPolicy(Qt.NoFocus)
        self.install.clicked.connect(lambda: self._invoke("music.install_ffmpeg"))
        self.list = MusicList(theme)
        self.list.opened.connect(self._open)
        self.list.play.connect(self._play)
        self.list.download.connect(lambda i: self._download([self.songs[i]["id"]]))
        self.recipients = RecipientPanel(theme)
        self.recipients.chosen.connect(self._recipient_chosen)
        self.recipients.cancelled.connect(self._close_recipients)
        self.recipients.hide()
        self.list.toggle.connect(self._toggle)
        self.list.back.connect(self._back)
        self.cookies = CookiePanel(theme)
        self.cookies.save.connect(lambda text: self._invoke("music.save_cookies", text=text))
        self.cookies.hide()
        layout = QVBoxLayout(self)
        layout.setContentsMargins(2, 0, 2, 0)
        layout.addLayout(head)
        layout.addWidget(self.note)
        layout.addWidget(self.install)
        layout.addWidget(self.list, 1)
        layout.addWidget(self.cookies, 1)
        layout.addWidget(self.recipients, 1)
        self.setStyleSheet(
            f"QWidget {{ background: transparent; color: {t.ink}; }}"
            f"QPushButton {{ background: {_css(t.hover)}; border: 1px solid {_css(t.line)}; border-radius: 8px;"
            f" padding: 6px 12px; font: {t.font_px}px '{t.font_family}'; }}"
            f"QPushButton:hover {{ border-color: {_css(t.gold_line)}; }}"
            f"QPushButton:disabled {{ color: {_css(t.dim)}; }}"
        )
        self._sync()

    def focus_first(self):
        (self.recipients if self.recipients.isVisible() else self.list).setFocus()

    # ---------- qué se ve ----------

    def _sync(self):
        songs = self.playlist is not None
        self.title.setText(self.playlist["title"] if songs else "Música")
        self.back.setVisible(songs)
        self.download.setVisible(songs)
        self.stop.setVisible(songs and self.running)
        self.download.setEnabled(self.ffmpeg and any(s["state"] in ("pending", "error") for s in self.songs))
        pending = sum(s["state"] in ("pending", "error") for s in self.songs)
        failed = any(s["state"] == "error" for s in self.songs)
        self.download.setText(("Reintentar" if failed else "Descargar") + (f" ({pending})" if pending else ""))
        self.install.setVisible(not self.ffmpeg)

    def _say(self, text, warn=False):
        self.note.setStyleSheet(f"color: {self.theme.warn if warn else self.theme.dim};")
        self.note.setText(text)

    # ---------- acciones del usuario ----------

    def _ask_cookies(self, text):
        """YouTube no dejó entrar: en lugar de un aviso, el botón para agregar cookies ocupa el centro."""
        self._say("")
        self.cookies.say(text)
        self.list.hide()
        self.cookies.show()

    def _cookies_done(self):
        self.cookies.hide()
        self.list.show()

    def activate(self):
        self._say("")
        if self.playlist is None:
            self.list.set_empty("Cargando tus listas de YouTube…")
        self._invoke("music.playlists")

    def _open(self, index):
        self.playlist = self.playlists[index]
        self.songs = []
        self.running = False
        self.list.set_items("songs", [])
        self.list.set_empty("Cargando canciones…")
        self._say("")
        self._sync()
        self._invoke("music.songs", playlist=self.playlist["id"])

    def _back(self):
        self._close_recipients(focus=False)
        self.playlist = None
        self.songs = []
        self._say("")
        self.list.set_items("playlists", self._playlist_rows(), "No hay listas")
        self._sync()
        self.list.setFocus()

    def _download(self, ids):
        """«Descargar»: pregunta a quién se manda (no se guarda nada en la PC). `ids` vacío = todas las pendientes."""
        if self.playlist is None:
            return
        self._say("")
        self.asking = list(ids) if ids else []
        count = len(ids) if ids else sum(s["state"] in ("pending", "error") for s in self.songs)
        self.recipients.ask("¿A quién se la mando?" if count == 1 else f"¿A quién se las mando? ({count})")
        self.list.hide()
        self.recipients.show()
        self.recipients.setFocus()
        self._invoke("music.recipients")

    def _close_recipients(self, focus=True):
        self.asking = None
        self.recipients.hide()
        self.list.show()
        if focus:
            self.list.setFocus()

    def _recipient_chosen(self, index):
        person = self.recipients.items[index]
        ids, self.asking = self.asking, None
        self.last_recipient = person
        self._close_recipients()
        if self.playlist is not None:
            self._invoke("music.download", playlist=self.playlist["id"], recipient=person["id"], recipient_name=person["name"],
                         **({"ids": ids} if ids else {}))

    # ---------- escuchar ----------

    def _play(self, index):
        if not 0 <= index < len(self.songs):
            return
        self.queue, self.at = list(self.songs), index
        self.queue_playlist = self.playlist["id"] if self.playlist else None
        self._start()

    def _start(self):
        song = self.queue[self.at]
        self.want = song["id"]
        self.sound = "loading"
        self._announce()
        self._mark()
        after = self.queue[self.at + 1]["id"] if self.at + 1 < len(self.queue) else None
        self._invoke("music.stream", id=song["id"], **({"next_id": after} if after else {}))

    def _mark(self):
        song = self.queue[self.at] if 0 <= self.at < len(self.queue) else None
        self.list.set_playing(song["id"] if song and self.sound else None, self.sound)

    def _ensure_player(self):
        if self.player is None:
            self.player = Player()
            self.player.state_changed.connect(self._state)
            self.player.finished.connect(self._next)
            self.player.moved.connect(self.progress_changed)
            self.player.level.connect(self.level_changed)
            self.player.failed.connect(lambda text: self._say(f"No se pudo reproducir: {text}", warn=True))
        return self.player

    def _state(self):
        playing = self.player.is_playing()
        if self.sound != "loading":
            self.sound = "playing" if playing else "paused"
            self._mark()
        self._announce()

    def _announce(self):
        """Avisa a la cápsula del panel de abajo de lo que suena (o de que ya no suena nada)."""
        if not self.sound or not 0 <= self.at < len(self.queue):
            self.playing_changed.emit(None)
        else:
            song = self.queue[self.at]
            self.playing_changed.emit({"title": song["title"], "playing": self.sound != "paused", "id": song["id"],
                                       "next": self.at + 1 < len(self.queue), "download": song.get("state", "")})

    def toggle_playback(self):
        self._toggle()

    def stop_playback(self):
        if self.player is not None:
            self.player.player.stop()
        self.sound, self.queue, self.at, self.want = "", [], -1, None
        self._mark()
        self._announce()

    def _toggle(self):
        if self.player is not None and self.sound in ("playing", "paused"):
            self.player.toggle()

    def download_current(self):
        """La tecla de descargar de la cápsula de abajo: manda la canción que suena a la última persona elegida en esta
        página (por defecto «Yo»), sin abrir el panel de destinatarios."""
        if self.sound and 0 <= self.at < len(self.queue) and self.queue_playlist is not None:
            person = self.last_recipient
            self._invoke("music.download", playlist=self.queue_playlist, ids=[self.queue[self.at]["id"]],
                         recipient=person["id"], recipient_name=person["name"])

    def next_track(self):
        """La cápsula de abajo: la canción siguiente de la lista (si hay)."""
        if self.sound and self.at + 1 < len(self.queue):
            self.at += 1
            self._start()

    def previous_track(self):
        """La cápsula de abajo: si ya sonaron unos segundos, vuelve al principio de esta; si no, la anterior."""
        if not self.sound:
            return
        if self.player is not None and (self.at <= 0 or self.player.player.position() > RESTART_MS):
            self.player.seek(0)
        elif self.at > 0:
            self.at -= 1
            self._start()

    def _next(self):
        if self.at + 1 < len(self.queue):
            self.at += 1
            self._start()
        else:
            self.sound = ""
            self._mark()
            self._announce()

    def _streamed(self, result):
        if result["id"] != self.want:  # ya pidió otra canción
            return
        self.sound = "playing"
        self._ensure_player().play(result["source"])
        self._mark()

    # ---------- respuestas del núcleo ----------

    def _playlist_rows(self):
        return [{"id": p["id"], "title": p["title"], "sub": f"{p['count']} canc." if p.get("count") else ""}
                for p in self.playlists]

    def on_result(self, result):
        kind = result["kind"]
        if kind == "ffmpeg":
            self.ffmpeg = result["available"]
            if result.get("message"):
                self._say(result["message"], warn=not self.ffmpeg)
            elif not self.ffmpeg:
                self._say("Falta FFmpeg para convertir a MP3", warn=True)
            self._sync()
        elif kind == "playlists":
            self._cookies_done()
            self.playlists = result["playlists"]
            if self.playlist is None:
                self.list.set_items("playlists", self._playlist_rows(), "No hay listas")
        elif kind == "songs" and self.playlist and result["playlist"] == self.playlist["id"]:
            self.songs = [{**s, "percent": 0} for s in result["songs"]]
            rows = [{**s, "sub": duration_text(s.get("duration"))} for s in self.songs]
            self.list.set_items("songs", rows, "La lista está vacía")
            self._mark()
            self._sync()
        elif kind == "stream":
            self._streamed(result)
        elif kind == "progress":
            self._progress(result)
        elif kind == "recipients":
            if self.asking is not None:
                self.recipients.set_people(result["recipients"])
        elif kind == "sync":
            self._sync_note(result)
        elif kind == "finished":
            self.running = False
            self._summary(result)
            self._sync()
        elif kind == "error":
            if result.get("where") == "stream":
                if result.get("id") != self.want:
                    return
                self.sound = ""
                self._mark()
                self._announce()
            if result.get("where") == "recipients":
                if self.asking is not None:
                    self.recipients.set_error(result["error"])
                return
            if result.get("where") == "playlists" and "cookies" in result["error"].lower():
                self._ask_cookies(result["error"])
                return
            self._say(result["error"], warn=True)
            if not self.list.items:
                self.list.set_empty("")

    def _progress(self, result):
        self.running = result["state"] in ("doing", "queued") or self.running
        fields = {"state": result["state"], "percent": result.get("percent", 0)}
        for song in self.songs:
            if song["id"] == result["id"]:
                song.update(fields)
        playing = self.queue[self.at] if 0 <= self.at < len(self.queue) else None
        if playing is not None and playing["id"] == result["id"]:
            if all(s is not playing for s in self.songs):  # la lista que suena ya no es la que se ve: se sigue su descarga igual
                playing.update(fields)
            self._announce()  # la tecla de descargar de la cápsula enseña cómo va
        self.list.update_song(result["id"], **fields)
        if result["state"] == "error":
            self._say(result["error"], warn=True)
        self._sync()

    def _sync_note(self, result):
        """La canción que se acaba de bajar sube a Supabase para quien elegiste: se cuenta en la línea de avisos."""
        title = result.get("title") or "la canción"
        to = result.get("to") or "Yo"
        mine = to == "Yo"
        if result["state"] == "uploading":
            self._say(f"Mandando «{title}» a tu móvil…" if mine else f"Mandando «{title}» a {to}…")
        elif result["state"] == "synced":
            self._say(f"En tu móvil: «{title}»" if mine else f"Enviada a {to}: «{title}»")
        else:
            self._say(result.get("message") or "No se pudo mandar la canción", warn=True)

    def _summary(self, result):
        left = sum(s["state"] in ("pending", "error") for s in self.songs)
        if result["cancelled"]:
            self._say(f"Detenido. Faltan {left} por bajar: Descargar sigue con ellas.")
        elif result["failed"]:
            self._say(f"{result['done']} descargadas, {result['failed']} fallaron: pulsa Reintentar.", warn=True)
        elif result["done"]:
            name = self.last_recipient["name"]
            self._say(f"Listo: {result['done']} bajadas; se mandan a {'tu móvil' if name == 'Yo' else name}.")
