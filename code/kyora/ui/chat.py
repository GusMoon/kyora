"""El chat, dentro del buscador (Ctrl+Shift+C, o la sección Chat de la píldora), con el mismo montaje que las notas.

Con el aire de un chat con un agente (como Claude): arriba, el estado de la conexión; en medio, lo de este dispositivo en
burbujas grises a la derecha y lo de tus otros dispositivos como texto suelto a la izquierda, firmado con un ✦; cada
mensaje con su **hora** y su **estado** (un reloj y «En espera» mientras no ha salido, ✓ cuando ya está **enviado**); abajo,
un compositor grande y redondo con «+» (adjuntar) y la flecha de enviar. Fotos y archivos salen como miniatura o tarjeta
(clic: se abren). Todo se pinta a mano, como el resto de Kyora.

Teclado: Enter envía, Shift+Enter salta de línea, Ctrl+O adjunta archivos, Ctrl+V pega texto, fotos del portapapeles o
archivos copiados, y también se pueden soltar archivos desde el Explorador. RePág/AvPág desplazan y Esc cierra. Borrar un
mensaje pide una segunda pulsación (el aviso sale en la misma burbuja).

Los datos vienen del servicio (`kyora/chat/service.py`): `call("chat.…")` para lo rápido y `on_event(evento)` para lo que
llega solo (mensajes nuevos, estados, conexión).
"""
import logging
import queue
import tempfile
import threading
from collections import OrderedDict
from datetime import datetime
from pathlib import Path

from PySide6.QtCore import QEvent, QMimeData, QObject, QPointF, QRectF, QSize, Qt, QTimer, QUrl, Signal
from PySide6.QtGui import (
    QColor,
    QFontMetrics,
    QImage,
    QImageReader,
    QPainter,
    QPainterPath,
    QPalette,
    QPen,
    QPixmap,
)
from PySide6.QtWidgets import QApplication, QFileDialog, QFrame, QTextEdit, QWidget

from kyora.search.folders import human_size
from kyora.ui import doc_excerpt, glyphs
from kyora.ui.bar import accent, font
from kyora.ui.explorer import file_icons
from kyora.ui.explorer.style import _css, stylesheet
from kyora.ui.hub.cards import FLAT_EDGE, paint_flat, paint_flat_well
from kyora.ui.search_tree import TreeList

log = logging.getLogger("kyora.ui")

MARGIN = 16
HEAD_H = 34
FOOT_H = 16  # el margen de abajo (el aviso corto, si lo hay, sale encima del compositor)
GAP = 2  # entre mensajes (además de la fila de acciones reservada bajo cada uno)
PAD_X, PAD_Y = 12, 8  # dentro de una burbuja
HEAD_LABEL_H = 32  # la línea de arriba cuando firma un dispositivo (lechuza y nombre)
HEAD_TIME_H = 18  # y cuando solo lleva la hora (visible al pasar el cursor)
ACT_H = 26  # la fila de acciones bajo cada mensaje (siempre reservada: así nada salta al pasar el cursor)
OWL_PX, NAME_PX = 22, 15
BODY_PX, TIME_PX = 15, 13
THUMB_MAX = (280, 220)  # lo más grande que se ve una foto
THUMB_LOAD = (560, 440)  # y a qué tamaño se lee (al doble: pantallas con escala)
THUMB_EMPTY = (220, 130)  # el hueco de una foto que aún no se ha bajado
FILE_W = 340  # el ancho de la tarjeta de un documento
CARD_HEAD = 40  # el encabezado de la tarjeta (hoja, nombre y descarga)
EXCERPT_LINES, EXCERPT_LH = 5, 17  # líneas del extracto y lo que mide cada una
BUBBLE_FRACTION = 0.78  # lo mío, en burbuja
TEXT_FRACTION = 0.92  # lo de los otros dispositivos, texto sin burbuja (más ancho, como la respuesta de un agente)
BUBBLE_MAX = 560
BUBBLE_R = 12
COMPOSER_MIN, COMPOSER_MAX = 42, 130
COMPOSER_R = 21
STAGE_H = 34
CONTROL_W = 30  # los botones redondos «+» (adjuntar) y la flecha (enviar)
TREE_W, TREE_GAP = 310, 6  # el árbol de archivos que se abre a la derecha del chat: lo que mide y lo que lo separa
SIDE_HEAD = 36  # el título del panel del árbol
CACHE = 40  # fotos en memoria como mucho
MONTHS = ("enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre", "noviembre",
          "diciembre")
STATES = {
    "unconfigured": ("Sin configurar", "rellena supabase/.env y reinicia Kyora", "warn"),
    "connecting": ("Conectando…", "", "dim"),
    "online": ("En línea", "", "gold"),
    "offline": ("Sin conexión", "los mensajes saldrán al volver", "warn"),
    "auth_error": ("No se pudo entrar", "revisa el correo y la contraseña de supabase/.env", "warn"),
}
IMAGE_TYPES = ("image/png", "image/jpeg", "image/gif", "image/bmp", "image/webp")


# ---------- utilidades puras ----------

def parse_time(stamp):
    """La hora local de un instante ISO ("2026-10-30T10:00:00.120Z"), o None si no se entiende."""
    try:
        return datetime.fromisoformat(str(stamp)).astimezone()
    except (ValueError, TypeError):
        return None


def clock_text(stamp):
    moment = parse_time(stamp)
    return moment.strftime("%H:%M") if moment else ""


def day_text(stamp, today=None):
    """«Hoy», «Ayer» o «30 de octubre» (con el año si no es el actual)."""
    moment = parse_time(stamp)
    if moment is None:
        return ""
    today = today or datetime.now().astimezone().date()
    gap = (today - moment.date()).days
    if gap == 0:
        return "Hoy"
    if gap == 1:
        return "Ayer"
    text = f"{moment.day} de {MONTHS[moment.month - 1]}"
    return text if moment.year == today.year else f"{text} de {moment.year}"


def is_image(att):
    return (att.get("mime_type") or "").lower() in IMAGE_TYPES


def fit(size, box):
    """`size` (ancho, alto) reducido para caber en `box`, sin cambiar la proporción ni agrandarlo."""
    w, h = size
    scale = min(box[0] / w, box[1] / h, 1.0) if w > 0 and h > 0 else 1.0
    return max(int(w * scale), 1), max(int(h * scale), 1)


