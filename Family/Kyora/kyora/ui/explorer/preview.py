"""Vista previa del explorador (Espacio): texto y código, Markdown, imágenes, PDF, audio y vídeo.

El PDF se dibuja con pypdfium2 (PDFium) y el audio y el vídeo con QtMultimedia (PySide6-Addons).
"""
import os

from PySide6.QtCore import QRectF, Qt, QTimer, QUrl
from PySide6.QtGui import QColor, QFont, QImage, QPainter, QPixmap
from PySide6.QtWidgets import (
    QAbstractButton,
    QHBoxLayout,
    QLabel,
    QPlainTextEdit,
    QSlider,
    QStackedWidget,
    QTextBrowser,
    QVBoxLayout,
    QWidget,
)

from kyora.ui import glyphs

TEXT_LIMIT = 512 * 1024  # de un archivo de texto se muestra el principio
TEXT_EXT = {
    ".txt", ".log", ".csv", ".py", ".pyw", ".json", ".js", ".ts", ".tsx", ".jsx", ".css", ".scss", ".html", ".htm",
    ".xml", ".yml", ".yaml", ".toml", ".ini", ".cfg", ".conf", ".bat", ".cmd", ".ps1", ".sh", ".c", ".h", ".cpp",
    ".hpp", ".cs", ".java", ".kt", ".rs", ".go", ".rb", ".php", ".sql", ".vbs", ".lua", ".r", ".env", ".gitignore",
    ".gitattributes", ".editorconfig", ".dockerfile",
}
IMAGE_EXT = {".png", ".jpg", ".jpeg", ".gif", ".bmp", ".webp", ".ico"}
AUDIO_EXT = {".mp3", ".wav", ".flac", ".ogg", ".m4a", ".aac", ".wma"}
VIDEO_EXT = {".mp4", ".mkv", ".avi", ".mov", ".webm", ".wmv", ".m4v"}


def kind_of(path):
    """Qué tipo de vista previa le toca: text, markdown, image, pdf, audio, video, folder o None."""
    if os.path.isdir(path):
        return "folder"
    name = os.path.basename(path).lower()
    ext = os.path.splitext(name)[1] or (name if name.startswith(".") else "")
    if ext == ".md" or ext == ".markdown":
        return "markdown"
    if ext in TEXT_EXT:
        return "text"
    if ext in IMAGE_EXT:
        return "image"
    if ext == ".pdf":
        return "pdf"
    if ext in AUDIO_EXT:
        return "audio"
    if ext in VIDEO_EXT:
        return "video"
    return None


def read_text(path):
    """El principio del archivo como texto, o None si parece binario."""
    with open(path, "rb") as f:
        raw = f.read(TEXT_LIMIT)
    if b"\0" in raw:
        return None
    for encoding in ("utf-8", "cp1252"):
        try:
            return raw.decode(encoding)
        except UnicodeDecodeError:
            continue
    return raw.decode("utf-8", errors="replace")


def _time(ms):
    s = max(ms, 0) // 1000
    return f"{s // 60}:{s % 60:02d}"


class GlyphButton(QAbstractButton):
    def __init__(self, theme, glyph, tip, size=34):
        super().__init__()
        self.theme, self.glyph = theme, glyph
        self.setToolTip(tip)
        self.setFixedSize(size, size)
        self.setCursor(Qt.PointingHandCursor)
        self.setAttribute(Qt.WA_Hover)

    def paintEvent(self, _):
        t = self.theme
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        if self.underMouse() or self.isChecked():
            p.setPen(Qt.NoPen)
            p.setBrush(QColor(t.gold_soft if self.isChecked() else t.hover))
            p.drawRoundedRect(QRectF(self.rect()), 8, 8)
        p.setPen(glyphs.pen(QColor(t.gold if self.isChecked() else t.ink), 1.6))
        p.setBrush(Qt.NoBrush)
        self.glyph(p, QRectF(self.rect()).adjusted(7, 7, -7, -7))


class _ImageView(QLabel):
    """Imagen ajustada al hueco sin deformarla."""

    def __init__(self):
        super().__init__()
        self.setAlignment(Qt.AlignCenter)
        self._pixmap = None

    def set_image(self, pixmap):
        self._pixmap = pixmap
        self._fit()

    def resizeEvent(self, event):
        self._fit()
        super().resizeEvent(event)

    def _fit(self):
        if self._pixmap is None or self._pixmap.isNull():
            self.clear()
            return
        dpr = self.devicePixelRatioF()
        scaled = self._pixmap.scaled(self.size() * dpr, Qt.KeepAspectRatio, Qt.SmoothTransformation)
        scaled.setDevicePixelRatio(dpr)
        self.setPixmap(scaled)


