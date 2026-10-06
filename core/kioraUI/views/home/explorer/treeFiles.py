from PySide6.QtWidgets import QWidget, QFrame, QVBoxLayout, QHBoxLayout, QLabel, QPushButton, QTreeView, QFileSystemModel, QLineEdit, QFileIconProvider, QHeaderView, QSplitter, QStyledItemDelegate, QStyle, QStyleFactory, QMenu, QDialog
from core.kioraUI.views.global_ui.simple_dialogs import SciFiInputDialog, SciFiConfirmDialog, SciFiContextMenu
from PySide6.QtCore import Qt, QModelIndex, QFileInfo, QDir, QPoint, Signal, QStandardPaths, QSize, QRect
from PySide6.QtGui import QIcon, QPixmap, QPainter, QColor, QPen, QStandardItemModel, QStandardItem, QShortcut, QKeySequence, QPainterPath, QFont
import os
import shutil

import math
from core.kioraUI.views.global_ui.styles import get_minimal_scrollbar_style

class NoBranchTreeView(QTreeView):
    def drawBranches(self, painter, rect, index):
        pass

class SciFiItemDelegate(QStyledItemDelegate):
    def __init__(self, show_arrow=True, enable_3d=True, parent=None):
        super().__init__(parent)
        self.show_arrow = show_arrow
        self.enable_3d = enable_3d

    def paint(self, painter, option, index):
        painter.save()
        painter.setRenderHint(QPainter.Antialiasing)
        
        rect = option.rect
        is_selected = option.state & QStyle.State_Selected
        is_hovered = option.state & QStyle.State_MouseOver
        
        # 3D Wheel effect
        widget = option.widget
        if widget and self.enable_3d:
            viewport_h = widget.height()
            center_y = rect.center().y()
            norm_y = center_y / viewport_h
            
            scale_xy = 1.0
            opacity = 1.0
            shift_x = 0.0
            edge_threshold = 0.05
            
            if norm_y < edge_threshold:
                falloff = (edge_threshold - norm_y) / edge_threshold
                scale_xy = max(0.9, 1.0 - (falloff * 0.1))
                opacity = max(0.6, 1.0 - (falloff * 0.4))
                shift_x = -falloff * 15.0
            elif norm_y > (1.0 - edge_threshold):
                falloff = (norm_y - (1.0 - edge_threshold)) / edge_threshold
                scale_xy = max(0.9, 1.0 - (falloff * 0.1))
                opacity = max(0.6, 1.0 - (falloff * 0.4))
                shift_x = -falloff * 15.0
                
            if scale_xy != 1.0 or opacity != 1.0 or shift_x != 0.0:
                painter.setOpacity(opacity)
                painter.translate(rect.center())
                painter.translate(shift_x, 0)
                painter.scale(scale_xy, scale_xy)
                painter.translate(-rect.center())
            
        primary_color = QColor("#FFFFFF") if is_selected else QColor("#A0C0FF")
        glow_color = QColor("#4D94FF")
        bg_color = QColor(77, 148, 255, 35 if is_selected else (15 if is_hovered else 0))
        
        margin = 4
        h_margin = 8
        x = rect.x() + h_margin
        y = rect.y() + margin
        w = rect.width() - h_margin * 2
        h = rect.height() - margin * 2
        
        # Thick left bar
        bar_width = 4
        painter.setPen(Qt.NoPen)
        painter.setBrush(QColor("#FFFFFF") if is_selected else QColor("#384553"))
        painter.drawRect(x, y, bar_width, h)
        
        # Main Box (bg + border)
        box_x = x + bar_width + 4
        box_w = w - bar_width - 4
        
        painter.setBrush(bg_color)
        painter.setPen(Qt.NoPen)
        painter.drawRect(box_x, y, box_w, h)
        
        pen = QPen(glow_color if is_selected else QColor("#182533"), 1)
        if is_selected: pen.setWidth(2)
        painter.setPen(pen)
        painter.setBrush(Qt.NoBrush)
        painter.drawRect(box_x, y, box_w, h)
        
        arrow_size = 5
        arrow_x = box_x + 10
        arrow_y = y + h // 2
        
        is_dir = True
        model = index.model()
        if hasattr(model, 'isDir'):
            is_dir = model.isDir(index)
        
        text_x = arrow_x
        if self.show_arrow and is_dir:
            arrow_path = QPainterPath()
            arrow_path.moveTo(arrow_x, arrow_y - arrow_size)
            arrow_path.lineTo(arrow_x + arrow_size, arrow_y)
            arrow_path.lineTo(arrow_x, arrow_y + arrow_size)
            arrow_path.closeSubpath()
            
            painter.setPen(Qt.NoPen)
            painter.setBrush(QColor("#FFFFFF") if is_selected else QColor("#80BFFF"))
            painter.drawPath(arrow_path)
            text_x += arrow_size + 10
        elif not is_dir:
            icon = index.data(Qt.DecorationRole)
            if icon and isinstance(icon, QIcon):
                icon_rect = QRect(arrow_x, y + (h - 16) // 2, 16, 16)
                icon.paint(painter, icon_rect, Qt.AlignCenter, QIcon.Normal, QIcon.On)
                text_x += 16 + 10
        elif self.show_arrow:
            text_x += arrow_size + 10
            
        text = index.data(Qt.DisplayRole)
        
        font = QFont("Segoe UI", 10, QFont.Bold if is_selected else QFont.Normal)
        font.setLetterSpacing(QFont.AbsoluteSpacing, 1)
        painter.setFont(font)
        painter.setPen(primary_color)
        text_rect = QRect(text_x, y, box_w - (text_x - box_x) - 30, h)
        painter.drawText(text_rect, Qt.AlignVCenter | Qt.AlignLeft, text)
        
        row_idx = str(index.row() + 1).zfill(2)
        num_font = QFont("Consolas", 10)
        painter.setFont(num_font)
        painter.setPen(glow_color)
        num_rect = QRect(box_x + box_w - 35, y, 25, h)
        painter.drawText(num_rect, Qt.AlignVCenter | Qt.AlignRight, row_idx)
        
        painter.restore()

    def sizeHint(self, option, index):
        return QSize(250, 46)

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
        painter.setPen(QPen(QColor("#4D94FF"), 2, Qt.SolidLine, Qt.RoundCap, Qt.RoundJoin))
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
            painter.setBrush(QColor("#4D94FF")) 
            painter.drawRect(1, 2, 6, 3)
            painter.drawRoundedRect(1, 5, 14, 9, 1, 1)
        else:
            painter.setPen(Qt.NoPen)
            painter.setBrush(QColor("#A0C0FF"))
            painter.drawRect(3, 2, 10, 12)
            painter.setBrush(QColor("#FFFFFF"))
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
        
        self.body_layout = QVBoxLayout(self)
        self.body_layout.setContentsMargins(0, 0, 0, 0)
        self.body_layout.setSpacing(5)
        
        self.icon_provider = SciFiIconProvider()
        
        # --- BARRA DE NAVEGACIÓN ---
        nav_layout = QHBoxLayout()
        nav_layout.setContentsMargins(10, 10, 10, 10)
        
        btn_style = """
            QPushButton { background-color: transparent; color: #80BFFF; border: 1px solid #182533; font-family: 'Segoe UI'; font-weight: bold; padding: 6px 15px; font-size: 11px; letter-spacing: 1px; }
            QPushButton:hover { background-color: rgba(77, 148, 255, 0.2); border: 1px solid #4D94FF; color: #FFFFFF; }
        """
        
        self.home_btn = QPushButton("HOME")
        self.home_btn.setStyleSheet(btn_style)
        self.home_btn.setCursor(Qt.PointingHandCursor)
        self.home_btn.clicked.connect(lambda: self.go_to_path(""))
        
        self.path_btn = QPushButton(" /")
        self.path_btn.setIcon(self.icon_provider.back_icon)
        self.path_btn.setStyleSheet(btn_style + "text-align: left;")
        self.path_btn.setCursor(Qt.PointingHandCursor)
        self.path_btn.clicked.connect(self.go_back)
        
        nav_layout.addWidget(self.home_btn)
        nav_layout.addWidget(self.path_btn, 1)
        self.body_layout.addLayout(nav_layout)
        
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
            QHeaderView::section { background-color: transparent; color: #4D94FF; border: none; padding: 4px; font-weight: bold; }
        """
        
        # --- SIDEBAR ---
        self.sidebar = NoBranchTreeView()
        self.sidebar.setStyle(QStyleFactory.create("windows"))
        self.sidebar.setStyleSheet(tree_style)
        self.sidebar.setRootIsDecorated(False)
        self.sidebar.setHeaderHidden(True)
        self.sidebar.setItemDelegate(SciFiItemDelegate(show_arrow=False, enable_3d=False))
        
        self.qa_model = QStandardItemModel()
        self.sidebar.setModel(self.qa_model)
        self.sidebar.clicked.connect(self.on_sidebar_clicked)
        
        # --- ARBOL PRINCIPAL ---
        self.tree = NoBranchTreeView()
        self.tree.setStyle(QStyleFactory.create("windows"))
        self.tree.setStyleSheet(tree_style)
        self.tree.setItemDelegate(SciFiItemDelegate(show_arrow=True, enable_3d=True))
        self.tree.setHeaderHidden(True)
        self.tree.setRootIsDecorated(False)
        self.tree.setIndentation(15)
        
        self.fs_model = QFileSystemModel()
        self.fs_model.setRootPath("")
        self.fs_model.setIconProvider(self.icon_provider)
        
        self.tree.setModel(self.fs_model)
        self.tree.hideColumn(1) # Ocultar size
        self.tree.hideColumn(2) # Ocultar tipo
        self.tree.hideColumn(3) # Ocultar fecha
        self.tree.setSortingEnabled(False)
        self.tree.setHorizontalScrollBarPolicy(Qt.ScrollBarAlwaysOff)
        self.tree.setVerticalScrollMode(QTreeView.ScrollPerPixel)
        self.sidebar.setVerticalScrollMode(QTreeView.ScrollPerPixel)
        
        self.tree.setDropIndicatorShown(False)
        self.sidebar.setDropIndicatorShown(False)
        
        self.tree.setSelectionMode(QTreeView.ExtendedSelection)
        self.tree.setSelectionBehavior(QTreeView.SelectRows)
        
        self.clipboard_paths = []
        self.clipboard_op = None
        
        QShortcut(QKeySequence("Ctrl+C"), self.tree, self._do_copy)
        QShortcut(QKeySequence("Ctrl+X"), self.tree, self._do_cut)
        QShortcut(QKeySequence("Ctrl+V"), self.tree, self._do_paste)
        QShortcut(QKeySequence("Ctrl+D"), self.tree, self._do_delete_selected)
        
        self.fs_model.directoryLoaded.connect(lambda _: self._apply_column_layout())
        self.tree.clicked.connect(self.on_tree_clicked)
        self.tree.doubleClicked.connect(self.on_tree_double_clicked)
        self.tree.setContextMenuPolicy(Qt.CustomContextMenu)
        self.tree.customContextMenuRequested.connect(self.show_context_menu)
        
        self.splitter.addWidget(self.sidebar)
        self.splitter.addWidget(self.tree)
        self.splitter.setSizes([200, 550])
        
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
        if model is None: return
        header.setSectionResizeMode(0, QHeaderView.Stretch)

    def on_sidebar_clicked(self, index: QModelIndex):
        from PySide6.QtCore import QTimer
        path = self.qa_model.data(index, Qt.UserRole)
        QTimer.singleShot(0, lambda: self.go_to_path(path))

    def on_tree_clicked(self, index: QModelIndex):
        info = self.fs_model.fileInfo(index)
        if info.isDir():
            is_expanded = self.tree.isExpanded(index)
            self.tree.setExpanded(index, not is_expanded)
        else:
            path = self.fs_model.filePath(index)
            self.file_opened.emit(path)

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

    def go_to_path(self, path):
        idx = self.fs_model.index(path)
        self.tree.setRootIndex(idx)
        self._apply_column_layout()
        self.path_btn.setText(f" {path}" if path else " Este equipo")

    def highlight_file(self, path):
        idx = self.fs_model.index(path)
        if idx.isValid():
            self.tree.setCurrentIndex(idx)
            self.tree.scrollTo(idx)

    def show_context_menu(self, pos):
        if self.tree.model() != self.fs_model: return
        index = self.tree.indexAt(pos)
        target_dir = self.fs_model.filePath(self.tree.rootIndex())
        target_file = None
        
        menu = SciFiContextMenu(self.tree)
        
        if index.isValid():
            info = self.fs_model.fileInfo(index)
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
            
        menu.move(self.tree.viewport().mapToGlobal(pos))
        menu.show()

    def _duplicate_item(self, target_path):
        import shutil
        from PySide6.QtCore import QFileInfo
        info = QFileInfo(target_path)
        dir_path = info.absolutePath()
        base_name = info.completeBaseName()
        ext = info.suffix()
        ext_str = f".{ext}" if ext else ""
        
        new_name = f"{base_name} (Copia){ext_str}"
        new_path = os.path.join(dir_path, new_name)
        counter = 1
        while os.path.exists(new_path):
            new_name = f"{base_name} (Copia {counter}){ext_str}"
            new_path = os.path.join(dir_path, new_name)
            counter += 1
            
        try:
            if info.isDir():
                shutil.copytree(target_path, new_path)
            else:
                shutil.copy2(target_path, new_path)
        except Exception as e:
            self.show_error(f"Error al duplicar:\n{e}")

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
        if not self.clipboard_paths: return
        target_dir = self.fs_model.filePath(self.tree.rootIndex())
        selected = self._get_selected_paths()
        if len(selected) == 1 and QFileInfo(selected[0]).isDir():
            target_dir = selected[0]
            
        for path in self.clipboard_paths:
            name = os.path.basename(path)
            dest = os.path.join(target_dir, name)
            if path == dest: continue
            try:
                if self.clipboard_op == "copy":
                    if os.path.isdir(path): shutil.copytree(path, dest, dirs_exist_ok=True)
                    else: shutil.copy2(path, dest)
                elif self.clipboard_op == "cut":
                    shutil.move(path, dest)
            except Exception as e:
                self.show_error(f"Error pasting {name}:\n{e}")
        if self.clipboard_op == "cut":
            self.clipboard_paths = []
            self.clipboard_op = None

    def _do_delete_selected(self):
        paths = self._get_selected_paths()
        if not paths: return
        msg = f"¿Borrar {os.path.basename(paths[0])}?" if len(paths) == 1 else f"¿Borrar {len(paths)} elementos?"
        dialog = SciFiConfirmDialog(self, "CONFIRMAR", msg)
        if dialog.exec() == QDialog.Accepted:
            for path in paths:
                try:
                    info = QFileInfo(path)
                    if info.isDir(): shutil.rmtree(path)
                    else: os.remove(path)
                except Exception as e:
                    self.show_error(f"Error al borrar {os.path.basename(path)}: {str(e)}")

    def _create_folder(self, parent_dir):
        dialog = SciFiInputDialog(self, "NUEVA CARPETA", "Nombre de la carpeta:")
        if dialog.exec() == QDialog.Accepted:
            name = dialog.get_text()
            if name:
                if not QDir(parent_dir).mkdir(name): self.show_error("No se pudo crear la carpeta.")

    def _create_file(self, parent_dir):
        dialog = SciFiInputDialog(self, "NUEVO ARCHIVO", "Nombre del archivo:")
        if dialog.exec() == QDialog.Accepted:
            name = dialog.get_text()
            if name:
                file_path = os.path.join(parent_dir, name)
                try:
                    with open(file_path, 'w') as f: pass
                except Exception as e: self.show_error(f"Error al crear archivo: {e}")

    def _rename_item(self, target_path):
        from PySide6.QtCore import QFile
        old_name = os.path.basename(target_path)
        parent_dir = os.path.dirname(target_path)
        dialog = SciFiInputDialog(self, "RENOMBRAR", "Nuevo nombre:", default_text=old_name)
        if dialog.exec() == QDialog.Accepted:
            new_name = dialog.get_text()
            if new_name and new_name != old_name:
                new_path = os.path.join(parent_dir, new_name)
                if not QFile.rename(target_path, new_path): self.show_error("No se pudo renombrar.")

    def _delete_item(self, target_path):
        from PySide6.QtCore import QFile, QFileInfo
        dialog = SciFiConfirmDialog(self, "CONFIRMAR", f"¿Borrar {os.path.basename(target_path)}?")
        if dialog.exec() == QDialog.Accepted:
            info = QFileInfo(target_path)
            if info.isDir():
                if not QDir(target_path).removeRecursively(): self.show_error("No se pudo borrar la carpeta.")
            else:
                if not QFile.remove(target_path): self.show_error("No se pudo borrar el archivo.")
        
    def show_error(self, msg):
        dialog = SciFiConfirmDialog(self, "ERROR", msg)
        dialog.exec()
