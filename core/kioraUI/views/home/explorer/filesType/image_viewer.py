from PySide6.QtWidgets import QLabel, QGraphicsView, QGraphicsScene, QGraphicsPixmapItem, QPushButton
from PySide6.QtGui import QPixmap, QPainter, QWheelEvent
from PySide6.QtCore import Qt, QRectF
from core.kioraUI.views.global_ui.viewer_base import SciFiViewerBase

class InteractiveGraphicsView(QGraphicsView):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setDragMode(QGraphicsView.ScrollHandDrag)
        self.setTransformationAnchor(QGraphicsView.AnchorUnderMouse)
        self.setResizeAnchor(QGraphicsView.AnchorUnderMouse)
        self.setVerticalScrollBarPolicy(Qt.ScrollBarAlwaysOff)
        self.setHorizontalScrollBarPolicy(Qt.ScrollBarAlwaysOff)
        self.setBackgroundBrush(Qt.transparent)
        self.setFrameShape(QGraphicsView.NoFrame)
        self.scene = QGraphicsScene(self)
        self.setScene(self.scene)
        self.pixmap_item = QGraphicsPixmapItem()
        self.scene.addItem(self.pixmap_item)
        
        self.original_pixmap = None

    def load_pixmap(self, pixmap):
        self.original_pixmap = pixmap
        self.pixmap_item.setPixmap(pixmap)
        self.scene.setSceneRect(QRectF(pixmap.rect()))
        self.reset_zoom()

    def wheelEvent(self, event: QWheelEvent):
        zoom_in_factor = 1.15
        zoom_out_factor = 1.0 / zoom_in_factor

        if event.angleDelta().y() > 0:
            zoom_factor = zoom_in_factor
        else:
            zoom_factor = zoom_out_factor

        self.scale(zoom_factor, zoom_factor)
        
    def reset_zoom(self):
        if self.original_pixmap:
            self.resetTransform()
            self.fitInView(self.scene.sceneRect(), Qt.KeepAspectRatio)

class ImageViewerPanel(SciFiViewerBase):
    def __init__(self, parent=None):
        super().__init__(parent, "IMAGE VIEWER SEQUENCE")
        self.resize(800, 650)
        
        self.view = InteractiveGraphicsView()
        self.set_body_widget(self.view)
        
        self.header.hide()
        self.close_btn.setParent(self)
        self.close_btn.setStyleSheet("""
            QPushButton { background-color: rgba(22, 22, 22, 0.8); color: #FFFFFF; font-weight: bold; border: 1px solid #4D94FF; }
            QPushButton:hover { background-color: #4D94FF; }
        """)
        self.close_btn.show()
        
        # Dimensions overlay
        self.info_label = QLabel("0x0", self.body_frame)
        self.info_label.setStyleSheet("color: #FFFFFF; background-color: rgba(22, 22, 22, 0.85); font-family: 'Consolas'; font-size: 12px; padding: 6px; border: 1px solid #182533;")
        
        # Reset zoom button overlay
        self.reset_btn = QPushButton("[ RESET ZOOM ]", self.body_frame)
        self.reset_btn.setCursor(Qt.PointingHandCursor)
        self.reset_btn.setStyleSheet("""
            QPushButton { background-color: rgba(58, 35, 38, 0.85); color: #FFFFFF; font-family: 'Consolas'; font-size: 11px; border: 1px solid #4D94FF; padding: 6px; }
            QPushButton:hover { background-color: #4D94FF; }
        """)
        self.reset_btn.clicked.connect(self.view.reset_zoom)
        
    def load_image(self, path):
        pixmap = QPixmap(path)
        if not pixmap.isNull():
            self.view.load_pixmap(pixmap)
            self.info_label.setText(f"{pixmap.width()} x {pixmap.height()} PX")
            self.info_label.adjustSize()
            
            # Adapt container to image size
            max_w = self.parent().width() * 0.85 if self.parent() else 1000
            max_h = self.parent().height() * 0.85 if self.parent() else 800
            
            target_w = pixmap.width() + 40
            target_h = pixmap.height() + 40
            
            if target_w > max_w:
                ratio = max_w / target_w
                target_w = max_w
                target_h *= ratio
                
            if target_h > max_h:
                ratio = max_h / target_h
                target_h = max_h
                target_w *= ratio
                
            self.resize(int(target_w), int(target_h))
            
            # Recenter
            if self.parent():
                x = (self.parent().width() - self.width()) // 2
                y = (self.parent().height() - self.height()) // 2
                self.move(x, y)
                
        else:
            self.info_label.setText("ERROR LOAD")
            self.info_label.adjustSize()
            
        # Ocultar nombre de archivo tal como pidio el usuario
        self.title_label.setText("IMAGE VIEWER")
        
    def resizeEvent(self, event):
        super().resizeEvent(event)
        # Position overlays in bottom right
        w = self.body_frame.width()
        h = self.body_frame.height()
        
        pad = 25
        self.info_label.move(w - self.info_label.width() - pad, h - self.info_label.height() - pad)
        self.reset_btn.move(w - self.reset_btn.width() - pad, self.info_label.y() - self.reset_btn.height() - 5)
        
        self.close_btn.move(self.width() - self.close_btn.width() - 5, 5)
        self.close_btn.raise_()
        
        # Make the image adapt continuously as the container resizes
        if self.view.original_pixmap:
            self.view.resetTransform()
            self.view.fitInView(self.view.scene.sceneRect(), Qt.KeepAspectRatio)