class _PdfView(QWidget):
    def __init__(self, theme):
        super().__init__()
        self.page = _ImageView()
        self.label = QLabel("")
        self.label.setObjectName("Dim")
        self.prev = GlyphButton(theme, lambda p, b: glyphs.arrow(p, b, "left"), "Página anterior")
        self.next = GlyphButton(theme, lambda p, b: glyphs.arrow(p, b, "right"), "Página siguiente")
        self.prev.clicked.connect(lambda: self.show_page(self.index - 1))
        self.next.clicked.connect(lambda: self.show_page(self.index + 1))
        bar = QHBoxLayout()
        bar.addWidget(self.prev)
        bar.addStretch(1)
        bar.addWidget(self.label)
        bar.addStretch(1)
        bar.addWidget(self.next)
        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.addWidget(self.page, 1)
        layout.addLayout(bar)
        self.doc, self.index = None, 0
        self._redraw = QTimer(self)  # al cambiar de tamaño, la página se dibuja otra vez con el ancho nuevo
        self._redraw.setSingleShot(True)
        self._redraw.timeout.connect(lambda: self.show_page(self.index))

    def resizeEvent(self, event):
        super().resizeEvent(event)
        if self.doc is not None:
            self._redraw.start(120)

    def load(self, path):
        import pypdfium2 as pdfium  # se carga solo al ver un PDF

        self.close_doc()
        self.doc = pdfium.PdfDocument(path)
        self.show_page(0)

    def show_page(self, index):
        if self.doc is None or not 0 <= index < len(self.doc):
            return
        self.index = index
        page = self.doc[index]
        width = max(self.page.width(), 300) * self.devicePixelRatioF()
        bitmap = page.render(scale=width / page.get_width(), prefer_bgrx=True)
        image = QImage(bitmap.buffer, bitmap.width, bitmap.height, bitmap.stride, QImage.Format_RGB32).copy()
        self.page.set_image(QPixmap.fromImage(image))
        self.label.setText(f"Página {index + 1} de {len(self.doc)}")
        self.prev.setEnabled(index > 0)
        self.next.setEnabled(index < len(self.doc) - 1)

    def close_doc(self):
        self._redraw.stop()
        if self.doc is not None:
            self.doc.close()
            self.doc = None


class _Note(QWidget):
    """Una nota musical grande: la "imagen" del audio."""

    def __init__(self, theme):
        super().__init__()
        self.theme = theme

    def paintEvent(self, _):
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        p.setPen(glyphs.pen(QColor(self.theme.dim), 2))
        side = min(self.width(), self.height(), 140)
        glyphs.music(p, QRectF((self.width() - side) / 2, (self.height() - side) / 2, side, side))


class _MediaView(QWidget):
    """Audio y vídeo: imagen (o una nota musical), play/pausa, barra de tiempo."""

    def __init__(self, theme):
        super().__init__()
        from PySide6.QtMultimedia import QAudioOutput, QMediaPlayer  # PySide6-Addons
        from PySide6.QtMultimediaWidgets import QVideoWidget

        self.theme = theme
        self.player = QMediaPlayer(self)
        self.audio = QAudioOutput(self)
        self.player.setAudioOutput(self.audio)
        self.video = QVideoWidget()
        self.player.setVideoOutput(self.video)
        self.note = _Note(theme)
        self.screen = QStackedWidget()
        self.screen.addWidget(self.video)
        self.screen.addWidget(self.note)
        self.toggle = GlyphButton(theme, self._play_glyph, "Reproducir o pausar (también con Enter)")
        self.toggle.clicked.connect(self.play_pause)
        self.seek = QSlider(Qt.Horizontal)
        self.seek.sliderMoved.connect(self.player.setPosition)
        self.clock = QLabel("0:00")
        self.clock.setObjectName("Dim")
        self.player.durationChanged.connect(lambda d: self.seek.setRange(0, d))
        self.player.positionChanged.connect(self._moved)
        self.player.playbackStateChanged.connect(lambda _: self.toggle.update())
        bar = QHBoxLayout()
        bar.addWidget(self.toggle)
        bar.addWidget(self.seek, 1)
        bar.addWidget(self.clock)
        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.addWidget(self.screen, 1)
        layout.addLayout(bar)

    def _play_glyph(self, p, box):
        from PySide6.QtMultimedia import QMediaPlayer

        (glyphs.pause if self.player.playbackState() == QMediaPlayer.PlayingState else glyphs.play)(p, box)

    def _moved(self, ms):
        if not self.seek.isSliderDown():
            self.seek.setValue(ms)
        self.clock.setText(f"{_time(ms)} / {_time(self.player.duration())}")

    def load(self, path, video):
        self.screen.setCurrentWidget(self.video if video else self.note)
        self.player.setSource(QUrl.fromLocalFile(path))

    def play_pause(self):
        from PySide6.QtMultimedia import QMediaPlayer

        if self.player.playbackState() == QMediaPlayer.PlayingState:
            self.player.pause()
        else:
            self.player.play()

    def stop(self):
        self.player.stop()
        self.player.setSource(QUrl())


