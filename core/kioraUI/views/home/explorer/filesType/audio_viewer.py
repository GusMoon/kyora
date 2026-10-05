from PySide6.QtWidgets import QLabel, QPushButton, QVBoxLayout, QWidget
from PySide6.QtCore import Qt
from core.kioraUI.views.global_ui.viewer_base import SciFiViewerBase

class AudioViewerPanel(SciFiViewerBase):
    def __init__(self, parent=None):
        super().__init__(parent, "AUDIO FREQUENCY VIEWER")
        self.setFixedSize(400, 200)
        
        container = QWidget()
        layout = QVBoxLayout(container)
        
        self.info_label = QLabel("NO AUDIO LOADED.")
        self.info_label.setAlignment(Qt.AlignCenter)
        self.info_label.setStyleSheet("color: #A31F34; font-family: 'Segoe UI'; font-size: 14px;")
        
        self.play_btn = QPushButton("▶ PLAY SEQUENCE")
        self.play_btn.setCursor(Qt.PointingHandCursor)
        self.play_btn.setStyleSheet("""
            QPushButton { background-color: #3A2326; color: #FFFFFF; font-weight: bold; border: 1px solid #A31F34; padding: 10px; font-family: 'Segoe UI Symbol'; }
            QPushButton:hover { background-color: #A31F34; }
        """)
        
        layout.addWidget(self.info_label)
        layout.addWidget(self.play_btn)
        
        self.set_body_widget(container)
        
    def load_audio(self, path):
        filename = path.replace("\\", "/").split('/')[-1]
        self.info_label.setText(f"LOADED:\n{filename}")
        self.title_label.setText(f"AUDIO VIEWER: {filename.upper()}")
