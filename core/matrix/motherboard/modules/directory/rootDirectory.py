"""Vista raíz del módulo directory: navegación de carpetas sobre el reactor y su contenido.

``RootDirectory`` ocupa toda la ventana y guarda el nivel actual de carpetas. A la
izquierda del reactor muestra el contenido de la carpeta elegida (``ContentPanel``) y,
encima del reactor, que se queda fijo a tamaño completo, el dial de carpetas
(``FolderDial``) que las escribe dentro del círculo y las gira. Girar elige la carpeta,
pulsar la elegida entra en ella y ``‹ ATRÁS`` sube un nivel.
"""
import math
import os
from datetime import datetime

from PySide6.QtCore import QPointF, QRect, QRectF, QStandardPaths, Qt, QTimer, Signal
from PySide6.QtGui import QColor, QCursor, QFont, QFontMetricsF, QPainter, QPainterPath
from PySide6.QtWidgets import QWidget

from core.matrix.motherboard.artifacts.globalArtifacts.reactor import (
    GROW_END, MENU_MS, MENU_OPEN_AT, WHEEL_FOLLOW, WHEEL_STEP_DELTA, DRAG_THRESHOLD, BRIGHT, MID, ease, unit,
)
from core.matrix.motherboard.modules import kyora_theme as kt
from core.matrix.motherboard.modules.directory.components.contentCard import Entry
from core.matrix.motherboard.modules.directory.components.contentPanel import ContentPanel

# (etiqueta, ubicación estándar de Qt) de las carpetas principales
FOLDERS = (
    ("ESCRITORIO", QStandardPaths.DesktopLocation),
    ("DESCARGAS", QStandardPaths.DownloadLocation),
    ("DOCUMENTOS", QStandardPaths.DocumentsLocation),
    ("IMÁGENES", QStandardPaths.PicturesLocation),
    ("MÚSICA", QStandardPaths.MusicLocation),
    ("VIDEOS", QStandardPaths.MoviesLocation),
)
DEFAULT_FOLDER = "DOCUMENTOS"
ROOT_TITLE = "DIRECTORIO"
BACK_LABEL = "‹ ATRÁS"  # primera opción del dial: sube un nivel
MAX_ENTRIES = 1000
MAX_FOLDERS = 300
TICK_MS = 16

# Dial de carpetas, en % del radio del reactor salvo los grados
LIST_STEP = 16           # grados entre carpetas contiguas
LIST_SPAN = 64           # grados a cada lado de la elegida hasta los que se ven carpetas
LIST_ANGLE = 180         # posición de la carpeta elegida (izquierda del centro)
LIST_LABEL_RADIUS = 64   # radio sobre el que se anclan los nombres
LIST_CHOSEN_SIZE = 7.4   # alto de la fuente del nombre elegido
LIST_OTHER_SIZE = 4.2    # alto de la fuente de los demás nombres
LIST_CHOSEN_SHIFT = 22   # cuánto más afuera se coloca el nombre elegido
LIST_GAP_PAD = 3         # margen libre de anillos alrededor del nombre elegido


def _tint(color: QColor, alpha: float) -> QColor:
    """Copia de ``color`` con su opacidad multiplicada por ``alpha`` (0..1)."""
    out = QColor(color)
    out.setAlpha(int(out.alpha() * min(1.0, max(0.0, alpha))))
    return out


