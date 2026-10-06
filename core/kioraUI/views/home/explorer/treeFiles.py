from PySide6.QtWidgets import QFrame, QVBoxLayout, QHBoxLayout, QLabel, QPushButton, QTreeView, QFileSystemModel, QLineEdit, QFileIconProvider, QHeaderView
from core.kioraUI.views.global_ui.custom_dialogs import RadialContextMenu, SciFiInputDialog, SciFiConfirmDialog
from core.kioraUI.views.global_ui.base_container import KioraBaseContainer
from PySide6.QtCore import Qt, QModelIndex, QFileInfo, QDir, QPoint, Signal, QStandardPaths
from PySide6.QtGui import QIcon, QPixmap, QPainter, QColor, QPen, QStandardItemModel, QStandardItem, QShortcut, QKeySequence
import os
import shutil

from core.kioraUI.views.global_ui.styles import get_minimal_scrollbar_style

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
        
        painter.setPen(QPen(QColor("#D96600"), 2, Qt.SolidLine, Qt.RoundCap, Qt.RoundJoin))
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
            painter.setBrush(QColor("#E8B923")) 
            painter.drawRect(1, 2, 6, 3)
            painter.drawRoundedRect(1, 5, 14, 9, 1, 1)
            painter.setPen(QPen(QColor("#FFE47A"), 1))
            painter.drawLine(2, 5, 14, 5)
        else:
            painter.setPen(Qt.NoPen)
            painter.setBrush(QColor("#A0A0A0"))
            painter.drawRect(3, 2, 10, 12)
            painter.setBrush(QColor("#D0D0D0"))
            painter.drawPolygon([QPoint(13,2), QPoint(13,5), QPoint(10,2)])
            painter.setPen(QPen(QColor("#404040"), 1))
            painter.drawLine(5, 6, 11, 6)
            painter.drawLine(5, 8, 11, 8)
            painter.drawLine(5, 10, 8, 10)
            
        painter.end()
        return QIcon(pixmap)

    def icon(self, info_or_type):
        if isinstance(info_or_type, QFileInfo):
            return self.folder_icon if info_or_type.isDir() else self.file_icon
        return self.folder_icon if info_or_type == QFileIconProvider.Folder else self.file_icon

