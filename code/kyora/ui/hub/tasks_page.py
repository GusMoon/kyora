"""Sección Tareas del panel de arriba (4.3 de kyoraBase.md), en tres placas de cristal:

- Filtros: fecha de entrega (todas, hoy, esta semana, vencidas, sin fecha), finalizadas y etiquetas (varias a la
  vez; clic derecho para renombrar o borrar).
- Lista: las tareas como en la referencia (punto de su etiqueta, nombre, descripción y entrega a la derecha); la
  abierta va en claro, las finalizadas atenuadas y tachadas.
- Detalle: nombre, descripción, entrega, tiempo esperado, tiempo real con su cronómetro, fechas, etiquetas,
  subtareas ordenadas, Finalizar/Reabrir y Borrar. Se guarda solo al dejar de escribir.

Teclas: Ctrl+N nueva tarea, Ctrl+Shift+N nueva subtarea, Ctrl+Enter finalizar o reabrir, Ctrl+T cronómetro,
Supr (en la lista) borrar, Ctrl+↑/↓ mover la subtarea elegida.
"""
from datetime import datetime, time, timedelta

from PySide6.QtCore import (
    QDate,
    QDateTime,
    QPoint,
    QRect,
    QRectF,
    QSize,
    Qt,
    QTime,
    QTimer,
)
from PySide6.QtGui import (
    QColor,
    QFont,
    QIcon,
    QKeySequence,
    QPainter,
    QPixmap,
    QShortcut,
)
from PySide6.QtWidgets import (
    QAbstractItemView,
    QButtonGroup,
    QDateTimeEdit,
    QHBoxLayout,
    QLabel,
    QLayout,
    QLineEdit,
    QListWidget,
    QListWidgetItem,
    QMenu,
    QPlainTextEdit,
    QPushButton,
    QStackedWidget,
    QStyle,
    QStyledItemDelegate,
    QVBoxLayout,
    QWidget,
)

from kyora.tasks import model
from kyora.ui import glyphs
from kyora.ui.bar import font
from kyora.ui.explorer import dialogs
from kyora.ui.explorer.preview import GlyphButton
from kyora.ui.hub.cards import Card, paint_glass

SAVE_MS = 400
ROW_H = 66
NO_DATE = QDateTime(QDate(2000, 1, 1), QTime(0, 0))
STAMP_SHOW = "%d/%m %H:%M"


def _stamp(text):
    return datetime.fromisoformat(text).strftime(STAMP_SHOW) if text else ""


class FlowLayout(QLayout):
    """Coloca los widgets en fila y salta de línea cuando no caben (las etiquetas del detalle)."""

    def __init__(self, spacing=6):
        super().__init__()
        self._items = []
        self._space = spacing

    def addItem(self, item):
        self._items.append(item)

    def count(self):
        return len(self._items)

    def itemAt(self, index):
        return self._items[index] if 0 <= index < len(self._items) else None

    def takeAt(self, index):
        return self._items.pop(index) if 0 <= index < len(self._items) else None

    def hasHeightForWidth(self):
        return True

    def heightForWidth(self, width):
        return self._place(QRect(0, 0, width, 0), apply=False)

    def setGeometry(self, rect):
        super().setGeometry(rect)
        self._place(rect, apply=True)

    def sizeHint(self):
        return self.minimumSize()

    def minimumSize(self):
        size = QSize()
        for item in self._items:
            size = size.expandedTo(item.minimumSize())
        return size

    def _place(self, rect, apply):
        x, y, line = rect.x(), rect.y(), 0
        for item in self._items:
            hint = item.sizeHint()
            if x + hint.width() > rect.right() + 1 and line:
                x, y, line = rect.x(), y + line + self._space, 0
            if apply:
                item.setGeometry(QRect(QPoint(x, y), hint))
            x += hint.width() + self._space
            line = max(line, hint.height())
        return y + line - rect.y()


