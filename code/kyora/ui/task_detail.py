"""El detalle de una tarea, dentro del buscador (sin ventanas aparte): una tarjeta como la de una conversación.

Arriba, a la izquierda, el nombre y debajo cuándo vence; a la derecha, el estado (un clic lo cambia). Debajo, una línea
con efecto de profundidad; después la descripción y las subtareas (si tiene) y, al final, un único campo para escribir y
añadir subtareas con Enter.

Se guarda solo al dejar de escribir. Teclas: Esc volver, Ctrl+N nueva, Ctrl+Enter terminar o reabrir, Ctrl+Supr dos
veces borrar (sin diálogo: la primera avisa), Ctrl+Shift+S nueva subtarea, Ctrl+↑/↓ deslizar la lista de subtareas, Alt+↑/↓ mover la
subtarea elegida.
"""
from datetime import datetime, time

from PySide6.QtCore import (
    QDate,
    QDateTime,
    QEasingCurve,
    QPointF,
    QRectF,
    QSize,
    QStringListModel,
    Qt,
    QTime,
    QTimer,
    Signal,
)
from PySide6.QtGui import (
    QColor,
    QFontMetrics,
    QKeySequence,
    QPainter,
    QPainterPath,
    QPen,
    QShortcut,
)
from PySide6.QtWidgets import (
    QAbstractButton,
    QCompleter,
    QFrame,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QPlainTextEdit,
    QPushButton,
    QScrollArea,
    QStackedLayout,
    QVBoxLayout,
    QWidget,
)

from kyora.tasks import model
from kyora.ui import glyphs
from kyora.ui.anim import Tween
from kyora.ui.bar import font
from kyora.ui.datepicker import DatePicker
from kyora.ui.explorer.style import stylesheet
from kyora.ui.hub.cards import paint_flat_well
from kyora.ui.status_icon import paint_status
from kyora.ui.subtask_list import SubtaskList

SAVE_MS = 400
FILL_MS = 450  # lo que tarda en llenarse el borde
PAD = 16
NO_DATE = QDateTime(QDate(2000, 1, 1), QTime(0, 0))
DEFAULT_HOUR = time(18, 0)


class Well(QWidget):
    """El recuadro gris oscuro de la derecha: la descripción y, cuando se elige la fecha, el calendario en su lugar."""

    def __init__(self, theme, text, picker):
        super().__init__()
        self.theme = theme
        self.text, self.picker = text, picker
        self.progress = 0.0  # cuánto del borde está encendido (0 a 1)
        margins = QVBoxLayout(self)
        margins.setContentsMargins(14, 12, 14, 12)
        self.stack = QStackedLayout()
        margins.addLayout(self.stack)
        self.stack.addWidget(text)
        self.stack.addWidget(picker)

    def show_picker(self):
        self.stack.setCurrentWidget(self.picker)

    def show_text(self):
        self.stack.setCurrentWidget(self.text)

    def picking(self):
        return self.stack.currentWidget() is self.picker

    def _outline(self, rect, r):
        """El contorno redondeado, empezando por arriba al centro y yendo hacia la derecha."""
        path = QPainterPath()
        x0, y0, x1, y1, d = rect.left(), rect.top(), rect.right(), rect.bottom(), 2 * r
        path.moveTo(rect.center().x(), y0)
        path.lineTo(x1 - r, y0)
        path.arcTo(x1 - d, y0, d, d, 90, -90)
        path.lineTo(x1, y1 - r)
        path.arcTo(x1 - d, y1 - d, d, d, 0, -90)
        path.lineTo(x0 + r, y1)
        path.arcTo(x0, y1 - d, d, d, 270, -90)
        path.lineTo(x0, y0 + r)
        path.arcTo(x0, y0, d, d, 180, -90)
        path.lineTo(rect.center().x(), y0)
        return path

    def paintEvent(self, _):
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        rect = QRectF(self.rect()).adjusted(0.5, 0.5, -0.5, -0.5)
        paint_flat_well(p, self.theme, rect, 14)
        if self.progress > 0.001:  # el borde que se va llenando
            path = self._outline(rect.adjusted(0.5, 0.5, -0.5, -0.5), 13.5)
            width = 2.0
            pen = QPen(QColor(self.theme.gold), width, Qt.CustomDashLine)
            length = path.length()
            pen.setDashPattern([max(length * min(self.progress, 1.0), 0.1) / width, length / width + 10])
            pen.setCapStyle(Qt.RoundCap)
            p.setPen(pen)
            p.setBrush(Qt.NoBrush)
            p.drawPath(path)


