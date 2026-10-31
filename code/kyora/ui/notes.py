"""Las notas de `>notes`, dentro del buscador (que se ensancha), como la referencia: un editor sencillo y plano (tipo
GNOME, la excepción de DISEÑO.md).

Arriba, centrada, la barra de formato (negrita, cursiva, tachado, título, lista, cita y enlace: lo que cabe en un .md).
Debajo, "TÍTULO", el título de la nota, una línea fina y el texto con su formato. Una sola nota a la vista: Ctrl+N
deja la hoja en blanco con un desvanecido suave, y Ctrl+RePág / Ctrl+AvPág (o las flechas de arriba) pasan de nota
igual. Se guarda solo al dejar de escribir, como Markdown. Ctrl+Supr dos veces la manda a la Papelera (la primera
avisa abajo; sin diálogos). Esc cierra.
"""
from datetime import datetime

from PySide6.QtCore import QEasingCurve, QEvent, QPointF, QRectF, Qt, QTimer
from PySide6.QtGui import (
    QColor,
    QFont,
    QPainter,
    QPainterPath,
    QPen,
    QTextBlockFormat,
    QTextCharFormat,
    QTextCursor,
    QTextDocument,
    QTextFormat,
    QTextListFormat,
)
from PySide6.QtWidgets import QLineEdit, QTextEdit, QWidget

from kyora.notes.store import legacy_to_markdown
from kyora.ui import glyphs
from kyora.ui.anim import Tween
from kyora.ui.bar import font
from kyora.ui.explorer.style import _css, stylesheet
from kyora.ui.hub.cards import FLAT_EDGE, paint_flat

SAVE_MS = 600
FADE_MS = 140  # cada mitad del desvanecido al cambiar de nota
MARGIN = 26
BAR_H = 38
BUTTON_W = 38
HEAD_Y = 62  # la línea de "TÍTULO", el paginador y la fecha
TITLE_Y = 86
TITLE_H = 40
BODY_Y = 140
FOOT = 34
MARKDOWN = QTextDocument.MarkdownDialectGitHub
QUOTE = QTextFormat.Property.BlockQuoteLevel
SIZE_ADJUST = QTextFormat.Property.FontSizeAdjustment
DAYS = ("lun", "mar", "mié", "jue", "vie", "sáb", "dom")
MONTHS = ("ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic")
# los botones de la barra: (clave, lo que se dibuja, ayuda)
TOOLS = (
    ("bold", "B", "Negrita (Ctrl+B)"),
    ("italic", "I", "Cursiva (Ctrl+I)"),
    ("strike", "S", "Tachado"),
    None,
    ("heading", "H", "Título dentro de la nota"),
    ("list", "list", "Lista"),
    ("quote", "quote", "Cita"),
    None,
    ("link", "link", "Enlace (Ctrl+K)"),
)


def _spacing(in_list):
    """El aire de un bloque: los párrafos algo separados y con renglones holgados; los puntos de una lista, juntos."""
    fmt = QTextBlockFormat()
    fmt.setBottomMargin(3 if in_list else 10)
    fmt.setLineHeight(135.0, QTextBlockFormat.ProportionalHeight.value)
    return fmt


def _when(stamp):
    """"vie 23 oct" de "2026-10-23 09:23"."""
    try:
        moment = datetime.strptime(stamp, "%Y-%m-%d %H:%M")
    except (TypeError, ValueError):
        return ""
    return f"{DAYS[moment.weekday()]} {moment.day} {MONTHS[moment.month - 1]}"


