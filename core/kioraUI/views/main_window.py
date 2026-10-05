from PySide6.QtWidgets import QMainWindow, QWidget, QPushButton, QVBoxLayout, QHBoxLayout, QSpacerItem, QSizePolicy, QLabel
from PySide6.QtCore import Qt
from PySide6.QtGui import QPainter, QColor, QPen

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
        self.showMaximized()

    def setup_ui(self):
        main_layout = QVBoxLayout(self.central_widget)
        # Márgenes a 0 para poder pegar el botón al borde absoluto
        main_layout.setContentsMargins(0, 0, 0, 0)
        
        # --- TOP LAYOUT ---
        top_layout = QHBoxLayout()
        # Margen: Izq=20, Arriba=10, Derecha=10, Abajo=0
        top_layout.setContentsMargins(20, 10, 10, 0)
        top_layout.setAlignment(Qt.AlignTop)
        
        # Espaciador para empujar todo a la derecha
        spacer = QSpacerItem(40, 20, QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Minimum)
        top_layout.addItem(spacer)
        
        # --- INFO LAYOUT (RELOJ Y CLIMA) ---
        info_layout = QVBoxLayout()
        info_layout.setAlignment(Qt.AlignRight | Qt.AlignTop)
        info_layout.setSpacing(0)
        
        self.time_label = QLabel("00:00")
        self.time_label.setAlignment(Qt.AlignRight | Qt.AlignVCenter)
        self.time_label.setStyleSheet("color: #3399FF; font-size: 56px; font-weight: 300; font-family: 'Segoe UI Light', 'Helvetica Neue', sans-serif; letter-spacing: 2px; margin: 0; padding: 0;")
        
        self.date_label = QLabel("--/--/----")
        self.date_label.setAlignment(Qt.AlignRight | Qt.AlignVCenter)
        self.date_label.setStyleSheet("color: #3399FF; font-size: 14px; font-family: 'Segoe UI', sans-serif; text-transform: uppercase; letter-spacing: 1px; margin: 0; padding: 0;")
        
        self.weather_label = QLabel("Calculando coordenadas...")
        self.weather_label.setAlignment(Qt.AlignRight | Qt.AlignVCenter)
        self.weather_label.setStyleSheet("color: #3399FF; font-size: 12px; font-family: 'Segoe UI', sans-serif; margin: 0; padding: 0;")
        
        info_layout.addWidget(self.time_label)
        info_layout.addWidget(self.date_label)
        info_layout.addWidget(self.weather_label)
        
        top_layout.addLayout(info_layout)
        
        # Espacio mínimo entre reloj y botón
        top_layout.addSpacing(15)
        
        # --- BOTÓN DE CIERRE ---
        self.close_btn = QPushButton("✕")
        self.close_btn.setFixedSize(25, 25) # Botón mucho más pequeño
        self.close_btn.setCursor(Qt.PointingHandCursor)
        self.close_btn.setStyleSheet("""
            QPushButton { background-color: transparent; color: #3399FF; font-weight: bold; font-size: 12px; border: 1px solid #3399FF; border-radius: 3px; }
            QPushButton:hover { background-color: #3399FF; color: #0B131C; }
            QPushButton:pressed { background-color: #0077CC; border: 1px solid #0077CC; }
        """)
        self.close_btn.clicked.connect(self.close)
        
        btn_layout = QVBoxLayout()
        btn_layout.setAlignment(Qt.AlignTop)
        btn_layout.addWidget(self.close_btn)
        
        top_layout.addLayout(btn_layout)
        
        main_layout.addLayout(top_layout)
        main_layout.addStretch()
        
        # --- CONEXIÓN AL VIEWMODEL ---
        self.viewmodel.time_updated.connect(self.time_label.setText)
        self.viewmodel.date_updated.connect(self.date_label.setText)
        self.viewmodel.weather_updated.connect(self.update_weather_label)
        
    def update_weather_label(self, loc, temp):
        self.weather_label.setText(f"{loc}  |  {temp}")
        
    def paintEvent(self, event):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)
        
        bg_color = QColor("#0B131C")
        painter.fillRect(self.rect(), bg_color)
        
        dot_color = QColor("#152A3D")
        dot_color.setAlpha(100)
        pen = QPen(dot_color)
        pen.setWidth(2)
        painter.setPen(pen)
        
        spacing = 15
        for x in range(0, self.width(), spacing):
            for y in range(0, self.height(), spacing):
                painter.drawPoint(x, y)
        painter.end()
