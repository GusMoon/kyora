from PySide6.QtWidgets import QMainWindow, QWidget, QPushButton, QVBoxLayout, QHBoxLayout, QSpacerItem, QSizePolicy, QLabel
from PySide6.QtCore import Qt
from PySide6.QtGui import QPainter, QColor, QPen

# Componentes
from core.kioraUI.views.home.configuration import ConfigurationPanel
from core.kioraUI.views.home.explorer.treeFiles import ExplorerPanel
from core.kioraUI.views.home.explorer.filesType.image_viewer import ImageViewerPanel
from core.kioraUI.views.home.explorer.filesType.audio_viewer import AudioViewerPanel
from core.kioraUI.views.home.explorer.filesType.text_viewer import TextViewerPanel

class MainWindow(QMainWindow):
    def __init__(self, viewmodel):
        super().__init__()
        self.viewmodel = viewmodel
        
        self.setWindowTitle("Kiora")
        self.setWindowOpacity(0.97)
        self.setWindowFlag(Qt.FramelessWindowHint)
        
        self.central_widget = QWidget()
        self.setCentralWidget(self.central_widget)
        
        self.setup_ui()
        
        # Instanciar paneles externos
        self.settings_panel = ConfigurationPanel(self.central_widget)
        self.settings_panel.hide()
        
        self.explorer_panel = ExplorerPanel(self.central_widget)
        self.explorer_panel.hide()
        self.explorer_panel.file_opened.connect(self.handle_file_opened)
        
        # Instanciar visores de archivos
        self.image_viewer = ImageViewerPanel(self.central_widget)
        self.image_viewer.hide()
        
        self.audio_viewer = AudioViewerPanel(self.central_widget)
        self.audio_viewer.hide()
        
        self.text_viewer = TextViewerPanel(self.central_widget)
        self.text_viewer.hide()
        
        self.showMaximized()

    def setup_ui(self):
        main_layout = QVBoxLayout(self.central_widget)
        main_layout.setContentsMargins(0, 0, 0, 0)
        
        # --- TOP LAYOUT ---
        top_layout = QHBoxLayout()
        top_layout.setContentsMargins(20, 10, 10, 0)
        top_layout.setAlignment(Qt.AlignTop)
        
        spacer = QSpacerItem(40, 20, QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Minimum)
        top_layout.addItem(spacer)
        
        # --- INFO LAYOUT (RELOJ Y CLIMA) ---
        info_layout = QVBoxLayout()
        info_layout.setAlignment(Qt.AlignRight | Qt.AlignTop)
        info_layout.setSpacing(0)
        
        self.time_label = QLabel("00:00")
        self.time_label.setAlignment(Qt.AlignRight | Qt.AlignVCenter)
        self.time_label.setStyleSheet("color: #A31F34; font-size: 56px; font-weight: 300; font-family: 'Segoe UI Light', 'Helvetica Neue', sans-serif; letter-spacing: 2px; margin: 0; padding: 0;")
        
        self.date_label = QLabel("--/--/----")
        self.date_label.setAlignment(Qt.AlignRight | Qt.AlignVCenter)
        self.date_label.setStyleSheet("color: #A31F34; font-size: 14px; font-family: 'Segoe UI', sans-serif; text-transform: uppercase; letter-spacing: 1px; margin: 0; padding: 0;")
        
        self.weather_label = QLabel("Calculando coordenadas...")
        self.weather_label.setAlignment(Qt.AlignRight | Qt.AlignVCenter)
        self.weather_label.setStyleSheet("color: #A31F34; font-size: 12px; font-family: 'Segoe UI', sans-serif; margin: 0; padding: 0;")
        
        info_layout.addWidget(self.time_label)
        info_layout.addWidget(self.date_label)
        info_layout.addWidget(self.weather_label)
        
        top_layout.addLayout(info_layout)
        top_layout.addSpacing(15)
        
        # --- BOTONES DE CONTROL ---
        btn_layout = QVBoxLayout()
        btn_layout.setAlignment(Qt.AlignTop)
        btn_layout.setSpacing(10)
        
        # Botón Cerrar
        self.close_btn = QPushButton("✕")
        self.close_btn.setFixedSize(25, 25)
        self.close_btn.setCursor(Qt.PointingHandCursor)
        self.close_btn.setStyleSheet("""
            QPushButton { background-color: transparent; color: #A31F34; font-weight: bold; font-size: 12px; border: 1px solid #A31F34; border-radius: 3px; }
            QPushButton:hover { background-color: #A31F34; color: #1E1E1E; }
            QPushButton:pressed { background-color: #7A1727; border: 1px solid #7A1727; }
        """)
        self.close_btn.clicked.connect(self.close)
        
        # Botón Configuración
        self.settings_btn = QPushButton("⚙")
        self.settings_btn.setFixedSize(25, 25)
        self.settings_btn.setCursor(Qt.PointingHandCursor)
        self.settings_btn.setStyleSheet("""
            QPushButton { background-color: transparent; color: #A31F34; font-size: 16px; border: 1px solid #A31F34; border-radius: 3px; font-family: 'Segoe UI Symbol', 'Arial'; }
            QPushButton:hover { background-color: #A31F34; color: #1E1E1E; }
            QPushButton:pressed { background-color: #7A1727; border: 1px solid #7A1727; }
        """)
        self.settings_btn.clicked.connect(self.toggle_settings)

        # Botón Archivos (File Explorer)
        self.explorer_btn = QPushButton("🖿")
        self.explorer_btn.setFixedSize(25, 25)
        self.explorer_btn.setCursor(Qt.PointingHandCursor)
        self.explorer_btn.setStyleSheet("""
            QPushButton { background-color: transparent; color: #A31F34; font-size: 15px; border: 1px solid #A31F34; border-radius: 3px; font-family: 'Segoe UI Symbol', 'Arial'; }
            QPushButton:hover { background-color: #A31F34; color: #1E1E1E; }
            QPushButton:pressed { background-color: #7A1727; border: 1px solid #7A1727; }
        """)
        self.explorer_btn.clicked.connect(self.toggle_explorer)
        
        btn_layout.addWidget(self.close_btn)
        btn_layout.addWidget(self.settings_btn)
        btn_layout.addWidget(self.explorer_btn)
        
        top_layout.addLayout(btn_layout)
        main_layout.addLayout(top_layout)
        main_layout.addStretch()
        
        # --- CONEXIÓN AL VIEWMODEL ---
        self.viewmodel.time_updated.connect(self.time_label.setText)
        self.viewmodel.date_updated.connect(self.date_label.setText)
        self.viewmodel.weather_updated.connect(self.update_weather_label)

    def toggle_settings(self):
        if self.settings_panel.isHidden():
            self.settings_panel.show()
            self.settings_panel.raise_()
        else:
            self.settings_panel.hide()

    def toggle_explorer(self):
        if self.explorer_panel.isHidden():
            self.explorer_panel.show()
            self.explorer_panel.raise_()
        else:
            self.explorer_panel.hide()
            
    def resizeEvent(self, event):
        super().resizeEvent(event)
        # Centrar paneles de manera individual si no los ha movido el usuario
        for panel in [getattr(self, 'settings_panel', None), getattr(self, 'explorer_panel', None), 
                      getattr(self, 'image_viewer', None), getattr(self, 'audio_viewer', None), getattr(self, 'text_viewer', None)]:
            if panel and not getattr(panel, 'user_moved', False):
                x = (self.width() - panel.width()) // 2
                y = (self.height() - panel.height()) // 2
                panel.move(x, y)
                
    def handle_file_opened(self, path):
        ext = path.split('.')[-1].lower() if '.' in path else ''
        
        image_exts = ['png', 'jpg', 'jpeg', 'gif', 'bmp', 'webp']
        audio_exts = ['mp3', 'wav', 'ogg', 'flac']
        
        if ext in image_exts:
            self.image_viewer.load_image(path)
            self.image_viewer.show()
            self.image_viewer.raise_()
        elif ext in audio_exts:
            self.audio_viewer.load_audio(path)
            self.audio_viewer.show()
            self.audio_viewer.raise_()
        else:
            # Fallback a texto para codigo y otros archivos
            self.text_viewer.load_text(path)
            self.text_viewer.show()
            self.text_viewer.raise_()
            
    def update_weather_label(self, loc, temp):
        self.weather_label.setText(f"{loc}  |  {temp}")
        
    def paintEvent(self, event):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)
        
        bg_color = QColor("#1E1E1E")
        painter.fillRect(self.rect(), bg_color)
        
        dot_color = QColor("#3A2326")
        dot_color.setAlpha(100)
        pen = QPen(dot_color)
        pen.setWidth(2)
        painter.setPen(pen)
        
        spacing = 15
        for x in range(0, self.width(), spacing):
            for y in range(0, self.height(), spacing):
                painter.drawPoint(x, y)
        painter.end()
