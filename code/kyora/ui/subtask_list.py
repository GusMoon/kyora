"""Las subtareas de una tarea como una lista: el círculo de si está terminada a la izquierda, el nombre (que crece en
varias líneas si es largo) con su descripción debajo, y una raya fina entre una subtarea y la siguiente.

- Clic en el círculo: la termina o la deja sin terminar (solo hay esos dos estados).
- Arrastrar una fila arriba o abajo: cambia el orden.
- La × que sale al pasar el cursor (o Supr): la borra. Doble clic (o F2): se edita ahí mismo, sin cambiar el fondo.
- `begin_new()` añade una fila al final donde se escribe la subtarea nueva: Enter la crea y abre otra; Enter en vacío o Esc
  la cierra.
"""
from PySide6.QtCore import QEvent, QPointF, QRect, QRectF, QSize, Qt, Signal
from PySide6.QtGui import QColor, QFontMetrics, QPainter, QPen
from PySide6.QtWidgets import QTextEdit, QWidget

from kyora.core.subtasks import drop_index, reordered
from kyora.ui.bar import font
from kyora.ui.status_icon import paint_status

ROW_H = 46  # lo mínimo que mide una fila
PAD_V = 10  # aire arriba y abajo del texto de una fila
RADIUS = 11  # el círculo de estado
AXIS = 24  # dónde está el centro del círculo
HIT = 8  # lo que se agranda la zona que se pulsa alrededor del círculo
TEXT_X = 50
CLOSE = 20
PAD = 4
DRAG_START = 6


class InlineEdit(QTextEdit):
    """Un campo que se confunde con la fila: sin fondo ni borde, con la misma letra. Enter guarda, Esc cancela sin cerrar el
    detalle y perder el foco también guarda."""

    submitted = Signal(str)
    cancelled = Signal()
    dropped = Signal(str)  # perdió el foco

    def __init__(self, parent, theme, text="", placeholder=""):
        super().__init__(parent)
        self.setFrameShape(QTextEdit.NoFrame)
        self.setHorizontalScrollBarPolicy(Qt.ScrollBarAlwaysOff)
        self.setVerticalScrollBarPolicy(Qt.ScrollBarAlwaysOff)
        self.setLineWrapMode(QTextEdit.WidgetWidth)
        self.document().setDocumentMargin(0)
        self.setPlaceholderText(placeholder)
        self.setStyleSheet(f"QTextEdit {{ background: transparent; border: 0; padding: 0; color: {theme.ink};"
                           f" font: {theme.font_px}px '{theme.font_family}'; }}")
        self.setAcceptRichText(False)
        self.setPlainText(text)
        self._finished = False

    def event(self, event):
        if event.type() == QEvent.ShortcutOverride and event.key() == Qt.Key_Escape:
            event.accept()
            return True
        return super().event(event)

    def keyPressEvent(self, event):
        if event.key() in (Qt.Key_Return, Qt.Key_Enter):
            self._finished = True
            self.submitted.emit(self.toPlainText().strip())
        elif event.key() == Qt.Key_Escape:
            self._finished = True
            self.cancelled.emit()
        else:
            super().keyPressEvent(event)

    def focusOutEvent(self, event):
        super().focusOutEvent(event)
        if not self._finished:
            self._finished = True
            self.dropped.emit(self.toPlainText().strip())

    def retire(self):
        """Lo quita sin que avise de nada."""
        self._finished = True
        self.hide()
        self.deleteLater()