class TaskDelegate(QStyledItemDelegate):
    """Una tarea como en la referencia: placa de cristal con su punto, nombre, descripción y entrega."""

    def __init__(self, theme):
        super().__init__()
        self.theme = theme

    def sizeHint(self, option, index):
        return QSize(option.rect.width(), ROW_H + 8)

    def paint(self, p, option, index):
        t = self.theme
        task = index.data(Qt.UserRole)
        p.save()
        p.setRenderHint(QPainter.Antialiasing)
        box = QRectF(option.rect).adjusted(2, 4, -2, -4)
        picked = bool(option.state & QStyle.State_Selected)
        hover = bool(option.state & QStyle.State_MouseOver)
        paint_glass(p, t, box, 14, hi=hover and not picked, fill=t.pick_bg if picked else None)
        done = bool(task.get("finished"))
        ink = QColor(t.pick_ink if picked else t.ink)
        dim = QColor("#5a5a5a" if picked else t.dim)
        if done:
            ink.setAlpha(140)
        dot = QColor(task["tags"][0]["color"]) if task.get("tags") else QColor(t.dim)
        p.setPen(Qt.NoPen)
        p.setBrush(dot)
        p.drawEllipse(QRectF(box.left() + 16, box.top() + 20, 8, 8))
        right = box.right() - 14
        if task.get("timer_started"):  # cronómetro en marcha
            p.setPen(Qt.NoPen)
            p.setBrush(QColor(t.positive))
            p.drawEllipse(QRectF(right - 8, box.top() + 20, 8, 8))
            right -= 18
        title = font(t, 16, bold=True)
        title.setStrikeOut(done)
        p.setFont(title)
        p.setPen(ink)
        name = p.fontMetrics().elidedText(task["name"], Qt.ElideRight, int(right - box.left() - 36))
        p.drawText(QRectF(box.left() + 34, box.top() + 10, right - box.left() - 34, 26), Qt.AlignVCenter, name)
        # segunda línea: subtareas y descripción a la izquierda, la entrega a la derecha
        p.setFont(font(t, 15))
        right = box.right() - 14
        due = model.due_label(task.get("due"))
        if due:
            width = p.fontMetrics().horizontalAdvance(due)
            late = not done and datetime.fromisoformat(task["due"]) < datetime.now()
            p.setPen(QColor(t.warn) if late else dim)
            p.drawText(QRectF(right - width, box.top() + 34, width, 24), Qt.AlignVCenter | Qt.AlignRight, due)
            p.setPen(glyphs.pen(QColor(t.warn) if late else dim, 1.4))
            p.setBrush(Qt.NoBrush)
            glyphs.clock(p, QRectF(right - width - 21, box.top() + 37, 17, 17))
            right -= width + 30
        line = " ".join((task.get("description") or "").split())
        if task.get("subtasks"):
            line = f"{task['subtasks_done']}/{task['subtasks']} subtareas" + (f" · {line}" if line else "")
        p.setPen(dim)
        line = p.fontMetrics().elidedText(line, Qt.ElideRight, int(right - box.left() - 36))
        p.drawText(QRectF(box.left() + 34, box.top() + 34, right - box.left() - 34, 24), Qt.AlignVCenter, line)
        p.restore()