class NoteEditor(QTextEdit):
    """El texto de la nota. Las citas llevan la barrita vertical del acento a la izquierda, como la referencia."""

    def __init__(self, theme):
        super().__init__()
        self.theme = theme
        self.setObjectName("NoteBody")
        self.setAcceptRichText(False)  # lo pegado llega como texto: el formato se pone con la barra
        self.setTabChangesFocus(False)

    def paintEvent(self, event):
        super().paintEvent(event)
        doc = self.document()
        layout = doc.documentLayout()
        p = QPainter(self.viewport())
        p.setRenderHint(QPainter.Antialiasing)
        p.setPen(Qt.NoPen)
        p.setBrush(QColor(self.theme.gold))
        dx, dy = self.horizontalScrollBar().value(), self.verticalScrollBar().value()
        block = doc.begin()
        while block.isValid():
            if block.blockFormat().intProperty(QUOTE) > 0:
                rect = layout.blockBoundingRect(block)
                p.drawRoundedRect(QRectF(doc.documentMargin() - dx, rect.top() - dy + 2, 3, rect.height() - 4), 1.5, 1.5)
            block = block.next()


class FormatBar(QWidget):
    """La barra de formato, pintada a mano: una píldora plana con sus botones; los que están en uso, encendidos."""

    def __init__(self, theme, on_tool):
        super().__init__()
        self.theme, self._on_tool = theme, on_tool
        self.active = set()
        self._hover = None
        self.setMouseTracking(True)
        self.setCursor(Qt.PointingHandCursor)
        width = sum(BUTTON_W if tool else 14 for tool in TOOLS) + 12
        self.setFixedSize(width, BAR_H)

    def _buttons(self):
        x, out = 6, []
        for tool in TOOLS:
            if tool is None:
                out.append((None, QRectF(x + 6, 9, 1, BAR_H - 18)))
                x += 14
            else:
                out.append((tool, QRectF(x, 3, BUTTON_W, BAR_H - 6)))
                x += BUTTON_W
        return out

    def _at(self, pos):
        return next((tool[0] for tool, rect in self._buttons() if tool and rect.contains(pos)), None)

    def mouseMoveEvent(self, event):
        hover = self._at(event.position())
        if hover != self._hover:
            self._hover = hover
            tip = next((tool[2] for tool, _ in self._buttons() if tool and tool[0] == hover), "")
            self.setToolTip(tip)
            self.update()

    def leaveEvent(self, _):
        self._hover = None
        self.update()

    def mousePressEvent(self, event):
        key = self._at(event.position())
        if key and event.button() == Qt.LeftButton:
            self._on_tool(key)

    def paintEvent(self, _):
        t = self.theme
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        paint_flat(p, t, self.rect(), BAR_H / 2, hi=True)
        for tool, rect in self._buttons():
            if tool is None:
                p.fillRect(rect, FLAT_EDGE)
                continue
            key, label, _ = tool
            on = key in self.active
            if on or key == self._hover:
                p.setPen(Qt.NoPen)
                p.setBrush(QColor(t.gold_soft) if on else QColor(255, 255, 255, 18))
                p.drawRoundedRect(rect.adjusted(2, 1, -2, -1), 9, 9)
            color = QColor(t.gold if on else t.ink)
            box = QRectF(rect.center().x() - 8, rect.center().y() - 8, 16, 16)
            if label == "list":
                p.setPen(glyphs.pen(color, 1.6))
                for i in range(3):
                    y = box.top() + 3 + i * 5
                    p.drawPoint(QPointF(box.left() + 2, y))
                    p.drawLine(QPointF(box.left() + 6, y), QPointF(box.right(), y))
            elif label == "quote":
                f = font(t, 22, bold=True)
                p.setFont(f)
                p.setPen(color)
                p.drawText(rect.adjusted(0, 6, 0, 0), Qt.AlignCenter, "”")
            elif label == "link":
                p.setPen(glyphs.pen(color, 1.6))
                p.setBrush(Qt.NoBrush)
                p.save()
                p.translate(box.center())
                p.rotate(-45)
                p.drawRoundedRect(QRectF(-8, -3.5, 9, 7), 3.5, 3.5)
                p.drawRoundedRect(QRectF(-1, -3.5, 9, 7), 3.5, 3.5)
                p.restore()
            else:
                f = font(t, 16, bold=label in ("B", "H"))
                f.setItalic(label == "I")
                f.setStrikeOut(label == "S")
                p.setFont(f)
                p.setPen(color)
                p.drawText(rect, Qt.AlignCenter, label)


