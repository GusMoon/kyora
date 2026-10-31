"""El tablero Kanban de las tareas (Ctrl+Shift+T), dentro del buscador (que se ensancha): cuatro columnas por estado
(Pendiente, En proceso, En revisión, Finalizada). Cada columna lleva el icono de su estado, su nombre, cuántas tareas
tiene y un "+" para crear una ahí; sus tarjetas son pequeñas (título, etiquetas, fecha y subtareas) y, si hay más de las
que caben, la columna se desplaza con la rueda (sin barra) y sus bordes se oscurecen mientras se desplaza.

Con el ratón: arrastrar una tarjeta a otra columna cambia su estado; un clic la abre. Con el teclado (los comandos de esta
sección): ↑/↓/←/→ eligen tarjeta, Enter la abre, Ctrl+←/→ la pasan al estado de al lado, Ctrl+Enter la termina o la
reabre y Ctrl+Supr la borra (dos veces, la primera avisa).
"""
from datetime import datetime

from PySide6.QtCore import QPointF, QRectF, Qt, Signal
from PySide6.QtGui import (
    QColor,
    QFontMetrics,
    QPainter,
    QPainterPath,
    QPen,
)
from PySide6.QtWidgets import QWidget

from kyora.tasks import model
from kyora.ui import glyphs
from kyora.ui.bar import font
from kyora.ui.hub.cards import paint_flat, paint_flat_well
from kyora.ui.status_icon import paint_status

MARGIN = 12
HEAD = 28  # la línea de ayuda de arriba
COL_GAP = 12
COL_HEAD = 42
CARD_H = 76  # tarjetas pequeñas: caben unas 5 por columna
CARD_GAP = 7
CARD_R = 12
COL_R = 18
PLUS = 24  # el botón + de cada columna
PAD = 12  # margen de dentro de una tarjeta
DRAG_START = 6  # píxeles que hay que mover antes de que un clic se convierta en arrastre
KEYS = tuple(key for key, _ in model.STATUSES)


