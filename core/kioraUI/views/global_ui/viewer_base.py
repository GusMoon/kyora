from PySide6.QtWidgets import QFrame, QVBoxLayout, QHBoxLayout, QLabel, QPushButton, QWidget
from PySide6.QtCore import Qt

class SciFiViewerBase(QFrame):
    def __init__(self, parent=None, title="VIEWER"):
        super().__init__(parent)
        self.user_moved = False
        
        self.setStyleSheet("""
            QFrame { background-color: #161616; border: 1px solid #A31F34; }
        """)
        
        self.main_layout = QVBoxLayout(self)
        self.main_layout.setContentsMargins(0, 0, 0, 0)
        self.main_layout.setSpacing(0)
        
        # --- HEADER ---
        self.header = QFrame()
        self.header.setFixedHeight(35)
        self.header.setStyleSheet("QFrame { background-color: #A31F34; border: none; border-bottom: 2px solid #7A1727; }")
        
        header_layout = QHBoxLayout(self.header)
        header_layout.setContentsMargins(15, 0, 10, 0)
        
        self.title_label = QLabel(title)
        self.title_label.setStyleSheet("QLabel { color: #FFFFFF; font-family: 'Segoe UI', sans-serif; font-size: 11px; font-weight: 800; letter-spacing: 2px; border: none; background: transparent; }")
        header_layout.addWidget(self.title_label)
        header_layout.addStretch()
        
        self.close_btn = QPushButton("✕")
        self.close_btn.setFixedSize(24, 24)
        self.close_btn.setCursor(Qt.PointingHandCursor)
        self.close_btn.setStyleSheet("QPushButton { background-color: transparent; color: #FFFFFF; font-weight: bold; font-size: 14px; border: none; } QPushButton:hover { color: #161616; }")
        self.close_btn.clicked.connect(self.hide)
        
        header_layout.addWidget(self.close_btn)
        self.main_layout.addWidget(self.header)
        
        # --- BODY CONTAINER ---
        self.body_frame = QFrame()
        self.body_frame.setStyleSheet("border: none; background-color: transparent;")
        self.body_layout = QVBoxLayout(self.body_frame)
        self.body_layout.setContentsMargins(20, 20, 20, 20)
        
        self.main_layout.addWidget(self.body_frame)

    def set_body_widget(self, widget):
        self.body_layout.addWidget(widget)

    # --- DRAG LOGIC ---
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
