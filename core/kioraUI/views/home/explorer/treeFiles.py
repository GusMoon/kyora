from PySide6.QtWidgets import QFrame, QVBoxLayout, QHBoxLayout, QLabel, QPushButton, QTreeView, QFileSystemModel, QLineEdit, QFileIconProvider, QHeaderView
from PySide6.QtCore import Qt, QModelIndex, QFileInfo, QDir, QPoint, Signal, QStandardPaths
from PySide6.QtGui import QIcon, QPixmap, QPainter, QColor, QPen, QStandardItemModel, QStandardItem
import os

from core.kioraUI.views.global_ui.styles import get_minimal_scrollbar_style

class SciFiIconProvider(QFileIconProvider):
    def __init__(self):
        super().__init__()
        self.folder_icon = self._create_icon(True)
        self.file_icon = self._create_icon(False)
        
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

class ExplorerPanel(QFrame):
    
    file_opened = Signal(str) # Emite la ruta del archivo a abrir
    
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setFixedSize(550, 500)
        self.user_moved = False
        
        self.setStyleSheet("""
            QFrame { background-color: #161616; border: 1px solid #A31F34; }
        """)
        
        main_layout = QVBoxLayout(self)
        main_layout.setContentsMargins(0, 0, 0, 0)
        main_layout.setSpacing(0)
        
        # --- HEADER ---
        self.header = QFrame()
        self.header.setFixedHeight(35)
        self.header.setStyleSheet("QFrame { background-color: #A31F34; border: none; border-bottom: 2px solid #7A1727; }")
        
        header_layout = QHBoxLayout(self.header)
        header_layout.setContentsMargins(15, 0, 10, 0)
        
        title = QLabel("SYSTEM FILE EXPLORER...")
        title.setStyleSheet("QLabel { color: #FFFFFF; font-family: 'Segoe UI', sans-serif; font-size: 11px; font-weight: 800; letter-spacing: 2px; border: none; background: transparent; }")
        
        header_layout.addWidget(title)
        header_layout.addStretch()
        
        self.close_btn = QPushButton("✕")
        self.close_btn.setFixedSize(24, 24)
        self.close_btn.setCursor(Qt.PointingHandCursor)
        self.close_btn.setStyleSheet("QPushButton { background-color: transparent; color: #FFFFFF; font-weight: bold; font-size: 14px; border: none; } QPushButton:hover { color: #161616; }")
        self.close_btn.clicked.connect(self.hide)
        
        header_layout.addWidget(self.close_btn)
        
        # --- BODY ---
        body_frame = QFrame()
        body_frame.setStyleSheet("border: none; background-color: transparent;")
        body_layout = QVBoxLayout(body_frame)
        body_layout.setContentsMargins(20, 20, 20, 20)
        
        # --- BARRA DE NAVEGACIÓN ---
        nav_layout = QHBoxLayout()
        
        btn_style = """
            QPushButton { background-color: #3A2326; color: #FFFFFF; border: 1px solid #A31F34; font-family: 'Segoe UI'; font-weight: bold; padding: 4px 10px; font-size: 11px; }
            QPushButton:hover { background-color: #A31F34; }
        """
        
        self.home_btn = QPushButton("⌂ HOME")
        self.home_btn.setStyleSheet(btn_style)
        self.home_btn.setCursor(Qt.PointingHandCursor)
        self.home_btn.clicked.connect(self.go_home)
        
        nav_layout.addWidget(self.home_btn)
        
        # Ruta actual (Editable para navegar directamente)
        self.path_label = QLineEdit()
        self.path_label.setReadOnly(False)
        self.path_label.setStyleSheet("QLineEdit { background-color: #1E1E1E; color: #A31F34; border: 1px solid #3A2326; padding: 6px; font-family: 'Consolas', monospace; font-size: 11px; }")
        self.path_label.returnPressed.connect(self.on_path_edited)
        
        # Autocompletado de directorios
        from PySide6.QtWidgets import QCompleter
        self.completer_model = QFileSystemModel()
        self.completer_model.setRootPath("")
        self.completer_model.setFilter(QDir.AllDirs | QDir.NoDotAndDotDot | QDir.Drives)
        self.dir_completer = QCompleter(self)
        self.dir_completer.setModel(self.completer_model)
        self.path_label.setCompleter(self.dir_completer)
        
        nav_layout.addWidget(self.path_label)
        body_layout.addLayout(nav_layout)
        
        # --- ARBOL ---
        self.tree = QTreeView()
        self.tree.setStyleSheet(get_minimal_scrollbar_style() + """
            QTreeView { background-color: #161616; color: #A31F34; border: 1px solid #3A2326; outline: 0; }
            QTreeView::item { padding: 5px; }
            QTreeView::item:selected { background-color: rgba(163, 31, 52, 0.25); color: #FFFFFF; }
            QTreeView::item:hover:!selected { background-color: rgba(58, 35, 38, 0.5); }
            QHeaderView::section { background-color: #161616; color: #7A1727; border: none; border-bottom: 1px solid #3A2326; padding: 4px; font-weight: bold; }
        """)
        
        # File System Model
        self.fs_model = QFileSystemModel()
        self.fs_model.setRootPath("")
        self.icon_provider = SciFiIconProvider()
        self.fs_model.setIconProvider(self.icon_provider)
        
        # Quick Access Model
        self.qa_model = QStandardItemModel()
        
        # La config de columnas se aplica en _apply_column_layout() tras cada setModel,
        # porque el header no tiene secciones antes de asignar modelo y se resetea al cambiarlo.
        self.tree.setTextElideMode(Qt.ElideRight)
        self.tree.setHorizontalScrollBarPolicy(Qt.ScrollBarAsNeeded)
        # Al terminar de cargar un directorio (carga asincrona), recalcular el ancho del nombre
        self.fs_model.directoryLoaded.connect(lambda _: self._apply_column_layout())
        
        self.tree.clicked.connect(self.on_tree_clicked)
        
        body_layout.addWidget(self.tree)
        
        # Ensamblar
        main_layout.addWidget(self.header)
        main_layout.addWidget(body_frame)
        
        self.go_home()

    def go_home(self):
        self.qa_model.clear()
        self.qa_model.setHorizontalHeaderLabels(["DIRECTORIOS PRINCIPALES"])
        
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
        
        self.tree.setModel(self.qa_model)
        self._apply_column_layout()
        self.path_label.setText("QUICK ACCESS / HOME")

    def _apply_column_layout(self):
        """Nombre SIEMPRE completo (ajustado a contenido); Tipo es secundario y ocupa el resto."""
        header = self.tree.header()
        model = self.tree.model()
        if model is None:
            return
        if model is self.qa_model:
            header.setStretchLastSection(True)
            return
        header.setStretchLastSection(False)
        header.setMinimumSectionSize(60)
        header.setSectionResizeMode(0, QHeaderView.ResizeToContents)
        if model.columnCount() > 2:
            header.setSectionResizeMode(2, QHeaderView.Stretch)
        
    def on_path_edited(self):
        path = self.path_label.text().strip()
        if path.upper() == "HOME" or path == "QUICK ACCESS / HOME":
            self.go_home()
            return
            
        from PySide6.QtCore import QDir
        if QDir(path).exists():
            self.go_to_path(path)
        else:
            # Revertir si no existe
            self.path_label.setText(self.fs_model.filePath(self.tree.rootIndex()) if self.tree.model() == self.fs_model else "QUICK ACCESS / HOME")
            
    def go_back(self):
        if self.tree.model() == self.qa_model:
            return
        
        current_idx = self.tree.rootIndex()
        parent_idx = self.fs_model.parent(current_idx)
        
        if not parent_idx.isValid() or self.fs_model.filePath(parent_idx) == "":
            self.go_home()
        else:
            self.tree.setRootIndex(parent_idx)
            self.path_label.setText(self.fs_model.filePath(parent_idx))

    def on_tree_clicked(self, index: QModelIndex):
        from PySide6.QtCore import QTimer
        if self.tree.model() == self.qa_model:
            path = self.qa_model.data(index, Qt.UserRole)
            # Usar QTimer evita el crasheo interno de C++ (Segfault) al cambiar de modelo o root_index durante un click
            QTimer.singleShot(0, lambda: self.go_to_path(path))
        else:
            info = self.fs_model.fileInfo(index)
            path = self.fs_model.filePath(index)
            if info.isDir():
                QTimer.singleShot(0, lambda: self.go_to_path(path))
            else:
                self.file_opened.emit(path)
                
    def go_to_path(self, path):
        if self.tree.model() != self.fs_model:
            self.tree.setModel(self.fs_model)
            self.tree.hideColumn(1) # Ocultar size
            self.tree.hideColumn(3) # Ocultar fecha
            self.tree.setSortingEnabled(False)
            self.tree.header().setSectionsClickable(False)
            
        idx = self.fs_model.index(path)
        self.tree.setRootIndex(idx)
        self._apply_column_layout()
        self.path_label.setText(path if path else "Este equipo")

    # --- LÓGICA DE MOVIMIENTO (DRAG & DROP) ---
    def mousePressEvent(self, event):
        if event.button() == Qt.LeftButton:
            self._drag_pos = event.globalPosition().toPoint()
            event.accept()

    def mouseMoveEvent(self, event):
        if hasattr(self, '_drag_pos') and event.buttons() == Qt.LeftButton:
            self.user_moved = True
            new_pos = event.globalPosition().toPoint()
            diff = new_pos - self._drag_pos
            self._drag_pos = new_pos
            
            next_pos = self.pos() + diff
            
            if self.parent():
                parent_rect = self.parent().rect()
                x = max(0, min(next_pos.x(), parent_rect.width() - self.width()))
                y = max(0, min(next_pos.y(), parent_rect.height() - self.height()))
                self.move(x, y)
            else:
                self.move(next_pos)
            
            event.accept()
            
    def mouseReleaseEvent(self, event):
        if event.button() == Qt.LeftButton:
            if hasattr(self, '_drag_pos'):
                del self._drag_pos
            event.accept()
