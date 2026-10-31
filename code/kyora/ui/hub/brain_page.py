"""Sección Segundo Cerebro del panel de arriba (4.4 de kyoraBase.md).

- La primera vez pide dónde crearlo (un campo con autocompletado: un diálogo de Windows cerraría el panel).
- Izquierda: los espacios Notas (con los Impulsos) y Corteza (Área › Dendrita › Neurona y sus axones), un campo
  para guardar un impulso, el buscador y el botón + según dónde estés. Clic derecho: crear, renombrar o borrar.
- Centro: el editor visual (QTextEdit: carga y guarda Markdown sin enseñar el código; Ctrl+M lo enseña). Las
  sinapsis `[[Título]]` se ven como enlaces (Ctrl+clic las abre) y al escribir `[[` salen los títulos. Se guarda
  solo al dejar de escribir, al cambiar de nota y al cerrar el panel. Al elegir una dendrita se ve su Núcleo.
- Derecha: Soma (los títulos de la nota; un clic lleva a ellos), Sinapsis, Enlaces de vuelta y los metadatos.
"""
import os
from urllib.parse import quote, unquote

from PySide6.QtCore import QDir, QStringListModel, Qt, QTimer, Signal
from PySide6.QtGui import (
    QColor,
    QFont,
    QKeySequence,
    QPalette,
    QShortcut,
    QTextBlockFormat,
    QTextCharFormat,
    QTextCursor,
    QTextDocument,
    QTextFormat,
    QTextListFormat,
)
from PySide6.QtWidgets import (
    QCompleter,
    QFileSystemModel,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QListWidget,
    QListWidgetItem,
    QMenu,
    QPlainTextEdit,
    QPushButton,
    QStackedWidget,
    QTextEdit,
    QTreeWidget,
    QTreeWidgetItem,
    QVBoxLayout,
    QWidget,
)

from kyora.brain import links
from kyora.ui import glyphs
from kyora.ui.explorer import dialogs, file_icons
from kyora.ui.explorer.preview import GlyphButton
from kyora.ui.hub.cards import Card, Glass, Pills

SAVE_MS = 1000
CORTEX_PART = os.sep + "Corteza" + os.sep


def note_in_cortex(path):
    return CORTEX_PART in path
SEARCH_MS = 250
HEADING_PX = {1: 26, 2: 21, 3: 18}
KIND_NAMES = {"neurona": "Neurona", "axón": "Axón", "nota": "Nota", "impulso": "Impulso"}


class Editor(QTextEdit):
    """El editor visual. Ctrl+clic en una sinapsis la abre; `[[` abre la lista de títulos."""

    open_link = Signal(str)
    wants_titles = Signal()

    def __init__(self):
        super().__init__()
        self.completer = None
        self.setAcceptRichText(False)  # al pegar, texto: el formato lo pone el editor

    def mouseReleaseEvent(self, event):
        href = self.anchorAt(event.position().toPoint())
        if href.startswith(links.SCHEME) and event.modifiers() & Qt.ControlModifier:
            self.open_link.emit(unquote(href[len(links.SCHEME):]))
            return
        super().mouseReleaseEvent(event)

    def mouseMoveEvent(self, event):
        href = self.anchorAt(event.position().toPoint())
        self.viewport().setCursor(Qt.PointingHandCursor if href and event.modifiers() & Qt.ControlModifier
                                  else Qt.IBeamCursor)
        super().mouseMoveEvent(event)

    def keyPressEvent(self, event):
        popup = self.completer.popup() if self.completer else None
        if popup is not None and popup.isVisible() and event.key() in (
                Qt.Key_Return, Qt.Key_Enter, Qt.Key_Tab, Qt.Key_Escape):
            event.ignore()  # las lleva el completador
            return
        super().keyPressEvent(event)
        cursor = self.textCursor()
        cursor.movePosition(QTextCursor.Left, QTextCursor.KeepAnchor, 2)
        if event.text() == "[" and cursor.selectedText() == "[[":
            self.wants_titles.emit()


