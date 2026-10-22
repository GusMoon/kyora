"""Ruta y árbol de carpetas de la sección Archivos.

- PathBar: la ruta como migas de pan ("Carpeta personal / Documents / Kyora", la última en negrita); un clic en una va
  a esa carpeta. Ctrl+L o un clic en el hueco la cambia por un campo para escribirla, con autocompletado.
- FolderTree: el árbol de carpetas, que sigue a la carpeta actual.
"""
import os

from PySide6.QtCore import QDir, QSize, Qt, Signal
from PySide6.QtWidgets import (
    QCompleter,
    QFileSystemModel,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QPushButton,
    QStackedWidget,
    QTreeView,
    QWidget,
)

from kyora.ui.explorer import file_icons

HOME =os.path.expanduser("~")


def crumbs(path):
    """[(texto, ruta)] de cada tramo. Lo que cuelga de la carpeta personal empieza en "Carpeta personal"."""
    path = os.path.normpath(path)
    if os.path.normcase(path).startswith(os.path.normcase(HOME)):
        parts = [("Carpeta personal", HOME)]
        rest = path[len(HOME):].strip("\\/")
        base = HOME
    else:
        drive, rest = os.path.splitdrive(path)
        parts = [(drive or path, drive + os.sep)]
        rest = rest.strip("\\/")
        base = drive + os.sep
    for piece in [p for p in rest.split(os.sep) if p]:
        base = os.path.join(base, piece)
        parts.append((piece, base))
    return parts


class PathBar(QWidget):
    navigate = Signal(str)  # una carpeta a la que ir
    open_file = Signal(str)  # se escribió la ruta de un archivo

    MAX_CRUMBS = 3  # con más tramos, los primeros se resumen en "…" (la mini barra está en el centro)
    CRUMB_WIDTH = 130  # un tramo más largo se recorta con "…"

    def __init__(self):
        super().__init__()
        self.path = ""
        self.box = QWidget()
        self.box.setObjectName("PathBox")
        self.box.setAttribute(Qt.WA_StyledBackground)
        self.row = QHBoxLayout(self.box)
        self.row.setContentsMargins(4, 2, 4, 2)
        self.row.setSpacing(0)
        self.edit = QLineEdit()
        self.edit.setPlaceholderText("Escribe una ruta y pulsa Enter")
        completer_model = QFileSystemModel(self)
        completer_model.setRootPath("")
        completer_model.setFilter(QDir.AllDirs | QDir.Drives | QDir.NoDotAndDotDot)
        self.edit.setCompleter(QCompleter(completer_model, self))
        self.edit.returnPressed.connect(self._typed)
        self.stack = QStackedWidget()
        self.stack.addWidget(self.box)
        self.stack.addWidget(self.edit)
        layout = QHBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.addWidget(self.stack)

    def set_path(self, path):
        self.path = path
        while self.row.count():
            item = self.row.takeAt(0)
            if item.widget():
                item.widget().deleteLater()
        parts = crumbs(path)
        if len(parts) > self.MAX_CRUMBS:
            parts = parts[:1] + [("…", parts[-self.MAX_CRUMBS + 1][1])] + parts[-self.MAX_CRUMBS + 2:]
        for i, (text, target) in enumerate(parts):
            if i:
                sep = QLabel("/")
                sep.setObjectName("Dim")
                self.row.addWidget(sep)
            b = QPushButton()
            b.setObjectName("Crumb")
            b.setText(b.fontMetrics().elidedText(text, Qt.ElideMiddle, self.CRUMB_WIDTH))
            b.setToolTip(target)
            b.setProperty("last", i == len(parts) - 1)
            b.setCursor(Qt.PointingHandCursor)
            b.clicked.connect(lambda _=False, p=target: self.navigate.emit(p))
            self.row.addWidget(b)
        self.row.addStretch(1)
        self.show_crumbs()

    def mousePressEvent(self, event):
        self.start_edit()  # clic en el hueco de la ruta: escribirla

    def start_edit(self):
        self.edit.setText(self.path)
        self.stack.setCurrentWidget(self.edit)
        self.edit.setFocus()
        self.edit.selectAll()

    def show_crumbs(self):
        self.stack.setCurrentWidget(self.box)

    def editing(self):
        return self.stack.currentWidget() is self.edit

    def _typed(self):
        path = os.path.expandvars(os.path.expanduser(self.edit.text().strip().strip('"')))
        if os.path.isdir(path):
            self.navigate.emit(os.path.abspath(path))
        elif os.path.isfile(path):
            self.open_file.emit(os.path.abspath(path))
        else:
            self.edit.selectAll()  # no existe: se queda para corregirla


class FolderTree(QTreeView):
    """El árbol de carpetas (desde las unidades), que sigue a la carpeta actual."""

    navigate = Signal(str)

    def __init__(self, theme):
        super().__init__()
        self.icons = file_icons.shared()
        self.dirs = QFileSystemModel(self)
        self.dirs.setRootPath("")
        self.dirs.setIconProvider(self.icons)
        self.dirs.setFilter(QDir.AllDirs | QDir.Drives | QDir.NoDotAndDotDot)
        self.setModel(self.dirs)
        for column in range(1, self.dirs.columnCount()):
            self.hideColumn(column)
        self.setHeaderHidden(True)
        self.setAnimated(False)
        self.setIndentation(14)
        self.setIconSize(QSize(20, 20))
        self.setFocusPolicy(Qt.NoFocus)
        self.setHorizontalScrollBarPolicy(Qt.ScrollBarAlwaysOff)  # la tarjeta es estrecha: los nombres se recortan
        self.setTextElideMode(Qt.ElideRight)
        self.clicked.connect(lambda index: self.navigate.emit(self.dirs.filePath(index)))

    def follow(self, path):
        """Despliega el árbol hasta `path` y lo marca."""
        index = self.dirs.index(path)
        if index.isValid():
            self.setCurrentIndex(index)
            self.scrollTo(index)
            self.horizontalScrollBar().setValue(0)  # seguir la carpeta sin desplazar el árbol hacia la derecha