class FolderDial(QWidget):
    """Nombres de las carpetas escritos dentro del círculo del reactor, a su izquierda.

    Es un widget transparente del mismo tamaño que el reactor y encima de él. La
    carpeta elegida queda a ``LIST_ANGLE``, desplazada hacia fuera, y los anillos del
    reactor se interrumpen a su alrededor (``gaps_changed``).

    Signals:
        option_changed(int): índice de la opción elegida al girar.
        option_activated(int): índice de la opción pulsada.
        gaps_changed(object): ``QPainterPath`` de huecos para el reactor, o None.
    """

    option_changed = Signal(int)
    option_activated = Signal(int)
    gaps_changed = Signal(object)

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setMouseTracking(True)
        self._labels = []
        self._selected = 0       # índice de la opción elegida
        self._wheel = 0.0        # posición suavizada del dial, en unidades de opción
        self._current = 0        # opción más cercana a la posición del dial
        self._wheel_delta = 0
        self._appear = 0.0       # progreso lineal 0..1 de la aparición
        self._press = None
        self._press_angle = 0.0
        self._dragging = False
        self._items = []         # (rect, texto, fuente, cercanía, grados) calculados en cada cuadro
        self._label_rects = []   # (QRectF, índice) para los clics
        self._gaps = None

        self._timer = QTimer(self, interval=TICK_MS)
        self._timer.timeout.connect(self._tick)
        self.hide()

    # ---- estado -------------------------------------------------------------
    def set_options(self, labels: list, selected: int) -> None:
        """Sustituye las opciones y deja elegida la de índice ``selected``."""
        self._labels = labels
        self._selected = selected
        self._wheel = float(selected)
        self._current = selected
        self._press = None
        self._dragging = False

    def start(self) -> None:
        """Muestra el dial y reproduce su aparición."""
        self._appear = 0.0
        self.show()
        self._timer.start()

    def stop(self) -> None:
        """Oculta el dial y devuelve al reactor su círculo entero."""
        self._timer.stop()
        self.hide()
        self._set_gaps(None)

    def step(self, delta: int) -> None:
        """Mueve la opción elegida ``delta`` pasos (el teclado)."""
        self._selected = self._clamp(round(self._wheel) + delta)

    def activate_current(self) -> None:
        """Activa la opción elegida, como pulsarla."""
        self.option_activated.emit(self._current)

    def _clamp(self, value):
        return max(0, min(len(self._labels) - 1, value))

    def _ready(self) -> bool:
        return self._appear >= MENU_OPEN_AT

    def _tick(self) -> None:
        """Avanza aparición y giro, recoloca los nombres y actualiza los huecos del reactor."""
        self._appear = min(1.0, self._appear + TICK_MS / MENU_MS)
        if not self._labels:
            return
        current = self._clamp(round(self._wheel))
        if current != self._current:
            self._current = current
            self.option_changed.emit(current)
        gap = self._selected - self._wheel
        if gap and not self._dragging:
            self._wheel = self._selected if abs(gap) < 0.003 else self._wheel + gap * WHEEL_FOLLOW
        self._layout()
        self._set_gaps(self._gap_path())
        if self._dragging:
            cursor = Qt.ClosedHandCursor
        elif self._ready() and self._hit_chosen(self.mapFromGlobal(QCursor.pos())):
            cursor = Qt.PointingHandCursor
        else:
            cursor = Qt.OpenHandCursor if self._ready() else Qt.ArrowCursor
        self.setCursor(cursor)
        self.update()

    def _set_gaps(self, path) -> None:
        if path != self._gaps:
            self._gaps = path
            self.gaps_changed.emit(path)

    # ---- geometría ----------------------------------------------------------
    def _center(self) -> QPointF:
        return QPointF(self.width() / 2, self.height() / 2)

    def _offset(self, index: int) -> float:
        return index - self._wheel

    def _layout(self) -> None:
        """Coloca los nombres: el elegido en ``LIST_ANGLE`` hacia fuera, los demás arriba y abajo."""
        u0 = unit(self.width(), self.height())
        c = self._center()
        self._items = []
        self._label_rects = []
        for index, label in enumerate(self._labels):
            offset = self._offset(index)
            angle = LIST_ANGLE + offset * LIST_STEP
            away = abs(angle - LIST_ANGLE)
            if away > LIST_SPAN:
                continue
            near = max(0.0, 1.0 - abs(offset))  # 1 en el elegido, 0 a un paso
            font = QFont(kt.FONT)
            font.setPixelSize(max(6, int((LIST_OTHER_SIZE + (LIST_CHOSEN_SIZE - LIST_OTHER_SIZE) * near) * u0)))
            font.setBold(near > 0.5)
            font.setLetterSpacing(QFont.AbsoluteSpacing, 1.2)
            metrics = QFontMetricsF(font)
            radius = (LIST_LABEL_RADIUS + LIST_CHOSEN_SHIFT * near) * u0
            a = math.radians(angle)
            anchor = QPointF(c.x() + radius * math.cos(a), c.y() - radius * math.sin(a))
            # El nombre se extiende hacia el centro, que es el borde de la ventana.
            text = metrics.elidedText(label, Qt.ElideRight, max(10.0, c.x() - anchor.x() - 3 * u0))
            rect = QRectF(anchor.x(), anchor.y() - metrics.height() / 2, metrics.horizontalAdvance(text) + 2,
                          metrics.height())
            self._label_rects.append((rect.adjusted(-6, -4, 6, 4), index))
            self._items.append((rect, text, font, near, away))

    def _gap_path(self):
        """Huecos para el reactor alrededor de los nombres cercanos al elegido, o None si no hay."""
        if self._appear <= GROW_END or not self._items:
            return None
        u0 = unit(self.width(), self.height())
        pad = LIST_GAP_PAD * u0
        gaps = QPainterPath()
        for rect, _, _, near, _ in self._items:
            gap = rect.adjusted(-2 * pad, -pad, pad, pad)
            gap.setHeight(gap.height() * near)
            gap.moveCenter(rect.center())
            gaps.addRoundedRect(gap, pad, pad)
        return gaps

    def _hit_chosen(self, pos: QPointF) -> bool:
        return any(rect.contains(pos) for rect, index in self._label_rects if index == self._current)

    # ---- eventos ------------------------------------------------------------
    def _cursor_angle(self, pos: QPointF) -> float:
        c = self._center()
        return math.degrees(math.atan2(c.y() - pos.y(), pos.x() - c.x()))

    def mousePressEvent(self, event) -> None:
        """Empieza un posible arrastre del dial."""
        if event.button() == Qt.LeftButton and self._ready():
            self._press = event.position()
            self._press_angle = self._cursor_angle(self._press)
            self._dragging = False
            return
        super().mousePressEvent(event)

    def mouseMoveEvent(self, event) -> None:
        """Gira el dial siguiendo el movimiento del cursor alrededor del centro."""
        if self._press is None:
            super().mouseMoveEvent(event)
            return
        pos = event.position()
        if not self._dragging:
            if math.hypot(pos.x() - self._press.x(), pos.y() - self._press.y()) < DRAG_THRESHOLD:
                return
            self._dragging = True
        angle = self._cursor_angle(pos)
        delta = (angle - self._press_angle + 180) % 360 - 180  # tramo corto, sin saltos en ±180
        self._press_angle = angle
        self._wheel = self._clamp(self._wheel - delta / LIST_STEP)

    def mouseReleaseEvent(self, event) -> None:
        """Termina el arrastre dejando la carpeta más cercana elegida; un clic activa o elige."""
        if self._press is None:
            super().mouseReleaseEvent(event)
            return
        if self._dragging:
            self._selected = self._clamp(round(self._wheel))
        elif self._hit_chosen(event.position()):
            self.option_activated.emit(self._current)
        else:
            for rect, index in self._label_rects:
                if rect.contains(event.position()):
                    self._selected = index
                    break
        self._press = None
        self._dragging = False

    def wheelEvent(self, event) -> None:
        """Un nombre por muesca de la rueda; hacia arriba, el anterior."""
        if not self._ready():
            super().wheelEvent(event)
            return
        self._wheel_delta += event.angleDelta().y()
        steps = int(self._wheel_delta / WHEEL_STEP_DELTA)
        if steps:
            self._wheel_delta -= steps * WHEEL_STEP_DELTA
            self._selected = self._clamp(round(self._wheel) - steps)
        event.accept()

    # ---- pintado ------------------------------------------------------------
    def paintEvent(self, event) -> None:
        """Escribe los nombres, más pequeños y tenues cuanto más lejos del elegido."""
        e = ease(min(1.0, max(0.0, (self._appear - GROW_END) / (1.0 - GROW_END))))
        if e <= 0:
            return
        u0 = unit(self.width(), self.height())
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        for rect, text, font, near, away in self._items:
            alpha = e * (0.3 + 0.7 * max(1.0 - away / LIST_SPAN, near))
            if near > 0.5:
                p.fillRect(QRectF(rect.left() - 5 * u0, rect.top(), 2, rect.height()), _tint(BRIGHT, e))
            p.setFont(font)
            p.setPen(_tint(BRIGHT if near > 0.5 else MID, alpha))
            p.drawText(rect, Qt.AlignLeft | Qt.AlignVCenter, text)
        p.end()


