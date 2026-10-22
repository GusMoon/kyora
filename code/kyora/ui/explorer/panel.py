"""Sección Archivos del panel de arriba (Directorio, 4.2 de kyoraBase.md), en tarjetas como la referencia:
- la ruta va en las migas de pan del panel (`self.pathbar`, que el panel coloca en su cabecera);
- a la izquierda, la tarjeta "Carpetas" con el árbol (los lugares están en la navegación del panel);
- en el centro, la tarjeta de la carpeta: ← → ↑, buscar, cuadrícula o lista y ⋮, y debajo los archivos
  (QFileSystemModel: asíncrono, con los iconos de Windows y al día con el disco);
- a la derecha, la tarjeta de vista previa (Espacio);
- abajo, el estado, la selección de varias carpetas y el progreso de las operaciones largas.

Las operaciones las hace el núcleo (kyora/directory/service.py) con acciones con nombre: `call` las ejecuta y
devuelve su resultado; copiar, mover, borrar y buscar avisan después con `on_event`.
"""
import os

from PySide6.QtCore import (
    QByteArray,
    QDir,
    QFileInfo,
    QItemSelectionModel,
    QMimeData,
    QSize,
    Qt,
    QTimer,
    QUrl,
)
from PySide6.QtGui import QGuiApplication, QKeySequence, QShortcut
from PySide6.QtWidgets import (
    QAbstractItemView,
    QApplication,
    QFileSystemModel,
    QHBoxLayout,
    QHeaderView,
    QLabel,
    QLineEdit,
    QListView,
    QListWidget,
    QListWidgetItem,
    QMenu,
    QProgressBar,
    QPushButton,
    QStackedWidget,
    QTreeView,
    QVBoxLayout,
    QWidget,
)

from kyora.directory.selection import MultiSelection
from kyora.ui import glyphs
from kyora.ui.explorer import dialogs, file_icons
from kyora.ui.explorer.navigation import HOME, FolderTree, PathBar
from kyora.ui.explorer.preview import GlyphButton, PreviewPane
from kyora.ui.hub.cards import Card
from kyora.ui.hub.nav import PlacesList

DROP_EFFECT = 'application/x-qt-windows-mime;value="Preferred DropEffect"'  # copiar (1) o cortar (2) en Windows
SEARCH_DELAY_MS = 300


def human_size(n):
    for unit in ("bytes", "KB", "MB", "GB", "TB"):
        if n < 1024 or unit == "TB":
            return f"{n:.0f} {unit}" if unit == "bytes" else f"{n:.1f} {unit}".replace(".", ",")
        n /= 1024
    return ""


def _plural(n, one, many):
    return f"{n} {one if n == 1 else many}"


PLACE_KEYS = {"H": "Carpeta personal", "E": "Escritorio", "O": "Documentos", "D": "Descargas", "I": "Imágenes"}