class TasksPage(QWidget):
    def __init__(self, theme, call):
        super().__init__()
        self.theme = theme
        self._call = call
        self.due_filter, self.tag_filter, self.show_finished = "all", set(), False
        self.task = None  # la tarea abierta en el detalle (dict de tasks.get)
        self._loading = False
        self.setFocusPolicy(Qt.StrongFocus)

        self._build_filters()
        self._build_list()
        self._build_detail()
        row = QHBoxLayout(self)
        row.setContentsMargins(0, 0, 0, 0)
        row.setSpacing(12)
        row.addWidget(self.filters_card)
        row.addWidget(self.list_card, 5)
        row.addWidget(self.detail_card, 4)

        self._save_timer = QTimer(self)
        self._save_timer.setSingleShot(True)
        self._save_timer.setInterval(SAVE_MS)
        self._save_timer.timeout.connect(self._save_text)
        self._tick = QTimer(self)
        self._tick.setInterval(1000)
        self._tick.timeout.connect(self._show_real)
        self._shortcuts()

    # ---------- piezas ----------

    def _build_filters(self):
        t = self.theme
        self.filters_card = Card(t, "Filtros")
        self.filters_card.setFixedWidth(200)
        layout = QVBoxLayout(self.filters_card.inner)
        layout.setContentsMargins(12, 12, 12, 12)
        layout.setSpacing(6)
        self.due_group = QButtonGroup(self)
        for key, text in model.DUE_FILTERS:
            b = QPushButton(text)
            b.setObjectName("Pill")
            b.setCheckable(True)
            b.setCursor(Qt.PointingHandCursor)
            b.setChecked(key == "all")
            b.clicked.connect(lambda _=False, k=key: self._set_due(k))
            self.due_group.addButton(b)
            layout.addWidget(b)
        self.finished_toggle = QPushButton("Ver finalizadas")
        self.finished_toggle.setObjectName("Pill")
        self.finished_toggle.setCheckable(True)
        self.finished_toggle.setCursor(Qt.PointingHandCursor)
        self.finished_toggle.toggled.connect(self._set_finished)
        layout.addWidget(self.finished_toggle)
        tags_title = QLabel("Etiquetas")
        tags_title.setObjectName("CardTitle")
        layout.addSpacing(8)
        layout.addWidget(tags_title)
        self.tag_list = QListWidget()
        self.tag_list.setSelectionMode(QAbstractItemView.MultiSelection)
        self.tag_list.setFocusPolicy(Qt.NoFocus)
        self.tag_list.setHorizontalScrollBarPolicy(Qt.ScrollBarAlwaysOff)
        self.tag_list.itemSelectionChanged.connect(self._tags_picked)
        self.tag_list.setContextMenuPolicy(Qt.CustomContextMenu)
        self.tag_list.customContextMenuRequested.connect(self._tag_menu)
        layout.addWidget(self.tag_list, 1)
        self.new_tag = QLineEdit()
        self.new_tag.setPlaceholderText("Nueva etiqueta…")
        self.new_tag.returnPressed.connect(self._create_tag)
        layout.addWidget(self.new_tag)

    def _build_list(self):
        t = self.theme
        self.list_card = Card(t, "Tareas")
        self.count = QLabel("")
        self.count.setObjectName("Dim")
        self.list_card.header.addWidget(self.count)
        self.new_task = QLineEdit()
        self.new_task.setPlaceholderText("Nueva tarea… (Enter para crearla)")
        self.new_task.returnPressed.connect(self._create_task)
        self.list = QListWidget()
        self.list.setItemDelegate(TaskDelegate(t))
        self.list.setMouseTracking(True)
        self.list.setVerticalScrollMode(QAbstractItemView.ScrollPerPixel)
        self.list.currentItemChanged.connect(self._picked)
        self.list.setStyleSheet("QListWidget::item, QListWidget::item:selected, QListWidget::item:hover"
                                " { background: transparent; border: 0; }")
        QShortcut(QKeySequence(Qt.Key_Delete), self.list, self.delete_task, context=Qt.WidgetShortcut)
        self.status = QLabel("")
        self.status.setObjectName("Dim")
        layout = QVBoxLayout(self.list_card.inner)
        layout.setContentsMargins(12, 12, 12, 10)
        layout.setSpacing(8)
        layout.addWidget(self.new_task)
        layout.addWidget(self.list, 1)
        layout.addWidget(self.status)

    def _field_label(self, text):
        label = QLabel(text)
        label.setObjectName("Dim")
        return label

    def _build_detail(self):
        t = self.theme
        self.detail_card = Card(t, "Detalle")
        self.detail_stack = QStackedWidget(self.detail_card.inner)
        empty = QLabel("Elige una tarea de la lista\no crea una con Ctrl+N.")
        empty.setObjectName("Dim")
        empty.setAlignment(Qt.AlignCenter)
        self.detail_stack.addWidget(empty)
        form = QWidget()
        self.detail_stack.addWidget(form)
        outer = QVBoxLayout(self.detail_card.inner)
        outer.setContentsMargins(14, 12, 14, 12)
        outer.addWidget(self.detail_stack)

        self.name = QLineEdit()
        self.name.setObjectName("Big")
        self.name.textEdited.connect(lambda _: self._save_timer.start())
        self.description = QPlainTextEdit()
        self.description.setObjectName("Field")
        self.description.setPlaceholderText("Descripción")
        self.description.setFixedHeight(70)
        self.description.textChanged.connect(self._description_changed)
        self.due = QDateTimeEdit()
        self.due.setDisplayFormat("dd/MM/yyyy HH:mm")
        self.due.setCalendarPopup(False)  # el calendario desplegable robaría el foco y cerraría el panel
        self.due.setMinimumDateTime(NO_DATE)
        self.due.setSpecialValueText("Sin fecha")
        self.due.editingFinished.connect(self._due_edited)
        due_row = QHBoxLayout()
        due_row.setSpacing(6)
        due_row.addWidget(self.due, 1)
        for text, days in (("Hoy", 0), ("Mañana", 1), ("Sin fecha", None)):
            b = QPushButton(text)
            b.setObjectName("Pill")
            b.setCursor(Qt.PointingHandCursor)
            b.clicked.connect(lambda _=False, d=days: self._quick_due(d))
            due_row.addWidget(b)
        self.expected = QLineEdit()
        self.expected.setPlaceholderText("p. ej. 1 h 30 min")
        self.expected.editingFinished.connect(self._expected_edited)
        self.real = QLabel("0:00")
        self.real.setObjectName("MidNumber")
        self.timer_button = QPushButton("Empezar")
        self.timer_button.setCursor(Qt.PointingHandCursor)
        self.timer_button.clicked.connect(self.toggle_timer)
        times = QHBoxLayout()
        times.setSpacing(10)
        expected_col = QVBoxLayout()
        expected_col.addWidget(self._field_label("Tiempo esperado"))
        expected_col.addWidget(self.expected)
        real_col = QVBoxLayout()
        real_col.addWidget(self._field_label("Tiempo real (Ctrl+T)"))
        real_row = QHBoxLayout()
        real_row.addWidget(self.real)
        real_row.addStretch(1)
        real_row.addWidget(self.timer_button)
        real_col.addLayout(real_row)
        times.addLayout(expected_col, 1)
        times.addLayout(real_col, 1)
        self.dates = QLabel("")
        self.dates.setObjectName("Dim")
        self.dates.setWordWrap(True)
        self.tag_chips = QWidget()
        self.tag_flow = FlowLayout()
        self.tag_chips.setLayout(self.tag_flow)

        self.subtasks = QListWidget()
        self.subtasks.setDragDropMode(QAbstractItemView.NoDragDrop)
        self.subtasks.setHorizontalScrollBarPolicy(Qt.ScrollBarAlwaysOff)
        self.subtasks.itemChanged.connect(self._subtask_changed)
        self.new_subtask = QLineEdit()
        self.new_subtask.setPlaceholderText("Nueva subtarea… (Ctrl+Shift+N)")
        self.new_subtask.returnPressed.connect(self._create_subtask)
        sub_head = QHBoxLayout()
        sub_title = QLabel("Subtareas")
        sub_title.setObjectName("CardTitle")
        sub_head.addWidget(sub_title)
        sub_head.addStretch(1)
        for glyph, tip, fn in ((lambda p, b: glyphs.chevron(p, b, "up"), "Subir (Ctrl+↑)", lambda: self.move_subtask(-1)),
                               (lambda p, b: glyphs.chevron(p, b, "down"), "Bajar (Ctrl+↓)",
                                lambda: self.move_subtask(1)),
                               (glyphs.trash, "Borrar la subtarea", self._delete_subtask)):
            b = GlyphButton(t, glyph, tip, size=30)
            b.clicked.connect(fn)
            sub_head.addWidget(b)

        self.finish_button = QPushButton("Finalizar")
        self.finish_button.setObjectName("Accent")
        self.finish_button.setCursor(Qt.PointingHandCursor)
        self.finish_button.clicked.connect(self.toggle_finished)
        delete = QPushButton("Borrar")
        delete.setCursor(Qt.PointingHandCursor)
        delete.clicked.connect(self.delete_task)
        actions = QHBoxLayout()
        actions.addWidget(self.dates, 1)
        actions.addWidget(delete)
        actions.addWidget(self.finish_button)

        layout = QVBoxLayout(form)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(6)
        layout.addWidget(self.name)
        layout.addWidget(self.description)
        layout.addWidget(self._field_label("Entrega"))
        layout.addLayout(due_row)
        layout.addLayout(times)
        layout.addWidget(self._field_label("Etiquetas"))
        layout.addWidget(self.tag_chips)
        layout.addLayout(sub_head)
        layout.addWidget(self.subtasks, 1)
        layout.addWidget(self.new_subtask)
        layout.addLayout(actions)

    def _shortcuts(self):
        keys = {
            "Ctrl+N": self.focus_new_task,
            "Ctrl+Shift+N": self.focus_new_subtask,
            "Ctrl+Return": self.toggle_finished,
            "Ctrl+Enter": self.toggle_finished,
            "Ctrl+T": self.toggle_timer,
            "Ctrl+Up": lambda: self.move_subtask(-1),
            "Ctrl+Down": lambda: self.move_subtask(1),
        }
        for key, fn in keys.items():
            QShortcut(QKeySequence(key), self, fn, context=Qt.WidgetWithChildrenShortcut)

    # ---------- núcleo ----------

    def _do(self, action, **payload):
        result = self._call(action, **payload)
        if not result["ok"]:
            self.say(result["error"]["message"])
            return None
        return result["data"] if result["data"] is not None else True

    def say(self, text):
        self.status.setText(text)

    # ---------- abrir ----------

    def activate(self):
        self.refresh()

    def focus_first(self):
        (self.list if self.list.count() else self.new_task).setFocus()

    def refresh(self, keep=True):
        """Vuelve a leer etiquetas y tareas (con los filtros) y mantiene la abierta si sigue en la lista."""
        self._fill_tags()
        tasks = self._do("tasks.list", tags=sorted(self.tag_filter), due=self.due_filter,
                         finished=self.show_finished) or []
        current = self.task["id"] if keep and self.task else None
        self.list.blockSignals(True)
        self.list.clear()
        pick = None
        for task in tasks:
            item = QListWidgetItem()
            item.setData(Qt.UserRole, task)
            item.setSizeHint(QSize(0, ROW_H + 8))
            self.list.addItem(item)
            if task["id"] == current:
                pick = item
        self.list.blockSignals(False)
        self.count.setText(f"{len(tasks)} {'tarea' if len(tasks) == 1 else 'tareas'}")
        if pick is not None:
            self.list.setCurrentItem(pick)
            self._open(current)
        elif current is None or not keep:
            self._open(None)
        else:
            self._open(current)  # sigue existiendo aunque el filtro la oculte

    def _fill_tags(self):
        tags = self._do("tags.list") or []
        self.tags = tags
        self.tag_list.blockSignals(True)
        self.tag_list.clear()
        for tag in tags:
            item = QListWidgetItem(f"{tag['name']}  ·  {tag['count']}")
            item.setData(Qt.UserRole, tag)
            item.setForeground(QColor(self.theme.ink))
            item.setIcon(self._dot(tag["color"]))
            self.tag_list.addItem(item)
            item.setSelected(tag["id"] in self.tag_filter)
        self.tag_list.blockSignals(False)
        self.tag_filter &= {tag["id"] for tag in tags}

    @staticmethod
    def _dot(color):
        pixmap = QPixmap(24, 24)
        pixmap.fill(Qt.transparent)
        p = QPainter(pixmap)
        p.setRenderHint(QPainter.Antialiasing)
        p.setPen(Qt.NoPen)
        p.setBrush(QColor(color))
        p.drawEllipse(QRectF(7, 7, 10, 10))
        p.end()
        return QIcon(pixmap)

    # ---------- filtros ----------

    def _set_due(self, key):
        self.due_filter = key
        self.refresh()

    def _set_finished(self, on):
        self.show_finished = on
        self.refresh()

    def _tags_picked(self):
        self.tag_filter = {item.data(Qt.UserRole)["id"] for item in self.tag_list.selectedItems()}
        self.refresh()

    def _create_tag(self):
        name = self.new_tag.text().strip()
        if name and self._do("tags.create", name=name):
            self.new_tag.clear()
            self.refresh()

    def _tag_menu(self, pos):
        item = self.tag_list.itemAt(pos)
        if item is None:
            return
        tag = item.data(Qt.UserRole)
        menu = QMenu(self)
        menu.addAction("Renombrar", lambda: self._rename_tag(tag))
        menu.addAction("Borrar la etiqueta", lambda: self._delete_tag(tag))
        menu.exec(self.tag_list.mapToGlobal(pos))

    def _rename_tag(self, tag):
        name = dialogs.ask_name(self, "Renombrar la etiqueta", tag["name"], select_stem=False)
        if name and self._do("tags.rename", tag_id=tag["id"], name=name):
            self.refresh()

    def _delete_tag(self, tag):
        if dialogs.confirm(self, f"¿Borrar la etiqueta «{tag['name']}»?",
                           "Se quita de sus tareas; las tareas se quedan.", "Borrar"):
            self._do("tags.delete", tag_id=tag["id"])
            self.refresh()

    # ---------- lista ----------

    def focus_new_task(self):
        self.new_task.setFocus()
        self.new_task.selectAll()

    def _create_task(self):
        name = self.new_task.text().strip()
        if not name:
            return
        task_id = self._do("tasks.create", name=name)
        if task_id:
            for tag_id in self.tag_filter:  # con un filtro de etiqueta puesto, la nueva lo lleva (si no, no se vería)
                self._do("tags.assign", task_id=task_id, tag_id=tag_id)
            self.new_task.clear()
            self.task = {"id": task_id}
            self.refresh()
            self.say(f"Creada «{name}»")

    def _picked(self, item, _previous=None):
        self.flush()
        self._open(item.data(Qt.UserRole)["id"] if item is not None else None)

    # ---------- detalle ----------

    def _open(self, task_id):
        task = self._do("tasks.get", task_id=task_id) if task_id is not None else None
        self.task = task if isinstance(task, dict) else None
        self.detail_stack.setCurrentIndex(1 if self.task else 0)
        if self.task is None:
            self._tick.stop()
            return
        task = self.task
        self._loading = True
        if self.name.text() != task["name"]:
            self.name.setText(task["name"])
        if self.description.toPlainText() != task["description"]:
            self.description.setPlainText(task["description"])
        self.due.setDateTime(QDateTime.fromString(task["due"], "yyyy-MM-ddTHH:mm") if task["due"] else NO_DATE)
        if not self.expected.hasFocus():
            self.expected.setText(model.format_duration(task["expected_min"]))
        self._fill_chips(task)
        self._fill_subtasks(task)
        self.finish_button.setText("Reabrir" if task["finished"] else "Finalizar")
        dates = [f"Creada {_stamp(task['created'])}", f"actualizada {_stamp(task['updated'])}"]
        if task["finished"]:
            dates.append(f"finalizada {_stamp(task['finished'])}")
        self.dates.setText(" · ".join(dates))
        self._loading = False
        self._show_real()
        if task["timer_started"] and self.isVisible():
            self._tick.start()
        else:
            self._tick.stop()

    def _fill_chips(self, task):
        while self.tag_flow.count():
            item = self.tag_flow.takeAt(0)
            if item.widget():
                item.widget().deleteLater()
        mine = {tag["id"] for tag in task["tags"]}
        for tag in getattr(self, "tags", []):
            b = QPushButton(tag["name"])
            b.setObjectName("Pill")
            b.setCheckable(True)
            b.setChecked(tag["id"] in mine)
            b.setIcon(self._dot(tag["color"]))
            b.setCursor(Qt.PointingHandCursor)
            b.toggled.connect(lambda on, tag_id=tag["id"]: self._toggle_tag(tag_id, on))
            self.tag_flow.addWidget(b)
        if not getattr(self, "tags", []):
            hint = QLabel("Crea etiquetas a la izquierda")
            hint.setObjectName("Dim")
            self.tag_flow.addWidget(hint)
        self.tag_chips.updateGeometry()

    def _fill_subtasks(self, task, pick=None):
        self.subtasks.blockSignals(True)
        current = pick if pick is not None else (self.subtasks.currentItem().data(Qt.UserRole)
                                                 if self.subtasks.currentItem() else None)
        self.subtasks.clear()
        for child in task["children"]:
            item = QListWidgetItem(child["name"])
            item.setData(Qt.UserRole, child["id"])
            item.setFlags(item.flags() | Qt.ItemIsUserCheckable | Qt.ItemIsEditable)
            item.setCheckState(Qt.Checked if child["finished"] else Qt.Unchecked)
            if child["finished"]:
                f = QFont(item.font())
                f.setStrikeOut(True)
                item.setFont(f)
                item.setForeground(QColor(self.theme.dim))
            self.subtasks.addItem(item)
            if child["id"] == current:
                self.subtasks.setCurrentItem(item)
        self.subtasks.blockSignals(False)

    def _show_real(self):
        if self.task:
            seconds = model.real_seconds(self.task, datetime.now())
            self.real.setText(model.format_seconds(seconds))
            running = bool(self.task["timer_started"])
            self.timer_button.setText("Parar" if running else "Empezar")
            self.timer_button.setObjectName("Accent" if running else "")
            self.timer_button.style().unpolish(self.timer_button)
            self.timer_button.style().polish(self.timer_button)

    def _reload(self):
        """Tras un cambio: relee la tarea abierta y la lista (sin perder la elegida)."""
        self.refresh()

    def _description_changed(self):
        if not self._loading:
            self._save_timer.start()

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
            self._refresh_row()

    def flush(self):
        """Guarda lo escrito antes de cambiar de tarea o cerrar el panel."""
        if self._save_timer.isActive():
            self._save_timer.stop()
            self._save_text()

    def _refresh_row(self):
        """Actualiza la fila de la lista de la tarea abierta sin recargar todo (mientras se escribe)."""
        item = self.list.currentItem()
        if item is not None and self.task and item.data(Qt.UserRole)["id"] == self.task["id"]:
            row = dict(item.data(Qt.UserRole))
            row.update(name=self.task["name"], description=self.task["description"])
            item.setData(Qt.UserRole, row)

    def _due_edited(self):
        if not self.task or self._loading:
            return
        value = self.due.dateTime()
        due = None if value == NO_DATE else value.toString("yyyy-MM-ddTHH:mm")
        if due != self.task["due"] and self._do("tasks.update", task_id=self.task["id"], due=due):
            self._reload()

    def _quick_due(self, days):
        if not self.task:
            return
        if days is None:
            due = None
        else:
            day = datetime.now().date() + timedelta(days=days)
            keep = datetime.fromisoformat(self.task["due"]).time() if self.task["due"] else time(18, 0)
            due = datetime.combine(day, keep).strftime("%Y-%m-%dT%H:%M")
        if self._do("tasks.update", task_id=self.task["id"], due=due):
            self._reload()

    def _expected_edited(self):
        if not self.task:
            return
        text = self.expected.text().strip()
        try:
            minutes = model.parse_duration(text)
        except ValueError as err:
            self.say(str(err))
            return
        if minutes != self.task["expected_min"] and self._do("tasks.update", task_id=self.task["id"],
                                                             expected_min=minutes):
            self.expected.setText(model.format_duration(minutes))
            self._reload()

    def _toggle_tag(self, tag_id, on):
        if self.task:
            self._do("tags.assign" if on else "tags.unassign", task_id=self.task["id"], tag_id=tag_id)
            QTimer.singleShot(0, self._reload)  # después del clic: el botón se rehace

    def toggle_finished(self):
        if self.task:
            self.flush()
            done = bool(self.task["finished"])
            if self._do("tasks.reopen" if done else "tasks.finish", task_id=self.task["id"]):
                self.say(f"«{self.task['name']}» {'reabierta' if done else 'finalizada'}")
                self._reload()

    def toggle_timer(self):
        if self.task:
            running = bool(self.task["timer_started"])
            if self._do("tasks.timer_stop" if running else "tasks.timer_start", task_id=self.task["id"]):
                self._reload()

    def delete_task(self):
        if not self.task:
            return
        task = self.task
        extra = f" y sus {len(task['children'])} subtareas" if task["children"] else ""
        if not dialogs.confirm(self, f"¿Borrar «{task['name']}»?",
                               f"Se borra la tarea{extra}. Las etiquetas se quedan.", "Borrar"):
            return
        if self._do("tasks.delete", task_id=task["id"]):
            self.task = None
            self.refresh(keep=False)
            self.say(f"Borrada «{task['name']}»")

    # ---------- subtareas ----------

    def focus_new_subtask(self):
        if self.task:
            self.new_subtask.setFocus()

    def _create_subtask(self):
        name = self.new_subtask.text().strip()
        if self.task and name and self._do("tasks.add_subtask", task_id=self.task["id"], name=name):
            self.new_subtask.clear()
            self._reload()

    def _subtask_changed(self, item):
        child_id = item.data(Qt.UserRole)
        child = next((c for c in self.task["children"] if c["id"] == child_id), None) if self.task else None
        if child is None:
            return
        name = item.text().strip()
        if name and name != child["name"]:
            self._do("tasks.update", task_id=child_id, name=name)
        done = item.checkState() == Qt.Checked
        if done != bool(child["finished"]):
            self._do("tasks.finish" if done else "tasks.reopen", task_id=child_id)
        QTimer.singleShot(0, self._reload)

    def move_subtask(self, delta):
        item = self.subtasks.currentItem()
        if not self.task or item is None:
            return
        row = self.subtasks.row(item) + delta
        if 0 <= row < self.subtasks.count():
            child_id = item.data(Qt.UserRole)
            if self._do("tasks.move", task_id=child_id, position=row):
                self.task = self._do("tasks.get", task_id=self.task["id"])
                self._fill_subtasks(self.task, pick=child_id)

    def _delete_subtask(self):
        item = self.subtasks.currentItem()
        if not self.task or item is None:
            return
        if (dialogs.confirm(self, f"¿Borrar la subtarea «{item.text()}»?", "No se puede deshacer.", "Borrar")
                and self._do("tasks.delete", task_id=item.data(Qt.UserRole))):
            self._reload()

    # ---------- visibilidad ----------

    def showEvent(self, event):
        if self.task and self.task.get("timer_started"):
            self._tick.start()
        super().showEvent(event)

    def hideEvent(self, event):
        self.flush()
        self._tick.stop()
        super().hideEvent(event)
