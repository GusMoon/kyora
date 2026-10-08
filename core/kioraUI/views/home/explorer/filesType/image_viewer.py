from PySide6.QtWidgets import QGraphicsView, QGraphicsScene, QGraphicsPixmapItem, QPushButton, QWidget, QLabel
from PySide6.QtGui import QPixmap, QWheelEvent
from PySide6.QtCore import Qt, QRectF, QPoint

class SimpleGraphicsView(QGraphicsView):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setTransformationAnchor(QGraphicsView.NoAnchor)
        self.setResizeAnchor(QGraphicsView.NoAnchor)
        self.setVerticalScrollBarPolicy(Qt.ScrollBarAlwaysOff)
        self.setHorizontalScrollBarPolicy(Qt.ScrollBarAlwaysOff)
        self.setBackgroundBrush(Qt.transparent)
        self.setFrameShape(QGraphicsView.NoFrame)
        self.setStyleSheet("background: transparent; border: none;")
        self.setMouseTracking(True)
        
        self.scene = QGraphicsScene(self)
        self.setScene(self.scene)
        self.pixmap_item = QGraphicsPixmapItem()
        self.scene.addItem(self.pixmap_item)
        
        self._is_panning = False
        self._pan_start = QPoint()

    def load_pixmap(self, pixmap):
        self.pixmap_item.setPixmap(pixmap)
        self.scene.setSceneRect(QRectF(pixmap.rect()))
        self.resetTransform()
        self.fitInView(self.scene.sceneRect(), Qt.KeepAspectRatio)

    def wheelEvent(self, event: QWheelEvent):
        zoom_in_factor = 1.15
        zoom_out_factor = 1.0 / zoom_in_factor

        if event.angleDelta().y() > 0:
            zoom_factor = zoom_in_factor
        else:
            zoom_factor = zoom_out_factor

        pos = event.position().toPoint()
        old_scene_pos = self.mapToScene(pos)
        
        self.scale(zoom_factor, zoom_factor)
        
        new_scene_pos = self.mapToScene(pos)
        delta = new_scene_pos - old_scene_pos
        self.translate(delta.x(), delta.y())
        
        event.accept()

    def mouseDoubleClickEvent(self, event):
        if event.button() == Qt.LeftButton:
            pos = event.position().toPoint()
            old_scene_pos = self.mapToScene(pos)
            
            self.scale(2.0, 2.0)
            
            new_scene_pos = self.mapToScene(pos)
            delta = new_scene_pos - old_scene_pos
            self.translate(delta.x(), delta.y())
            event.accept()
        else:
            event.ignore()

    def mousePressEvent(self, event):
        if event.button() == Qt.RightButton:
            self._is_panning = True
            self._pan_start = event.pos()
            self.setCursor(Qt.ClosedHandCursor)
            event.accept()
        else:
            event.ignore()

    def mouseMoveEvent(self, event):
        if self._is_panning:
            delta = event.pos() - self._pan_start
            self._pan_start = event.pos()
            
            h_bar = self.horizontalScrollBar()
            v_bar = self.verticalScrollBar()
            h_bar.setValue(h_bar.value() - delta.x())
            v_bar.setValue(v_bar.value() - delta.y())
            event.accept()
        else:
            event.ignore()

    def mouseReleaseEvent(self, event):
        if event.button() == Qt.RightButton:
            self._is_panning = False
            self.unsetCursor()
            event.accept()
        else:
            event.ignore()