class DateButton(QAbstractButton):
    """Debajo del nombre: un calendario pequeño y la fecha ("Sin fecha" si no hay). Al pulsarlo se abre el calendario."""

    def __init__(self, theme):
        super().__init__()
        self.theme, self.late = theme, False
        self.setText("Sin fecha")
        self.setCursor(Qt.PointingHandCursor)
        self.setFixedHeight(28)
        self.setAttribute(Qt.WA_Hover)

    def set_label(self, text, late=False):
        self.setText(text)
        self.late = late
        self.updateGeometry()
        self.update()

    def sizeHint(self):
        return QSize(QFontMetrics(font(self.theme)).horizontalAdvance(self.text()) + 2 * 10 + self.theme.icon_px + 6, 28)

    def paintEvent(self, _):
        t = self.theme
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        if self.underMouse():
            p.setPen(Qt.NoPen)
            p.setBrush(QColor(255, 255, 255, 18))
            p.drawRoundedRect(QRectF(self.rect()).adjusted(0, 1, 0, -1), 8, 8)
        color = QColor(t.warn if self.late else t.dim)
        p.setPen(glyphs.pen(color, 1.3))
        p.setBrush(Qt.NoBrush)
        glyphs.calendar(p, QRectF(10, (self.height() - t.icon_px) / 2, t.icon_px, t.icon_px))
        p.setFont(font(t))
        p.setPen(color if self.late else QColor(t.ink))
        p.drawText(QRectF(10 + t.icon_px + 6, 0, self.width(), self.height()), Qt.AlignVCenter, self.text())


class TagBar(QWidget):
    """Las etiquetas de la tarea como píldoras con el color de cada una y una × para quitarla."""

    removed = Signal(int)  # el id de la etiqueta que se quitó

    def __init__(self, theme):
        super().__init__()
        self.theme, self.tags = theme, []
        self._hits = []  # (rectángulo de la ×, id)
        self.setFixedHeight(24)
        self.setMouseTracking(True)

    def set_tags(self, tags):
        self.tags = list(tags)
        self.update()

    def _width(self, tag):
        return min(QFontMetrics(font(self.theme)).horizontalAdvance(tag["name"]) + 40, 150)

    def sizeHint(self):
        return QSize(sum(self._width(t) + 6 for t in self.tags) + 2, 24)

    def mouseReleaseEvent(self, event):
        for rect, tag_id in self._hits:
            if rect.contains(event.position()):
                self.removed.emit(tag_id)
                return

    def paintEvent(self, _):
        t = self.theme
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        x, self._hits = 0.0, []
        for tag in self.tags:
            width = self._width(tag)
            rect = QRectF(x, 2, width, 20)
            color = QColor(tag["color"])
            fill = QColor(color)
            fill.setAlpha(46)
            p.setPen(Qt.NoPen)
            p.setBrush(fill)
            p.drawRoundedRect(rect, 10, 10)
            p.setBrush(color)
            p.drawEllipse(QPointF(rect.left() + 11, rect.center().y()), 3.5, 3.5)
            p.setFont(font(t))
            p.setPen(color.lighter(130))
            p.drawText(rect.adjusted(21, 0, -21, 0), Qt.AlignVCenter,
                       QFontMetrics(font(t)).elidedText(tag["name"], Qt.ElideRight, int(width - 42)))
            cross = QRectF(rect.right() - 19, rect.top(), 18, rect.height())
            p.setPen(QPen(color.lighter(130), 1.4, Qt.SolidLine, Qt.RoundCap))
            cx, cy = cross.center().x(), cross.center().y()
            p.drawLine(QPointF(cx - 3, cy - 3), QPointF(cx + 3, cy + 3))
            p.drawLine(QPointF(cx - 3, cy + 3), QPointF(cx + 3, cy - 3))
            self._hits.append((cross, tag["id"]))
            x += width + 6