class SubtaskList(QWidget):
    status_cycled = Signal(int)  # clic en el círculo de una subtarea
    removed = Signal(int)  # la × o Supr
    moved = Signal(int, int)  # (subtarea, nueva posición) tras arrastrarla
    renamed = Signal(int, str)  # editada (vacío = borrar)
    created = Signal(str)  # Enter en la fila nueva
    cancelled = Signal()  # se cerró la fila nueva sin crear nada
    height_changed = Signal(int)  # lo que mide ahora la lista entera (cambia con el ancho y con el texto)

    def __init__(self, theme):
        super().__init__()
        self.theme = theme
        self.items = []  # [{id, name, description, status}]
        self.selected = -1
        self._hover = -1
        self._press = None  # (índice, punto, sobre_el_círculo)
        self._drag = None  # (índice de origen, y actual del cursor, desplazamiento dentro de la fila)
        self._target = 0
        self._edit = None  # (id, campo): la fila que se está renombrando
        self._adding = False
        self._new = None  # el campo de la fila nueva
        self._live = {}  # id (o "new") -> el texto que se está escribiendo
        self._live_h = {}  # y lo que mide ese campo, para que la fila crezca con él
        self._heights = None
        self._last = -1
        self.setMouseTracking(True)
        self.setFocusPolicy(Qt.StrongFocus)

    # ---------- datos ----------

    def set_items(self, children, pick=None):
        keep = pick if pick is not None else self.current_id()
        self.items = [{"id": c["id"], "name": c["name"], "description": c.get("description") or "",
                       "status": "done" if c.get("status") == "done" or c.get("finished") else "open"} for c in children]
        ids = [i["id"] for i in self.items]
        self.selected = ids.index(keep) if keep in ids else (0 if ids else -1)
        self._cancel_edit()
        self._live, self._live_h = {}, {}
        self._relayout()
        if self._adding:  # la fila nueva sigue abierta para escribir la siguiente
            self._place_new(focus=True)

    def current_id(self):
        return self.items[self.selected]["id"] if 0 <= self.selected < len(self.items) else None

    def select(self, delta):
        if self.items:
            self.selected = max(0, min(self.selected + delta, len(self.items) - 1))
            self.update()

    # ---------- medidas ----------

    def _text_w(self):
        return max(self.width() - TEXT_X - CLOSE - 18, 80)

    def _title_h(self, text):
        fm = QFontMetrics(font(self.theme))
        return fm.boundingRect(QRect(0, 0, self._text_w(), 100000), Qt.TextWordWrap | Qt.AlignLeft, text or " ").height()

    def _name_h(self, key, text):
        """Lo que mide el nombre: si se está escribiendo, lo que mide el propio campo (así nunca se corta)."""
        return self._live_h.get(key) or self._title_h(text)

    def _row_h(self, item):
        extra = (QFontMetrics(font(self.theme)).height() + 2) if item["description"] else 0
        return max(ROW_H, 2 * PAD_V + self._name_h(item["id"], item["name"]) + extra)

    def _new_h(self):
        return max(ROW_H, 2 * PAD_V + self._name_h("new", ""))

    def _hs(self):
        if self._heights is None:
            self._heights = [self._row_h(i) for i in self.items]
        return self._heights

    def _tops(self, order=None):
        """La y de arriba de cada fila (por índice), con las filas puestas en `order`."""
        hs = self._hs()
        tops, y = {}, PAD
        for index in order if order is not None else range(len(self.items)):
            tops[index] = y
            y += hs[index]
        return tops

    def _content(self):
        total = PAD * 2 + sum(self._hs())
        return total + (self._new_h() if self._adding else 0)

    def wanted_height(self):
        return self._content()

    def _relayout(self):
        self._heights = None
        height = self._content()
        self.setMinimumHeight(height)
        if height != self._last:
            self._last = height
            self.height_changed.emit(height)
        self.updateGeometry()
        self.update()

    def sizeHint(self):
        return QSize(260, self._content())

    def resizeEvent(self, event):
        super().resizeEvent(event)
        self._relayout()
        if self._edit:
            self._place_edit()
        if self._new:
            self._place_new()

    # ---------- geometría ----------

    def _top(self, index):
        return self._tops()[index]

    def _row_at(self, y):
        hs = self._hs()
        for index, top in self._tops().items():
            if top <= y < top + hs[index]:
                return index
        return -1

    def _icon_center(self, index):
        return QPointF(AXIS, self._top(index) + ROW_H / 2)

    def _close_rect(self, index):
        top = self._top(index)
        return QRectF(self.width() - CLOSE - 10, top + (self._hs()[index] - CLOSE) / 2, CLOSE, CLOSE)

    # ---------- ratón y teclas ----------

    def mouseMoveEvent(self, event):
        pos = event.position()
        if self._press and self._drag is None and (pos - self._press[1]).manhattanLength() > DRAG_START \
                and not self._press[2]:
            index = self._press[0]
            self._drag = (index, pos.y(), pos.y() - self._top(index))
        if self._drag is not None:
            self._drag = (self._drag[0], pos.y(), self._drag[2])
            centre = pos.y() - self._drag[2] + self._hs()[self._drag[0]] / 2
            tops = self._tops()
            self._target = drop_index(centre, [tops[i] for i in range(len(self.items))], self._hs())
            self.update()
            return
        hover = self._row_at(pos.y())
        if hover != self._hover:
            self._hover = hover
            self.update()
        self.setCursor(Qt.PointingHandCursor if hover >= 0 and self._on_icon(hover, pos) else Qt.ArrowCursor)

    def _on_icon(self, index, pos):
        centre = self._icon_center(index)
        return (pos.x() - centre.x()) ** 2 + (pos.y() - centre.y()) ** 2 <= (RADIUS + HIT) ** 2

    def leaveEvent(self, _):
        self._hover = -1
        self.update()

    def mousePressEvent(self, event):
        if event.button() != Qt.LeftButton:
            return
        pos = event.position()
        index = self._row_at(pos.y())
        if index < 0:
            return
        if self._close_rect(index).contains(pos) and index == self._hover:
            self.removed.emit(self.items[index]["id"])
            return
        self.selected = index
        self.setFocus()
        self._press = (index, pos, self._on_icon(index, pos))
        self.update()

    def mouseReleaseEvent(self, event):
        press, drag = self._press, self._drag
        self._press = self._drag = None
        if press is None:
            return
        if drag is not None:
            source, target = drag[0], self._target
            if target != source:
                self.moved.emit(self.items[source]["id"], target)
            self.update()
        elif press[2]:  # un clic en el círculo: terminada o no
            self.status_cycled.emit(self.items[press[0]]["id"])

    def mouseDoubleClickEvent(self, event):
        index = self._row_at(event.position().y())
        if index >= 0 and not self._on_icon(index, event.position()):
            self._start_edit(index)

    def keyPressEvent(self, event):
        if event.key() == Qt.Key_Delete and self.current_id() is not None:
            self.removed.emit(self.current_id())
        elif event.key() in (Qt.Key_Up, Qt.Key_Down) and not event.modifiers():
            self.select(-1 if event.key() == Qt.Key_Up else 1)
        elif event.key() == Qt.Key_F2 and self.selected >= 0:
            self._start_edit(self.selected)
        else:
            super().keyPressEvent(event)

    # ---------- renombrar (ahí mismo) ----------

    def _place_edit(self):
        item_id, edit = self._edit
        index = next((i for i, it in enumerate(self.items) if it["id"] == item_id), None)
        if index is not None:
            edit.setGeometry(TEXT_X, int(self._top(index) + PAD_V), int(self._text_w()), self._fit_edit(item_id, edit))

    def _start_edit(self, index):
        self._cancel_edit()
        item = self.items[index]
        edit = InlineEdit(self, self.theme, item["name"])
        edit.submitted.connect(lambda text, i=item["id"], e=edit: self._finish_edit(i, e, text))
        edit.dropped.connect(lambda text, i=item["id"], e=edit: self._finish_edit(i, e, text))
        edit.cancelled.connect(self._cancel_edit)
        edit.textChanged.connect(lambda i=item["id"], e=edit: self._grow(i, e))
        self._edit = (item["id"], edit)
        self._place_edit()
        edit.show()
        edit.setFocus()
        edit.selectAll()
        self.update()

    def _fit_edit(self, key, edit):
        """El alto del campo según su propio texto ajustado al ancho de la fila (se guarda para la fila)."""
        doc = edit.document()
        doc.setTextWidth(self._text_w())
        height = max(int(doc.size().height()) + 2, QFontMetrics(edit.font()).height() + 2)
        self._live_h[key] = height
        return height

    def _grow(self, key, edit):
        """Lo escrito cambia lo que mide la fila: se ajusta mientras se teclea."""
        self._live[key] = edit.toPlainText()
        self._fit_edit(key, edit)
        self._relayout()
        if key == "new":
            self._place_new()
        elif self._edit:
            self._place_edit()

    def _finish_edit(self, item_id, edit, text):
        if self._edit is None or self._edit[1] is not edit:
            return
        self._edit = None
        edit.retire()
        self._live.pop(item_id, None)
        self._live_h.pop(item_id, None)
        current = next((i["name"] for i in self.items if i["id"] == item_id), None)
        if current is not None and text != current:
            self.renamed.emit(item_id, text)
        else:
            self._relayout()
            self.setFocus()

    def _cancel_edit(self):
        if self._edit is not None:
            item_id, edit = self._edit
            self._edit = None
            edit.retire()
            self._live.pop(item_id, None)
            self._live_h.pop(item_id, None)
            self._relayout()
            self.setFocus()

    # ---------- la fila nueva ----------

    def begin_new(self):
        self._adding = True
        self._relayout()
        self._place_new(focus=True)

    def end_new(self):
        was = self._adding
        self._adding = False
        self._live.pop("new", None)
        self._live_h.pop("new", None)
        if self._new is not None:
            edit, self._new = self._new, None
            edit.retire()
        self._relayout()
        if was:
            self.cancelled.emit()

    def _place_new(self, focus=False):
        if self._new is None:
            edit = InlineEdit(self, self.theme, placeholder="Nombre de la subtarea")
            edit.submitted.connect(self._submit_new)
            edit.dropped.connect(self._drop_new)
            edit.cancelled.connect(self.end_new)
            edit.textChanged.connect(lambda e=edit: self._grow("new", e))
            self._new = edit
            edit.show()
        top = PAD + sum(self._hs())
        self._new.setGeometry(TEXT_X, int(top + PAD_V), int(self._text_w()), self._fit_edit("new", self._new))
        if focus:
            self._new.setFocus()

    def _submit_new(self, text):
        if not text:
            self.end_new()
            return
        edit, self._new = self._new, None  # `set_items` lo vuelve a abrir en limpio tras crear la subtarea
        edit.retire()
        self._live.pop("new", None)
        self._live_h.pop("new", None)
        self.created.emit(text)

    def _drop_new(self, text):
        if self._new is not None and self.sender() is self._new:
            self._submit_new(text)

    # ---------- pintura ----------

    def _order(self):
        """El orden en que se dibujan las filas: con un arrastre, la arrastrada se abre hueco en su destino."""
        ids = list(range(len(self.items)))
        if self._drag is not None:
            return reordered(ids, self._drag[0], self._target)
        return ids

    def paintEvent(self, _):
        t = self.theme
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        p.setClipRect(self.rect())
        order = self._order()
        tops = self._tops(order)
        dragged = self._drag[0] if self._drag is not None else None
        line = QColor(t.ink)
        line.setAlpha(26)
        hs = self._hs()
        for index in order:
            if index != dragged:
                self._paint_row(p, index, tops[index])
        for slot, index in enumerate(order):  # la raya de abajo de cada fila (salvo la última si no hay fila nueva)
            if slot == len(order) - 1 and not self._adding:
                continue
            y = tops[index] + hs[index] - 0.5
            p.setPen(QPen(line, 1))
            p.drawLine(QPointF(AXIS - RADIUS, y), QPointF(self.width() - 6, y))
        if self._adding:
            top = PAD + sum(hs)
            paint_status(p, QPointF(AXIS, top + ROW_H / 2), RADIUS, "open", t)
        if dragged is not None:  # la fila levantada, siguiendo al cursor
            y = self._drag[1] - self._drag[2]
            p.setPen(Qt.NoPen)
            for grow, alpha in ((10, 20), (5, 36)):
                p.setBrush(QColor(0, 0, 0, alpha))
                p.drawRoundedRect(QRectF(4 - grow / 2, y + 2 - grow / 4, self.width() - 8 + grow, hs[dragged] - 4 + grow),
                                  12, 12)
            self._paint_row(p, dragged, y, lifted=True)

    def _paint_row(self, p, index, top, lifted=False):
        t = self.theme
        item = self.items[index]
        height = self._hs()[index]
        if top + height < 0 or top > self.height():
            return
        hovered = index == self._hover and self._drag is None
        if lifted or hovered or (index == self.selected and self.hasFocus()):
            p.setPen(Qt.NoPen)
            p.setBrush(QColor(t.plate_pick) if lifted else QColor(255, 255, 255, 18 if hovered else 10))
            p.drawRoundedRect(QRectF(2, top + 1, self.width() - 4, height - 2), 10, 10)
        paint_status(p, QPointF(AXIS, top + ROW_H / 2), RADIUS, item["status"], t)
        ink, dim = QColor(t.ink), QColor(t.dim)
        done = item["status"] == "done"
        width = self._text_w()
        name_h = self._name_h(item["id"], item["name"])
        if not (self._edit and self._edit[0] == item["id"]):  # mientras se edita, el campo ocupa su sitio
            face = font(t)
            face.setStrikeOut(done)
            p.setFont(face)
            p.setPen(dim if done else ink)
            p.drawText(QRectF(TEXT_X, top + PAD_V, width, name_h), Qt.TextWordWrap | Qt.AlignLeft | Qt.AlignTop,
                       item["name"])
        if item["description"]:
            p.setFont(font(t))
            p.setPen(dim)
            first_line = " ".join(item["description"].split())
            p.drawText(QRectF(TEXT_X, top + PAD_V + name_h + 2, width, p.fontMetrics().height()), Qt.AlignVCenter,
                       p.fontMetrics().elidedText(first_line, Qt.ElideRight, int(width)))
        if hovered:  # la × para borrarla
            box = QRectF(self.width() - CLOSE - 10, top + (height - CLOSE) / 2, CLOSE, CLOSE)
            p.setPen(QPen(dim, 1.6, Qt.SolidLine, Qt.RoundCap))
            c, m = box.center(), CLOSE * 0.25
            p.drawLine(QPointF(c.x() - m, c.y() - m), QPointF(c.x() + m, c.y() + m))
            p.drawLine(QPointF(c.x() - m, c.y() + m), QPointF(c.x() + m, c.y() - m))