class ImageViewerPanel(QWidget):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowFlags(Qt.FramelessWindowHint)
        self.hide()
        
        self.view = SimpleGraphicsView(self)
        self.view.setStyleSheet("border: 1px solid #4D94FF; background-color: #0A1118;")
        
        self.close_btn = QPushButton("✕", self)
        self.close_btn.setFixedSize(24, 24)
        self.close_btn.setCursor(Qt.PointingHandCursor)
        self.close_btn.setStyleSheet("""
            QPushButton { background-color: rgba(10, 17, 24, 0.8); color: #FFFFFF; font-weight: bold; border: 1px solid #4D94FF; }
            QPushButton:hover { background-color: #4D94FF; color: #0A1118; }
        """)
        self.close_btn.clicked.connect(self.hide)
        
        self.rotate_btn = QPushButton("⟳", self)
        self.rotate_btn.setFixedSize(24, 24)
        self.rotate_btn.setCursor(Qt.PointingHandCursor)
        self.rotate_btn.setStyleSheet("""
            QPushButton { background-color: rgba(10, 17, 24, 0.8); color: #FFFFFF; font-weight: bold; border: 1px solid #4D94FF; }
            QPushButton:hover { background-color: #4D94FF; color: #0A1118; }
        """)
        self.rotate_btn.clicked.connect(self._rotate_image)
        
        self.reset_btn = QPushButton("RESET", self)
        self.reset_btn.setFixedSize(45, 24)
        self.reset_btn.setCursor(Qt.PointingHandCursor)
        self.reset_btn.setStyleSheet("""
            QPushButton { background-color: rgba(10, 17, 24, 0.8); color: #FFFFFF; font-weight: bold; border: 1px solid #4D94FF; font-family: 'Space Grotesk'; font-size: 11px;}
            QPushButton:hover { background-color: #4D94FF; color: #0A1118; }
        """)
        self.reset_btn.clicked.connect(self.reset_view)
        
        self.info_label = QLabel("", self)
        self.info_label.setStyleSheet("color: #FFFFFF; background-color: rgba(10, 17, 24, 0.85); font-family: 'Space Grotesk'; font-size: 11px; padding: 4px; border: 1px solid #4D94FF;")
        
        self._drag_pos = None
        self._is_resizing = False
        self._resize_dir = None
        self.aspect_ratio = 1.0
        self.default_size = (800, 600)
        
        self.setMouseTracking(True)

    def load_image(self, path):
        pixmap = QPixmap(path)
        if pixmap.isNull():
            self.hide()
            return
            
        self.info_label.setText(f"{pixmap.width()}x{pixmap.height()}")
        self.info_label.adjustSize()
        
        max_w = self.parent().width() * 0.50 if self.parent() else 800
        max_h = self.parent().height() * 0.50 if self.parent() else 600
        
        tw, th = pixmap.width(), pixmap.height()
        if th > 0:
            self.aspect_ratio = tw / th
        
        if tw > max_w or th > max_h:
            ratio = min(max_w / tw, max_h / th)
            tw = int(tw * ratio)
            th = int(th * ratio)
            
        self.default_size = (tw, th)
        self.resize(tw, th)
        self.view.load_pixmap(pixmap)
        
        if self.parent():
            x = (self.parent().width() - tw) // 2
            y = (self.parent().height() - th) // 2
            self.move(x, y)
            
        self.show()
        self.raise_()

    def _rotate_image(self):
        self.view.rotate(90)
        w, h = self.width(), self.height()
        self.aspect_ratio = 1.0 / self.aspect_ratio
        
        cx = self.x() + w // 2
        cy = self.y() + h // 2
        
        self.resize(h, w)
        self.move(cx - h // 2, cy - w // 2)

    def reset_view(self):
        w, h = self.default_size
        self.aspect_ratio = w / h if h > 0 else 1.0
        self.resize(w, h)
        if self.parent():
            x = (self.parent().width() - w) // 2
            y = (self.parent().height() - h) // 2
            self.move(x, y)
        self.view.resetTransform()
        self.view.fitInView(self.view.scene.sceneRect(), Qt.KeepAspectRatio)
        self.view.rotation_angle = 0
        self.view.pixmap_item.setRotation(0)

    def resizeEvent(self, event):
        super().resizeEvent(event)
        w, h = self.width(), self.height()
        self.view.setGeometry(0, 0, w, h)
        self.close_btn.move(w - self.close_btn.width() - 5, 5)
        self.rotate_btn.move(self.close_btn.x() - self.rotate_btn.width() - 5, 5)
        self.reset_btn.move(self.rotate_btn.x() - self.reset_btn.width() - 5, 5)
        self.info_label.move(w - self.info_label.width() - 5, h - self.info_label.height() - 5)
        
        if self._is_resizing:
            self.view.fitInView(self.view.scene.sceneRect(), Qt.KeepAspectRatio)

    def _get_resize_dir(self, pos):
        x, y = pos.x(), pos.y()
        w, h = self.width(), self.height()
        margin = 25
        
        dir_y = ""
        dir_x = ""
        
        if y < margin: dir_y = "top"
        elif y > h - margin: dir_y = "bottom"
            
        if x < margin: dir_x = "left"
        elif x > w - margin: dir_x = "right"
            
        if dir_y and dir_x: return f"{dir_y}-{dir_x}"
        return None

    def mousePressEvent(self, event):
        self.raise_()
        if event.button() == Qt.LeftButton:
            direction = self._get_resize_dir(event.pos())
            if direction:
                self._is_resizing = True
                self._resize_dir = direction
                self._drag_start_pos = event.globalPosition().toPoint()
                self._drag_start_geom = self.geometry()
            else:
                self._drag_pos = event.globalPosition().toPoint()
            event.accept()

    def mouseMoveEvent(self, event):
        if not (event.buttons() & Qt.LeftButton):
            direction = self._get_resize_dir(event.pos())
            if direction in ("top-left", "bottom-right"):
                self.setCursor(Qt.SizeFDiagCursor)
            elif direction in ("top-right", "bottom-left"):
                self.setCursor(Qt.SizeBDiagCursor)
            else:
                self.unsetCursor()
            return
            
        if self._is_resizing:
            new_pos = event.globalPosition().toPoint()
            diff = new_pos - self._drag_start_pos
            rect = self._drag_start_geom
            
            new_x = rect.x()
            new_y = rect.y()
            
            if "left" in self._resize_dir:
                new_w = max(150, rect.width() - diff.x())
                new_h = int(new_w / self.aspect_ratio)
                new_x = rect.x() + (rect.width() - new_w)
            elif "right" in self._resize_dir:
                new_w = max(150, rect.width() + diff.x())
                new_h = int(new_w / self.aspect_ratio)
            else:
                return
                
            if "top" in self._resize_dir:
                new_y = rect.y() + (rect.height() - new_h)
                
            self.setGeometry(new_x, new_y, new_w, new_h)
            event.accept()
        elif self._drag_pos is not None:
            new_pos = event.globalPosition().toPoint()
            diff = new_pos - self._drag_pos
            self._drag_pos = new_pos
            
            next_pos = self.pos() + diff
            if self.parent():
                parent_rect = self.parent().rect()
                px = max(0, min(next_pos.x(), parent_rect.width() - self.width()))
                py = max(0, min(next_pos.y(), parent_rect.height() - self.height()))
                self.move(px, py)
            else:
                self.move(next_pos)
            event.accept()

    def mouseReleaseEvent(self, event):
        if event.button() == Qt.LeftButton:
            self._is_resizing = False
            self._resize_dir = None
            self._drag_pos = None
            self.unsetCursor()
            event.accept()