class StatusToggle(QWidget):
    """El estado de la tarea: su icono y su nombre. Un clic pasa al estado siguiente."""

    clicked = Signal()

    def __init__(self, theme):
        super().__init__()
        self.theme, self.status, self.name = theme, "pending", "Pendiente"
        self._hover = False
        self.setCursor(Qt.PointingHandCursor)
        self.setAttribute(Qt.WA_Hover)
        self.setFixedHeight(38)

    def set_status(self, theme, status, name):
        self.theme, self.status, self.name = theme, status, name
        self.updateGeometry()
        self.update()

    def sizeHint(self):
        return QSize(48 + QFontMetrics(font(self.theme)).horizontalAdvance(self.name) + 14, 38)

    def enterEvent(self, _):
        self._hover = True
        self.update()

    def leaveEvent(self, _):
        self._hover = False
        self.update()

    def mouseReleaseEvent(self, event):
        if event.button() == Qt.LeftButton and self.rect().contains(event.position().toPoint()):
            self.clicked.emit()

    def paintEvent(self, _):
        t = self.theme
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        if self._hover:
            p.setPen(Qt.NoPen)
            p.setBrush(QColor(255, 255, 255, 16))
            p.drawRoundedRect(QRectF(self.rect()).adjusted(0, 1, 0, -1), 12, 12)
        paint_status(p, QPointF(22, self.height() / 2), 11, self.status, t)
        p.setFont(font(t))
        p.setPen(QColor(t.ink))
        p.drawText(QRectF(44, 0, self.width() - 48, self.height()), Qt.AlignVCenter, self.name)


