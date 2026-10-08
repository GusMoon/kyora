from PySide6.QtWidgets import QWidget, QFrame, QVBoxLayout, QHBoxLayout, QLabel, QPushButton, QTreeView, QListView, QAbstractItemView, QFileSystemModel, QLineEdit, QFileIconProvider, QHeaderView, QSplitter, QStyledItemDelegate, QStyle, QStyleFactory, QMenu, QDialog
from PySide6.QtCore import QSortFilterProxyModel
from core.matrix.ecosystems.motherBoard.simple_dialogs import SciFiInputDialog, SciFiConfirmDialog, SciFiContextMenu, SciFiFileEditDialog
from core.ecosystems.explorer.file_system_ecosystem import FileSystemEcosystem
from PySide6.QtCore import Qt, QModelIndex, QFileInfo, QDir, QPoint, Signal, QStandardPaths, QSize, QRect
from PySide6.QtGui import QIcon, QPixmap, QPainter, QColor, QPen, QStandardItemModel, QStandardItem, QShortcut, QKeySequence, QPainterPath, QFont
import os
import shutil

import math
from core.matrix.ecosystems.motherBoard.styles import get_minimal_scrollbar_style
from core.matrix.ecosystems.explorer.components.sidebar_delegate import SidebarDelegate
from core.matrix.ecosystems.explorer.components.explorer_delegate import ExplorerDelegate

class FolderProxyModel(QSortFilterProxyModel):
    def filterAcceptsRow(self, source_row, source_parent):
        model = self.sourceModel()
        if not model: return True
        idx = model.index(source_row, 0, source_parent)
        return model.isDir(idx)

class FileProxyModel(QSortFilterProxyModel):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.current_root_path = ""

    def filterAcceptsRow(self, source_row, source_parent):
        model = self.sourceModel()
        if not model: return True
        idx = model.index(source_row, 0, source_parent)
        
        if model.isDir(idx):
            import os
            parent_path = model.filePath(source_parent)
            
            if self.current_root_path == "":
                return False
                
            if parent_path and self.current_root_path:
                if os.path.normpath(parent_path).lower() == os.path.normpath(self.current_root_path).lower():
                    return False
            return True
        return True

class NoBranchTreeView(QTreeView):
    def drawBranches(self, painter, rect, index):
        pass


class SciFiIconProvider(QFileIconProvider):
    def __init__(self):
        super().__init__()
        self.folder_icon = self._create_icon(True)
        self.file_icon = self._create_icon(False)
        self.back_icon = self._create_back_icon()
        
    def _create_back_icon(self):
        pixmap = QPixmap(16, 16)
        pixmap.fill(Qt.transparent)
        painter = QPainter(pixmap)
        painter.setRenderHint(QPainter.Antialiasing)
        painter.setPen(QPen(QColor("#0099FF"), 2, Qt.SolidLine, Qt.RoundCap, Qt.RoundJoin))
        painter.drawLine(12, 8, 4, 8)
        painter.drawLine(4, 8, 8, 4)
        painter.drawLine(4, 8, 8, 12)
        painter.end()
        return QIcon(pixmap)
        
    def _create_icon(self, is_dir):
        pixmap = QPixmap(16, 16)
        pixmap.fill(Qt.transparent)
        painter = QPainter(pixmap)
        painter.setRenderHint(QPainter.Antialiasing)
        if is_dir:
            painter.setPen(Qt.NoPen)
            painter.setBrush(QColor("#0099FF")) 
            painter.drawRect(1, 2, 6, 3)
            painter.drawRoundedRect(1, 5, 14, 9, 1, 1)
        else:
            painter.setPen(Qt.NoPen)
            painter.setBrush(QColor("#A0C0FF"))
            painter.drawRect(3, 2, 10, 12)
            painter.setBrush(QColor("#FFB84D"))
            painter.drawPolygon([QPoint(13,2), QPoint(13,5), QPoint(10,2)])
        painter.end()
        return QIcon(pixmap)

    def icon(self, info_or_type):
        if isinstance(info_or_type, QFileInfo):
            return self.folder_icon if info_or_type.isDir() else self.file_icon
        return self.folder_icon if info_or_type == QFileIconProvider.Folder else self.file_icon