class ImageLoader(QObject):
    """Lee las fotos del chat en un hilo, ya reducidas, de una en una (como las miniaturas de Fondos)."""

    ready = Signal(str, QImage)

    def __init__(self):
        super().__init__()
        self._queue = queue.Queue()
        self._asked = set()
        self._worker = None

    def request(self, path):
        if path in self._asked:
            return
        self._asked.add(path)
        self._queue.put(path)
        if self._worker is None:
            self._worker = threading.Thread(target=self._run, daemon=True, name="kyora-chat-images")
            self._worker.start()

    def forget(self, path):
        self._asked.discard(path)

    def _run(self):
        while True:
            path = self._queue.get()
            try:
                reader = QImageReader(path)
                reader.setAutoTransform(True)
                size = reader.size()
                if size.isValid() and (size.width() > THUMB_LOAD[0] or size.height() > THUMB_LOAD[1]):
                    reader.setScaledSize(size.scaled(QSize(*THUMB_LOAD), Qt.KeepAspectRatio))
                image = reader.read()
            except Exception:  # noqa: BLE001 - una imagen rota no debe parar a las demás
                image = QImage()
            self.ready.emit(path, image)


class DocLoader(QObject):
    """Saca el extracto de los documentos del chat en un hilo, de uno en uno (como `ImageLoader` con las fotos)."""

    ready = Signal(str, str)  # (ruta, extracto; "" si no tiene)

    def __init__(self):
        super().__init__()
        self._queue = queue.Queue()
        self._asked = set()
        self._worker = None

    def request(self, path):
        if path in self._asked:
            return
        self._asked.add(path)
        self._queue.put(path)
        if self._worker is None:
            self._worker = threading.Thread(target=self._run, daemon=True, name="kyora-chat-docs")
            self._worker.start()

    def _run(self):
        while True:
            path = self._queue.get()
            self.ready.emit(path, doc_excerpt.excerpt(path) or "")


class Composer(QTextEdit):
    """El campo para escribir: Enter envía, Shift+Enter salta de línea. Pegar o soltar archivos y fotos los adjunta."""

    submit = Signal()
    attach = Signal()
    escaped = Signal()
    scroll_page = Signal(int)  # -1 / 1
    files = Signal(list)  # rutas
    at = Signal()  # se escribió «@»: abre el árbol de archivos (la arroba no llega a escribirse)

    def __init__(self):
        super().__init__()
        self.setAcceptRichText(False)
        self.setTabChangesFocus(True)
        self.setObjectName("ChatComposer")
        self.setFrameShape(QFrame.NoFrame)  # sin el marco que Windows 11 pinta (con su color de sistema) bajo el campo
        palette = self.palette()
        palette.setColor(QPalette.Base, Qt.transparent)  # el fondo es el del compositor, que pinta ChatBoard
        self.setPalette(palette)
        self.viewport().setAutoFillBackground(False)
        self.setPlaceholderText("Escribe un mensaje…")

    def keyPressEvent(self, event):
        key, mods = event.key(), event.modifiers()
        if key in (Qt.Key_Return, Qt.Key_Enter) and not mods & Qt.ShiftModifier:
            self.submit.emit()
        elif key == Qt.Key_Escape:
            self.escaped.emit()
        elif key == Qt.Key_O and mods & Qt.ControlModifier:
            self.attach.emit()
        elif key in (Qt.Key_PageUp, Qt.Key_PageDown):
            self.scroll_page.emit(-1 if key == Qt.Key_PageUp else 1)
        elif event.text() == "@" and not mods & Qt.ControlModifier:
            self.at.emit()
        else:
            super().keyPressEvent(event)

    def canInsertFromMimeData(self, source):
        return source.hasUrls() or source.hasImage() or super().canInsertFromMimeData(source)

    def insertFromMimeData(self, source):
        paths = [str(Path(url.toLocalFile())) for url in source.urls() if url.isLocalFile()] if source.hasUrls() else []
        paths = [p for p in paths if Path(p).is_file()]
        if paths:
            self.files.emit(paths)
        elif source.hasImage():
            image = source.imageData()
            if isinstance(image, QImage) and not image.isNull():
                folder = Path(tempfile.gettempdir()) / "KyoraChat"
                folder.mkdir(parents=True, exist_ok=True)
                path = folder / f"captura-{datetime.now():%Y%m%d-%H%M%S-%f}.png"
                if image.save(str(path), "PNG"):
                    self.files.emit([str(path)])
        elif source.hasText():
            self.insertPlainText(source.text())