class PreviewPane(QWidget):
    """El panel de la derecha. `show_path(ruta)` decide cómo mostrarla; `stop()` para el audio o el vídeo."""

    def __init__(self, theme):
        super().__init__()
        self.setObjectName("Preview")
        self.setAttribute(Qt.WA_StyledBackground)
        self.theme = theme
        self.path = None
        self.title = QLabel("")
        self.title.setStyleSheet("font-weight: bold;")
        self.title.setWordWrap(True)
        self.info = QLabel("")
        self.info.setObjectName("Dim")
        self.info.setWordWrap(True)
        self.message = QLabel("")
        self.message.setObjectName("Dim")
        self.message.setAlignment(Qt.AlignCenter)
        self.message.setWordWrap(True)
        self.text = QPlainTextEdit()
        self.text.setReadOnly(True)
        mono = QFont(theme.mono_family)
        mono.setPixelSize(theme.explorer_font_px - 1)
        self.text.setFont(mono)
        self.markdown = QTextBrowser()
        self.markdown.setOpenExternalLinks(True)
        self.image = _ImageView()
        self.pdf = _PdfView(theme)
        self._media = None  # se crea la primera vez que hace falta (QtMultimedia tarda en cargar)
        self.stack = QStackedWidget()
        for w in (self.message, self.text, self.markdown, self.image, self.pdf):
            self.stack.addWidget(w)
        layout = QVBoxLayout(self)
        layout.setContentsMargins(14, 12, 14, 12)
        layout.addWidget(self.title)
        layout.addWidget(self.info)
        layout.addWidget(self.stack, 1)

    def media(self):
        if self._media is None:
            self._media = _MediaView(self.theme)
            self.stack.addWidget(self._media)
        return self._media

    def stop(self):
        if self._media is not None:
            self._media.stop()
        self.pdf.close_doc()

    def show_path(self, path, info=""):
        self.stop()
        self.path = path
        self.title.setText(os.path.basename(path.rstrip("\\/")) or path)
        self.info.setText(info)
        kind = kind_of(path)
        try:
            if kind in ("text", "markdown"):
                content = read_text(path)
                if content is None:
                    return self._say("Este archivo no es de texto")
                if kind == "markdown":
                    self.markdown.setMarkdown(content)
                    self.stack.setCurrentWidget(self.markdown)
                else:
                    self.text.setPlainText(content)
                    self.stack.setCurrentWidget(self.text)
            elif kind == "image":
                pixmap = QPixmap(path)
                if pixmap.isNull():
                    return self._say("No se pudo leer la imagen")
                self.image.set_image(pixmap)
                self.stack.setCurrentWidget(self.image)
                self.info.setText(f"{info}{' · ' if info else ''}{pixmap.width()} × {pixmap.height()} px")
            elif kind == "pdf":
                self.stack.setCurrentWidget(self.pdf)
                self.pdf.load(path)
            elif kind in ("audio", "video"):
                media = self.media()
                self.stack.setCurrentWidget(media)
                media.load(path, video=kind == "video")
                media.player.play()
            elif kind == "folder":
                self._say("Carpeta")
            else:
                self._say("No hay vista previa para este tipo de archivo" + chr(10) + "Enter lo abre con su programa")
        except OSError as err:
            self._say(f"No se pudo abrir: {err.strerror or err}")
        except Exception as err:  # noqa: BLE001 - un PDF dañado no debe tumbar el explorador
            self._say(f"No se pudo mostrar: {err}")

    def _say(self, text):
        self.message.setText(text)
        self.stack.setCurrentWidget(self.message)

    def play_pause(self):
        """Enter en la vista previa de audio o vídeo."""
        if self._media is not None and self.stack.currentWidget() is self._media:
            self._media.play_pause()
            return True
        return False