class ExplorerPanel(QWidget):
    
    file_opened = Signal(str)
    
    def __init__(self, parent=None):
        super().__init__(parent)
        self.resize(750, 600)
        self.setStyleSheet("background-color: transparent;")
        
        self.fs_ecosystem = FileSystemEcosystem()
        
        self.body_layout = QVBoxLayout(self)
        self.body_layout.setContentsMargins(0, 0, 0, 0)
        self.body_layout.setSpacing(5)
        
        self.icon_provider = SciFiIconProvider()
        
        # --- BARRA DE RUTA (TABS) ---
        from core.matrix.ecosystems.explorer.components.path_view import PathView
        self.path_view = PathView()
        self.path_view.path_clicked.connect(self.go_to_path)
        self.body_layout.addWidget(self.path_view)
        
        # --- SPLITTER ---
        self.splitter = QSplitter(Qt.Horizontal)
        self.splitter.setStyleSheet("QSplitter::handle { background-color: transparent; width: 0px; }")
        
        tree_style = get_minimal_scrollbar_style() + """
            QTreeView { background-color: transparent; border: none; outline: none; }
            QTreeView::item { background: transparent; border: none; outline: none; }
            QTreeView::item:hover { background: transparent; border: none; outline: none; }
            QTreeView::item:selected { background: transparent; border: none; outline: none; }
            QTreeView:focus { outline: none; }
            QTreeView::item:focus { outline: none; }
            QTreeView::branch { width: 0px; border-image: none; image: none; }
            QTreeView::drop-indicator { background: transparent; image: none; border: none; }
            QHeaderView::section { background-color: transparent; color: #0099FF; border: none; padding: 4px; font-weight: bold; }
        """
        
        # --- SIDEBAR ---
        self.sidebar = NoBranchTreeView()
        self.sidebar.setStyle(QStyleFactory.create("windows"))
        self.sidebar.setStyleSheet(tree_style)
        self.sidebar.setRootIsDecorated(False)
        self.sidebar.setHeaderHidden(True)
        self.sidebar.setItemDelegate(SidebarDelegate(show_arrow=False, enable_3d=False))
        
        self.qa_model = QStandardItemModel()
        self.sidebar.setModel(self.qa_model)
        self.sidebar.clicked.connect(self.on_sidebar_clicked)
        
        # --- MODELOS ---
        self.fs_model = QFileSystemModel()
        self.fs_model.setRootPath("")
        self.fs_model.setIconProvider(self.icon_provider)
        
        self.folder_proxy = FolderProxyModel()
        self.folder_proxy.setSourceModel(self.fs_model)
        
        self.file_proxy = FileProxyModel()
        self.file_proxy.setSourceModel(self.fs_model)

        # --- VISTAS ---
        list_style = get_minimal_scrollbar_style() + """
            QListView { background-color: transparent; border: none; outline: none; }
            QListView::item { background: transparent; border: none; outline: none; }
            QListView::item:hover { background: transparent; border: none; }
            QListView::item:selected { background: transparent; border: none; }
            QListView:focus { outline: none; }
        """
        
        self.folder_view = QListView()
        self.folder_view.setStyle(QStyleFactory.create("windows"))
        self.folder_view.setStyleSheet(list_style)
        self.folder_view.setViewMode(QListView.ListMode)
        self.folder_view.setFlow(QListView.LeftToRight)
        self.folder_view.setWrapping(True)
        self.folder_view.setResizeMode(QListView.Adjust)
        self.folder_view.setMovement(QListView.Static)
        self.folder_view.setUniformItemSizes(False)
        self.folder_view.setSpacing(4)
        self.folder_view.setMouseTracking(True)
        self.folder_view.setItemDelegate(ExplorerDelegate(view=self.folder_view))
        self.folder_view.setModel(self.folder_proxy)
        self.folder_view.setHorizontalScrollBarPolicy(Qt.ScrollBarAlwaysOff)
        self.folder_view.setVerticalScrollMode(QAbstractItemView.ScrollPerPixel)
        self.folder_view.setSelectionMode(QAbstractItemView.ExtendedSelection)
        self.folder_view.setSelectionBehavior(QAbstractItemView.SelectRows)
        
        self.file_view = QListView()
        self.file_view.setStyle(QStyleFactory.create("windows"))
        self.file_view.setStyleSheet(list_style)
        self.file_view.setViewMode(QListView.ListMode)
        self.file_view.setFlow(QListView.TopToBottom)
        self.file_view.setWrapping(False)
        self.file_view.setResizeMode(QListView.Adjust)
        self.file_view.setMovement(QListView.Static)
        self.file_view.setUniformItemSizes(False)
        self.file_view.setSpacing(6)
        self.file_view.setMouseTracking(True)
        self.file_view.setItemDelegate(ExplorerDelegate(view=self.file_view))
        self.file_view.setModel(self.file_proxy)
        self.file_view.setHorizontalScrollBarPolicy(Qt.ScrollBarAlwaysOff)
        self.file_view.setVerticalScrollMode(QAbstractItemView.ScrollPerPixel)
        self.file_view.setSelectionMode(QAbstractItemView.ExtendedSelection)
        self.file_view.setSelectionBehavior(QAbstractItemView.SelectRows)
        
        self.sidebar.setVerticalScrollMode(QTreeView.ScrollPerPixel)
        self.sidebar.setDropIndicatorShown(False)
        
        # Unir vistas en un splitter
        self.main_split = QSplitter(Qt.Horizontal)
        self.main_split.setStyleSheet("QSplitter::handle { background-color: transparent; width: 0px; }")
        self.main_split.addWidget(self.folder_view)
        self.main_split.addWidget(self.file_view)
        self.main_split.setSizes([400, 400])
        
        self.clipboard_paths = []
        self.clipboard_op = None
        
        QShortcut(QKeySequence("Ctrl+C"), self.folder_view, self._do_copy)
        QShortcut(QKeySequence("Ctrl+X"), self.folder_view, self._do_cut)
        QShortcut(QKeySequence("Ctrl+V"), self.folder_view, self._do_paste)
        QShortcut(QKeySequence("Ctrl+D"), self.folder_view, self._do_delete_selected)
        QShortcut(QKeySequence("Ctrl+C"), self.file_view, self._do_copy)
        QShortcut(QKeySequence("Ctrl+X"), self.file_view, self._do_cut)
        QShortcut(QKeySequence("Ctrl+V"), self.file_view, self._do_paste)
        QShortcut(QKeySequence("Ctrl+D"), self.file_view, self._do_delete_selected)
        
        self.folder_view.clicked.connect(self.on_tree_clicked)
        self.folder_view.doubleClicked.connect(self.on_tree_double_clicked)
        self.folder_view.setContextMenuPolicy(Qt.CustomContextMenu)
        self.folder_view.customContextMenuRequested.connect(lambda pos: self.show_context_menu(pos, self.folder_view))
        
        self.file_view.clicked.connect(self.on_tree_clicked)
        self.file_view.doubleClicked.connect(self.on_tree_double_clicked)
        self.file_view.setContextMenuPolicy(Qt.CustomContextMenu)
        self.file_view.customContextMenuRequested.connect(lambda pos: self.show_context_menu(pos, self.file_view))
        
        self.sidebar.setFixedWidth(200)
        self.splitter.addWidget(self.sidebar)
        self.splitter.addWidget(self.main_split)
        self.splitter.setStretchFactor(0, 0)
        self.splitter.setStretchFactor(1, 1)
        self.splitter.setSizes([200, 10000])
        
        self.body_layout.addWidget(self.splitter)
        
        self.populate_sidebar()
        self.go_to_path(QStandardPaths.writableLocation(QStandardPaths.DocumentsLocation))

    def populate_sidebar(self):
        def add_qa(name, path):
            item = QStandardItem(name)
            item.setData(path, Qt.UserRole)
            item.setIcon(self.icon_provider.folder_icon)
            self.qa_model.appendRow(item)
            
        add_qa("Escritorio", QStandardPaths.writableLocation(QStandardPaths.DesktopLocation))
        add_qa("Descargas", QStandardPaths.writableLocation(QStandardPaths.DownloadLocation))
        add_qa("Documentos", QStandardPaths.writableLocation(QStandardPaths.DocumentsLocation))
        add_qa("Imágenes", QStandardPaths.writableLocation(QStandardPaths.PicturesLocation))
        add_qa("Música", QStandardPaths.writableLocation(QStandardPaths.MusicLocation))
        add_qa("Videos", QStandardPaths.writableLocation(QStandardPaths.MoviesLocation))
        add_qa("Este equipo", "") # root

    def on_sidebar_clicked(self, index: QModelIndex):
        from PySide6.QtCore import QTimer
        path = self.qa_model.data(index, Qt.UserRole)
        QTimer.singleShot(0, lambda: self.go_to_path(path))

    def _map_to_source(self, index: QModelIndex):
        model = index.model()
        if isinstance(model, QSortFilterProxyModel):
            return model.mapToSource(index)
        return index

    def on_tree_clicked(self, index: QModelIndex):
        source_idx = self._map_to_source(index)
        info = self.fs_model.fileInfo(source_idx)
        if not info.isDir():
            path = self.fs_model.filePath(source_idx)
            self.file_opened.emit(path)

    def go_back(self):
        current_idx = self.fs_model.index(self.current_root_path) if hasattr(self, 'current_root_path') else self.fs_model.index("")
        parent_idx = self.fs_model.parent(current_idx)
        if not parent_idx.isValid() or self.fs_model.filePath(parent_idx) == "":
            self.go_to_path("")
        else:
            self.go_to_path(self.fs_model.filePath(parent_idx))

    def on_tree_double_clicked(self, index: QModelIndex):
        from PySide6.QtCore import QTimer
        source_idx = self._map_to_source(index)
        info = self.fs_model.fileInfo(source_idx)
        path = self.fs_model.filePath(source_idx)
        if info.isDir():
            QTimer.singleShot(0, lambda: self.go_to_path(path))

    def go_to_path(self, path):
        self.file_proxy.current_root_path = path
        self.file_proxy.invalidateFilter()
        
        source_idx = self.fs_model.index(path)
        folder_idx = self.folder_proxy.mapFromSource(source_idx)
        file_idx = self.file_proxy.mapFromSource(source_idx)
        
        self.folder_view.setRootIndex(folder_idx)
        self.file_view.setRootIndex(file_idx)
        
        self.current_root_path = path
        self.path_view.set_path(path)

    def highlight_file(self, path):
        source_idx = self.fs_model.index(path)
        if not source_idx.isValid(): return
        
        if self.fs_model.isDir(source_idx):
            idx = self.folder_proxy.mapFromSource(source_idx)
            if idx.isValid():
                self.folder_view.setCurrentIndex(idx)
                self.folder_view.scrollTo(idx)
        else:
            idx = self.file_proxy.mapFromSource(source_idx)
            if idx.isValid():
                self.file_view.setCurrentIndex(idx)
                self.file_view.scrollTo(idx)

    def show_context_menu(self, pos, view):
        index = view.indexAt(pos)
        target_dir = self.current_root_path if hasattr(self, 'current_root_path') else ""
        target_file = None
        
        menu = SciFiContextMenu(view)
        
        if index.isValid():
            source_idx = self._map_to_source(index)
            info = self.fs_model.fileInfo(source_idx)
            if info.isDir():
                target_dir = info.absoluteFilePath()
                target_file = info.absoluteFilePath()
            else:
                target_dir = info.absolutePath()
                target_file = info.absoluteFilePath()
                
            menu.add_action("Editar nombre", lambda: self._rename_item(target_file))
            menu.add_action("Duplicar", lambda: self._duplicate_item(target_file))
            menu.add_action("Borrar", lambda: self._delete_item(target_file))
        else:
            menu.add_action("Nueva carpeta", lambda: self._create_folder(target_dir))
            menu.add_action("Nuevo archivo", lambda: self._create_file(target_dir))
            
        menu.move(view.viewport().mapToGlobal(pos))
        menu.show()

    def _duplicate_item(self, target_path):
        success, err = self.fs_ecosystem.duplicate_item(target_path)
        if not success:
            self.show_error(err)

    def _get_selected_paths(self):
        paths = []
        for view in [self.folder_view, self.file_view]:
            for index in view.selectionModel().selectedIndexes():
                if index.column() == 0:
                    source_idx = self._map_to_source(index)
                    paths.append(self.fs_model.filePath(source_idx))
        return list(set(paths))

    def _do_copy(self):
        paths = self._get_selected_paths()
        if paths:
            self.clipboard_paths = paths
            self.clipboard_op = "copy"

    def _do_cut(self):
        paths = self._get_selected_paths()
        if paths:
            self.clipboard_paths = paths
            self.clipboard_op = "cut"

    def _do_paste(self):
        if not self.clipboard_paths: return
        target_dir = self.current_root_path if hasattr(self, 'current_root_path') else ""
        selected = self._get_selected_paths()
        if len(selected) == 1 and QFileInfo(selected[0]).isDir():
            target_dir = selected[0]
            
        success, err = self.fs_ecosystem.paste_items(self.clipboard_paths, self.clipboard_op, target_dir)
        if not success:
            self.show_error(err)
            
        if self.clipboard_op == "cut":
            self.clipboard_paths = []
            self.clipboard_op = None

    def _do_delete_selected(self):
        paths = self._get_selected_paths()
        if not paths: return
        msg = f"¿Borrar {os.path.basename(paths[0])}?" if len(paths) == 1 else f"¿Borrar {len(paths)} elementos?"
        dialog = SciFiConfirmDialog(self, "CONFIRMAR", msg)
        if dialog.exec() == QDialog.Accepted:
            success, err = self.fs_ecosystem.delete_items(paths)
            if not success:
                self.show_error(err)

    def _create_folder(self, parent_dir):
        dialog = SciFiInputDialog(self, "NUEVA CARPETA", "Nombre de la carpeta:")
        if dialog.exec() == QDialog.Accepted:
            name = dialog.get_text()
            if name:
                success, err = self.fs_ecosystem.create_folder(parent_dir, name)
                if not success:
                    self.show_error(err)

    def _create_file(self, parent_dir):
        dialog = SciFiFileEditDialog(self, "NUEVO ARCHIVO", "Nombre y tipo de archivo:", default_name="nuevo_archivo", default_ext="txt")
        if dialog.exec() == QDialog.Accepted:
            name = dialog.get_full_name()
            if name:
                success, err = self.fs_ecosystem.create_file(parent_dir, name)
                if not success:
                    self.show_error(err)

    def _rename_item(self, target_path):
        import os
        from PySide6.QtCore import QFileInfo
        info = QFileInfo(target_path)
        parent_dir = os.path.dirname(target_path)
        
        if info.isDir():
            old_name = info.fileName()
            dialog = SciFiInputDialog(self, "RENOMBRAR CARPETA", "Nuevo nombre:", default_text=old_name)
            if dialog.exec() == QDialog.Accepted:
                new_name = dialog.get_text()
                if new_name and new_name != old_name:
                    new_path = os.path.join(parent_dir, new_name)
                    success, err = self.fs_ecosystem.rename_item(target_path, new_path)
                    if not success:
                        self.show_error(err)
        else:
            base_name = info.completeBaseName()
            ext = info.suffix()
            dialog = SciFiFileEditDialog(self, "RENOMBRAR ARCHIVO", "Nuevo nombre y tipo:", default_name=base_name, default_ext=ext)
            if dialog.exec() == QDialog.Accepted:
                new_full_name = dialog.get_full_name()
                if new_full_name and new_full_name != info.fileName():
                    new_path = os.path.join(parent_dir, new_full_name)
                    success, err = self.fs_ecosystem.rename_item(target_path, new_path)
                    if not success:
                        self.show_error(err)

    def _delete_item(self, target_path):
        from PySide6.QtCore import QFileInfo
        dialog = SciFiConfirmDialog(self, "CONFIRMAR", f"¿Borrar {os.path.basename(target_path)}?")
        if dialog.exec() == QDialog.Accepted:
            success, err = self.fs_ecosystem.delete_items([target_path])
            if not success:
                self.show_error(err)
        
    def show_error(self, msg):
        dialog = SciFiConfirmDialog(self, "ERROR", msg)
        dialog.exec()