class RootDirectory(QWidget):
    """Modelo de carpetas del directorio y los dos componentes que lo muestran.

    Signals:
        file_opened(str): ruta del archivo pulsado.
        back_requested(): se pidió subir desde las carpetas principales.
        gaps_changed(object): huecos que el reactor debe dejar libres (``QPainterPath`` o None).
    """

    file_opened = Signal(str)
    back_requested = Signal()
    gaps_changed = Signal(object)

    def __init__(self, parent=None):
        super().__init__(parent)
        self._items = []         # (etiqueta, ruta) del nivel actual
        self._stack = []         # niveles superiores: (items, índice elegido)
        self._target = 0         # carpeta elegida del nivel actual

        self._panel = ContentPanel(self)
        self._panel.entry_activated.connect(self._on_entry_activated)
        self._panel.crumb_activated.connect(self.go_to_level)
        self._dial = FolderDial(self)
        self._dial.option_changed.connect(self.select_option)
        self._dial.option_activated.connect(self.activate)
        self._dial.gaps_changed.connect(self.gaps_changed)

    # ---- disposición --------------------------------------------------------
    def set_reactor_rect(self, rect: QRect) -> None:
        """Coloca el dial sobre el reactor y deja a su izquierda el espacio del contenido."""
        self._dial.setGeometry(rect)
        self._panel.setGeometry(0, 0, max(0, rect.left()), self.height())

    def start_dial(self) -> None:
        """Muestra el dial sobre el reactor (que ya debe estar fijo y en su sitio)."""
        self._dial.start()

    def stop_dial(self) -> None:
        """Oculta el dial."""
        self._dial.stop()

    # ---- datos --------------------------------------------------------------
    def reload(self) -> None:
        """Vuelve al nivel de las carpetas principales y reinicia la entrada."""
        self._stack = []
        self._items = []
        for label, location in FOLDERS:
            path = QStandardPaths.writableLocation(location)
            if path and os.path.isdir(path):
                self._items.append((label, path))
        labels = [label for label, _ in self._items]
        self._target = labels.index(DEFAULT_FOLDER) if DEFAULT_FOLDER in labels else 0
        self._refresh()
        self._panel.play_intro()

    def _refresh(self) -> None:
        """Actualiza el contenido mostrado y las opciones del dial con el estado actual."""
        title = self._items[self._target][0] if self._items else ""
        self._panel.set_content(self._crumbs(), title, self._entries())
        self._dial.set_options([BACK_LABEL] + [label for label, _ in self._items], self._target + 1)

    def _entries(self) -> list:
        """Subcarpetas y archivos de la carpeta elegida: primero las carpetas, cada grupo por nombre."""
        if not self._items:
            return []
        dirs, files = [], []
        try:
            with os.scandir(self._items[self._target][1]) as scan:
                for entry in scan:
                    if len(dirs) + len(files) >= MAX_ENTRIES:
                        break
                    try:
                        is_dir = entry.is_dir()
                        if is_dir and entry.name[0] in ".$":
                            continue
                        info = entry.stat()
                    except OSError:
                        continue
                    date = datetime.fromtimestamp(info.st_mtime).strftime("%d/%m/%Y")
                    if is_dir:
                        dirs.append(Entry(entry.name, entry.path, True, "CARPETA", date))
                    else:
                        ext = os.path.splitext(entry.name)[1].lstrip(".").upper() or "ARCHIVO"
                        files.append(Entry(entry.name, entry.path, False, ext,
                                           f"{self._size_text(info.st_size)}  ·  {date}"))
        except OSError:
            return []
        dirs.sort(key=lambda item: item.name.lower())
        files.sort(key=lambda item: item.name.lower())
        return dirs + files

    @staticmethod
    def _size_text(size: float) -> str:
        """Tamaño legible: bytes, KB, MB o GB."""
        for unit_name in ("B", "KB", "MB"):
            if size < 1024:
                return f"{size:.0f} {unit_name}" if unit_name == "B" else f"{size:.1f} {unit_name}"
            size /= 1024
        return f"{size:.1f} GB"

    @staticmethod
    def _subfolders(path: str) -> list:
        """Subcarpetas visibles de ``path`` como (etiqueta, ruta), ordenadas por nombre."""
        found = []
        try:
            with os.scandir(path) as entries:
                for entry in entries:
                    if len(found) >= MAX_FOLDERS:
                        break
                    if entry.name[0] in ".$" or not entry.is_dir():
                        continue
                    found.append((entry.name.upper(), entry.path))
        except OSError:
            return []
        found.sort(key=lambda item: item[0])
        return found

    # ---- navegación ---------------------------------------------------------
    def select_option(self, index: int) -> None:
        """Elige la carpeta de la opción ``index`` del dial y muestra su contenido; ``ATRÁS`` no cambia nada."""
        folder = index - 1
        if 0 <= folder < len(self._items) and folder != self._target:
            self._target = folder
            self._panel.set_content(self._crumbs(), self._items[folder][0], self._entries())

    def _crumbs(self) -> list:
        """Nombres de las migas: las carpetas principales y la cadena de carpetas entradas."""
        return [ROOT_TITLE] + [items[target][0] for items, target in self._stack]

    def activate(self, index: int) -> None:
        """Pulsar una opción del dial: ``ATRÁS`` sube (o sale en las principales); una carpeta entra."""
        if index == 0:
            if not self.up():
                self.back_requested.emit()
            return
        self.select_option(index)
        self.enter()

    def enter(self) -> bool:
        """Baja un nivel: el dial pasa a mostrar las subcarpetas de la elegida.

        Returns:
            False si la carpeta elegida no tiene subcarpetas.
        """
        if not self._items:
            return False
        subfolders = self._subfolders(self._items[self._target][1])
        if not subfolders:
            return False
        self._stack.append((self._items, self._target))
        self._items = subfolders
        self._target = 0
        self._refresh()
        return True

    def up(self) -> bool:
        """Sube un nivel, dejando elegida la carpeta de la que se venía.

        Returns:
            False si ya se está en las carpetas principales.
        """
        if not self._stack:
            return False
        self._items, self._target = self._stack.pop()
        self._refresh()
        return True

    def go_to_level(self, level: int) -> None:
        """Sube hasta el nivel ``level`` (0 = carpetas principales)."""
        while len(self._stack) > level and self.up():
            pass

    def step(self, delta: int) -> None:
        """Mueve la carpeta elegida ``delta`` pasos en el dial."""
        self._dial.step(delta)

    def activate_current(self) -> None:
        """Activa la opción elegida del dial."""
        self._dial.activate_current()

    def _on_entry_activated(self, path: str, is_dir: bool) -> None:
        """Una tarjeta de archivo emite ``file_opened``; una de carpeta entra en ella."""
        if not is_dir:
            self.file_opened.emit(path)
            return
        if not self.enter():
            return
        for index, (_, folder_path) in enumerate(self._items):
            if folder_path == path:
                self._target = index
                self._refresh()
                break

    # ---- ciclo de vida ------------------------------------------------------
    def showEvent(self, event) -> None:
        """Recarga las carpetas cada vez que se muestra."""
        super().showEvent(event)
        self.reload()

    def hideEvent(self, event) -> None:
        """Oculta el dial al ocultarse."""
        self._dial.stop()
        super().hideEvent(event)

    def resizeEvent(self, event) -> None:
        """Mantiene el panel a la altura de la ventana."""
        super().resizeEvent(event)
        self._panel.setGeometry(0, 0, self._panel.width(), self.height())