class BrainPage(QWidget):
    def __init__(self, theme, call):
        super().__init__()
        self.theme = theme
        self._call = call
        self.space = "notes"
        self.note = None  # la nota abierta: {path, mtime, meta, …} de brain.read
        self._loading = False
        self.setFocusPolicy(Qt.StrongFocus)

        self.stack = QStackedWidget()
        self.stack.addWidget(self._build_setup())
        self.stack.addWidget(self._build_main())
        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.addWidget(self.stack)

        self._save_timer = QTimer(self)
        self._save_timer.setSingleShot(True)
        self._save_timer.setInterval(SAVE_MS)
        self._save_timer.timeout.connect(self.save)
        self._search_timer = QTimer(self)
        self._search_timer.setSingleShot(True)
        self._search_timer.setInterval(SEARCH_MS)
        self._search_timer.timeout.connect(self._search)
        self._shortcuts()

    # ---------- primera vez ----------

    def _build_setup(self):
        t = self.theme
        page = QWidget()
        card = Glass(t)
        card.setFixedWidth(620)
        title = QLabel("Elige dónde crear tu Segundo Cerebro")
        title.setObjectName("Big")
        text = QLabel("Es una carpeta normal con tus notas en archivos .md: Notas (con los Impulsos) y Corteza "
                      "(Áreas › Dendritas › Neuronas). Puedes abrirla también con otros programas.")
        text.setObjectName("Dim")
        text.setWordWrap(True)
        self.setup_path = QLineEdit()
        dirs = QFileSystemModel(self)
        dirs.setRootPath("")
        dirs.setFilter(QDir.AllDirs | QDir.Drives | QDir.NoDotAndDotDot)
        completer = QCompleter(dirs, self)
        completer.setCaseSensitivity(Qt.CaseInsensitive)
        self.setup_path.setCompleter(completer)
        self.setup_path.returnPressed.connect(self._setup)
        create = QPushButton("Crear aquí")
        create.setObjectName("Accent")
        create.setCursor(Qt.PointingHandCursor)
        create.clicked.connect(self._setup)
        row = QHBoxLayout()
        row.addWidget(self.setup_path, 1)
        row.addWidget(create)
        self.setup_status = QLabel("")
        self.setup_status.setObjectName("Dim")
        inner = QVBoxLayout(card)
        inner.setContentsMargins(28, 24, 28, 24)
        inner.setSpacing(12)
        inner.addWidget(title)
        inner.addWidget(text)
        inner.addLayout(row)
        inner.addWidget(self.setup_status)
        outer = QVBoxLayout(page)
        outer.addStretch(1)
        outer.addWidget(card, 0, Qt.AlignHCenter)
        outer.addStretch(2)
        return page

    def _setup(self):
        result = self._call("brain.setup", path=self.setup_path.text())
        if not result["ok"]:
            self.setup_status.setText(result["error"]["message"])
            return
        self.activate()

    # ---------- piezas ----------

    def _build_main(self):
        t = self.theme
        page = QWidget()
        # izquierda
        self.left = Card(t, "Cerebro", glyph=glyphs.brain)
        self.left.setFixedWidth(280)
        self.add_button = GlyphButton(t, glyphs.plus, "Crear…", size=30)
        self.add_button.clicked.connect(lambda: self._create_menu(self.add_button.mapToGlobal(
            self.add_button.rect().bottomLeft())))
        self.left.header.addWidget(self.add_button)
        self.spaces = Pills((("notes", "Notas"), ("cortex", "Corteza")))
        self.spaces.chosen.connect(self._set_space)
        self.impulse = QLineEdit()
        self.impulse.setPlaceholderText("Impulso: una idea y Enter")
        self.impulse.returnPressed.connect(self._save_impulse)
        self.search_edit = QLineEdit()
        self.search_edit.setPlaceholderText("Buscar… (Ctrl+Shift+F)")
        self.search_edit.textChanged.connect(lambda _: self._search_timer.start())
        self.tree = QTreeWidget()
        self.tree.setHeaderHidden(True)
        self.tree.setIndentation(14)
        self.tree.setHorizontalScrollBarPolicy(Qt.ScrollBarAlwaysOff)
        self.tree.itemClicked.connect(self._tree_clicked)
        self.tree.itemActivated.connect(self._tree_clicked)
        self.tree.setContextMenuPolicy(Qt.CustomContextMenu)
        self.tree.customContextMenuRequested.connect(self._tree_menu)
        self.results = QListWidget()
        self.results.setHorizontalScrollBarPolicy(Qt.ScrollBarAlwaysOff)
        self.results.itemClicked.connect(lambda item: self.open(item.data(Qt.UserRole)))
        self.results.itemActivated.connect(lambda item: self.open(item.data(Qt.UserRole)))
        self.left_views = QStackedWidget()
        self.left_views.addWidget(self.tree)
        self.left_views.addWidget(self.results)
        left = QVBoxLayout(self.left.inner)
        left.setContentsMargins(10, 12, 10, 10)
        left.setSpacing(8)
        left.addWidget(self.spaces)
        left.addWidget(self.impulse)
        left.addWidget(self.search_edit)
        left.addWidget(self.left_views, 1)

        # centro
        self.center = Card(t, "")
        self.saved = QLabel("")
        self.saved.setObjectName("Dim")
        self.center.header.addWidget(self.saved)
        self.source_button = QPushButton("Markdown")
        self.source_button.setObjectName("Pill")
        self.source_button.setCheckable(True)
        self.source_button.setToolTip("Ver y editar el Markdown (Ctrl+M)")
        self.source_button.setCursor(Qt.PointingHandCursor)
        self.source_button.toggled.connect(self._show_source)
        self.center.header.addWidget(self.source_button)
        self.toolbar = QWidget()
        bar = QHBoxLayout(self.toolbar)
        bar.setContentsMargins(0, 0, 0, 0)
        bar.setSpacing(2)
        for text, tip, fn in (
            ("T1", "Título 1 (Ctrl+Alt+1)", lambda: self.heading(1)),
            ("T2", "Título 2 (Ctrl+Alt+2)", lambda: self.heading(2)),
            ("T3", "Título 3 (Ctrl+Alt+3)", lambda: self.heading(3)),
            ("N", "Negrita (Ctrl+B)", self.bold),
            ("C", "Cursiva (Ctrl+I)", self.italic),
            ("•", "Lista (Ctrl+Shift+8)", lambda: self.make_list(QTextListFormat.ListDisc)),
            ("1.", "Lista numerada", lambda: self.make_list(QTextListFormat.ListDecimal)),
            ("❝", "Cita", self.quote_block),
            ("</>", "Código", self.code),
            ("[[ ]]", "Sinapsis: enlazar otra nota", self.insert_link),
        ):
            b = QPushButton(text)
            b.setObjectName("Ghost")
            b.setToolTip(tip)
            b.setCursor(Qt.PointingHandCursor)
            b.setFocusPolicy(Qt.NoFocus)
            b.clicked.connect(fn)
            if text == "N":
                b.setStyleSheet("font-weight: bold;")
            elif text == "C":
                b.setStyleSheet("font-style: italic;")
            bar.addWidget(b)
        bar.addStretch(1)
        self.editor = Editor()
        palette = self.editor.palette()
        palette.setColor(QPalette.Link, QColor(t.gold))
        palette.setColor(QPalette.Text, QColor(t.ink))
        self.editor.setPalette(palette)
        self.editor.document().setDocumentMargin(10)
        self.editor.textChanged.connect(self._edited)
        self.editor.open_link.connect(self.open_title)
        self.editor.wants_titles.connect(self._complete_titles)
        self.completer = QCompleter(self)
        self.completer.setWidget(self.editor)
        self.completer.setCaseSensitivity(Qt.CaseInsensitive)
        self.completer.setFilterMode(Qt.MatchContains)
        self.completer.activated.connect(self._insert_title)
        self.editor.completer = self.completer
        self.source = QPlainTextEdit()
        self.source.setObjectName("Source")
        self.source.setFont(QFont(t.mono_family, 11))
        self.source.textChanged.connect(self._edited)
        self.nucleus = QListWidget()
        self.nucleus.setHorizontalScrollBarPolicy(Qt.ScrollBarAlwaysOff)
        self.nucleus.setWordWrap(True)
        self.nucleus.itemClicked.connect(lambda item: self.open(item.data(Qt.UserRole)))
        self.nucleus.itemActivated.connect(lambda item: self.open(item.data(Qt.UserRole)))
        self.empty = QLabel("Elige una nota a la izquierda, o crea una con Ctrl+N.\n"
                            "Las ideas rápidas van en el campo Impulso.")
        self.empty.setObjectName("Dim")
        self.empty.setAlignment(Qt.AlignCenter)
        self.views = QStackedWidget()
        for w in (self.empty, self.editor, self.source, self.nucleus):
            self.views.addWidget(w)
        self.status = QLabel("")
        self.status.setObjectName("Dim")
        center = QVBoxLayout(self.center.inner)
        center.setContentsMargins(12, 8, 12, 8)
        center.setSpacing(4)
        center.addWidget(self.toolbar)
        center.addWidget(self.views, 1)
        center.addWidget(self.status)

        # derecha
        self.soma_card = Card(t, "Soma")
        self.soma = QListWidget()
        self.soma.setHorizontalScrollBarPolicy(Qt.ScrollBarAlwaysOff)
        self.soma.itemClicked.connect(self._go_heading)
        self.parts = QLabel("")
        self.parts.setObjectName("Dim")
        self.parts.setWordWrap(True)
        soma = QVBoxLayout(self.soma_card.inner)
        soma.setContentsMargins(8, 8, 8, 8)
        soma.addWidget(self.soma, 1)
        soma.addWidget(self.parts)
        self.synapses_card = Card(t, "Sinapsis")
        self.synapses = QListWidget()
        self.synapses.setHorizontalScrollBarPolicy(Qt.ScrollBarAlwaysOff)
        self.synapses.itemClicked.connect(self._open_synapse)
        QVBoxLayout(self.synapses_card.inner).addWidget(self.synapses)
        self.synapses_card.inner.layout().setContentsMargins(8, 8, 8, 8)
        self.backlinks_card = Card(t, "Enlaces de vuelta")
        self.backlinks = QListWidget()
        self.backlinks.setHorizontalScrollBarPolicy(Qt.ScrollBarAlwaysOff)
        self.backlinks.itemClicked.connect(lambda item: self.open(item.data(Qt.UserRole)))
        QVBoxLayout(self.backlinks_card.inner).addWidget(self.backlinks)
        self.backlinks_card.inner.layout().setContentsMargins(8, 8, 8, 8)
        self.meta = QLabel("")
        self.meta.setObjectName("Dim")
        self.meta.setWordWrap(True)
        right = QVBoxLayout()
        right.setSpacing(8)
        right.addWidget(self.soma_card, 3)
        right.addWidget(self.synapses_card, 2)
        right.addWidget(self.backlinks_card, 2)
        right.addWidget(self.meta)
        side = QWidget()
        side.setFixedWidth(250)
        side.setLayout(right)
        right.setContentsMargins(0, 0, 0, 0)

        row = QHBoxLayout(page)
        row.setContentsMargins(0, 0, 0, 0)
        row.setSpacing(12)
        row.addWidget(self.left)
        row.addWidget(self.center, 1)
        row.addWidget(side)
        self._show_note_tools(False)
        return page

    def _shortcuts(self):
        page_keys = {
            "Ctrl+S": self.save,
            "Ctrl+M": lambda: self.source_button.toggle() if self.note else None,
            "Ctrl+N": self.new_here,
            "Ctrl+Shift+F": self.focus_search,
            "Ctrl+Shift+I": self.focus_impulse,
        }
        for key, fn in page_keys.items():
            QShortcut(QKeySequence(key), self, fn, context=Qt.WidgetWithChildrenShortcut)
        editor_keys = {
            "Ctrl+B": self.bold,
            "Ctrl+I": self.italic,
            "Ctrl+Alt+1": lambda: self.heading(1),
            "Ctrl+Alt+2": lambda: self.heading(2),
            "Ctrl+Alt+3": lambda: self.heading(3),
            "Ctrl+Alt+0": lambda: self.heading(0),
            "Ctrl+Shift+8": lambda: self.make_list(QTextListFormat.ListDisc),
        }
        for key, fn in editor_keys.items():
            QShortcut(QKeySequence(key), self.editor, fn, context=Qt.WidgetShortcut)

    # ---------- núcleo ----------

    def _do(self, action, **payload):
        result = self._call(action, **payload)
        if not result["ok"]:
            self.say(result["error"]["message"])
            return None
        return result["data"] if result["data"] is not None else True

    def say(self, text):
        self.status.setText(text)

    # ---------- abrir el panel ----------

    def activate(self):
        status = self._do("brain.status") or {}
        if not status.get("configured"):
            self.setup_path.setText(status.get("default", ""))
            self.stack.setCurrentIndex(0)
            return
        self.stack.setCurrentIndex(1)
        self.left.title.setText(os.path.basename(status["root"]) or "Cerebro")
        self.left.title.setToolTip(status["root"])
        self.refresh_tree()
        if self.note and not os.path.exists(self.note["path"]):
            self._close_note()

    def focus_first(self):
        if self.stack.currentIndex() == 0:
            self.setup_path.setFocus()
        elif self.note:
            (self.source if self.source_button.isChecked() else self.editor).setFocus()
        else:
            self.tree.setFocus()

    def deactivate(self):
        self.flush()

    # ---------- árbol ----------

    def _set_space(self, key):
        self.space = key
        self.refresh_tree()

    def refresh_tree(self):
        tree = self._do("brain.tree")
        if not tree:
            return
        icons = file_icons.shared()
        open_path = self.note["path"] if self.note else None
        expanded = {self._key(i) for i in self._items() if i.isExpanded()}
        self.tree.clear()

        def add(parent, text, data, icon=None):
            item = QTreeWidgetItem([text])
            item.setData(0, Qt.UserRole, data)
            if icon is not None:
                item.setIcon(0, icon)
            item.setToolTip(0, data.get("path", ""))
            (parent.addChild if parent is not None else self.tree.addTopLevelItem)(item)
            return item

        def add_notes(parent, notes):
            by_title = {n["title"].casefold(): n for n in notes}
            children = {}
            for n in notes:
                if n["kind"] == "axón" and n["origin"].casefold() in by_title:
                    children.setdefault(n["origin"].casefold(), []).append(n)
            for n in notes:
                if n["kind"] == "axón" and n["origin"].casefold() in by_title:
                    continue
                item = add(parent, n["title"], {"type": "note", **n}, icons.file())
                for axon in children.get(n["title"].casefold(), ()):
                    add(item, axon["title"], {"type": "note", **axon}, icons.file())

        if self.space == "notes":
            add_notes(None, tree["notes"])
            group = add(None, f"Impulsos · {len(tree['impulses'])}", {"type": "impulses"}, icons.folder())
            add_notes(group, list(reversed(tree["impulses"])))  # los más nuevos arriba
        else:
            for area in tree["cortex"]:
                area_item = add(None, area["name"], {"type": "area", "path": area["path"]}, icons.folder())
                for dendrite in area["dendrites"]:
                    d_item = add(area_item, dendrite["name"], {"type": "dendrite", "path": dendrite["path"]},
                                 icons.folder())
                    add_notes(d_item, dendrite["notes"])
            if not tree["cortex"]:
                hint = QTreeWidgetItem(["Crea un área con el botón +"])
                hint.setData(0, Qt.UserRole, {"type": "hint"})
                hint.setForeground(0, QColor(self.theme.dim))
                self.tree.addTopLevelItem(hint)
        for item in self._items():
            data = item.data(0, Qt.UserRole) or {}
            if self._key(item) in expanded or data.get("type") == "impulses" and not expanded:
                item.setExpanded(True)
            if open_path and data.get("path") == open_path:
                self.tree.setCurrentItem(item)
                parent = item.parent()
                while parent is not None:
                    parent.setExpanded(True)
                    parent = parent.parent()

    def _items(self):
        found, stack = [], [self.tree.topLevelItem(i) for i in range(self.tree.topLevelItemCount())]
        while stack:
            item = stack.pop()
            found.append(item)
            stack.extend(item.child(i) for i in range(item.childCount()))
        return found

    @staticmethod
    def _key(item):
        data = item.data(0, Qt.UserRole) or {}
        return data.get("path") or data.get("type")

    def _tree_clicked(self, item, _column=0):
        data = item.data(0, Qt.UserRole) or {}
        if data.get("type") == "note":
            self.open(data["path"])
        elif data.get("type") == "dendrite":
            self.show_nucleus(data["path"])

    def _context(self):
        """(qué hay elegido en el árbol, sus datos) para saber qué se puede crear."""
        item = self.tree.currentItem()
        return item.data(0, Qt.UserRole) if item is not None else {}

    def _create_menu(self, where):
        menu = QMenu(self)
        self._fill_create(menu, self._context() or {})
        menu.exec(where)

    def _tree_menu(self, pos):
        item = self.tree.itemAt(pos)
        if item is not None:
            self.tree.setCurrentItem(item)
        data = (item.data(0, Qt.UserRole) if item is not None else None) or {}
        menu = QMenu(self)
        self._fill_create(menu, data)
        if data.get("path") and data.get("type") in ("note", "area", "dendrite"):
            menu.addSeparator()
            menu.addAction("Renombrar", lambda: self.rename(data))
            menu.addAction("Borrar (a la Papelera)", lambda: self.delete(data))
        menu.exec(self.tree.viewport().mapToGlobal(pos))

    def _fill_create(self, menu, data):
        if self.space == "notes":
            menu.addAction("Nueva nota", self.new_note)
            return
        menu.addAction("Nueva área", self.new_area)
        area = self._area_of(data)
        if area:
            menu.addAction("Nueva dendrita", lambda: self.new_dendrite(area))
        dendrite = self._dendrite_of(data)
        if dendrite:
            menu.addAction("Nueva neurona", lambda: self.new_neuron(dendrite))
        if data.get("type") == "note" and data.get("kind") == "neurona":
            menu.addAction("Nuevo axón", lambda: self.new_axon(data["path"]))

    @staticmethod
    def _area_of(data):
        path = data.get("path")
        if data.get("type") == "area":
            return path
        if data.get("type") == "dendrite":
            return os.path.dirname(path)
        if data.get("type") == "note" and data.get("kind") in ("neurona", "axón"):
            return os.path.dirname(os.path.dirname(path))
        return None

    @staticmethod
    def _dendrite_of(data):
        if data.get("type") == "dendrite":
            return data["path"]
        if data.get("type") == "note" and data.get("kind") in ("neurona", "axón"):
            return os.path.dirname(data["path"])
        return None

    # ---------- crear, renombrar y borrar ----------

    def new_here(self):
        """Ctrl+N: en Notas, una nota; en la Corteza, una neurona en la dendrita elegida (o un área si no hay)."""
        if self.stack.currentIndex() == 0:
            return
        data = self._context() or {}
        if self.space == "notes":
            self.new_note()
        elif self._dendrite_of(data):
            self.new_neuron(self._dendrite_of(data))
        else:
            self.new_area()

    def _ask(self, title, current=""):
        return dialogs.ask_name(self, title, current, select_stem=False)

    def new_note(self):
        name = self._ask("Nueva nota")
        path = name and self._do("brain.create_note", title=name)
        if path:
            self.refresh_tree()
            self.open(path)

    def new_area(self):
        name = self._ask("Nueva área de la Corteza")
        if name and self._do("brain.create_area", name=name):
            self.refresh_tree()

    def new_dendrite(self, area):
        name = self._ask(f"Nueva dendrita en «{os.path.basename(area)}»")
        path = name and self._do("brain.create_dendrite", area=area, name=name)
        if path:
            self.refresh_tree()
            self.show_nucleus(path)

    def new_neuron(self, dendrite):
        name = self._ask(f"Nueva neurona en «{os.path.basename(dendrite)}»")
        path = name and self._do("brain.create_neuron", dendrite=dendrite, title=name)
        if path:
            self.refresh_tree()
            self.open(path)

    def new_axon(self, neuron):
        name = self._ask(f"Nuevo axón de «{os.path.splitext(os.path.basename(neuron))[0]}»")
        path = name and self._do("brain.derive", path=neuron, title=name)
        if path:
            self.refresh_tree()
            self.open(path)

    def _save_impulse(self):
        text = self.impulse.text().strip()
        if text and self._do("brain.impulse", text=text):
            self.impulse.clear()
            self.say("Impulso guardado en Notas › Impulsos")
            if self.space == "notes":
                self.refresh_tree()

    def rename(self, data):
        current = data.get("title") or os.path.basename(data["path"])
        name = self._ask("Renombrar", current)
        if not name or name == current:
            return
        self.flush()
        new = self._do("brain.rename", path=data["path"], name=name)
        if new:
            if self.note and self.note["path"] == data["path"]:
                self.note["path"] = new
            elif self.note and not os.path.exists(self.note["path"]):
                self._close_note()
            self.refresh_tree()
            if self.note:
                self.open(self.note["path"], save_first=False)

    def delete(self, data):
        name = data.get("title") or os.path.basename(data["path"])
        what = "la nota" if data["type"] == "note" else ("el área" if data["type"] == "area" else "la dendrita")
        extra = "" if data["type"] == "note" else " con todo lo que tiene dentro"
        if not dialogs.confirm(self, f"¿Borrar {what} «{name}»{extra}?",
                               "Va a la Papelera de Windows: se puede recuperar desde allí.", "Borrar"):
            return
        if self._do("brain.delete", path=data["path"]):
            if self.note and not os.path.exists(self.note["path"]):
                self._close_note()
            self.refresh_tree()

    # ---------- abrir notas ----------

    def open(self, path, save_first=True):
        if not path:
            return
        if save_first:
            self.flush()
        note = self._do("brain.read", path=path)
        if not isinstance(note, dict):
            return
        self.note = note
        self._loading = True
        self._set_markdown(note["body"])
        self.editor.document().setModified(False)
        self.source.setPlainText(note["body"])
        self._loading = False
        self.center.title.setText(note["title"])
        self.views.setCurrentWidget(self.source if self.source_button.isChecked() else self.editor)
        self._show_note_tools(True)
        self._show_details(note)
        self.saved.setText("")
        self.say("")
        self._select_in_tree(note["path"])

    def _select_in_tree(self, path):
        """Marca la nota abierta en el árbol (y despliega sus carpetas); si es del otro espacio, cambia a él."""
        space = "cortex" if note_in_cortex(path) else "notes"
        if space != self.space:
            self.space = space
            self.spaces.choose(space, silent=True)
            self.refresh_tree()
            return  # refresh_tree ya la marca
        for item in self._items():
            if (item.data(0, Qt.UserRole) or {}).get("path") == path:
                self.tree.setCurrentItem(item)
                parent = item.parent()
                while parent is not None:
                    parent.setExpanded(True)
                    parent = parent.parent()
                return

    def _set_markdown(self, body):
        """Carga el Markdown en el editor visual con las sinapsis como enlaces del color de acento."""
        self.editor.setMarkdown(links.wiki_to_anchor(body))
        self._color_links()

    def _color_links(self):
        """Las sinapsis, del color de acento (el editor no lo toma solo de la paleta)."""
        color = QColor(self.theme.gold)
        modified = self.editor.document().isModified()
        loading, self._loading = self._loading, True
        block = self.editor.document().begin()
        while block.isValid():
            it = block.begin()
            while not it.atEnd():
                fragment = it.fragment()
                if fragment.charFormat().isAnchor():
                    cursor = QTextCursor(self.editor.document())
                    cursor.setPosition(fragment.position())
                    cursor.setPosition(fragment.position() + fragment.length(), QTextCursor.KeepAnchor)
                    link = QTextCharFormat()
                    link.setForeground(color)
                    cursor.mergeCharFormat(link)
                it += 1
            block = block.next()
        self.editor.document().setModified(modified)
        self._loading = loading

    def retheme(self, theme):
        """Colores nuevos (el fondo cambió): texto y sinapsis del editor."""
        palette = self.editor.palette()
        palette.setColor(QPalette.Link, QColor(theme.gold))
        palette.setColor(QPalette.Text, QColor(theme.ink))
        self.editor.setPalette(palette)
        self._color_links()

    def open_title(self, title):
        path = self._do("brain.resolve", title=title)
        if path:
            self.open(path)
        else:
            self.say(f"No hay ninguna nota «{title}». Créala desde la lista de Sinapsis.")

    def _close_note(self):
        self.note = None
        self.center.title.setText("")
        self.views.setCurrentWidget(self.empty)
        self._show_note_tools(False)
        for w in (self.soma, self.synapses, self.backlinks):
            w.clear()
        self.parts.setText("")
        self.meta.setText("")

    def _show_note_tools(self, on):
        self.toolbar.setVisible(on and not self.source_button.isChecked())
        self.source_button.setVisible(on)

    def show_nucleus(self, dendrite):
        rows = self._do("brain.nucleus", path=dendrite)
        if rows is None:
            return
        self.flush()
        self.note = None
        self._show_note_tools(False)
        self.center.title.setText(f"Núcleo · {os.path.basename(dendrite)}")
        self.nucleus.clear()
        for row in rows:
            heads = " · ".join(h["text"] for h in row["headings"] if h["level"] > 1)
            text = f"{row['title']}   ({KIND_NAMES.get(row['kind'], row['kind'])}"
            text += f" de {row['origin']})" if row["origin"] else ")"
            item = QListWidgetItem(text + (f"\n{heads}" if heads else ""))
            item.setData(Qt.UserRole, row["path"])
            item.setIcon(file_icons.shared().file())
            self.nucleus.addItem(item)
        if not rows:
            item = QListWidgetItem("Esta dendrita aún no tiene neuronas: Ctrl+N crea una.")
            item.setForeground(QColor(self.theme.dim))
            self.nucleus.addItem(item)
        self.views.setCurrentWidget(self.nucleus)
        for w in (self.soma, self.synapses, self.backlinks):
            w.clear()
        self.parts.setText("")
        self.meta.setText(f"Dendrita con {len(rows)} {'nota' if len(rows) == 1 else 'notas'}")

    def _show_details(self, note):
        t = self.theme
        self.soma.clear()
        for h in note["soma"]["headings"]:
            item = QListWidgetItem("   " * (h["level"] - 1) + h["text"])
            item.setData(Qt.UserRole, h["text"])
            if h["level"] == 1:
                f = QFont(item.font())
                f.setBold(True)
                item.setFont(f)
            self.soma.addItem(item)
        self.parts.setText(" · ".join(f"{name} {count}" for name, count in note["soma"]["parts"].items()))
        self.synapses.clear()
        for s in note["synapses"]:
            item = QListWidgetItem(s["title"] if s["path"] else f"{s['title']}  (crear)")
            item.setData(Qt.UserRole, s)
            if not s["path"]:
                item.setForeground(QColor(t.dim))
            self.synapses.addItem(item)
        self.backlinks.clear()
        for b in note["backlinks"]:
            item = QListWidgetItem(b["title"])
            item.setData(Qt.UserRole, b["path"])
            self.backlinks.addItem(item)
        meta = note.get("meta") or {}
        bits = [KIND_NAMES.get(note["kind"], note["kind"])]
        if meta.get("corteza"):
            bits.append(f"{meta['corteza']} › {meta.get('dendrita', '')}")
        if meta.get("origen"):
            bits.append(f"origen {meta['origen']}")
        if meta.get("creada"):
            bits.append(f"creada {meta['creada']}")
        if meta.get("actualizada"):
            bits.append(f"actualizada {meta['actualizada']}")
        self.meta.setText("\n".join(bits))

    def _go_heading(self, item):
        text = item.data(Qt.UserRole)
        if self.source_button.isChecked():
            found = self.source.document().find(text)
            target = self.source
        else:
            found = self.editor.document().find(text)
            target = self.editor
        if not found.isNull():
            target.setTextCursor(found)
            target.ensureCursorVisible()
            target.setFocus()

    def _open_synapse(self, item):
        synapse = item.data(Qt.UserRole)
        if synapse["path"]:
            self.open(synapse["path"])
            return
        path = self._do("brain.create_note", title=synapse["title"])  # una sinapsis a una nota que aún no existe
        if path:
            self.refresh_tree()
            self.open(path)

    # ---------- buscar ----------

    def focus_search(self):
        if self.stack.currentIndex() == 1:
            self.search_edit.setFocus()
            self.search_edit.selectAll()

    def focus_impulse(self):
        if self.stack.currentIndex() == 1:
            self.impulse.setFocus()

    def _search(self):
        query = self.search_edit.text().strip()
        if not query:
            self.left_views.setCurrentWidget(self.tree)
            return
        hits = self._do("brain.search", query=query) or []
        self.results.clear()
        for hit in hits:
            item = QListWidgetItem(f"{hit['title']}\n{hit['snippet']}")
            item.setData(Qt.UserRole, hit["path"])
            item.setToolTip(hit["path"])
            self.results.addItem(item)
        if not hits:
            item = QListWidgetItem("Nada encontrado")
            item.setForeground(QColor(self.theme.dim))
            self.results.addItem(item)
        self.left_views.setCurrentWidget(self.results)

    # ---------- guardar ----------

    def _edited(self):
        if self._loading or not self.note:
            return
        self.saved.setText("Sin guardar")
        self._save_timer.start()

    def _editor_markdown(self):
        """El Markdown del editor visual, con las sinapsis como `[[…]]` y sin los cortes de línea del editor."""
        markdown = self.editor.document().toMarkdown(QTextDocument.MarkdownDialectGitHub)
        return links.anchor_to_wiki(links.unwrap(markdown))

    def _body(self):
        return self.source.toPlainText() if self.source_button.isChecked() else self._editor_markdown()

    def flush(self):
        """Guarda ya si hay algo pendiente (al cambiar de nota o cerrar el panel)."""
        if self._save_timer.isActive():
            self._save_timer.stop()
            self.save()

    def save(self, force=False):
        if not self.note:
            return
        self._save_timer.stop()
        body = self._body()
        result = self._call("brain.save", path=self.note["path"], body=body, mtime=self.note["mtime"], force=force)
        if not result["ok"]:
            if result["error"]["code"] == "changed" and dialogs.confirm(
                    self, "La nota cambió fuera de Kyora",
                    "Otro programa la modificó desde que la abriste. ¿Guardar tu versión encima?", "Guardar la mía"):
                self.save(force=True)
            else:
                self.say(result["error"]["message"])
            return
        data = result["data"]
        self.note.update(mtime=data["mtime"], body=body, meta=data["meta"], soma=data["soma"],
                         synapses=data["synapses"], backlinks=data["backlinks"])
        self._show_details(self.note)
        self.saved.setText("Guardado")

    def _show_source(self, on):
        """Ctrl+M: cambia entre el editor visual y el Markdown (lo escrito pasa de uno a otro)."""
        if not self.note:
            return
        self._loading = True
        if on:
            self.source.setPlainText(self._editor_markdown())
            self.views.setCurrentWidget(self.source)
            self.source.setFocus()
        else:
            self._set_markdown(self.source.toPlainText())
            self.views.setCurrentWidget(self.editor)
            self.editor.setFocus()
        self._loading = False
        self.toolbar.setVisible(not on)

    # ---------- formatos ----------

    def heading(self, level):
        cursor = self.editor.textCursor()
        block = QTextBlockFormat(cursor.blockFormat())
        level = 0 if block.headingLevel() == level else level  # pulsar otra vez lo quita
        block.setHeadingLevel(level)
        cursor.beginEditBlock()
        cursor.setBlockFormat(block)
        cursor.select(QTextCursor.BlockUnderCursor)
        char = QTextCharFormat()
        char.setFontWeight(QFont.Bold if level else QFont.Normal)
        char.setProperty(QTextFormat.FontSizeAdjustment, 0)
        size = HEADING_PX.get(level)
        if size:
            char.setFontPointSize(size * 0.75)
        else:
            char.setFontPointSize(self.editor.font().pointSizeF())
        cursor.mergeCharFormat(char)
        cursor.endEditBlock()

    def bold(self):
        char = QTextCharFormat()
        bold = self.editor.fontWeight() < QFont.Bold
        char.setFontWeight(QFont.Bold if bold else QFont.Normal)
        self._merge(char)

    def italic(self):
        char = QTextCharFormat()
        char.setFontItalic(not self.editor.fontItalic())
        self._merge(char)

    def code(self):
        char = QTextCharFormat()
        on = not self.editor.currentCharFormat().fontFixedPitch()
        char.setFontFixedPitch(on)
        char.setFontFamilies([self.theme.mono_family] if on else [self.theme.font_family])
        self._merge(char)

    def _merge(self, char):
        cursor = self.editor.textCursor()
        if not cursor.hasSelection():
            cursor.select(QTextCursor.WordUnderCursor)
        cursor.mergeCharFormat(char)
        self.editor.mergeCurrentCharFormat(char)

    def make_list(self, style):
        cursor = self.editor.textCursor()
        current = cursor.currentList()
        if current is not None and current.format().style() == style:
            block = QTextBlockFormat(cursor.blockFormat())
            current.remove(cursor.block())
            block.setIndent(0)
            cursor.setBlockFormat(block)
            return
        cursor.createList(style)

    def quote_block(self):
        cursor = self.editor.textCursor()
        block = QTextBlockFormat(cursor.blockFormat())
        quoted = block.property(QTextFormat.BlockQuoteLevel) or 0
        block.setProperty(QTextFormat.BlockQuoteLevel, 0 if quoted else 1)
        block.setLeftMargin(0 if quoted else 24)
        cursor.setBlockFormat(block)

    def insert_link(self):
        self.editor.setFocus()
        self.editor.insertPlainText("[[")
        self._complete_titles()

    def _complete_titles(self):
        titles = self._do("brain.titles") or []
        if self.note:
            titles = [t for t in titles if t != self.note["title"]]
        self.completer.setModel(QStringListModel(titles, self.completer))
        rect = self.editor.cursorRect()
        rect.setWidth(320)
        self.completer.complete(rect)

    def _insert_title(self, title):
        cursor = self.editor.textCursor()
        cursor.movePosition(QTextCursor.Left, QTextCursor.KeepAnchor, 2)
        if cursor.selectedText() == "[[":
            cursor.removeSelectedText()
        link = QTextCharFormat()
        link.setAnchor(True)
        link.setAnchorHref(links.SCHEME + quote(title))
        link.setForeground(QColor(self.theme.gold))
        link.setFontUnderline(True)
        cursor.insertText(title, link)
        cursor.insertText(" ", QTextCharFormat())
        self.editor.setTextCursor(cursor)
        self.editor.setFocus()

    def hideEvent(self, event):
        self.flush()
        super().hideEvent(event)