class KanbanBoard(QWidget):
    open_task = Signal(int)  # clic o Enter en una tarjeta

    def __init__(self, theme, call):
        super().__init__()
        self.setMouseTracking(True)
        self.theme, self._call = theme, call
        self.columns = {key: [] for key in KEYS}
        self.scroll = {key: 0 for key in KEYS}
        self.sel = [0, 0]  # (columna, tarjeta) elegidas con el teclado
        self._kb = False  # se usó el teclado: la tarjeta elegida se marca
        self.armed = None  # la tarea que espera el segundo Ctrl+Supr
        self._press = None  # (tarjeta, columna, punto donde se pulsó, desplazamiento dentro de la tarjeta)
        self._drag = None  # punto actual mientras se arrastra
        self._hover = None

    def reload(self):
        """Vuelve a leer las tareas de cada columna (por lo que vence antes)."""
        for key in KEYS:
            result = self._call("tasks.list", status=key)
            self.columns[key] = result["data"] if result["ok"] else []
        self._clamp()
        self.update()

    # ---------- geometría ----------

    def _column_rects(self):
        inner = QRectF(self.rect()).adjusted(MARGIN, HEAD, -MARGIN, -MARGIN)
        n = len(KEYS)
        width = (inner.width() - COL_GAP * (n - 1)) / n
        return {key: QRectF(inner.left() + i * (width + COL_GAP), inner.top(), width, inner.height())
                for i, key in enumerate(KEYS)}

    @staticmethod
    def _viewport(column):
        """Donde se ven las tarjetas de una columna (debajo de su cabecera)."""
        return QRectF(column.left(), column.top() + COL_HEAD, column.width(), column.height() - COL_HEAD - 6)

    def _content(self, key):
        n = len(self.columns[key])
        return n * (CARD_H + CARD_GAP) + 4 if n else 0

    def _limit(self, key, column):
        return max(self._content(key) - self._viewport(column).height(), 0)

    def _card_rects(self, key, column):
        """Todas las tarjetas de la columna con su rectángulo (ya desplazadas); solo se ven las del área visible."""
        view = self._viewport(column)
        y = view.top() + 4 - self.scroll[key]
        return [(task, QRectF(column.left() + 8, y + i * (CARD_H + CARD_GAP), column.width() - 16, CARD_H))
                for i, task in enumerate(self.columns[key])]

    @staticmethod
    def _plus_rect(column):
        return QRectF(column.right() - PLUS - 10, column.top() + (COL_HEAD - PLUS) / 2, PLUS, PLUS)

    def _hit(self, pos):
        for key, column in self._column_rects().items():
            if column.contains(pos):
                view = self._viewport(column)
                for task, rect in self._card_rects(key, column):
                    if rect.contains(pos) and view.contains(pos):
                        return key, task, rect
                return key, None, None
        return None, None, None

    def _clamp(self):
        rects = self._column_rects()
        for i, key in enumerate(KEYS):
            self.scroll[key] = int(min(max(self.scroll[key], 0), self._limit(key, rects[key])))
            if self.sel[0] == i:
                self.sel[1] = min(self.sel[1], max(len(self.columns[key]) - 1, 0))

    # ---------- desplazar y oscurecer los bordes ----------

    def _scrolled(self, key):
        self.update()

    def _scroll_column(self, key, delta):
        column = self._column_rects()[key]
        new = int(min(max(self.scroll[key] + delta, 0), self._limit(key, column)))
        if new != self.scroll[key]:
            self.scroll[key] = new
            self._scrolled(key)

    def wheelEvent(self, event):
        key = self._hit(event.position())[0]
        if key is not None:
            self._scroll_column(key, -event.angleDelta().y() / 2)

    # ---------- el teclado (los comandos de esta sección) ----------

    def selected(self):
        """(estado, tarea) de la tarjeta elegida, o (None, None)."""
        key = KEYS[self.sel[0]]
        tasks = self.columns[key]
        return (key, tasks[self.sel[1]]) if tasks and 0 <= self.sel[1] < len(tasks) else (None, None)

    def _show_selected(self):
        key = KEYS[self.sel[0]]
        column = self._column_rects()[key]
        view = self._viewport(column)
        top = 4 + self.sel[1] * (CARD_H + CARD_GAP)
        if top < self.scroll[key]:
            self.scroll[key] = top
        elif top + CARD_H > self.scroll[key] + view.height():
            self.scroll[key] = top + CARD_H - view.height() + 4
        self.scroll[key] = int(min(max(self.scroll[key], 0), self._limit(key, column)))
        self._scrolled(key)

    def move_sel(self, dx, dy):
        """↑/↓ cambian de tarjeta y ←/→ de columna (se salta a la más cercana que tenga tareas)."""
        self._kb, self.armed = True, None
        col = self.sel[0]
        if not self.columns[KEYS[col]]:  # la columna elegida está vacía: a la primera que tenga tareas
            first = next((i for i, k in enumerate(KEYS) if self.columns[k]), None)
            if first is not None:
                self.sel = [first, 0]
        elif dx:
            step = 1 if dx > 0 else -1
            nxt = col + step
            while 0 <= nxt < len(KEYS) and not self.columns[KEYS[nxt]]:
                nxt += step
            if 0 <= nxt < len(KEYS):
                self.sel = [nxt, min(self.sel[1], len(self.columns[KEYS[nxt]]) - 1)]
        elif dy:
            self.sel[1] = min(max(self.sel[1] + dy, 0), len(self.columns[KEYS[col]]) - 1)
        self._show_selected()

    def open_selected(self):
        _, task = self.selected()
        if task is not None:
            self.open_task.emit(task["id"])
            return True
        return False

    def shift_status(self, delta):
        """Ctrl+←/→: la tarjeta elegida pasa al estado de al lado (y la elección la sigue)."""
        _, task = self.selected()
        if task is None:
            return
        target = self.sel[0] + delta
        if 0 <= target < len(KEYS):
            self._call("tasks.set_status", task_id=task["id"], status=KEYS[target])
            self.reload()
            self.sel[0] = target
            self.sel[1] = next((i for i, t in enumerate(self.columns[KEYS[target]]) if t["id"] == task["id"]), 0)
            self._kb = True
            self._show_selected()

    def toggle_done(self):
        """Ctrl+Enter: terminarla (o reabrirla si ya estaba terminada)."""
        key, task = self.selected()
        if task is None:
            return
        self._call("tasks.set_status", task_id=task["id"], status="pending" if key == "done" else "done")
        self.reload()

    def arm_delete(self):
        """Ctrl+Supr: la primera vez avisa en la tarjeta; la segunda borra la tarea."""
        _, task = self.selected()
        if task is None:
            return
        if self.armed == task["id"]:
            self.armed = None
            self._call("tasks.delete", task_id=task["id"])
            self.reload()
        else:
            self.armed = task["id"]
            self.update()

    # ---------- ratón ----------

    def mousePressEvent(self, event):
        pos = event.position()
        if event.button() != Qt.LeftButton:
            return
        key, task, rect = self._hit(pos)
        if task is not None:
            self._press = (task, key, pos, pos - rect.topLeft())
            return
        for column_key, column in self._column_rects().items():
            if self._plus_rect(column).contains(pos):
                self._create_in(column_key)
                return

    def _create_in(self, status):
        """El + de una columna: una tarea nueva con ese estado, abierta para escribirla."""
        made = self._call("tasks.create", name="Nueva tarea")
        if not made["ok"] or not made["data"]:
            return
        if status != KEYS[0]:
            self._call("tasks.set_status", task_id=made["data"], status=status)
        self.reload()
        self.open_task.emit(made["data"])

    def mouseMoveEvent(self, event):
        pos = event.position()
        self._kb = False
        if self._press and self._drag is None and (pos - self._press[2]).manhattanLength() > DRAG_START:
            self._drag = pos
        if self._drag is not None:
            self._drag = pos
            self._hover = self._hit(pos)[0]
            self.update()
        else:
            hover = self._hit(pos)[1]
            hover_id = hover["id"] if hover else None
            if hover_id != self._hover:
                self._hover = hover_id
                self.update()

    def mouseReleaseEvent(self, event):
        if event.button() != Qt.LeftButton or not self._press:
            return
        task, source, _, _ = self._press
        if self._drag is not None:
            target = self._hit(event.position())[0]
            if target and target != source:
                self._call("tasks.set_status", task_id=task["id"], status=target)
                self.reload()
        else:
            self.open_task.emit(task["id"])
        self._press = self._drag = self._hover = None
        self.update()

    # ---------- pintura ----------

    def paintEvent(self, _):
        t = self.theme
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        p.setFont(font(t))
        p.setPen(QColor(t.dim))
        hint = "Escribe arriba para crear una tarea  ·  ↑↓←→ elegir  ·  Enter abrir  ·  Ctrl+←/→ cambiar de estado  ·  Ctrl+Supr borrar"
        p.drawText(QRectF(MARGIN + 4, 2, self.width() - 2 * MARGIN, HEAD - 4), Qt.AlignVCenter,
                   QFontMetrics(font(t)).elidedText(hint, Qt.ElideRight, self.width() - 2 * MARGIN - 8))
        dragging = self._press[0]["id"] if self._drag is not None else None
        selected = self.selected()[1]
        for key, column in self._column_rects().items():
            target = self._drag is not None and self._hover == key and key != self._press[1]
            self._paint_column(p, key, column, target)
            view = self._viewport(column)
            p.save()
            p.setClipPath(self._clip(column, view))
            for task, rect in self._card_rects(key, column):
                if rect.bottom() < view.top() or rect.top() > view.bottom():
                    continue
                if task["id"] == dragging:
                    p.setPen(QPen(QColor(255, 255, 255, 40), 1, Qt.DashLine))  # su hueco mientras se arrastra
                    p.setBrush(Qt.NoBrush)
                    p.drawRoundedRect(rect.adjusted(0.5, 0.5, -0.5, -0.5), CARD_R, CARD_R)
                    continue
                chosen = (self._kb or self.armed == task["id"]) and selected is not None and task["id"] == selected["id"]
                self._paint_card(p, rect, task, hover=self._hover == task["id"], chosen=chosen)
            p.restore()
        if self._drag is not None:  # la tarjeta levantada: sombra suave, algo girada y con borde del acento
            task, _, _, offset = self._press
            width = self._column_rects()[KEYS[0]].width() - 16
            top_left = self._drag - offset
            p.save()
            p.translate(top_left + QPointF(width / 2, CARD_H / 2))
            p.rotate(-2.5)
            rect = QRectF(-width / 2, -CARD_H / 2, width, CARD_H)
            for grow, alpha in ((16, 14), (10, 22), (5, 34)):  # la sombra, en capas
                p.setPen(Qt.NoPen)
                p.setBrush(QColor(0, 0, 0, alpha))
                p.drawRoundedRect(rect.adjusted(-grow / 2, -grow / 4, grow / 2, grow), CARD_R + grow / 2, CARD_R + grow / 2)
            self._paint_card(p, rect, task, hover=True)
            p.setPen(QPen(QColor(t.gold), 1.5))
            p.setBrush(Qt.NoBrush)
            p.drawRoundedRect(rect.adjusted(0.5, 0.5, -0.5, -0.5), CARD_R, CARD_R)
            p.restore()

    @staticmethod
    def _clip(column, view):
        """Lo visible de una columna: desde su cabecera hasta su borde de abajo, con sus esquinas redondas."""
        well = QPainterPath()
        well.addRoundedRect(column.adjusted(1, 1, -1, -1), COL_R - 1, COL_R - 1)
        below = QPainterPath()
        below.addRect(QRectF(column.left(), view.top(), column.width(), column.bottom() - view.top()))
        return well.intersected(below)

    def _paint_column(self, p, key, column, target):
        t = self.theme
        paint_flat_well(p, t, column, COL_R)
        if target:  # la columna de destino, resaltada
            accent = QColor(t.gold)
            accent.setAlpha(150)
            p.setPen(QPen(accent, 2))
            p.setBrush(Qt.NoBrush)
            p.drawRoundedRect(column.adjusted(1, 1, -1, -1), COL_R - 1, COL_R - 1)
        paint_status(p, QPointF(column.left() + 24, column.top() + COL_HEAD / 2), 8, key, t)
        p.setFont(font(t, bold=True))
        p.setPen(QColor(t.ink))
        name = dict(model.STATUSES)[key]
        p.drawText(QRectF(column.left() + 40, column.top(), column.width() - 110, COL_HEAD), Qt.AlignVCenter, name)
        p.setFont(font(t))
        p.setPen(QColor(t.dim))
        count_x = column.left() + 40 + QFontMetrics(font(t, bold=True)).horizontalAdvance(name) + 8
        p.drawText(QRectF(count_x, column.top(), 40, COL_HEAD), Qt.AlignVCenter, str(len(self.columns[key])))
        plus = self._plus_rect(column)
        p.setPen(QPen(QColor(t.dim), 1.6, Qt.SolidLine, Qt.RoundCap))
        cx, cy = plus.center().x(), plus.center().y()
        p.drawLine(QPointF(cx - 5, cy), QPointF(cx + 5, cy))
        p.drawLine(QPointF(cx, cy - 5), QPointF(cx, cy + 5))

    def _paint_card(self, p, rect, task, hover=False, chosen=False):
        """Una tarjeta pequeña: título (hasta dos líneas) y, abajo, sus etiquetas, la fecha y las subtareas."""
        t = self.theme
        shadow = QPainterPath()
        shadow.addRoundedRect(rect.adjusted(0, 2, 0, 2), CARD_R, CARD_R)
        p.fillPath(shadow, QColor(0, 0, 0, 50))
        paint_flat(p, t, rect, CARD_R, hi=hover or chosen)
        if chosen:
            p.setPen(QPen(QColor(t.gold), 1.6))
            p.setBrush(Qt.NoBrush)
            p.drawRoundedRect(rect.adjusted(0.8, 0.8, -0.8, -0.8), CARD_R, CARD_R)
        left, right = rect.left() + PAD, rect.right() - PAD
        width = right - left
        armed = self.armed == task["id"]
        p.save()
        title = QRectF(left, rect.top() + 8, width, 36)
        p.setClipRect(title, Qt.IntersectClip)  # sin soltar el recorte de la columna
        p.setFont(font(t, bold=True))
        p.setPen(QColor(t.warn) if armed else QColor(t.ink))
        p.drawText(title, Qt.TextWordWrap | Qt.AlignTop, "Ctrl+Supr otra vez para borrarla" if armed else task["name"])
        p.restore()
        y = rect.bottom() - PAD - 18
        x = left
        due = model.parse_time(task.get("due"))
        right_x = right
        if task.get("subtasks"):
            text = f"{task['subtasks_done']}/{task['subtasks']}"
            p.setFont(font(t))
            p.setPen(QColor(t.dim))
            w = QFontMetrics(font(t)).horizontalAdvance(text)
            p.drawText(QRectF(right - w, y, w, 18), Qt.AlignVCenter | Qt.AlignRight, text)
            right_x -= w + 8
        if due:
            late = due < datetime.now() and task.get("status") != "done"
            text = model.date_text(due, datetime.now())
            color = QColor(t.warn if late else t.dim)
            p.setFont(font(t))
            w = QFontMetrics(font(t)).horizontalAdvance(text) + 20
            if right_x - w > x + 40:
                p.setPen(glyphs.pen(color, 1.2))
                glyphs.clock(p, QRectF(right_x - w, y + 1, 15, 15))
                p.setPen(color)
                p.drawText(QRectF(right_x - w + 19, y, w, 18), Qt.AlignVCenter, text)
                right_x -= w + 8
        for tag in task.get("tags", ())[:3]:  # sus etiquetas, de izquierda a derecha mientras quepan
            width_tag = min(QFontMetrics(font(t)).horizontalAdvance(tag["name"]) + 22, 96)
            if x + width_tag > right_x:
                break
            self._paint_tag(p, QRectF(x, y, width_tag, 18), tag)
            x += width_tag + 5

    def _paint_tag(self, p, rect, tag):
        """Una etiqueta: píldora con el color de la etiqueta y su nombre."""
        t = self.theme
        color = QColor(tag["color"])
        p.setPen(Qt.NoPen)
        fill = QColor(color)
        fill.setAlpha(46)
        p.setBrush(fill)
        p.drawRoundedRect(rect, 9, 9)
        p.setBrush(color)
        p.drawEllipse(QPointF(rect.left() + 9, rect.center().y()), 3, 3)
        p.setFont(font(t))
        p.setPen(color.lighter(130))
        p.drawText(rect.adjusted(17, 0, -5, 0), Qt.AlignVCenter,
                   QFontMetrics(font(t)).elidedText(tag["name"], Qt.ElideRight, int(rect.width() - 22)))
