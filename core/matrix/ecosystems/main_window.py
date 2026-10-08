from PySide6.QtWidgets import QMainWindow, QWidget, QPushButton, QVBoxLayout, QHBoxLayout, QGridLayout, QSpacerItem, QSizePolicy, QLabel
from PySide6.QtCore import Qt
from PySide6.QtGui import QPainter, QColor, QPen

# Componentes
from core.matrix.ecosystems.configuration import ConfigurationPanel
from core.matrix.ecosystems.explorer.treeFiles import ExplorerPanel
from core.matrix.ecosystems.youtube_music import YoutubeMusicPanel
from core.matrix.ecosystems.explorer.filesType.image_viewer import ImageViewerPanel
from core.matrix.ecosystems.explorer.filesType.audio_viewer import AudioPlayerWidget
from core.matrix.ecosystems.explorer.filesType.text_viewer import TextViewerPanel
from core.matrix.ecosystems.explorer.filesType.pdf_viewer import PdfViewerPanel
from core.matrix.ecosystems.explorer.filesType.task_viewer import TaskViewerPanel
from core.matrix.ecosystems.motherBoard.top_navigation_bar import TopNavigationBar

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
        self.explorer_panel.move(0, 50) # Fixed position left, below top bar
        self.explorer_panel.file_opened.connect(self.handle_file_opened)
        
        self.youtube_panel = YoutubeMusicPanel(self.central_widget)
        self.youtube_panel.hide()
        
        # Instanciar visores de archivos
        self.image_viewer = ImageViewerPanel(self.central_widget)
        self.image_viewer.hide()
        
        self.audio_player = AudioPlayerWidget(self.central_widget)
        self.audio_player.hide()
        self.audio_player.song_changed.connect(self.explorer_panel.highlight_file)
        
        self.text_viewer = TextViewerPanel(self.central_widget)
        self.text_viewer.hide()
        
        self.pdf_viewer = PdfViewerPanel(self.central_widget)
        self.pdf_viewer.hide()
        
        self.task_viewer = TaskViewerPanel(self.central_widget)
        self.task_viewer.hide()
        
        self.handle_nav_selection("EXPLORER")
        self.showMaximized()

    def setup_ui(self):
        main_layout = QVBoxLayout(self.central_widget)
        main_layout.setContentsMargins(0, 0, 0, 0)
        
        # --- TOP LAYOUT ---
        top_container = QWidget()
        top_layout = QGridLayout(top_container)
        top_layout.setContentsMargins(0, 15, 10, 0)
        
        self.nav_bar = TopNavigationBar(top_container)
        self.nav_bar.option_selected.connect(self.handle_nav_selection)
        top_layout.addWidget(self.nav_bar, 0, 1, Qt.AlignHCenter | Qt.AlignTop)
        
        # --- INFO LAYOUT (RELOJ Y CLIMA) ---
        info_layout = QVBoxLayout()
        info_layout.setAlignment(Qt.AlignRight | Qt.AlignTop)
        info_layout.setSpacing(0)
        
        self.time_label = QLabel("00:00")
        self.time_label.setAlignment(Qt.AlignRight | Qt.AlignVCenter)
        self.time_label.setStyleSheet("color: #0099FF; font-size: 56px; font-weight: 300; font-family: 'Space Grotesk', sans-serif; letter-spacing: 2px; margin: 0; padding: 0;")
        
        self.date_label = QLabel("--/--/----")
        self.date_label.setAlignment(Qt.AlignRight | Qt.AlignVCenter)
        self.date_label.setStyleSheet("color: #0099FF; font-size: 14px; font-family: 'Space Grotesk', sans-serif; text-transform: uppercase; letter-spacing: 1px; margin: 0; padding: 0;")
        
        self.weather_label = QLabel("Calculando coordenadas...")
        self.weather_label.setAlignment(Qt.AlignRight | Qt.AlignVCenter)
        self.weather_label.setStyleSheet("color: #0099FF; font-size: 12px; font-family: 'Space Grotesk', sans-serif; margin: 0; padding: 0;")
        
        info_layout.addWidget(self.time_label)
        info_layout.addWidget(self.date_label)
        info_layout.addWidget(self.weather_label)
        
        self.right_panel = QHBoxLayout()
        self.right_panel.setContentsMargins(0, 0, 0, 0)
        self.right_panel.setAlignment(Qt.AlignRight | Qt.AlignTop)
        
        self.right_panel.addLayout(info_layout)
        self.right_panel.addSpacing(15)
        
        # --- BOTONES DE CONTROL ---
        btn_layout = QVBoxLayout()
        btn_layout.setAlignment(Qt.AlignTop)
        btn_layout.setSpacing(10)
        
        # Botón Cerrar
        self.close_btn = QPushButton("✕")
        self.close_btn.setFixedSize(25, 25)
        self.close_btn.setCursor(Qt.PointingHandCursor)
        self.close_btn.setStyleSheet("""
            QPushButton { background-color: transparent; color: #0099FF; font-weight: bold; font-size: 12px; border: 1px solid #0099FF; border-radius: 3px; }
            QPushButton:hover { background-color: #0099FF; color: #0A1118; }
            QPushButton:pressed { background-color: #80BFFF; border: 1px solid #80BFFF; }
        """)
        self.close_btn.clicked.connect(self.close)
        
        btn_layout.addWidget(self.close_btn)
        
        self.right_panel.addLayout(btn_layout)
        
        top_layout.addLayout(self.right_panel, 0, 2, Qt.AlignRight | Qt.AlignTop)
        
        top_layout.setColumnStretch(0, 1)
        top_layout.setColumnStretch(1, 0)
        top_layout.setColumnStretch(2, 1)
        
        main_layout.addWidget(top_container)
        main_layout.addStretch()
        
        # --- CONEXIÓN AL VIEWMODEL ---
        self.viewmodel.time_updated.connect(self.time_label.setText)
        self.viewmodel.date_updated.connect(self.date_label.setText)
        self.viewmodel.weather_updated.connect(self.update_weather_label)

    def handle_nav_selection(self, option):
        self.settings_panel.hide()
        self.explorer_panel.hide()
        self.youtube_panel.hide()
        
        if option == "EXPLORER":
            self.explorer_panel.show()
            self.explorer_panel.raise_()
        elif option == "MUSIC":
            self.youtube_panel.show()
            self.youtube_panel.raise_()
        elif option == "CONFIG":
            self.settings_panel.show()
            self.settings_panel.raise_()
            
    def resizeEvent(self, event):
        super().resizeEvent(event)
        
        if hasattr(self, 'explorer_panel') and self.explorer_panel:
            self.explorer_panel.resize(int(self.width() * 0.6), self.height() - 50)
            
        # Centrar paneles de manera individual si no los ha movido el usuario
        for panel in [getattr(self, 'settings_panel', None), 
                      getattr(self, 'youtube_panel', None),
                      getattr(self, 'image_viewer', None), getattr(self, 'text_viewer', None),
                      getattr(self, 'pdf_viewer', None), getattr(self, 'task_viewer', None)]:
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
        
        if ext == 'task':
            self.task_viewer.load_task(path)
            self.task_viewer.show()
            self.task_viewer.raise_()
        elif ext in image_exts:
            self.image_viewer.load_image(path)
            self.image_viewer.show()
            self.image_viewer.raise_()
        elif ext in audio_exts:
            self.audio_player.load_audio(path)
            self.audio_player.show()
            self.audio_player.raise_()
            self.audio_player.move(self.width() - self.audio_player.width() - 20, self.height() - self.audio_player.height() - 20)
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
        dot_color = QColor("#0099FF") 
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
            (0.45, 0.15, 0.3, 0.6, "#0099FF", 10),
            (0.25, 0.7, 0.1, 0.2, "#0099FF", 15)
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