class ChatView(QWidget):
    """Los mensajes: burbujas con scroll, siempre pegado al final mientras no subas a leer lo anterior."""

    older_wanted = Signal(str)  # la hora del mensaje más antiguo que se tiene
    open_attachment = Signal(str, str)  # (mensaje, adjunto): hacer clic en una foto o archivo
    fetch_attachment = Signal(str, str)  # bajar un adjunto para verlo (sin abrirlo)
    retry = Signal(str)
    delete = Signal(str)
    copy = Signal(str)  # el botón «Copiar» de un mensaje
    download = Signal(str)  # y «Descargar»

    def __init__(self, theme):
        super().__init__()
        self.theme = theme
        self.device = "pc"
        self.messages = []
        self.scroll = 0.0
        self._items = []
        self._content = 0.0
        self._hover = None  # id del mensaje bajo el cursor
        self._armed = None  # el mensaje que espera la segunda pulsación de «Borrar»
        self._pixmaps = OrderedDict()  # ruta -> QPixmap
        self._fetched = set()  # adjuntos que ya se pidieron bajar
        self._older_for = None
        self._stick = True
        self.loader = ImageLoader()
        self.loader.ready.connect(self._thumb_ready)
        self.docs = DocLoader()
        self.docs.ready.connect(self._doc_ready)
        self._excerpts = {}  # ruta -> extracto ("" = sin extracto)
        self.setMouseTracking(True)
        self.setFocusPolicy(Qt.NoFocus)

    # ---------- datos ----------

    def set_messages(self, messages):
        self.messages = sorted(messages, key=_order)
        self._stick = True
        self._older_for = None
        self._relayout()

    def add(self, message):
        """Un mensaje nuevo (o uno que ya estaba: se sustituye)."""
        self.replace(message) if self._index(message["id"]) is not None else self._insert(message)

    def _insert(self, message):
        near_end = self.scroll >= self._max_scroll() - 4
        self.messages = sorted([*self.messages, message], key=_order)
        self._stick = self._stick or near_end or message.get("device") == self.device
        self._relayout()

    def replace(self, message):
        i = self._index(message["id"])
        if i is not None:
            self.messages[i] = message
            self._relayout()

    def remove(self, message_id):
        self.messages = [m for m in self.messages if m["id"] != message_id]
        if self._armed == message_id:
            self._armed = None
        self._relayout()

    def prepend(self, older):
        """Mensajes anteriores: se suman arriba sin mover lo que se está leyendo."""
        known = {m["id"] for m in self.messages}
        fresh = [m for m in older if m["id"] not in known]
        if not fresh:
            return
        before = self._content
        self.messages = sorted([*fresh, *self.messages], key=_order)
        self._stick = False
        self._relayout()
        self.scroll += self._content - before
        self._clamp()

    def set_attachment_path(self, attachment_id, path):
        for message in self.messages:
            for att in message["attachments"]:
                if att["id"] == attachment_id:
                    att["local_path"] = path
        self._relayout()

    def _index(self, message_id):
        return next((i for i, m in enumerate(self.messages) if m["id"] == message_id), None)

    def retheme(self, theme):
        self.theme = theme
        self._relayout()

    # ---------- fotos ----------

    def _local(self, att):
        path = att.get("local_path")
        return path if path and Path(path).is_file() else None

    def _pixmap(self, att, message):
        """La foto lista para pintar, o None: pide leerla (si ya está en el disco) o bajarla (si solo está en Supabase)."""
        path = self._local(att)
        if path is None:
            if att.get("storage_path") and message["status"] == "sent" and att["id"] not in self._fetched:
                self._fetched.add(att["id"])
                self.fetch_attachment.emit(message["id"], att["id"])
            return None
        pixmap = self._pixmaps.get(path)
        if pixmap is None:
            self.loader.request(path)
            return None
        self._pixmaps.move_to_end(path)
        return pixmap

    def _excerpt(self, att, message):
        """El extracto del documento listo para pintar, o None: pide leerlo (si está en el disco) o bajarlo (si es un PDF,
        Word, TXT o MD que no pesa mucho y solo está en Supabase)."""
        if not doc_excerpt.supported(att.get("file_name") or ""):
            return None
        path = self._local(att)
        if path is None:
            small = int(att.get("size_bytes") or 0) <= doc_excerpt.MAX_AUTO_BYTES
            if att.get("storage_path") and message["status"] == "sent" and small and att["id"] not in self._fetched:
                self._fetched.add(att["id"])
                self.fetch_attachment.emit(message["id"], att["id"])
            return None
        if path not in self._excerpts:
            self.docs.request(path)
            return None
        return self._excerpts[path] or None

    def _doc_ready(self, path, text):
        self._excerpts[path] = text
        self._relayout()

    def _thumb_ready(self, path, image):
        if image.isNull():
            return
        self._pixmaps[path] = QPixmap.fromImage(image)
        while len(self._pixmaps) > CACHE:
            old, _ = self._pixmaps.popitem(last=False)
            self.loader.forget(old)
        self._relayout()

    # ---------- geometría ----------

    def _body_font(self):
        return font(self.theme, BODY_PX)

    def _time_font(self):
        return font(self.theme, TIME_PX)

    def _max_scroll(self):
        return max(self._content - self.height() + MARGIN, 0.0)

    def _clamp(self):
        self.scroll = min(max(self.scroll, 0.0), self._max_scroll())

    def resizeEvent(self, event):
        super().resizeEvent(event)
        self._relayout()

    def _relayout(self):
        """Mide todos los mensajes: cuánto ocupa cada burbuja y dónde va cada pieza dentro de ella."""
        width = self.width()
        items, y = [], float(MARGIN)
        last_day, last_device = None, None
        mine_max = max(min(int((width - 2 * MARGIN) * BUBBLE_FRACTION), BUBBLE_MAX) - 2 * PAD_X, 80)
        theirs_max = max(int((width - 2 * MARGIN) * TEXT_FRACTION) - 2 * PAD_X, 80)
        body, small = QFontMetrics(self._body_font()), QFontMetrics(self._time_font())
        for message in self.messages:
            day = day_text(message["sent_at"])
            if day != last_day:
                items.append({"kind": "day", "y": y, "h": 26.0, "text": day})
                y += 26 + GAP
                last_day, last_device = day, None
            mine = message["device"] == self.device
            inner_max = mine_max if mine else theirs_max
            parts, cy, content_w = [], float(PAD_Y), 0
            for att in message["attachments"]:
                if is_image(att):
                    pixmap = self._pixmap(att, message)
                    if pixmap is not None:
                        w, h = fit((pixmap.width(), pixmap.height()), (min(THUMB_MAX[0], inner_max), THUMB_MAX[1]))
                    elif att.get("width") and att.get("height"):
                        w, h = fit((att["width"], att["height"]), (min(THUMB_MAX[0], inner_max), THUMB_MAX[1]))
                    else:
                        w, h = min(THUMB_EMPTY[0], inner_max), THUMB_EMPTY[1]
                    parts.append({"kind": "image", "rect": (0, cy, w, h), "att": att, "pixmap": pixmap})
                else:
                    w = min(FILE_W, inner_max)
                    text = self._excerpt(att, message)
                    lines = 0
                    if text:
                        wrapped = body.boundingRect(0, 0, w - 28, 100000, Qt.TextWordWrap | Qt.AlignLeft, text).height()
                        lines = min(EXCERPT_LINES, max(round(wrapped / EXCERPT_LH), 1))
                    h = CARD_HEAD + 10 + 24 + (lines * EXCERPT_LH + 6 if lines else 0) + 18 + 10  # cabecera, título, extracto, pie
                    parts.append({"kind": "file", "rect": (0, cy, w, h), "att": att, "excerpt": text, "lines": lines})
                cy += h + 6
                content_w = max(content_w, w)
            text = message.get("body") or ""
            if text:
                box = body.boundingRect(0, 0, inner_max, 100000, Qt.TextWordWrap | Qt.AlignLeft, text)
                parts.append({"kind": "text", "rect": (0, cy, box.width() + 2, box.height() + 2), "text": text})
                cy += box.height() + 2
                content_w = max(content_w, box.width() + 2)
            error = message.get("error")
            if error:
                line = f"No se envió: {error} · clic para reintentar"
                box = small.boundingRect(0, 0, inner_max, 100000, Qt.TextWordWrap, line)
                parts.append({"kind": "error", "rect": (0, cy + 2, box.width() + 2, box.height() + 2), "text": line})
                cy += box.height() + 6
                content_w = max(content_w, box.width() + 2)
            bubble_w, bubble_h = max(content_w, 24) + 2 * PAD_X, max(cy, 6) + PAD_Y
            label = ""
            if not mine and message["device"] != last_device:
                label = message["device"] or "otro dispositivo"
            label_h = float(HEAD_LABEL_H) if label else 0.0
            head_h = label_h or float(HEAD_TIME_H)  # arriba siempre hay una línea: firma, o solo la hora
            x = width - MARGIN - bubble_w if mine else MARGIN
            items.append({"kind": "message", "y": y, "h": head_h + bubble_h + ACT_H, "message": message, "mine": mine,
                          "label": label, "label_h": label_h, "head_h": head_h,
                          "bubble": (x, y + head_h, bubble_w, bubble_h), "parts": parts})
            y += head_h + bubble_h + ACT_H + GAP
            last_device = message["device"]
        self._items, self._content = items, y
        if self._stick:
            self.scroll = self._max_scroll()
        self._clamp()
        self.update()

    # ---------- ratón y teclado ----------

    def wheelEvent(self, event):
        delta = event.angleDelta().y()
        self.scroll_by(-delta / 2)
        if delta > 0 and self.scroll <= 0 and self.messages:
            oldest = self.messages[0]
            if self._older_for != oldest["id"]:
                self._older_for = oldest["id"]
                self.older_wanted.emit(oldest["sent_at"])

    def scroll_by(self, amount):
        self.scroll = min(max(self.scroll + amount, 0.0), self._max_scroll())
        self._stick = self.scroll >= self._max_scroll() - 2
        self.update()

    def scroll_page(self, direction):
        self.scroll_by(direction * self.height() * 0.85)

    def _actions(self, item):
        """[(nombre, zona en pantalla)] de las acciones que salen bajo un mensaje al pasar el cursor."""
        message = item["message"]
        names = ["copy"] + (["download"] if message["attachments"] else []) + ["delete"]
        widths = [72 if name == "delete" and self._armed == message["id"] else 28 for name in names]
        x, y, w, h = item["bubble"]
        left = x + w - (sum(widths) + 4 * (len(names) - 1)) if item["mine"] else x
        out, top = [], y - self.scroll + h + 2
        for name, width in zip(names, widths):
            out.append((name, QRectF(left, top, width, 24)))
            left += width + 4
        return out

    def _action_rect(self, item, name):
        return next(rect for n, rect in self._actions(item) if n == name)

    def _hit(self, pos):
        """('att', mensaje, adjunto) | ('retry' | 'copy' | 'download' | 'delete' | 'bubble', mensaje) | None.
        Todo el renglón del mensaje (la línea de arriba, la burbuja y la fila de acciones) cuenta como «encima»."""
        for item in self._items:
            if item["kind"] != "message":
                continue
            top = item["y"] - self.scroll
            if top + item["h"] < 0 or top > self.height() or not QRectF(0, top, self.width(), item["h"]).contains(pos):
                continue
            message = item["message"]
            if self._hover == message["id"]:  # los botones solo existen mientras se ven
                for name, rect in self._actions(item):
                    if rect.contains(pos):
                        return (name, message)
            bx, by, bw, bh = item["bubble"]
            if not QRectF(bx, by - self.scroll, bw, bh).contains(pos):
                return ("bubble", message)
            for part in item["parts"]:
                px, py, pw, ph = part["rect"]
                rect = QRectF(bx + PAD_X + px, by - self.scroll + py, pw, ph)
                if part["kind"] == "file" and self._card_download(rect).contains(pos):
                    return ("download", message)
                if part["kind"] in ("image", "file") and rect.contains(pos):
                    return ("att", message, part["att"])
                if part["kind"] == "error" and rect.contains(pos):
                    return ("retry", message)
            return ("bubble", message)
        return None

    @staticmethod
    def _card_download(rect):
        """El icono de descarga del encabezado de una tarjeta de documento."""
        return QRectF(rect.right() - 38, rect.top() + 6, 30, 28)

    def mouseMoveEvent(self, event):
        hit = self._hit(event.position())
        hover = hit[1]["id"] if hit else None
        if hover != self._hover:
            self._hover = hover
            self.update()
        self.setCursor(Qt.PointingHandCursor if hit and hit[0] in ("att", "retry", "copy", "download", "delete")
                       else Qt.ArrowCursor)

    def leaveEvent(self, _):
        self._hover = None
        self.update()

    def mouseReleaseEvent(self, event):
        if event.button() != Qt.LeftButton:
            return
        hit = self._hit(event.position())
        if hit and hit[0] == "delete":
            if self._armed == hit[1]["id"]:
                self._armed = None
                self.delete.emit(hit[1]["id"])
            else:
                self._armed = hit[1]["id"]
                self.update()
            return
        if self._armed is not None:
            self._armed = None
            self.update()
        if hit and hit[0] == "att":
            self.open_attachment.emit(hit[1]["id"], hit[2]["id"])
        elif hit and hit[0] == "retry":
            self.retry.emit(hit[1]["id"])
        elif hit and hit[0] == "copy":
            self.copy.emit(hit[1]["id"])
        elif hit and hit[0] == "download":
            self.download.emit(hit[1]["id"])

    # ---------- pintura ----------

    def paintEvent(self, _):
        t = self.theme
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        p.setRenderHint(QPainter.SmoothPixmapTransform)
        if not self.messages:
            p.setFont(font(t, BODY_PX))
            p.setPen(QColor(t.dim))
            p.drawText(QRectF(self.rect()), Qt.AlignCenter,
                       "Aún no hay mensajes.\nEscribe abajo, o pega o suelta una foto o un archivo.")
            return
        for item in self._items:
            top = item["y"] - self.scroll
            if top + item["h"] < 0 or top > self.height():
                continue
            if item["kind"] == "day":
                self._paint_day(p, item, top)
            else:
                self._paint_message(p, item)

    def _paint_day(self, p, item, top):
        t = self.theme
        p.setFont(font(t, TIME_PX, bold=True))  # el día, solo el texto atenuado en el centro (sin cápsula)
        label = item["text"]
        p.setPen(QColor(t.dim))
        p.drawText(QRectF(0, top + 2, self.width(), 22), Qt.AlignCenter, label)

    def _paint_message(self, p, item):
        t = self.theme
        message = item["message"]
        x, y, w, h = item["bubble"]
        y -= self.scroll
        hover = self._hover == message["id"]
        self._paint_line(p, item, y - item["head_h"], hover)
        bubble = QRectF(x, y, w, h)
        if item["mine"] and message.get("body"):  # lo mío con texto, en un cuadro redondeado; lo demás, suelto
            p.setPen(QPen(FLAT_EDGE, 1))
            p.setBrush(self._mine_fill())
            p.drawRoundedRect(bubble.adjusted(0.5, 0.5, -0.5, -0.5), BUBBLE_R, BUBBLE_R)
        if message.get("error"):
            p.setPen(QPen(QColor(t.warn), 1))
            p.setBrush(Qt.NoBrush)
            p.drawRoundedRect(bubble.adjusted(0.5, 0.5, -0.5, -0.5), BUBBLE_R, BUBBLE_R)
        for part in item["parts"]:
            px, py, pw, ph = part["rect"]
            rect = QRectF(x + PAD_X + px, y + py, pw, ph)
            kind = part["kind"]
            if kind == "text":
                p.setFont(self._body_font())
                p.setPen(QColor(t.ink))
                p.drawText(rect, Qt.TextWordWrap | Qt.AlignLeft | Qt.AlignTop, part["text"])
            elif kind == "image":
                self._paint_image(p, rect, part)
            elif kind == "file":
                self._paint_file(p, rect, part)
            elif kind == "error":
                p.setFont(self._time_font())
                p.setPen(QColor(t.warn))
                p.drawText(rect, Qt.TextWordWrap | Qt.AlignLeft | Qt.AlignTop, part["text"])
        if hover:
            self._paint_actions(p, item)

    def _paint_line(self, p, item, top, hover):
        """La línea de arriba de cada mensaje: la lechuza y el nombre (en lo ajeno, al empezar una tanda) y la hora, que solo
        se ve con el cursor encima. El reloj de «En espera» se ve siempre: avisa de algo."""
        t = self.theme
        message, mine = item["message"], item["mine"]
        x, _, w, _ = item["bubble"]
        pending = message["status"] == "pending" and not message.get("error")
        failed = bool(message.get("error"))
        text = clock_text(message["sent_at"]) if hover else ""
        if pending:
            text = f"{text}  ·  En espera" if text else "En espera"
        show_mark = mine and (pending or failed or (hover and message["status"] == "sent"))
        row_h = item["head_h"]
        p.setFont(self._time_font())
        fm = QFontMetrics(p.font())
        if mine:
            right = x + w - PAD_X - (20 if show_mark else 0)
            p.setPen(QColor(t.dim))
            p.drawText(QRectF(right - fm.horizontalAdvance(text) - 2, top, fm.horizontalAdvance(text) + 2, row_h),
                       Qt.AlignVCenter | Qt.AlignRight, text)
            if show_mark:
                self._paint_mark(p, QRectF(x + w - PAD_X - 14, top + row_h / 2 - 7, 14, 14), message)
            return
        left = x + PAD_X
        if item["label"]:
            p.setPen(glyphs.pen(accent(t, True), 1.7))
            p.setBrush(Qt.NoBrush)
            glyphs.owl(p, QRectF(left, top + (row_h - OWL_PX) / 2, OWL_PX, OWL_PX))
            p.setFont(font(t, NAME_PX, bold=True))
            p.setPen(QColor(t.ink))
            name_w = QFontMetrics(p.font()).horizontalAdvance(item["label"])
            p.drawText(QRectF(left + OWL_PX + 8, top, name_w + 4, row_h), Qt.AlignVCenter, item["label"])
            left += OWL_PX + 8 + name_w + 14
            p.setFont(self._time_font())
        p.setPen(QColor(t.dim))
        p.drawText(QRectF(left, top, fm.horizontalAdvance(text) + 4, row_h), Qt.AlignVCenter, text)

    def _paint_actions(self, p, item):
        """Copiar, descargar y borrar, bajo el mensaje: iconos pequeños con el borde fino de lo plano."""
        t = self.theme
        message = item["message"]
        for name, rect in self._actions(item):
            armed = name == "delete" and self._armed == message["id"]
            p.setPen(QPen(QColor(t.warn) if armed else FLAT_EDGE, 1))
            p.setBrush(QColor(t.warn) if armed else QColor(255, 255, 255, 14))
            p.drawRoundedRect(rect, 8, 8)
            if armed:
                p.setFont(font(t, TIME_PX, bold=True))
                p.setPen(QColor(t.pick_ink))
                p.drawText(rect, Qt.AlignCenter, "¿Seguro?")
                continue
            p.setPen(glyphs.pen(QColor(t.dim), 1.5))
            p.setBrush(Qt.NoBrush)
            icon = QRectF(rect.center().x() - 7, rect.center().y() - 7, 14, 14)
            {"copy": glyphs.copy, "download": glyphs.download, "delete": glyphs.trash}[name](p, icon)

    def _mine_fill(self):
        """El relleno de mis burbujas: el gris algo más claro de lo elegido, liso (como el mensaje del usuario en Claude)."""
        return QColor(self.theme.plate_pick)

    def _paint_image(self, p, rect, part):
        t = self.theme
        p.save()
        shape = _rounded(rect, 10)
        p.setClipPath(shape)
        if part["pixmap"] is not None:
            p.drawPixmap(rect, part["pixmap"], QRectF(part["pixmap"].rect()))
        else:
            p.fillRect(rect, QColor(255, 255, 255, 14))
            p.setPen(glyphs.pen(QColor(t.dim), 1.4))
            size = 28
            glyphs.picture(p, QRectF(rect.center().x() - size / 2, rect.center().y() - size / 2, size, size))
        p.restore()
        p.setBrush(Qt.NoBrush)
        p.setPen(QPen(FLAT_EDGE, 1))
        p.drawRoundedRect(rect, 10, 10)

    def _paint_file(self, p, rect, part):
        """Un documento como la tarjeta de un plan en Claude: arriba su encabezado (hoja, nombre y el icono de descarga),
        debajo el título, un extracto del contenido (si se pudo leer) y el tipo con el tamaño."""
        t = self.theme
        att = part["att"]
        name = att.get("file_name") or "archivo"
        paint_flat(p, t, rect, 14)
        icon = QRectF(rect.left() + 12, rect.top() + (CARD_HEAD - 22) / 2, 22, 22)
        file_icons.shared().file().paint(p, icon.toRect())
        dl = self._card_download(rect)
        p.setFont(font(t, TIME_PX + 1))
        p.setPen(QColor(t.dim))
        head_w = rect.width() - 42 - 44
        p.drawText(QRectF(rect.left() + 42, rect.top(), head_w, CARD_HEAD), Qt.AlignVCenter,
                   QFontMetrics(p.font()).elidedText(name, Qt.ElideMiddle, int(head_w)))
        p.setPen(glyphs.pen(QColor(t.dim), 1.6))
        p.setBrush(Qt.NoBrush)
        glyphs.download(p, QRectF(dl.center().x() - 9, dl.center().y() - 9, 18, 18))
        p.setPen(QPen(FLAT_EDGE, 1))
        p.drawLine(QPointF(rect.left() + 1, rect.top() + CARD_HEAD), QPointF(rect.right() - 1, rect.top() + CARD_HEAD))
        x, width, y = rect.left() + 14, rect.width() - 28, rect.top() + CARD_HEAD + 10
        p.setFont(font(t, BODY_PX + 1, bold=True))
        p.setPen(QColor(t.ink))
        stem = Path(name).stem or name
        p.drawText(QRectF(x, y, width, 22), Qt.AlignVCenter, QFontMetrics(p.font()).elidedText(stem, Qt.ElideRight, int(width)))
        y += 24
        if part["lines"]:
            p.setFont(font(t, TIME_PX + 1))
            p.setPen(QColor(t.dim))
            p.drawText(QRectF(x, y, width, part["lines"] * EXCERPT_LH), Qt.TextWordWrap | Qt.AlignLeft | Qt.AlignTop,
                       part["excerpt"])
            y += part["lines"] * EXCERPT_LH + 6
        p.setFont(self._time_font())
        p.setPen(QColor(t.dim))
        kind = (Path(name).suffix.lstrip(".") or "archivo").upper()
        p.drawText(QRectF(x, y, width, 18), Qt.AlignVCenter, f"{kind} · {human_size(int(att.get('size_bytes') or 0))}")

    def _paint_mark(self, p, mark, message):
        """El estado de lo mío: reloj mientras está en espera, ✓ cuando ya se envió."""
        t = self.theme
        failed = bool(message.get("error"))
        if message["status"] == "sent":
            p.setPen(QPen(accent(t, True), 1.8, Qt.SolidLine, Qt.RoundCap, Qt.RoundJoin))
            p.drawLine(QPointF(mark.left() + 2, mark.center().y()), QPointF(mark.left() + 6, mark.bottom() - 3))
            p.drawLine(QPointF(mark.left() + 6, mark.bottom() - 3), QPointF(mark.right() - 1, mark.top() + 3))
        else:
            p.setPen(glyphs.pen(QColor(t.warn if failed else t.dim), 1.3))
            p.setBrush(Qt.NoBrush)
            glyphs.clock(p, mark)