class NotesBoard(QWidget):
    def __init__(self, theme, call, escape=lambda: None):
        """`call(acción, **datos)`: el núcleo; `escape()`: Esc (el buscador se cierra)."""
        super().__init__()
        self.setFocusPolicy(Qt.StrongFocus)
        self.theme, self._call, self._escape = theme, call, escape
        self.notes = []
        self.index = 0
        self.armed = None  # la nota que espera el segundo Ctrl+Supr
        self._cover = 0.0  # 0..1: la tapa del desvanecido sobre el texto
        self._after_cover = None  # lo que se hace con la hoja tapada (cambiar de nota)
        self._loading = False
        self._fade = Tween(self, self._set_cover, self._faded)
        self._save_timer = QTimer(self)
        self._save_timer.setSingleShot(True)
        self._save_timer.setInterval(SAVE_MS)
        self._save_timer.timeout.connect(self._save)
        self.bar = FormatBar(theme, self.apply_tool)
        self.bar.setParent(self)
        self.title = QLineEdit(self)
        self.title.setObjectName("NoteTitle")
        self.title.setPlaceholderText("Sin título")
        self.title.textEdited.connect(lambda _: self._edited())
        self.text = NoteEditor(theme)
        self.text.setParent(self)
        self.text.setPlaceholderText("Escribe tu nota…")
        self.text.textChanged.connect(self._edited)
        self.text.cursorPositionChanged.connect(self._sync_bar)
        self.text.currentCharFormatChanged.connect(lambda _: self._sync_bar())
        self.link = QLineEdit(self)  # el campo del enlace, en la propia pantalla (sin diálogos)
        self.link.setObjectName("LinkField")
        self.link.setPlaceholderText("https://…  (Enter pone el enlace · Esc cancela)")
        self.link.returnPressed.connect(self._apply_link)
        self.link.hide()
        self.cover = _Cover(self)  # la tapa del desvanecido, encima del título y del texto
        for widget in (self, self.title, self.text, self.link):
            widget.installEventFilter(self)
        self.retheme(theme)

    # ---------- entrar y salir ----------

    def open(self):
        """Al entrar en `>notes`: la nota más reciente, lista para escribir."""
        self.reload()
        self.index = 0
        self.armed = None
        self._fill()
        self.focus_editor()

    def leave(self):
        """Al salir de `>notes` (o cerrar el buscador): se guarda lo escrito."""
        self.flush()
        self.armed = None
        self.link.hide()

    def escape(self):
        if self.link.isVisible():
            self.link.hide()
            self.text.setFocus()
            return
        self.leave()
        self._escape()

    def retheme(self, theme):
        self.theme = theme
        t = theme
        self.setStyleSheet(
            stylesheet(t, flat_style=True)
            + f"QLineEdit#NoteTitle {{ background: transparent; border: 0; padding: 2px 0;"
            f" font: 600 {t.font_px}px '{t.font_family}'; color: {t.ink}; }}"
            f"QTextEdit#NoteBody {{ background: transparent; border: 0; font: {t.font_px}px '{t.font_family}'; color: {t.ink};"
            f" selection-background-color: {_css(t.gold_soft)}; }}"
            f"QLineEdit#LinkField {{ border-radius: 10px; padding: 4px 10px; }}"
        )

    # ---------- datos ----------

    def _do(self, action, **payload):
        result = self._call(action, **payload)
        return result["data"] if result["ok"] else None

    def reload(self):
        self.notes = self._do("notes.list") or []
        self.index = min(self.index, max(len(self.notes) - 1, 0))

    def current(self):
        return self.notes[self.index] if self.notes else None

    def _edited(self):
        if not self._loading:
            self._disarm()
            self._save_timer.start()

    def _markdown(self):
        return self.text.document().toMarkdown(MARKDOWN).strip("\n")

    def _save(self):
        note = self.current()
        if note is None:
            if not (self.title.text().strip() or self.text.toPlainText().strip()):
                return
            note = self._do("notes.create")  # se escribió sin ninguna nota: se crea al guardar
            if not note:
                return
            self.notes.insert(0, note)
            self.index = 0
        title, text = self.title.text(), self._markdown()
        if (title, text) != (note["title"], note["text"]) or not note.get("markdown"):
            saved = self._do("notes.save", id=note["id"], title=title, text=text)
            if saved:
                self.notes[self.index] = saved
                self.update()

    def flush(self):
        if self._save_timer.isActive():
            self._save_timer.stop()
            self._save()

    def _fill(self):
        """Pone la nota actual en los campos (o la hoja en blanco si no hay ninguna)."""
        note = self.current()
        self._loading = True
        self.title.setText(note["title"] if note else "")
        text = note["text"] if note else ""
        doc = self.text.document()
        doc.setMarkdown(text if not note or note.get("markdown") else legacy_to_markdown(text), MARKDOWN)
        block = doc.begin()
        while block.isValid():  # aire entre párrafos, como la referencia (el .md no lo guarda: es solo cómo se ve)
            QTextCursor(block).mergeBlockFormat(_spacing(block.textList() is not None))
            block = block.next()
        doc.clearUndoRedoStacks()
        self.text.moveCursor(QTextCursor.End)
        self._loading = False
        self._sync_bar()
        self.update()

    def focus_editor(self):
        (self.text if self.title.text() else self.title).setFocus()

    def _disarm(self):
        if self.armed is not None:
            self.armed = None
            self.update()

    def _blank(self):
        note = self.current()
        return note is not None and not note["title"].strip() and not note["text"].strip()

    # ---------- acciones ----------

    def new_note(self):
        """Ctrl+N: el contenido se desvanece y queda la hoja en blanco para otra nota."""
        self.flush()
        self._disarm()
        if self._blank():  # ya está en blanco: no se amontonan notas vacías
            self.title.setFocus()
            return

        def swap():
            note = self._do("notes.create")
            if note:
                self.notes.insert(0, note)
                self.index = 0
            self._fill()
            self.title.setFocus()

        self._cover_and(swap)

    def step(self, delta):
        if len(self.notes) < 2:
            return
        self.flush()
        self._disarm()
        target = (self.index + delta) % len(self.notes)

        def swap():
            self.index = target
            self._fill()
            self.focus_editor()

        self._cover_and(swap)

    def delete_note(self):
        """Ctrl+Supr dos veces: la primera solo avisa abajo (sin ventanas)."""
        note = self.current()
        if note is None:
            return
        if self.armed != note["id"]:
            self.armed = note["id"]
            self.update()
            return
        self.armed = None
        self._save_timer.stop()
        if self._do("notes.delete", id=note["id"]) is None:
            return

        def swap():
            self.notes.pop(self.index)
            self.index = min(self.index, max(len(self.notes) - 1, 0))
            self._fill()
            self.focus_editor()

        self._cover_and(swap)

    # ---------- el desvanecido ----------

    def _cover_and(self, swap):
        """Tapa el texto con el color del fondo, hace `swap` con la hoja tapada y la destapa."""
        self._after_cover = swap
        self._fade.start(self._cover, 1.0, FADE_MS, QEasingCurve.InOutSine)

    def _set_cover(self, value):
        self._cover = float(value)
        self.cover.update()

    def _faded(self):
        if self._after_cover is not None:
            swap, self._after_cover = self._after_cover, None
            swap()
            self._fade.start(1.0, 0.0, FADE_MS, QEasingCurve.InOutSine)

    # ---------- formato ----------

    def apply_tool(self, key):
        editor = self.text
        cursor = editor.textCursor()
        if key == "link":
            self._ask_link()
            return
        if key in ("bold", "italic", "strike"):
            fmt = QTextCharFormat()
            current = editor.currentCharFormat()
            if key == "bold":
                fmt.setFontWeight(QFont.Normal if current.fontWeight() > QFont.Normal else QFont.Bold)
            elif key == "italic":
                fmt.setFontItalic(not current.fontItalic())
            else:
                fmt.setFontStrikeOut(not current.fontStrikeOut())
            editor.mergeCurrentCharFormat(fmt)
        elif key == "heading":
            block = QTextBlockFormat()
            heading = cursor.blockFormat().headingLevel() == 0
            block.setHeadingLevel(2 if heading else 0)
            chars = QTextCharFormat()
            chars.setProperty(SIZE_ADJUST, 1 if heading else 0)
            chars.setFontWeight(QFont.Bold if heading else QFont.Normal)
            cursor.beginEditBlock()
            cursor.mergeBlockFormat(block)
            cursor.select(QTextCursor.BlockUnderCursor)
            cursor.mergeCharFormat(chars)
            cursor.endEditBlock()
            editor.mergeCurrentCharFormat(chars)
        elif key == "list":
            current = cursor.currentList()
            if current is not None:
                current.remove(cursor.block())
                block = cursor.blockFormat()
                block.setIndent(0)
                cursor.setBlockFormat(block)
                cursor.mergeBlockFormat(_spacing(False))
            else:
                cursor.createList(QTextListFormat.ListDisc)
                cursor.mergeBlockFormat(_spacing(True))
        elif key == "quote":
            block = cursor.blockFormat()
            quoted = block.intProperty(QUOTE) > 0
            block.setProperty(QUOTE, 0 if quoted else 1)
            block.setLeftMargin(0 if quoted else 18)
            cursor.setBlockFormat(block)
        editor.setFocus()
        self._sync_bar()

    def _sync_bar(self):
        """Los botones encendidos: el formato que hay donde está el cursor."""
        cursor = self.text.textCursor()
        chars = self.text.currentCharFormat()
        active = set()
        if chars.fontWeight() > QFont.Normal and cursor.blockFormat().headingLevel() == 0:
            active.add("bold")
        if chars.fontItalic():
            active.add("italic")
        if chars.fontStrikeOut():
            active.add("strike")
        if chars.isAnchor():
            active.add("link")
        if cursor.blockFormat().headingLevel():
            active.add("heading")
        if cursor.currentList() is not None:
            active.add("list")
        if cursor.blockFormat().intProperty(QUOTE) > 0:
            active.add("quote")
        if active != self.bar.active:
            self.bar.active = active
            self.bar.update()

    def _ask_link(self):
        self.link.clear()
        self.link.show()
        self.link.raise_()
        self.link.setFocus()

    def _apply_link(self):
        url = self.link.text().strip()
        self.link.hide()
        self.text.setFocus()
        if not url:
            return
        if "://" not in url and not url.startswith("mailto:"):
            url = "https://" + url
        cursor = self.text.textCursor()
        fmt = QTextCharFormat()
        fmt.setAnchor(True)
        fmt.setAnchorHref(url)
        fmt.setForeground(QColor(self.theme.gold))
        fmt.setFontUnderline(True)
        if cursor.hasSelection():
            cursor.mergeCharFormat(fmt)
        else:
            cursor.insertText(url, fmt)
            cursor.setCharFormat(QTextCharFormat())  # lo que se escriba después ya no es enlace
            self.text.setTextCursor(cursor)

    # ---------- teclas ----------

    def eventFilter(self, obj, event):
        # se miran aquí y no con atajos: el texto se queda con Ctrl+Supr (borrar palabra) y otras antes que ellos
        if event.type() == QEvent.KeyPress and self._key(event):
            return True
        return super().eventFilter(obj, event)

    def _key(self, event):
        key, mods = event.key(), event.modifiers()
        ctrl = bool(mods & Qt.ControlModifier) and not mods & (Qt.AltModifier | Qt.ShiftModifier)
        if key == Qt.Key_Escape:
            self.escape()
            return True
        if not ctrl:
            return False
        actions = {
            Qt.Key_N: self.new_note, Qt.Key_PageUp: lambda: self.step(-1), Qt.Key_PageDown: lambda: self.step(1),
            Qt.Key_Delete: self.delete_note, Qt.Key_B: lambda: self.apply_tool("bold"),
            Qt.Key_I: lambda: self.apply_tool("italic"), Qt.Key_K: lambda: self.apply_tool("link"),
        }
        if key in actions:
            actions[key]()
            return True
        return False

    # ---------- geometría ----------

    def _pager_rects(self):
        right = self.width() - MARGIN
        return QRectF(right - 110, HEAD_Y - 2, 26, 26), QRectF(right - 26, HEAD_Y - 2, 26, 26)

    def resizeEvent(self, event):
        w, h = self.width(), self.height()
        self.bar.move(round((w - self.bar.width()) / 2), 10)
        self.link.setGeometry(round((w - 460) / 2), 10 + BAR_H + 6, 460, 34)
        self.title.setGeometry(MARGIN - 2, TITLE_Y, w - 2 * MARGIN, TITLE_H)
        self.text.setGeometry(MARGIN - 6, BODY_Y, w - 2 * MARGIN + 12, max(h - BODY_Y - FOOT, 40))
        self.cover.setGeometry(MARGIN - 8, HEAD_Y - 4, w - 2 * MARGIN + 16, max(h - HEAD_Y - FOOT + 4, 40))
        self.cover.raise_()
        super().resizeEvent(event)

    def mouseReleaseEvent(self, event):
        if event.button() != Qt.LeftButton:
            return
        back, forward = self._pager_rects()
        if back.contains(event.position()):
            self.step(-1)
        elif forward.contains(event.position()):
            self.step(1)

    # ---------- pintura ----------

    def paintEvent(self, _):
        t = self.theme
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        label = font(t, 15, bold=True)
        label.setLetterSpacing(QFont.AbsoluteSpacing, 1.5)
        p.setFont(label)
        p.setPen(QColor(t.dim))
        p.drawText(QRectF(MARGIN, HEAD_Y, 200, 22), Qt.AlignVCenter, "TÍTULO")
        note = self.current()
        back, forward = self._pager_rects()
        p.setFont(font(t, 15))
        if len(self.notes) > 1:
            p.setPen(glyphs.pen(QColor(t.ink), 1.6))
            glyphs.arrow(p, back.adjusted(6, 6, -6, -6), "left")
            glyphs.arrow(p, forward.adjusted(6, 6, -6, -6), "right")
        p.setPen(QColor(t.dim))
        if self.notes:
            p.drawText(QRectF(back.right(), HEAD_Y, forward.left() - back.right(), 22), Qt.AlignCenter,
                       f"{self.index + 1} / {len(self.notes)}")
        if note and note.get("created"):
            p.drawText(QRectF(MARGIN, HEAD_Y, back.left() - MARGIN - 14, 22), Qt.AlignVCenter | Qt.AlignRight,
                       f"Creada {_when(note['created'])}")
        line_y = TITLE_Y + TITLE_H + 6
        p.setPen(QPen(FLAT_EDGE, 1))
        p.drawLine(QPointF(MARGIN, line_y), QPointF(self.width() - MARGIN, line_y))
        foot = QRectF(MARGIN, self.height() - FOOT, self.width() - 2 * MARGIN, FOOT - 6)
        if note is not None and self.armed == note["id"]:
            p.setFont(font(t, 15, bold=True))
            p.setPen(QColor(t.warn))
            p.drawText(foot, Qt.AlignCenter, "Ctrl+Supr otra vez para borrarla (va a la Papelera)")
        else:
            p.setFont(font(t, 15))
            p.setPen(QColor(t.dim))
            p.drawText(foot, Qt.AlignCenter,
                       "Ctrl+N nueva · Ctrl+RePág/AvPág pasar · Ctrl+B/I negrita/cursiva · Ctrl+Supr ×2 borrar · Esc cerrar")


class _Cover(QWidget):
    """Encima del título y del texto: el color del fondo con la opacidad del desvanecido. Es pintura sobre una
    superficie lisa, no un efecto de opacidad sobre los widgets (DISEÑO.md)."""

    def __init__(self, board):
        super().__init__(board)
        self.board = board
        self.setAttribute(Qt.WA_TransparentForMouseEvents)

    def paintEvent(self, _):
        if self.board._cover <= 0.01:
            return
        color = QColor(self.board.theme.plate_top)
        color.setAlphaF(min(self.board._cover, 1.0))
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        shape = QPainterPath()
        shape.addRect(QRectF(self.rect()))
        p.fillPath(shape, color)