class ExplorerPanel(KioraBaseContainer):
    
    file_opened = Signal(str) # Emite la ruta del archivo a abrir
    
    def __init__(self, parent=None):
        super().__init__(title_text="SYSTEM FILE EXPLORER...", parent=parent)
        self.resize(750, 500)
        
        self.icon_provider = SciFiIconProvider()
        
        # --- BARRA DE NAVEGACIÓN ---
        nav_layout = QHBoxLayout()
        
        btn_style = """
            QPushButton { background-color: #182533; color: #FFFFFF; border: 1px solid #D96600; font-family: 'Segoe UI'; font-weight: bold; padding: 4px 10px; font-size: 11px; }
            QPushButton:hover { background-color: #D96600; }
        """
        
        self.home_btn = QPushButton("⌂ HOME")
        self.home_btn.setStyleSheet(btn_style)
        self.home_btn.setCursor(Qt.PointingHandCursor)
        self.home_btn.clicked.connect(lambda: self.go_to_path(""))
        
        self.path_btn = QPushButton(" QUICK ACCESS / HOME")
        self.path_btn.setIcon(self.icon_provider.back_icon)
        self.path_btn.setStyleSheet("""
            QPushButton { background-color: #0A1118; color: #D96600; border: 1px solid #182533; padding: 6px; font-family: 'Consolas', monospace; font-size: 11px; text-align: left; }
            QPushButton:hover { background-color: #2A1A1C; border: 1px solid #D96600; }
        """)
        self.path_btn.setCursor(Qt.PointingHandCursor)
        self.path_btn.clicked.connect(self.go_back)
        
        nav_layout.addWidget(self.home_btn)
        nav_layout.addWidget(self.path_btn, 1)
        self.body_layout.addLayout(nav_layout)
        
        # --- SPLITTER ---
        from PySide6.QtWidgets import QSplitter, QTreeView
        self.splitter = QSplitter(Qt.Horizontal)
        self.splitter.setStyleSheet("QSplitter::handle { background-color: #182533; width: 2px; }")
        
        # --- SIDEBAR (Quick Access) ---
        self.sidebar = QTreeView()
        self.sidebar.setStyleSheet(get_minimal_scrollbar_style() + """
            QTreeView { background-color: #111111; color: #D96600; border: 1px solid #182533; outline: 0; padding: 5px; }
            QTreeView::item { padding: 8px; border-radius: 4px; }
            QTreeView::item:selected { background-color: rgba(217, 102, 0, 0.25); color: #FFFFFF; }
            QTreeView::item:hover:!selected { background-color: rgba(58, 35, 38, 0.5); }
            QHeaderView::section { background-color: #111111; color: #D48800; border: none; border-bottom: 1px solid #182533; padding: 4px; font-weight: bold; }
        """)
        self.sidebar.setRootIsDecorated(False)
        
        self.qa_model = QStandardItemModel()
        self.qa_model.setHorizontalHeaderLabels(["DIRECTORIOS PRINCIPALES"])
        self.sidebar.setModel(self.qa_model)
        self.sidebar.clicked.connect(self.on_sidebar_clicked)
        
        # --- ARBOL ---
        self.tree = QTreeView()
        self.tree.setStyleSheet(get_minimal_scrollbar_style() + """
            QTreeView { background-color: #060A0F; color: #D96600; border: 1px solid #182533; outline: 0; }
            QTreeView::item { padding: 5px; }
            QTreeView::item:selected { background-color: rgba(217, 102, 0, 0.25); color: #FFFFFF; }
            QTreeView::item:hover:!selected { background-color: rgba(58, 35, 38, 0.5); }
            QHeaderView::section { background-color: #060A0F; color: #D48800; border: none; border-bottom: 1px solid #182533; padding: 4px; font-weight: bold; }
        """)
        
        # File System Model
        self.fs_model = QFileSystemModel()
        self.fs_model.setRootPath("")
        self.icon_provider = SciFiIconProvider()
        self.fs_model.setIconProvider(self.icon_provider)
        
        self.tree.setModel(self.fs_model)
        self.tree.hideColumn(1) # Ocultar size
        self.tree.hideColumn(3) # Ocultar fecha
        self.tree.setSortingEnabled(False)
        self.tree.header().setSectionsClickable(False)
        self.tree.setTextElideMode(Qt.ElideRight)
        self.tree.setHorizontalScrollBarPolicy(Qt.ScrollBarAsNeeded)
        
        # Selección nativa Ctrl + Click
        self.tree.setSelectionMode(QTreeView.ExtendedSelection)
        self.tree.setSelectionBehavior(QTreeView.SelectRows)
        
        # Atajos de Teclado para Portapapeles (Copy, Cut, Paste)
        self.clipboard_paths = []
        self.clipboard_op = None
        
        QShortcut(QKeySequence("Ctrl+C"), self.tree, self._do_copy)
        QShortcut(QKeySequence("Ctrl+X"), self.tree, self._do_cut)
        QShortcut(QKeySequence("Ctrl+V"), self.tree, self._do_paste)
        QShortcut(QKeySequence("Ctrl+D"), self.tree, self._do_delete_selected)
        
        self.fs_model.directoryLoaded.connect(lambda _: self._apply_column_layout())
        
        self.tree.doubleClicked.connect(self.on_tree_double_clicked)
        
        self.tree.setContextMenuPolicy(Qt.CustomContextMenu)
        self.tree.customContextMenuRequested.connect(self.show_context_menu)
        
        self.splitter.addWidget(self.sidebar)
        self.splitter.addWidget(self.tree)
        self.splitter.setSizes([180, 570])
        
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

    def _apply_column_layout(self):
        header = self.tree.header()
        model = self.tree.model()
        if model is None:
            return
        header.setStretchLastSection(False)
        header.setMinimumSectionSize(60)
        header.setSectionResizeMode(0, QHeaderView.ResizeToContents)
        if model.columnCount() > 2:
            header.setSectionResizeMode(2, QHeaderView.Stretch)

    def on_sidebar_clicked(self, index: QModelIndex):
        from PySide6.QtCore import QTimer
        path = self.qa_model.data(index, Qt.UserRole)
        QTimer.singleShot(0, lambda: self.go_to_path(path))

    def go_back(self):
        current_idx = self.tree.rootIndex()
        parent_idx = self.fs_model.parent(current_idx)
        
        if not parent_idx.isValid() or self.fs_model.filePath(parent_idx) == "":
            self.go_to_path("")
        else:
            self.go_to_path(self.fs_model.filePath(parent_idx))

    def on_tree_double_clicked(self, index: QModelIndex):
        from PySide6.QtCore import QTimer
        info = self.fs_model.fileInfo(index)
        path = self.fs_model.filePath(index)
        if info.isDir():
            QTimer.singleShot(0, lambda: self.go_to_path(path))
        else:
            self.file_opened.emit(path)

    def go_to_path(self, path):
        idx = self.fs_model.index(path)
        self.tree.setRootIndex(idx)
        self._apply_column_layout()
        self.path_btn.setText(f" {path}" if path else " Este equipo")

    # --- CONTEXT MENU LOGIC ---
    def show_context_menu(self, pos):
        if self.tree.model() != self.fs_model:
            return
            
        index = self.tree.indexAt(pos)
        
        target_dir = self.fs_model.filePath(self.tree.rootIndex())
        target_file = None
        
        if index.isValid():
            info = self.fs_model.fileInfo(index)
            if info.isDir():
                target_dir = info.absoluteFilePath()
                target_file = info.absoluteFilePath()
            else:
                target_dir = info.absolutePath()
                target_file = info.absoluteFilePath()
                
            actions = ["rename", "delete"]
        else:
            actions = ["new_folder", "new_file"]
            
        # Posición siempre al centro del contenedor
        center_x = self.body_frame.width() / 2
        center_y = self.body_frame.height() / 2
        local_pos = QPoint(int(center_x), int(center_y))
        
        self.menu_overlay = RadialContextMenu(self.body_frame, self.tree, local_pos, actions, lambda action: self.handle_menu_action(action, target_dir, target_file))
        self.menu_overlay.show()

    def handle_menu_action(self, action, target_dir, target_file):
        if action == "new_folder":
            self._create_folder(target_dir)
        elif action == "new_file":
            self._create_file(target_dir)
        elif action == "rename":
            if target_file:
                self._rename_item(target_file)
            else:
                self.show_error("No file or folder selected to rename.")
        elif action == "delete":
            if target_file:
                self._delete_item(target_file)
            else:
                self.show_error("No file or folder selected to delete.")

    # --- CLIPBOARD LOGIC (Copy/Cut/Paste) ---
    def _get_selected_paths(self):
        paths = []
        for index in self.tree.selectionModel().selectedRows():
            paths.append(self.fs_model.filePath(index))
        return paths

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
        if not self.clipboard_paths:
            return
            
        target_dir = self.fs_model.filePath(self.tree.rootIndex())
        selected = self._get_selected_paths()
        if len(selected) == 1 and QFileInfo(selected[0]).isDir():
            target_dir = selected[0]
            
        for path in self.clipboard_paths:
            name = os.path.basename(path)
            dest = os.path.join(target_dir, name)
            
            if path == dest:
                continue
                
            try:
                if self.clipboard_op == "copy":
                    if os.path.isdir(path):
                        shutil.copytree(path, dest, dirs_exist_ok=True)
                    else:
                        shutil.copy2(path, dest)
                elif self.clipboard_op == "cut":
                    shutil.move(path, dest)
            except Exception as e:
                self.show_error(f"Error pasting {name}:\n{e}")
                
        if self.clipboard_op == "cut":
            self.clipboard_paths = []
            self.clipboard_op = None

    def _do_delete_selected(self):
        paths = self._get_selected_paths()
        if not paths:
            return
            
        def on_confirm():
            for path in paths:
                try:
                    info = QFileInfo(path)
                    if info.isDir():
                        shutil.rmtree(path)
                    else:
                        os.remove(path)
                except Exception as e:
                    self.show_error(f"Could not delete {os.path.basename(path)}: {str(e)}")
                    
        msg = f"Delete {os.path.basename(paths[0])}?" if len(paths) == 1 else f"Delete {len(paths)} selected items?"
        self.confirm_overlay = SciFiConfirmDialog(self.body_frame, self.tree, "CONFIRM DELETION", msg, on_confirm)
        self.confirm_overlay.show()

    def _create_folder(self, parent_dir):
        def on_accept(name):
            if name:
                dir_obj = QDir(parent_dir)
                if not dir_obj.mkdir(name):
                    self.show_error("Could not create folder.")
        
        self.dialog_overlay = SciFiInputDialog(self.body_frame, self.tree, "NEW FOLDER SEQUENCE", "Enter folder name...", "", on_accept)
        self.dialog_overlay.show()

    def _create_file(self, parent_dir):
        def on_accept(name):
            if name:
                file_path = os.path.join(parent_dir, name)
                try:
                    with open(file_path, 'w') as f:
                        pass
                except Exception as e:
                    self.show_error(f"Could not create file: {e}")
                    
        self.dialog_overlay = SciFiInputDialog(self.body_frame, self.tree, "NEW FILE SEQUENCE", "Enter filename (e.g. data.txt)", "", on_accept)
        self.dialog_overlay.show()

    def _rename_item(self, target_path):
        from PySide6.QtCore import QFile
        old_name = os.path.basename(target_path)
        parent_dir = os.path.dirname(target_path)
        
        def on_accept(new_name):
            if new_name and new_name != old_name:
                new_path = os.path.join(parent_dir, new_name)
                if not QFile.rename(target_path, new_path):
                    self.show_error("Could not rename item.")
                    
        self.dialog_overlay = SciFiInputDialog(self.body_frame, self.tree, "RENAME SEQUENCE", "New name...", old_name, on_accept)
        self.dialog_overlay.show()

    def _delete_item(self, target_path):
        from PySide6.QtCore import QFile, QFileInfo
        
        def on_confirm():
            info = QFileInfo(target_path)
            if info.isDir():
                if not QDir(target_path).removeRecursively():
                    self.show_error("Could not delete folder.")
            else:
                if not QFile.remove(target_path):
                    self.show_error("Could not delete file.")
                    
        self.dialog_overlay = SciFiConfirmDialog(self.body_frame, self.tree, "CONFIRM DELETION", f"Are you sure you want to permanently delete\n{os.path.basename(target_path)}?", on_confirm)
        self.dialog_overlay.show()
        
    def show_error(self, msg):
        self.dialog_overlay = SciFiConfirmDialog(self.body_frame, self.tree, "ERROR", msg, lambda: None)
        self.dialog_overlay.show()


