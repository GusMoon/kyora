from PySide6.QtWidgets import QMainWindow, QWidget, QPushButton, QVBoxLayout, QHBoxLayout, QSpacerItem, QSizePolicy, QLabel
from PySide6.QtCore import Qt
from PySide6.QtGui import QPainter, QColor, QPen

# Componentes
from core.kioraUI.views.home.configuration import ConfigurationPanel
from core.kioraUI.views.home.explorer.treeFiles import ExplorerPanel
from core.kioraUI.views.home.explorer.filesType.image_viewer import ImageViewerPanel
from core.kioraUI.views.home.explorer.filesType.audio_viewer import AudioPlayerWidget
from core.kioraUI.views.home.explorer.filesType.text_viewer import TextViewerPanel
from core.kioraUI.views.home.explorer.filesType.pdf_viewer import PdfViewerPanel

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
        self.explorer_panel.move(0, 0) # Fixed position top-left
        self.explorer_panel.file_opened.connect(self.handle_file_opened)
        
        # Instanciar visores de archivos
        self.image_viewer = ImageViewerPanel(self.central_widget)
        self.image_viewer.hide()
        
        self.audio_player = AudioPlayerWidget(self.central_widget)
        self.audio_player.hide()
        
        self.text_viewer = TextViewerPanel(self.central_widget)
        self.text_viewer.hide()
        
        self.pdf_viewer = PdfViewerPanel(self.central_widget)
        self.pdf_viewer.hide()
        
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
        self.time_label.setStyleSheet("color: #4D94FF; font-size: 56px; font-weight: 300; font-family: 'Segoe UI Light', 'Helvetica Neue', sans-serif; letter-spacing: 2px; margin: 0; padding: 0;")
        
        self.date_label = QLabel("--/--/----")
        self.date_label.setAlignment(Qt.AlignRight | Qt.AlignVCenter)
        self.date_label.setStyleSheet("color: #4D94FF; font-size: 14px; font-family: 'Segoe UI', sans-serif; text-transform: uppercase; letter-spacing: 1px; margin: 0; padding: 0;")
        
        self.weather_label = QLabel("Calculando coordenadas...")
        self.weather_label.setAlignment(Qt.AlignRight | Qt.AlignVCenter)
        self.weather_label.setStyleSheet("color: #4D94FF; font-size: 12px; font-family: 'Segoe UI', sans-serif; margin: 0; padding: 0;")
        
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
            QPushButton { background-color: transparent; color: #4D94FF; font-weight: bold; font-size: 12px; border: 1px solid #4D94FF; border-radius: 3px; }
            QPushButton:hover { background-color: #4D94FF; color: #0A1118; }
            QPushButton:pressed { background-color: #80BFFF; border: 1px solid #80BFFF; }
        """)
        self.close_btn.clicked.connect(self.close)
        
        # Botón Configuración
        self.settings_btn = QPushButton("⚙")
        self.settings_btn.setFixedSize(25, 25)
        self.settings_btn.setCursor(Qt.PointingHandCursor)
        self.settings_btn.setStyleSheet("""
            QPushButton { background-color: transparent; color: #4D94FF; font-size: 16px; border: 1px solid #4D94FF; border-radius: 3px; font-family: 'Segoe UI Symbol', 'Arial'; }
            QPushButton:hover { background-color: #4D94FF; color: #0A1118; }
            QPushButton:pressed { background-color: #80BFFF; border: 1px solid #80BFFF; }
        """)
        self.settings_btn.clicked.connect(self.toggle_settings)

        # Botón Archivos (File Explorer)
        self.explorer_btn = QPushButton("🖿")
        self.explorer_btn.setFixedSize(25, 25)
        self.explorer_btn.setCursor(Qt.PointingHandCursor)
        self.explorer_btn.setStyleSheet("""
            QPushButton { background-color: transparent; color: #4D94FF; font-size: 15px; border: 1px solid #4D94FF; border-radius: 3px; font-family: 'Segoe UI Symbol', 'Arial'; }
            QPushButton:hover { background-color: #4D94FF; color: #0A1118; }
            QPushButton:pressed { background-color: #80BFFF; border: 1px solid #80BFFF; }
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
        for panel in [getattr(self, 'settings_panel', None), 
                      getattr(self, 'image_viewer', None), getattr(self, 'text_viewer', None),
                      getattr(self, 'pdf_viewer', None)]:
            if panel and not getattr(panel, 'user_moved', False):
                x = (self.width() - panel.width()) // 2
                y = (self.height() - panel.height()) // 2
                panel.move(x, y)
                
        if hasattr(self, 'audio_player') and self.audio_player:
            self.audio_player.move(20, self.height() - self.audio_player.height() - 20)
                
    def handle_file_opened(self, path):
        ext = path.split('.')[-1].lower() if '.' in path else ''
        
        image_exts = ['png', 'jpg', 'jpeg', 'gif', 'bmp', 'webp']
        audio_exts = ['mp3', 'wav', 'ogg', 'flac']
        pdf_exts = ['pdf']
        
        if ext in image_exts:
            self.image_viewer.load_image(path)
            self.image_viewer.show()
            self.image_viewer.raise_()
        elif ext in audio_exts:
            self.audio_player.load_audio(path)
            self.audio_player.show()
            self.audio_player.raise_()
            self.audio_player.move(20, self.height() - self.audio_player.height() - 20)
        elif ext in pdf_exts:
            self.pdf_viewer.load_pdf(path)
            self.pdf_viewer.show()
            self.pdf_viewer.raise_()
        else:
            # Fallback a texto para codigo y otros archivos (incluyendo docx)
            self.text_viewer.load_text(path)
            self.text_viewer.show()
            self.text_viewer.raise_()
            
    def update_weather_label(self, loc, temp):
        self.weather_label.setText(f"{loc}  |  {temp}")
        
    def paintEvent(self, event):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)
        
        w = self.width()
        h = self.height()
        
        # 1. Base Background (No negro intenso)
        bg_color = QColor("#0A1118") 
        painter.fillRect(self.rect(), bg_color)
        
        # 2. Puntos (Más visibles)
        dot_color = QColor("#4D94FF") 
        dot_color.setAlpha(60) 
        pen = QPen(dot_color)
        pen.setWidth(2)
        painter.setPen(pen)
        
        spacing = 20
        for x in range(0, w, spacing):
            for y in range(0, h, spacing):
                painter.drawPoint(x, y)
        
        # 3. Bloques sutiles (Menos y más transparentes)
        blocks = [
            (0.2, 0.3, 0.15, 0.4, "#182533", 30),
            (0.45, 0.15, 0.3, 0.6, "#4D94FF", 10),
            (0.25, 0.7, 0.1, 0.2, "#4D94FF", 15)
        ]
        
        painter.setPen(Qt.NoPen)
        for bx, by, bw, bh, col, alpha in blocks:
            c = QColor(col)
            c.setAlpha(alpha)
            painter.setBrush(QColor(c))
            painter.drawRect(int(w * bx), int(h * by), int(w * bw), int(h * bh))
            
        # 4. Líneas más sencillas
        h_lines = [0.25, 0.75]
        v_lines = [0.35, 0.75]
        
        line_color = QColor("#182533")
        line_color.setAlpha(150)
        painter.setPen(QPen(line_color, 1, Qt.SolidLine))
        
        for y_pct in h_lines:
            painter.drawLine(0, int(h * y_pct), w, int(h * y_pct))
            
        for x_pct in v_lines:
            painter.drawLine(int(w * x_pct), 0, int(w * x_pct), h)
            
        painter.end()