def _order(message):
    return (message["sent_at"], message["id"])


def _rounded(rect, radius):
    path = QPainterPath()
    path.addRoundedRect(rect, radius, radius)
    return path


class ChatBoard(QWidget):
    notify = Signal(str)  # un aviso corto (mensaje nuevo con el chat cerrado, errores): sale como el resto de avisos
    side_changed = Signal()  # el árbol de archivos se abrió o se cerró: el buscador cambia de ancho

    def __init__(self, theme, call, escape=lambda: None, children=lambda path: [], roots=lambda: ([], ())):
        """`call(acción, **datos)`: el núcleo, devuelve {ok, data|error}; `escape()`: Esc (el buscador se cierra);
        `children(ruta)` y `roots()` -> (filas, desplegadas): las carpetas del árbol de archivos que se abre a la derecha."""
        super().__init__()
        self.setFocusPolicy(Qt.StrongFocus)
        self.setAcceptDrops(True)
        self.theme, self._call, self._escape = theme, call, escape
        self._roots = roots
        self.tree_open = False
        self.tree = TreeList(theme, children, self._tree_open_row, on_pick=self._tree_pick)
        self.tree.setParent(self)
        self.tree.hide()
        self.device, self.state, self.detail = "pc", "connecting", ""
        self.staged = []  # archivos listos para salir con el próximo mensaje
        self._note = ""  # un aviso corto sobre el compositor (por ejemplo, un archivo demasiado grande)
        self._error_note = False  # ¿el aviso es un error? (sale en rojo)
        self._chips = []
        self.view = ChatView(theme)
        self.view.setParent(self)
        self.composer = Composer()
        self.composer.setParent(self)
        self.composer.document().contentsChanged.connect(self._arrange)
        self.composer.submit.connect(self.send)
        self.composer.attach.connect(self.pick_files)
        self.composer.at.connect(self.pick_files)
        self.composer.escaped.connect(self.escape)
        self.composer.scroll_page.connect(self.view.scroll_page)
        self.composer.files.connect(self.stage)
        self.view.older_wanted.connect(lambda before: self._call("chat.older", before=before))
        self.view.open_attachment.connect(self._open)
        self.view.fetch_attachment.connect(lambda m, a: self._call("chat.fetch_attachment", message_id=m, attachment_id=a))
        self.view.retry.connect(lambda mid: self._call("chat.retry", id=mid))
        self.view.delete.connect(lambda mid: self._call("chat.delete", id=mid))
        self.view.copy.connect(self._copy)
        self.view.download.connect(self._download)
        self._copy_after = set()  # adjuntos que se están bajando para copiarlos al portapapeles
        self._note_timer = QTimer(self)
        self._note_timer.setSingleShot(True)
        self._note_timer.setInterval(4000)
        self._note_timer.timeout.connect(self._clear_note)
        self.retheme(theme)

    # ---------- entrar y salir ----------

    def open(self):
        """Al entrar en el chat: lo guardado, con la conexión, y listo para escribir."""
        result = self._call("chat.history")
        if result.get("ok"):
            data = result["data"]
            self.device, self.state, self.detail = data["device"], data["state"], data["detail"]
            self.view.device = self.device
            self.view.set_messages(data["messages"])
        self._arrange()
        self.composer.setFocus()
        self.update()

    def leave(self):
        """Al salir: el borrador y los archivos preparados se quedan donde están."""

    def escape(self):
        """Esc: si el árbol de archivos está abierto, lo cierra; si no, se cierra el buscador."""
        if self.tree_open:
            self.toggle_tree(False)
        else:
            self._escape()

    def retheme(self, theme):
        self.theme = theme
        self.view.retheme(theme)
        t = theme
        self.setStyleSheet(
            stylesheet(t, flat_style=True)
            + f"QTextEdit#ChatComposer {{ background: transparent; border: 0; font: {BODY_PX}px '{t.font_family}';"
            f" color: {t.ink}; selection-background-color: {_css(t.gold_soft)}; }}")
        self.update()

    # ---------- lo que llega del servicio ----------

    def on_event(self, event):
        kind = event.get("kind")
        if kind == "connection":
            self.state, self.detail = event["state"], event.get("detail", "")
            self.update()
        elif kind == "history":
            self.view.set_messages(event["messages"])
        elif kind == "message":
            message = event["message"]
            self.view.add(message)
            if event.get("incoming") and not self.isVisible():
                text = message.get("body") or ("📎 " + (message["attachments"][0]["file_name"] if message["attachments"] else ""))
                self.notify.emit(f"Chat · {message.get('device') or 'otro dispositivo'}: {text.strip()[:80]}")
        elif kind == "status":
            if event.get("message"):
                self.view.replace(event["message"])
        elif kind == "deleted":
            self.view.remove(event["id"])
        elif kind == "older":
            self.view.prepend(event["messages"])
        elif kind == "attachment":
            self.view.set_attachment_path(event["attachment_id"], event["path"])
            if event["attachment_id"] in self._copy_after:
                self._copy_after.discard(event["attachment_id"])
                self._copy_file(event["path"])
        elif kind == "saved":
            self._say(f"Guardado en Descargas: {event['name']}")
        elif kind == "error":
            self.notify.emit(event["error"])

    # ---------- enviar y adjuntar ----------

    def send(self):
        text = self.composer.toPlainText().strip()
        if not text and not self.staged:
            return
        result = self._call("chat.send", text=text, paths=list(self.staged))
        if not result.get("ok"):
            self._say(result["error"]["message"], warn=True)
            return
        self.composer.clear()
        self.staged = []
        self._arrange()
        self.update()

    def stage(self, paths):
        """Archivos listos para salir (pegados, soltados o elegidos con Ctrl+O)."""
        for path in paths:
            if path not in self.staged:
                self.staged.append(path)
        self._arrange()
        self.composer.setFocus()
        self.update()

    def pick_files(self):
        """«+», «@» o Ctrl+O: abre (o cierra) a la derecha el árbol de carpetas para elegir qué mandar."""
        self.toggle_tree()

    def toggle_tree(self, show=None):
        show = (not self.tree_open) if show is None else bool(show)
        if show == self.tree_open:
            return
        self.tree_open = show
        if show:
            rows, expanded = self._roots()
            self.tree.set_roots(rows, expanded=expanded)
        self._arrange()
        self.composer.setFocus()
        self.side_changed.emit()

    def _tree_pick(self, row):
        """Un clic en un archivo del árbol lo manda (las carpetas se despliegan solas)."""
        self._send_path(row["id"], row.get("name") or Path(row["id"]).name)

    def _tree_open_row(self, row, ctrl):
        if not row.get("is_dir"):
            self._tree_pick(row)

    def _send_path(self, path, name):
        result = self._call("chat.send", text="", paths=[path])
        if result.get("ok"):
            self._say(f"Enviado: {name}")
        else:
            self._say(result["error"]["message"], warn=True)

    def _message(self, message_id):
        return next((m for m in self.view.messages if m["id"] == message_id), None)

    def _copy(self, message_id):
        """«Copiar»: el texto del mensaje; si es solo un archivo, el archivo (se baja antes si hace falta)."""
        message = self._message(message_id)
        if message is None:
            return
        text = (message.get("body") or "").strip()
        if text:
            QApplication.clipboard().setText(text)
            self._say("Texto copiado")
            return
        for att in message["attachments"]:
            path = att.get("local_path")
            if path and Path(path).is_file():
                self._copy_file(path)
                return
        if message["attachments"]:
            att = message["attachments"][0]
            self._copy_after.add(att["id"])
            self._call("chat.fetch_attachment", message_id=message_id, attachment_id=att["id"])
            self._say("Bajando el archivo para copiarlo…")

    def _copy_file(self, path):
        mime = QMimeData()
        mime.setUrls([QUrl.fromLocalFile(path)])  # se pega en el Explorador como un archivo
        QApplication.clipboard().setMimeData(mime)
        self._say("Archivo copiado")

    def _download(self, message_id):
        """«Descargar»: una copia de cada adjunto en la carpeta Descargas."""
        message = self._message(message_id)
        for att in (message or {}).get("attachments", []):
            self._call("chat.save_attachment", message_id=message_id, attachment_id=att["id"])

    def _open(self, message_id, attachment_id):
        self._call("chat.fetch_attachment", message_id=message_id, attachment_id=attachment_id, open=True)

    def dragEnterEvent(self, event):
        if event.mimeData().hasUrls():
            event.acceptProposedAction()

    def dropEvent(self, event):
        paths = [str(Path(u.toLocalFile())) for u in event.mimeData().urls() if u.isLocalFile() and Path(u.toLocalFile()).is_file()]
        if paths:
            self.stage(paths)
            event.acceptProposedAction()

    def _say(self, text, warn=False):
        self._note, self._error_note = text, warn
        self._note_timer.start()
        self.update()

    def _clear_note(self):
        self._note = ""
        self.update()

    # ---------- geometría ----------

    def _composer_h(self):
        doc = self.composer.document()
        doc.setTextWidth(max(self.composer.viewport().width(), 100))
        return int(min(max(doc.size().height() + 14, COMPOSER_MIN), COMPOSER_MAX))

    def _rects(self):
        """Dónde va cada zona: cabecera, mensajes, archivos preparados, compositor (con sus dos botones), pie y, a la derecha,
        el árbol de archivos cuando está abierto (el resto se estrecha para dejarle sitio)."""
        w, h = self.width() - (TREE_W + TREE_GAP if self.tree_open else 0), self.height()
        foot = QRectF(MARGIN, h - FOOT_H, w - 2 * MARGIN, FOOT_H)
        comp_h = self._composer_h()
        composer = QRectF(MARGIN, foot.top() - comp_h - 4, w - 2 * MARGIN, comp_h)
        stage = QRectF(MARGIN, composer.top() - STAGE_H - 4, w - 2 * MARGIN, STAGE_H) if self.staged else None
        view_bottom = (stage.top() if stage else composer.top()) - 6
        view = QRectF(0, HEAD_H, w, max(view_bottom - HEAD_H, 40))
        # los dos botones, redondos y abajo del campo (si crece con varias líneas, se quedan junto a la última)
        button_y = composer.bottom() - (COMPOSER_MIN + CONTROL_W) / 2
        side = QRectF(w + TREE_GAP, HEAD_H, TREE_W - MARGIN, h - HEAD_H - 10) if self.tree_open else None
        return {"head": QRectF(MARGIN, 0, w - 2 * MARGIN, HEAD_H), "view": view, "stage": stage, "composer": composer,
                "attach": QRectF(composer.left() + 10, button_y, CONTROL_W, CONTROL_W),
                "send": QRectF(composer.right() - CONTROL_W - 10, button_y, CONTROL_W, CONTROL_W), "foot": foot,
                "side": side}

    def _arrange(self):
        r = self._rects()
        self.view.setGeometry(r["view"].toRect())
        if r["side"]:  # el árbol, debajo de su título
            self.tree.setGeometry(r["side"].adjusted(4, SIDE_HEAD, -4, -4).toRect())
        self.tree.setVisible(bool(r["side"]))
        c = r["composer"]
        self.composer.setGeometry(round(c.left() + CONTROL_W + 20), round(c.top() + 5), round(c.width() - 2 * CONTROL_W - 40),
                                  round(c.height() - 10))
        self.update()

    def resizeEvent(self, event):
        super().resizeEvent(event)
        self._arrange()

    # ---------- ratón ----------

    def mouseReleaseEvent(self, event):
        pos, r = event.position(), self._rects()
        if event.button() != Qt.LeftButton:
            return
        if r["attach"].contains(pos):
            self.pick_files()
        elif r["send"].contains(pos):
            self.send()
        else:
            for rect, path in self._chips_at(r):
                if rect.contains(pos):
                    self.staged.remove(path)
                    self._arrange()
                    return

    def _chips_at(self, r):
        """[(zona de la ✕, ruta)] de los archivos preparados."""
        if not r["stage"]:
            return []
        out, x = [], r["stage"].left()
        metrics = QFontMetrics(font(self.theme, TIME_PX + 1))
        for path in self.staged:
            label = metrics.elidedText(Path(path).name, Qt.ElideMiddle, 180)
            width = metrics.horizontalAdvance(label) + 66
            out.append((QRectF(x + width - 28, r["stage"].top() + 4, 24, STAGE_H - 8), path))
            x += width + 8
        return out

    # ---------- pintura ----------

    def paintEvent(self, _):
        t = self.theme
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        r = self._rects()
        self._paint_head(p, r["head"])
        if r["side"]:  # el panel del árbol de archivos
            paint_flat(p, t, r["side"], 16)
            p.setFont(font(t, TIME_PX + 1, bold=True))
            p.setPen(QColor(t.dim))
            p.drawText(QRectF(r["side"].left() + 16, r["side"].top(), r["side"].width() - 32, SIDE_HEAD), Qt.AlignVCenter,
                       "Un clic en un archivo lo envía")
        if r["stage"]:
            self._paint_stage(p, r)
        paint_flat_well(p, t, r["composer"], COMPOSER_R)
        self._round_button(p, r["attach"], "plus")
        self._round_button(p, r["send"], "send", strong=bool(self.composer.toPlainText().strip() or self.staged))
        if self._note:  # un aviso corto, en una pastilla justo encima del compositor
            p.setFont(font(t, TIME_PX))
            text = QFontMetrics(p.font()).elidedText(self._note, Qt.ElideRight, int(r["composer"].width() - 40))
            width = QFontMetrics(p.font()).horizontalAdvance(text) + 28
            top = (r["stage"].top() if r["stage"] else r["composer"].top()) - 30
            pill = QRectF(r["composer"].center().x() - width / 2, top, width, 24)
            paint_flat(p, t, pill, 12)
            p.setPen(QColor(t.warn) if self._error_note else QColor(t.dim))
            p.drawText(pill, Qt.AlignCenter, text)

    def _paint_head(self, p, rect):
        t = self.theme
        p.setFont(font(t, 15, bold=True))
        p.setPen(QColor(t.ink))
        p.drawText(QRectF(rect.left(), rect.top(), 120, rect.height() - 2), Qt.AlignVCenter, "Chat")
        label, hint, tone = STATES.get(self.state, STATES["connecting"])
        color = QColor(t.warn) if tone == "warn" else accent(t, True) if tone == "gold" else QColor(t.dim)
        p.setFont(font(t, TIME_PX))
        text = label + (f" · {hint}" if hint else "")
        if self.state == "auth_error" and self.detail or self.state == "unconfigured" and self.detail:
            text = f"{label} · {self.detail}"
        width = QFontMetrics(p.font()).horizontalAdvance(text)
        room = rect.width() - 140
        text = QFontMetrics(p.font()).elidedText(text, Qt.ElideRight, int(room))
        width = min(width, room)
        p.setPen(color)
        p.drawText(QRectF(rect.right() - width - 4, rect.top(), width + 4, rect.height() - 2), Qt.AlignVCenter | Qt.AlignRight, text)
        p.setPen(Qt.NoPen)
        p.setBrush(color)
        p.drawEllipse(QPointF(rect.right() - width - 16, rect.center().y() - 1), 4, 4)

    def _paint_stage(self, p, r):
        t = self.theme
        metrics = QFontMetrics(font(t, TIME_PX + 1))
        x = r["stage"].left()
        p.setFont(font(t, TIME_PX + 1))
        for path in self.staged:
            label = metrics.elidedText(Path(path).name, Qt.ElideMiddle, 180)
            width = metrics.horizontalAdvance(label) + 66
            chip = QRectF(x, r["stage"].top() + 2, width, STAGE_H - 4)
            paint_flat_well(p, t, chip, 12)
            icon = QRectF(chip.left() + 8, chip.center().y() - 9, 18, 18)
            file_icons.shared().file().paint(p, icon.toRect())
            p.setPen(QColor(t.ink))
            p.drawText(QRectF(icon.right() + 6, chip.top(), width - 58, chip.height()), Qt.AlignVCenter, label)
            p.setPen(glyphs.pen(QColor(t.dim), 1.4))
            glyphs.cross(p, QRectF(chip.right() - 26, chip.center().y() - 9, 18, 18))
            x += width + 8

    def _round_button(self, p, rect, glyph, strong=False):
        """«+» (adjuntar) con un borde fino, o la flecha de enviar: un disco del acento si hay algo que mandar."""
        t = self.theme
        if glyph == "send":
            p.setPen(Qt.NoPen)
            p.setBrush(accent(t, True) if strong else QColor(255, 255, 255, 22))
        else:
            p.setPen(QPen(FLAT_EDGE, 1))
            p.setBrush(QColor(255, 255, 255, 10))
        p.drawEllipse(rect)
        c, s = rect.center(), rect.width() * 0.24
        ink = QColor(t.pick_ink) if strong else QColor(t.dim) if glyph == "send" else QColor(t.ink)
        p.setPen(QPen(ink, 2, Qt.SolidLine, Qt.RoundCap, Qt.RoundJoin))
        if glyph == "plus":
            p.drawLine(QPointF(c.x() - s, c.y()), QPointF(c.x() + s, c.y()))
            p.drawLine(QPointF(c.x(), c.y() - s), QPointF(c.x(), c.y() + s))
        else:  # una flecha hacia arriba
            p.drawLine(QPointF(c.x(), c.y() + s), QPointF(c.x(), c.y() - s))
            p.drawLine(QPointF(c.x() - s * 0.85, c.y() - s * 0.15), QPointF(c.x(), c.y() - s))
            p.drawLine(QPointF(c.x() + s * 0.85, c.y() - s * 0.15), QPointF(c.x(), c.y() - s))

    def event(self, event):
        # Ctrl+O también con el foco fuera del compositor (por ejemplo, tras pulsar un botón)
        if event.type() == QEvent.KeyPress and event.key() == Qt.Key_O and event.modifiers() & Qt.ControlModifier:
            self.pick_files()
            return True
        return super().event(event)


def modal_open():
    """True si hay un diálogo modal abierto (el de elegir archivos): el buscador no debe cerrarse por perder el foco."""
    return QApplication.activeModalWidget() is not None