class FilesPage(QWidget):

    def __init__(self, theme, call):
        super().__init__()
        t = theme
        self.theme = theme
        self._call = call
        self.multi = MultiSelection()
        self.cwd, self.back, self.forward = "", [], []
        self._navigating = False
        self._query = ""
        self.icons = file_icons.shared()

        self.fs = QFileSystemModel(self)
        self.fs.setReadOnly(True)
        self.fs.setIconProvider(self.icons)  # los iconos propios de Kyora (carpeta de cristal y hoja)
        self.fs.setRootPath("")
        self.fs.directoryLoaded.connect(self._loaded)

        # ---------- cabecera ----------
        self.btn_back = GlyphButton(t, lambda p, b: glyphs.arrow(p, b, "left"), "Atrás")
        self.btn_forward = GlyphButton(t, lambda p, b: glyphs.arrow(p, b, "right"), "Adelante")
        self.btn_up = GlyphButton(t, lambda p, b: glyphs.arrow(p, b, "up"), "Carpeta de arriba (Retroceso)")
        self.btn_back.clicked.connect(self.go_back)
        self.btn_forward.clicked.connect(self.go_forward)
        self.btn_up.clicked.connect(self.go_up)
        self.pathbar = PathBar()
        self.pathbar.navigate.connect(self.go)
        self.pathbar.open_file.connect(self.open_path)
        self.search_edit = QLineEdit()
        self.search_edit.setPlaceholderText("Buscar en esta carpeta y sus subcarpetas…")
        self.search_edit.textChanged.connect(lambda _: self._search_timer.start(SEARCH_DELAY_MS))
        self.folder_title = QLabel("")
        self.folder_title.setObjectName("CardTitle")
        self.top = QStackedWidget()
        self.top.addWidget(self.folder_title)
        self.top.addWidget(self.search_edit)
        self.btn_search = GlyphButton(t, glyphs.magnifier, "Buscar (Ctrl+F)")
        self.btn_search.setCheckable(True)
        self.btn_search.toggled.connect(self.set_search)
        self.btn_view = GlyphButton(t, self._view_glyph, "Cuadrícula o lista")
        self.btn_view.clicked.connect(self.toggle_view)
        self.btn_menu = GlyphButton(t, glyphs.dots, "Más opciones")
        self.btn_menu.clicked.connect(self._main_menu)
        self.files_card = Card(t)
        self.files_card.title.hide()  # el título es el nombre de la carpeta, que cambia por la búsqueda
        head = self.files_card.header
        head.setSpacing(4)
        head.setContentsMargins(8, 0, 8, 0)
        head.takeAt(head.count() - 1)  # sin el hueco elástico de la tarjeta: lo pone la pila de título y búsqueda
        for w in (self.btn_back, self.btn_forward, self.btn_up):
            head.addWidget(w)
        head.addWidget(self.top, 1)
        for w in (self.btn_search, self.btn_view, self.btn_menu):
            head.addWidget(w)

        # ---------- centro ----------
        self.tree = FolderTree(t)
        self.tree.navigate.connect(self.go)
        self.places = PlacesList(t)
        self.places.place.connect(self.go)
        self.places.unpin.connect(self.unpin)
        folders = QLabel("Carpetas")
        folders.setObjectName("Dim")
        self.tree_card = Card(t, "Lugares")
        self.tree_card.setFixedWidth(t.explorer_sidebar)
        tree_layout = QVBoxLayout(self.tree_card.inner)
        tree_layout.setContentsMargins(6, 8, 6, 8)
        tree_layout.addWidget(self.places)
        tree_layout.addWidget(folders)
        tree_layout.addWidget(self.tree, 1)
        self.grid = QListView()
        self.grid.setViewMode(QListView.IconMode)
        self.grid.setIconSize(QSize(t.explorer_icon, t.explorer_icon))
        self.grid.setGridSize(QSize(t.explorer_icon + 70, t.explorer_icon + 56))
        self.grid.setWordWrap(True)
        self.grid.setResizeMode(QListView.Adjust)
        self.grid.setMovement(QListView.Static)
        self.grid.setUniformItemSizes(True)
        self.list = QTreeView()
        self.list.setRootIsDecorated(False)
        self.list.setItemsExpandable(False)
        self.list.setUniformRowHeights(True)
        self.list.setSortingEnabled(True)
        for view in (self.grid, self.list):
            view.setModel(self.fs)
            view.setSelectionMode(QAbstractItemView.ExtendedSelection)
            view.setDragEnabled(True)
            view.setDragDropMode(QAbstractItemView.DragOnly)  # arrastrar hacia otras apps; soltar aquí no
            view.setContextMenuPolicy(Qt.CustomContextMenu)
            view.customContextMenuRequested.connect(self._context_menu)
            view.activated.connect(lambda index: self.open_path(self.fs.filePath(index)))
        self.list.setSelectionModel(self.grid.selectionModel())  # la misma selección en las dos vistas
        self.list.sortByColumn(0, Qt.AscendingOrder)
        self.list.header().setSectionResizeMode(0, QHeaderView.Stretch)
        self.list.header().setStretchLastSection(False)
        self.grid.selectionModel().selectionChanged.connect(self._selection_changed)
        self.grid.selectionModel().currentChanged.connect(lambda *_: self._follow_preview())
        self.results = QListWidget()
        self.results.setSelectionMode(QAbstractItemView.ExtendedSelection)
        self.results.setContextMenuPolicy(Qt.CustomContextMenu)
        self.results.customContextMenuRequested.connect(self._context_menu)
        self.results.itemActivated.connect(lambda item: self.open_path(item.data(Qt.UserRole)))
        self.results.itemSelectionChanged.connect(self._selection_changed)
        self.results.currentItemChanged.connect(lambda *_: self._follow_preview())
        self.views = QStackedWidget()
        for w in (self.grid, self.list, self.results):
            self.views.addWidget(w)
        views_layout = QVBoxLayout(self.files_card.inner)
        views_layout.setContentsMargins(8, 8, 8, 8)
        views_layout.addWidget(self.views)
        self.preview = PreviewPane(t)
        self.preview_card = Card(t, "Vista previa")
        self.preview_card.setMinimumWidth(t.explorer_preview)
        preview_layout = QVBoxLayout(self.preview_card.inner)
        preview_layout.setContentsMargins(4, 4, 4, 4)
        preview_layout.addWidget(self.preview)
        self.preview_card.hide()
        split = QHBoxLayout()  # árbol (ancho fijo) · archivos (lo que sobra) · vista previa (cuando se abre)
        split.setSpacing(10)
        split.addWidget(self.tree_card)
        split.addWidget(self.files_card, 1)
        split.addWidget(self.preview_card)

        # ---------- estado ----------
        self.status = QLabel("")
        self.status.setObjectName("Dim")
        self.chip = QPushButton("")
        self.chip.setObjectName("Chip")
        self.chip.setCursor(Qt.PointingHandCursor)
        self.chip.clicked.connect(self._chip_menu)
        self.chip.hide()
        self.progress = QProgressBar()
        self.progress.setTextVisible(False)
        self.progress.setFixedWidth(180)
        self.progress.hide()
        self.btn_cancel = QPushButton("Cancelar")
        self.btn_cancel.clicked.connect(lambda: self._do("directory.cancel"))
        self.btn_cancel.hide()
        foot = QHBoxLayout()
        foot.addWidget(self.status, 1)
        foot.addWidget(self.chip)
        foot.addWidget(self.progress)
        foot.addWidget(self.btn_cancel)

        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(8)
        layout.addLayout(head)
        layout.addLayout(split, 1)
        layout.addLayout(foot)

        self._search_timer = QTimer(self)
        self._search_timer.setSingleShot(True)
        self._search_timer.timeout.connect(self._run_search)
        self._shortcuts()
        prefs = self._do("directory.prefs") or {"show_hidden": False, "view": "grid"}
        self.show_hidden, self.view = prefs["show_hidden"], prefs["view"]
        self._apply_filter()
        self.views.setCurrentWidget(self.list if self.view == "list" else self.grid)

    # ---------- núcleo ----------

    def _do(self, action, **payload):
        """Ejecuta una acción del núcleo; si falla lo dice en la barra de estado y devuelve None."""
        result = self._call(action, **payload)
        if not result["ok"]:
            self.say(result["error"]["message"])
            return None
        return result["data"] if result["data"] is not None else True

    def say(self, text):
        self.status.setText(text)

    # ---------- cuando el panel se abre o se cierra ----------

    def activate(self):
        places = self._do("directory.places")
        if places:
            self.places.set_places([tuple(x) for x in places["places"]], places["pinned"])
        if not self.cwd or not os.path.isdir(self.cwd):
            self.go(HOME, remember=False)

    def focus_view(self):
        self.views.currentWidget().setFocus()

    def deactivate(self):
        self.preview.stop()
        self._do("directory.stop_search")

    def escape(self):
        """Esc va cerrando de dentro afuera: la ruta escrita, la vista previa y la búsqueda. False si no quedaba
        nada (entonces el panel se cierra)."""
        if self.pathbar.editing():
            self.pathbar.show_crumbs()
        elif self.preview_card.isVisible():
            self.toggle_preview()
        elif self.btn_search.isChecked():
            self.btn_search.setChecked(False)
        else:
            return False
        return True

    # ---------- navegar ----------

    def go(self, path, remember=True):
        path = os.path.abspath(path)
        if not os.path.isdir(path):
            self.say(f"No existe la carpeta {path}")
            return
        if remember and self.cwd and os.path.normcase(path) != os.path.normcase(self.cwd):
            self.back.append(self.cwd)
            self.forward.clear()
        self._navigating = True  # al cambiar de carpeta la vista se vacía: no es que el usuario deseleccione
        self.cwd = path
        root = self.fs.setRootPath(path)
        self.grid.setRootIndex(root)
        self.list.setRootIndex(root)
        self.grid.selectionModel().clearSelection()
        self._navigating = False
        if self.btn_search.isChecked():
            self.btn_search.setChecked(False)
        self.pathbar.set_path(path)
        self.tree.follow(path)
        self.folder_title.setText(os.path.basename(path.rstrip("\\/")) or path)
        self.btn_back.setEnabled(bool(self.back))
        self.btn_forward.setEnabled(bool(self.forward))
        self.btn_up.setEnabled(os.path.dirname(path) != path)
        self._update_status()
        self.views.currentWidget().setFocus()

    def go_back(self):
        if self.back:
            self.forward.append(self.cwd)
            self.go(self.back.pop(), remember=False)

    def go_forward(self):
        if self.forward:
            self.back.append(self.cwd)
            self.go(self.forward.pop(), remember=False)

    def go_up(self):
        parent = os.path.dirname(self.cwd)
        if parent and parent != self.cwd:
            previous = self.cwd
            self.go(parent)
            self.select([previous])

    def open_path(self, path):
        if os.path.isdir(path):
            self.go(path)
        elif self._do("directory.open", path=path):
            self.say(f"Abriendo {os.path.basename(path)}…")

    def _loaded(self, path):
        if os.path.normcase(os.path.abspath(path)) == os.path.normcase(self.cwd):
            self.fs.sort(0, Qt.AscendingOrder)
            self._update_status()

    # ---------- vistas, filtro y búsqueda ----------

    def _view_glyph(self, p, box):
        (glyphs.rows if self.view == "grid" else glyphs.grid)(p, box)

    def toggle_view(self):
        self.view = "list" if self.view == "grid" else "grid"
        self._do("directory.set_prefs", view=self.view)
        if not self.btn_search.isChecked():
            self.views.setCurrentWidget(self.list if self.view == "list" else self.grid)
        self.btn_view.update()

    def toggle_hidden(self):
        self.show_hidden = not self.show_hidden
        self._do("directory.set_prefs", show_hidden=self.show_hidden)
        self._apply_filter()
        self.say("Se muestran los archivos ocultos" if self.show_hidden else "Archivos ocultos escondidos")

    def _apply_filter(self):
        f = QDir.AllEntries | QDir.NoDotAndDotDot | QDir.AllDirs
        if self.show_hidden:
            f |= QDir.Hidden | QDir.System
        self.fs.setFilter(f)

    def set_search(self, on):
        if on:
            self.top.setCurrentWidget(self.search_edit)
            self.search_edit.setFocus()
            self.search_edit.selectAll()
            if self.search_edit.text().strip():
                self._run_search()
        else:
            self._do("directory.stop_search")
            self._query = ""
            self.top.setCurrentWidget(self.folder_title)
            self.views.setCurrentWidget(self.list if self.view == "list" else self.grid)
            self._update_status()
            self.views.currentWidget().setFocus()

    def _run_search(self):
        query = self.search_edit.text().strip()
        self.results.clear()
        self._query = query
        if not query:
            self._do("directory.stop_search")
            self.views.setCurrentWidget(self.list if self.view == "list" else self.grid)
            return
        self.views.setCurrentWidget(self.results)
        self.say(f"Buscando «{query}»…")
        self._do("directory.search", root=self.cwd, query=query)

    def _add_results(self, paths):
        for path in paths:
            item = QListWidgetItem(self.icons.icon(QFileInfo(path)), os.path.basename(path))
            item.setData(Qt.UserRole, path)
            item.setToolTip(path)
            self.results.addItem(item)

    # ---------- selección ----------

    def selected_here(self):
        """Rutas elegidas en la vista que se ve ahora."""
        if self.views.currentWidget() is self.results:
            return [item.data(Qt.UserRole) for item in self.results.selectedItems()]
        rows = {i.row(): i for i in self.grid.selectionModel().selectedIndexes() if i.column() == 0}
        return [self.fs.filePath(i) for _, i in sorted(rows.items())]

    def targets(self):
        """Sobre qué actúan copiar, cortar, borrar…: la selección (de una o de varias carpetas)."""
        return self.multi.paths()

    def _selection_changed(self, *_):
        if self._navigating:
            return
        paths = self.selected_here()
        ctrl = QApplication.keyboardModifiers() & Qt.ControlModifier
        if ctrl and self.views.currentWidget() is not self.results:
            self.multi.set_folder(self.cwd, paths)  # Ctrl: se suma a lo elegido en otras carpetas
        else:
            self.multi.replace(paths)
        self._update_status()

    def select(self, paths):
        """Marca `paths` en la carpeta actual (por ejemplo lo recién pegado o creado)."""
        model = self.grid.selectionModel()
        first = True
        for path in paths:
            index = self.fs.index(path)
            if index.isValid() and os.path.normcase(os.path.dirname(path)) == os.path.normcase(self.cwd):
                flags = QItemSelectionModel.Select | QItemSelectionModel.Rows
                if first:
                    flags |= QItemSelectionModel.Clear
                    model.setCurrentIndex(index, QItemSelectionModel.NoUpdate)
                    self.views.currentWidget().scrollTo(index)
                model.select(index, flags)
                first = False

    def _update_status(self):
        if self.views.currentWidget() is self.results:
            text = f"{_plural(self.results.count(), 'resultado', 'resultados')} de «{self._query}»"
        else:
            text = _plural(self.fs.rowCount(self.grid.rootIndex()), "elemento", "elementos")
        here = self.selected_here()
        if here:
            size = sum(os.path.getsize(p) for p in here if os.path.isfile(p))
            text += f" · {_plural(len(here), 'seleccionado', 'seleccionados')}"
            if size:
                text += f" ({human_size(size)})"
        self.say(text)
        summary = self.multi.summary()
        self.chip.setText(summary)
        self.chip.setVisible(bool(summary))

    def _chip_menu(self):
        menu = QMenu(self)
        for path in self.multi.paths()[:15]:
            menu.addAction(path).setEnabled(False)
        if len(self.multi) > 15:
            menu.addAction(f"… y {len(self.multi) - 15} más").setEnabled(False)
        menu.addSeparator()
        menu.addAction("Vaciar la selección", self._clear_selection)
        menu.exec(self.chip.mapToGlobal(self.chip.rect().topLeft()))

    def _clear_selection(self):
        self.multi.clear()
        self.grid.selectionModel().clearSelection()
        self.results.clearSelection()
        self._update_status()

    # ---------- vista previa ----------

    def toggle_preview(self):
        if self.preview_card.isVisible():
            self.preview.stop()
            self.preview_card.hide()
        else:
            self.preview_card.show()
            self._follow_preview()

    def _current_path(self):
        if self.views.currentWidget() is self.results:
            item = self.results.currentItem()
            return item.data(Qt.UserRole) if item else None
        index = self.grid.selectionModel().currentIndex()
        return self.fs.filePath(index) if index.isValid() else None

    def _follow_preview(self):
        if not self.preview_card.isVisible():
            return
        path = self._current_path()
        if path and path != self.preview.path:
            info = human_size(os.path.getsize(path)) if os.path.isfile(path) else ""
            self.preview.show_path(path, info)

    # ---------- operaciones ----------

    def copy(self, cut=False):
        paths = self.targets()
        if not paths:
            return self.say("No hay nada seleccionado")
        data = QMimeData()
        data.setUrls([QUrl.fromLocalFile(p) for p in paths])
        data.setData(DROP_EFFECT, QByteArray((2 if cut else 1).to_bytes(4, "little")))  # el Explorador lo entiende
        QGuiApplication.clipboard().setMimeData(data)
        self.say(f"{_plural(len(paths), 'elemento', 'elementos')} {'para mover' if cut else 'copiados'}: pega con Ctrl+V")

    def paste(self):
        data = QGuiApplication.clipboard().mimeData()
        sources = [u.toLocalFile() for u in data.urls() if u.isLocalFile()] if data and data.hasUrls() else []
        if not sources:
            return self.say("No hay archivos en el portapapeles")
        effect = bytes(data.data(DROP_EFFECT))
        move = len(effect) >= 4 and int.from_bytes(effect[:4], "little") & 2 == 2
        if self._do("directory.transfer", sources=sources, dest=self.cwd, move=move) and move:
            QGuiApplication.clipboard().clear()  # lo cortado solo se pega una vez

    def duplicate(self):
        if self.targets():
            self._do("directory.duplicate", paths=self.targets())

    def rename(self):
        paths = self.targets()
        if len(paths) != 1:
            return self.say("Elige un solo elemento para renombrarlo")
        name = dialogs.ask_name(self, "Renombrar", os.path.basename(paths[0]))
        if name and name != os.path.basename(paths[0]):
            new = self._do("directory.rename", path=paths[0], name=name)
            if new:
                QTimer.singleShot(150, lambda: self.select([new]))

    def recycle(self):
        paths = self.targets()
        if not paths:
            return self.say("No hay nada seleccionado")
        what = f"«{os.path.basename(paths[0])}»" if len(paths) == 1 else _plural(len(paths), "elemento", "elementos")
        if dialogs.confirm(self, "Mover a la Papelera", f"¿Mover {what} a la Papelera de Windows?", "Mover a la Papelera"):
            self._do("directory.recycle", paths=paths)

    def create(self, kind):
        action, label = ("directory.create_folder", "Nueva carpeta") if kind == "folder" else ("directory.create_file", "Nuevo archivo")
        path = self._do(action, parent=self.cwd)
        if not path:
            return
        name = dialogs.ask_name(self, label, os.path.basename(path))
        if name and name != os.path.basename(path):
            path = self._do("directory.rename", path=path, name=name) or path
        QTimer.singleShot(150, lambda: self.select([path]))

    def undo(self):
        message = self._do("directory.undo")
        if message:
            self.say(message)

    def pin(self, path=None):
        places = self._do("directory.pin", path=path or self.cwd)
        if places:
            self.places.set_places([tuple(x) for x in places["places"]], places["pinned"])
            self.say("Carpeta anclada en el lateral")

    def unpin(self, path):
        places = self._do("directory.unpin", path=path)
        if places:
            self.places.set_places([tuple(x) for x in places["places"]], places["pinned"])

    def _go_place(self, name):
        """Ctrl+Mayús+H/E/O/D/I: a la carpeta personal, el escritorio, documentos, descargas o imágenes."""
        path = self.places.by_name.get(name)
        if path:
            self.go(path)

    def copy_path(self):
        paths = self.targets() or [self.cwd]
        QGuiApplication.clipboard().setText(chr(10).join(paths))
        self.say("Ruta copiada")

    # ---------- avisos del núcleo ----------

    def on_event(self, e):
        kind = e["kind"]
        if kind == "progress":
            self.progress.show()
            self.btn_cancel.show()
            self.progress.setRange(0, max(e["total"], 1))
            self.progress.setValue(min(e["done"], e["total"]))
            self.say(f"{human_size(e['done'])} de {human_size(e['total'])} · {os.path.basename(e['current'])}")
        elif kind == "conflict":
            choice, every = dialogs.ask_conflict(self, e["name"])
            self._do("directory.resolve", choice=choice, every=every)
        elif kind in ("done", "error"):
            self.progress.hide()
            self.btn_cancel.hide()
            self.say(e["message"])
            if e.get("paths"):
                QTimer.singleShot(300, lambda: self.select(e["paths"]))
        elif kind == "search" and e["query"] == self._query:
            self._add_results(e["paths"])
            self._update_status()
        elif kind == "search_done" and e["query"] == self._query:
            self._update_status()
            if not e["count"]:
                self.say(f"No hay nada que se llame «{self._query}» aquí")

    # ---------- menús y teclado ----------

    def _context_menu(self, pos):
        view = self.sender()
        on_item = view.indexAt(pos).isValid() if view is not self.results else view.itemAt(pos) is not None
        menu = QMenu(self)
        if on_item and self.targets():
            single = len(self.targets()) == 1
            path = self.targets()[0]
            menu.addAction("Abrir", lambda: self.open_path(path)).setEnabled(single)
            menu.addAction("Abrir con…", lambda: self._do("directory.open_with", path=path)).setEnabled(
                single and os.path.isfile(path))
            if view is self.results:
                menu.addAction("Abrir la carpeta que lo contiene", lambda: self._reveal(path))
            menu.addAction("Vista previa", self.toggle_preview)
            menu.addSeparator()
            menu.addAction("Cortar", lambda: self.copy(cut=True))
            menu.addAction("Copiar", self.copy)
            menu.addAction("Duplicar", self.duplicate)
            menu.addAction("Renombrar…", self.rename).setEnabled(single)
            menu.addAction("Mover a la Papelera", self.recycle)
            menu.addSeparator()
            menu.addAction("Copiar ruta", self.copy_path)
            if single and os.path.isdir(path):
                menu.addAction("Anclar en el lateral", lambda: self.pin(path))
        else:
            menu.addAction("Pegar", self.paste)
            menu.addAction("Nueva carpeta", lambda: self.create("folder"))
            menu.addAction("Nuevo archivo", lambda: self.create("file"))
            menu.addSeparator()
            menu.addAction("Anclar esta carpeta", self.pin)
        menu.exec(view.viewport().mapToGlobal(pos))

    def _reveal(self, path):
        self.go(os.path.dirname(path))
        QTimer.singleShot(300, lambda: self.select([path]))

    def _main_menu(self):
        menu = QMenu(self)
        hidden = menu.addAction("Mostrar archivos ocultos", self.toggle_hidden)
        hidden.setCheckable(True)
        hidden.setChecked(self.show_hidden)
        hidden.setShortcut(QKeySequence("Ctrl+H"))
        menu.addAction("Nueva carpeta", lambda: self.create("folder")).setShortcut(QKeySequence("Ctrl+Shift+N"))
        menu.addAction("Nuevo archivo", lambda: self.create("file"))
        menu.addAction("Pegar", self.paste).setShortcut(QKeySequence("Ctrl+V"))
        menu.addAction("Deshacer", self.undo).setShortcut(QKeySequence("Ctrl+Z"))
        menu.addSeparator()
        menu.addAction("Anclar esta carpeta", self.pin)
        menu.addAction("Copiar la ruta de esta carpeta", lambda: QGuiApplication.clipboard().setText(self.cwd))
        menu.exec(self.btn_menu.mapToGlobal(self.btn_menu.rect().bottomLeft()))

    def _shortcuts(self):
        keys = {
            "Ctrl+C": self.copy, "Ctrl+X": lambda: self.copy(cut=True), "Ctrl+V": self.paste,
            "Ctrl+D": self.duplicate, "F2": self.rename, "Delete": self.recycle, "Ctrl+Z": self.undo,
            "Ctrl+H": self.toggle_hidden, "Ctrl+L": self.pathbar.start_edit,
            "Ctrl+F": lambda: self.btn_search.setChecked(True), "Ctrl+Shift+N": lambda: self.create("folder"),
            "Backspace": self.go_up, "Space": self.toggle_preview, "F5": lambda: self.go(self.cwd, remember=False),
        }
        for letter, name in PLACE_KEYS.items():
            keys[f"Ctrl+Shift+{letter}"] = lambda n=name: self._go_place(n)
        for key, fn in keys.items():
            QShortcut(QKeySequence(key), self, fn, context=Qt.WidgetWithChildrenShortcut)
