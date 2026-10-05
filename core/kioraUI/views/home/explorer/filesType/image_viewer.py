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
        self.setFixedSize(800, 650)
        
        self.view = InteractiveGraphicsView()
        self.set_body_widget(self.view)
        
        # Dimensions overlay
        self.info_label = QLabel("0x0", self.body_frame)
        self.info_label.setStyleSheet("color: #FFFFFF; background-color: rgba(22, 22, 22, 0.85); font-family: 'Consolas'; font-size: 12px; padding: 6px; border: 1px solid #3A2326;")
        
        # Reset zoom button overlay
        self.reset_btn = QPushButton("[ RESET ZOOM ]", self.body_frame)
        self.reset_btn.setCursor(Qt.PointingHandCursor)
        self.reset_btn.setStyleSheet("""
            QPushButton { background-color: rgba(58, 35, 38, 0.85); color: #FFFFFF; font-family: 'Consolas'; font-size: 11px; border: 1px solid #A31F34; padding: 6px; }
            QPushButton:hover { background-color: #A31F34; }
        """)
        self.reset_btn.clicked.connect(self.view.reset_zoom)
        
    def load_image(self, path):
        pixmap = QPixmap(path)
        if not pixmap.isNull():
            self.view.load_pixmap(pixmap)
            self.info_label.setText(f"{pixmap.width()} x {pixmap.height()} PX")
            self.info_label.adjustSize()
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