class TaskDetail(QWidget):
    deleted = Signal()  # la tarea se borró
    created = Signal(int)  # Ctrl+N creó una tarea: se enseña con el nombre listo para escribir
    changed = Signal()  # cambió algo que se ve en el checklist (terminada, borrada, nombre, entrega)
    back = Signal()  # Esc: de vuelta al checklist o al Kanban

    def __init__(self, theme, call):
        super().__init__()
        self.theme = theme
        self._call = call
        self.task = None
        self._loading = False
        self._armed = False  # el primer Ctrl+Supr solo avisa
        self._shown = 0.0  # lo llena que se ve la barra ahora (0-1), animada hacia `_goal`
        self._goal = 0.0
        self.setFocusPolicy(Qt.StrongFocus)
        self.setStyleSheet(self._style(theme))
        self._build()
        self._fill_anim = Tween(self, self._set_progress)
        self._save_timer = QTimer(self)
        self._save_timer.setSingleShot(True)
        self._save_timer.setInterval(SAVE_MS)
        self._save_timer.timeout.connect(self._save_text)
        keys = {
            "Ctrl+N": self.new_task,
            "Ctrl+Return": self.toggle_done,
            "Ctrl+Enter": self.toggle_done,
            "Ctrl+Del": self.delete_task,
            "Ctrl+Shift+S": self.begin_subtask,
            "Ctrl+Up": lambda: self.scroll_by(-1),
            "Ctrl+Down": lambda: self.scroll_by(1),
            "Alt+Up": lambda: self.move_subtask(-1),
            "Alt+Down": lambda: self.move_subtask(1),
            "Esc": self.go_back,
        }
        for key, fn in keys.items():
            QShortcut(QKeySequence(key), self, fn, context=Qt.WidgetWithChildrenShortcut)

    @staticmethod
    def _style(theme):
        reply = (f"QLineEdit#Reply {{ background: {theme.frame_dark}; color: {theme.ink}; border: 1px solid rgba(255, 255, 255, 22);"
                 f" border-radius: 14px; padding: 9px 16px; }}"
                 f"QLineEdit#Reply:focus {{ border-color: {theme.gold}; }}"
                 f"QPushButton#Status {{ border-radius: 12px; padding: 5px 14px; font-weight: bold; }}")
        title = f"QLineEdit#Title {{ font: 600 {theme.font_px + 4}px '{theme.font_family}'; }}"
        return stylesheet(theme, flat_style=True) + reply + title

    def retheme(self, theme):
        self.setStyleSheet(self._style(theme))
        self.well.theme = theme
        self.subtasks.theme = theme
        self._paint_status()

    def _set_progress(self, value):
        self._shown = float(value)
        self.well.progress = self._shown
        self.well.update()

    # ---------- piezas ----------

    def _build(self):
        self.name = QLineEdit()
        self.name.setObjectName("Title")
        self.name.setPlaceholderText("Nombre de la tarea")
        self.name.textEdited.connect(lambda _: self._save_timer.start())
        # cuándo vence, debajo del nombre: un calendario que se abre en el recuadro de la derecha
        self.due_button = DateButton(self.theme)
        self.due_button.clicked.connect(self._open_calendar)
        due_row = QHBoxLayout()
        due_row.setContentsMargins(0, 0, 0, 0)
        due_row.addWidget(self.due_button)
        due_row.addStretch(1)
        names = QVBoxLayout()
        names.setSpacing(0)
        names.addWidget(self.name)
        names.addLayout(due_row)
        self.tag_bar = TagBar(self.theme)
        self.tag_bar.removed.connect(self._remove_tag)
        self.tag_input = QLineEdit()
        self.tag_input.setObjectName("Bare")
        self.tag_input.setPlaceholderText("+ etiqueta")
        self.tag_input.setFixedWidth(120)
        self.tag_input.returnPressed.connect(self._add_tag)
        self.tag_names = QStringListModel(self)
        completer = QCompleter(self.tag_names, self.tag_input)
        completer.setCaseSensitivity(Qt.CaseInsensitive)
        self.tag_input.setCompleter(completer)
        tag_row = QHBoxLayout()
        tag_row.setContentsMargins(4, 4, 0, 0)
        tag_row.setSpacing(6)
        tag_row.addWidget(self.tag_bar)
        tag_row.addWidget(self.tag_input)
        tag_row.addStretch(1)
        names.addLayout(tag_row)
        # el estado, a la derecha
        self.status_button = StatusToggle(self.theme)
        self.status_button.clicked.connect(self._next_status)
        head = QHBoxLayout()
        head.setSpacing(10)
        head.addLayout(names, 1)
        head.addWidget(self.status_button, 0, Qt.AlignTop)
        self.description = QPlainTextEdit()
        self.description.setObjectName("Body")
        self.description.setFrameShape(QFrame.NoFrame)
        self.description.setPlaceholderText("Añade una descripción…")
        self.description.textChanged.connect(lambda: None if self._loading else self._save_timer.start())
        self.subtasks = SubtaskList(self.theme)
        self.subtasks.status_cycled.connect(self._cycle_subtask)
        self.subtasks.removed.connect(self._remove_subtask)
        self.subtasks.moved.connect(self._moved_subtask)
        self.subtasks.renamed.connect(self._renamed_subtask)
        self.status = QLabel("")  # avisos (borrar con Ctrl+Supr...); oculto mientras no haya nada que decir
        self.status.setObjectName("Dim")
        self.status.hide()
        self.subtasks.created.connect(self._create_subtask)
        self.subtasks.cancelled.connect(lambda: self.add_button.show())
        self.subtasks.height_changed.connect(self._fit_subtasks)
        self.add_button = QPushButton("+  Añadir subtarea")
        self.add_button.setObjectName("Ghost")
        self.add_button.setCursor(Qt.PointingHandCursor)
        self.add_button.setFocusPolicy(Qt.NoFocus)
        self.add_button.clicked.connect(self.begin_subtask)
        # a la izquierda la tarea con sus subtareas; a la derecha, en un recuadro gris oscuro, solo la descripción
        self.scroll = QScrollArea()
        self.scroll.setWidget(self.subtasks)
        self.scroll.setWidgetResizable(True)
        self.scroll.setFrameShape(QFrame.NoFrame)
        self.scroll.setHorizontalScrollBarPolicy(Qt.ScrollBarAlwaysOff)
        self.scroll.setStyleSheet("QScrollArea, QScrollArea > QWidget > QWidget { background: transparent; }")
        self.scroll.hide()  # solo se ve si la tarea tiene subtareas
        left = QVBoxLayout()
        left.setSpacing(8)
        left.addLayout(head)
        left.addWidget(self.scroll, 1)
        left.addWidget(self.add_button, 0, Qt.AlignLeft)
        left.addStretch(1)
        left.addWidget(self.status)
        self.picker = DatePicker(self.theme, DEFAULT_HOUR)
        self.picker.accepted.connect(self._picked)
        self.picker.cancelled.connect(self.well_text)
        self.well = Well(self.theme, self.description, self.picker)
        layout = QHBoxLayout(self)
        layout.setContentsMargins(PAD, PAD - 2, PAD, PAD)
        layout.setSpacing(14)
        layout.addLayout(left, 5)
        layout.addWidget(self.well, 6)

    # ---------- núcleo ----------

    def _do(self, action, **payload):
        result = self._call(action, **payload)
        if not result["ok"]:
            self.say(result["error"]["message"])
            return None
        return result["data"] if result["data"] is not None else True

    def say(self, text, warn=False):
        self.status.setText(text)
        self.status.setStyleSheet(f"color: {self.theme.warn};" if warn else "")
        self.status.setVisible(bool(text))

    def go_back(self):
        if self.well.picking():  # Esc con el calendario abierto: solo lo cierra
            self.well_text()
            return
        self.flush()
        self.back.emit()

    def focus_name(self, select=False):
        self.name.setFocus()
        if select:
            self.name.selectAll()

    # ---------- mostrar ----------

    def show_task(self, task_id):
        """Lee la tarea y la enseña; False si ya no existe."""
        self.flush()
        self.say("")
        self._armed = False
        self._load_tag_names()
        task = self._do("tasks.get", task_id=task_id)
        self.task = task if isinstance(task, dict) else None
        if self.task is None:
            return False
        self._fill()
        return True

    def reload(self):
        if self.task:
            self.show_task(self.task["id"])

    def _fill(self):
        task = self.task
        self._loading = True
        if self.name.text() != task["name"]:
            self.name.setText(task["name"])
        if self.description.toPlainText() != task["description"]:
            self.description.setPlainText(task["description"])
        due = model.parse_time(task["due"])
        late = bool(due and due < datetime.now() and task["status"] != "done")
        self.due_button.set_label(model.date_text(due, datetime.now()) if due else "Sin fecha", late)
        self.well_text()
        self._paint_status()
        self.tag_bar.set_tags(task.get("tags", []))
        self.tag_bar.setFixedWidth(max(self.tag_bar.sizeHint().width(), 1))
        self._fill_subtasks(task)
        self.scroll.setVisible(bool(task["children"]) or self.subtasks._adding)
        self._show_progress(task)
        self._loading = False

    def _show_progress(self, task):
        """El borde del recuadro de la derecha se llena con las subtareas hechas (con una animación corta); sin subtareas,
        se enciende entero solo cuando la tarea está terminada."""
        done, total = model.progress(task["children"])
        self._goal = done / total if total else (1.0 if task["status"] == "done" else 0.0)
        if abs(self._goal - self._shown) > 0.001:
            self._fill_anim.start(self._shown, self._goal, FILL_MS, QEasingCurve.OutCubic)
        else:
            self.well.update()

    def _paint_status(self):
        """El estado de la tarea: su icono y su nombre."""
        if not self.task:
            return
        status = self.task["status"]
        self.status_button.set_status(self.theme, status, dict(model.STATUSES).get(status, status))

    def _next_status(self):
        """Un clic en el estado: pasa al siguiente y se ve al momento."""
        if self.task:
            self._set_status(model.next_status(self.task["status"]))

    def _set_status(self, status):
        if self.task and status != self.task["status"]:
            self.flush()
            if self._do("tasks.set_status", task_id=self.task["id"], status=status):
                self.reload()
                self.changed.emit()

    def _fill_subtasks(self, task, pick=None):
        self.subtasks.set_items(task["children"], pick)
        self._fit_subtasks(self.subtasks.wanted_height() if task["children"] or self.subtasks._adding else 0)

    def _fit_subtasks(self, height):
        """La lista mide lo que ocupan sus filas: se ve entera hasta cierto punto y después se desliza."""
        self.scroll.setMinimumHeight(min(height, 280) + 4)
        self.scroll.setMaximumHeight(height + 4)

    # ---------- guardar ----------

    def _save_text(self):
        if not self.task:
            return
        changes = {}
        if self.name.text().strip() and self.name.text().strip() != self.task["name"]:
            changes["name"] = self.name.text()
        if self.description.toPlainText() != self.task["description"]:
            changes["description"] = self.description.toPlainText()
        if changes and self._do("tasks.update", task_id=self.task["id"], **changes):
            self.task.update(changes)
            self.changed.emit()

    def flush(self):
        """Guarda lo escrito (antes de cambiar de tarea o cerrar el panel)."""
        if self._save_timer.isActive():
            self._save_timer.stop()
            self._save_text()

    def _set_due(self, due):
        if self.task and self._do("tasks.update", task_id=self.task["id"], due=due):
            self.reload()
            self.changed.emit()

    def _open_calendar(self):
        """El botón de la fecha: el calendario ocupa el recuadro de la derecha (la descripción vuelve al aceptar o cancelar)."""
        if not self.task:
            return
        self.picker.open(self.task["due"])
        self.well.show_picker()
        self.picker.setFocus()

    def well_text(self):
        self.well.show_text()

    def _picked(self, due):
        self.well_text()
        if self.task and due != self.task["due"]:
            self._set_due(due)

    # ---------- crear, terminar y borrar ----------

    def new_task(self):
        """Ctrl+N: una tarea nueva, que se abre en este mismo panel con el nombre seleccionado."""
        self.flush()
        task_id = self._do("tasks.create", name="Nueva tarea")
        if task_id:
            self.changed.emit()
            self.created.emit(task_id)

    def toggle_done(self):
        if self.task:
            self.flush()
            self._armed = False
            done = self.task["status"] == "done"
            if self._do("tasks.set_status", task_id=self.task["id"], status="pending" if done else "done"):
                self.say("Reabierta" if done else "Terminada")
                self.reload()
                self.changed.emit()

    def delete_task(self):
        """Ctrl+Supr, dos veces: la primera solo avisa aquí mismo (sin ventanas)."""
        if not self.task:
            return
        task = self.task
        if not self._armed:
            self._armed = True
            extra = f" (y sus {len(task['children'])} subtareas)" if task["children"] else ""
            self.say(f"Pulsa Ctrl+Supr otra vez para borrarla{extra}", warn=True)
            return
        self._armed = False
        self._save_timer.stop()
        if self._do("tasks.delete", task_id=task["id"]):
            self.task = None
            self.changed.emit()
            self.deleted.emit()

    # ---------- subtareas ----------

    def begin_subtask(self):
        """El botón (o Ctrl+Mayús+S): una fila más al final de la lista para escribir la subtarea nueva."""
        if not self.task:
            return
        self.add_button.hide()
        self.scroll.show()
        self.subtasks.begin_new()
        QTimer.singleShot(0, self._to_end)

    def _to_end(self):
        bar = self.scroll.verticalScrollBar()
        bar.setValue(bar.maximum())

    def _create_subtask(self, name):
        """Enter en la fila nueva: crea la subtarea y la lista abre otra fila para la siguiente."""
        if self.task and self._do("tasks.add_subtask", task_id=self.task["id"], name=name):
            self.reload()
            self.changed.emit()
            QTimer.singleShot(0, self._to_end)

    def _child(self, child_id):
        return next((c for c in self.task["children"] if c["id"] == child_id), None) if self.task else None

    def _add_tag(self):
        """Enter en "+ etiqueta": la crea si no existía y se la pone a la tarea."""
        name = self.tag_input.text().strip()
        if not self.task or not name:
            return
        tag_id = self._do("tags.create", name=name)
        if tag_id and tag_id is not True and self._do("tags.assign", task_id=self.task["id"], tag_id=tag_id):
            self.tag_input.clear()
            self._subtasks_changed()
            self._load_tag_names()

    def _remove_tag(self, tag_id):
        if self.task and self._do("tags.unassign", task_id=self.task["id"], tag_id=tag_id):
            self._subtasks_changed()

    def _load_tag_names(self):
        """Las etiquetas que ya existen, para que el campo las sugiera al escribir."""
        names = self._do("tags.list")
        self.tag_names.setStringList([t["name"] for t in names] if isinstance(names, list) else [])

    def _cycle_subtask(self, child_id):
        """Clic en el icono de una subtarea: la termina o la deja sin terminar (no tienen más estados)."""
        child = self._child(child_id)
        if child is None:
            return
        done = child.get("status") == "done" or bool(child.get("finished"))
        if self._do("tasks.set_status", task_id=child_id, status="pending" if done else "done"):
            self._subtasks_changed()

    def _remove_subtask(self, child_id):
        if self._child(child_id) is not None and self._do("tasks.delete", task_id=child_id):
            self._subtasks_changed()

    def _moved_subtask(self, child_id, position):
        if self._do("tasks.move", task_id=child_id, position=position):
            self.task = self._do("tasks.get", task_id=self.task["id"])
            self._fill_subtasks(self.task, pick=child_id)
            self.changed.emit()

    def _renamed_subtask(self, child_id, name):
        if not name:  # vaciar el nombre de una subtarea la quita
            self._remove_subtask(child_id)
        elif self._do("tasks.update", task_id=child_id, name=name):
            self._subtasks_changed()

    def _subtasks_changed(self):
        self.reload()
        self.changed.emit()

    def scroll_by(self, direction):
        """Ctrl+↑/↓: se desliza la lista de subtareas (a la izquierda)."""
        bar = self.scroll.verticalScrollBar()
        bar.setValue(bar.value() + direction * max(int(self.scroll.viewport().height() * 0.8), 60))

    def move_subtask(self, delta):
        child_id = self.subtasks.current_id()
        if not self.task or child_id is None:
            return
        ids = [c["id"] for c in self.task["children"]]
        row = ids.index(child_id) + delta
        if 0 <= row < len(ids):
            self._moved_subtask(child_id, row)

    def hideEvent(self, event):
        self.flush()
        super().hideEvent(event)
