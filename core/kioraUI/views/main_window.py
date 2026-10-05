"""
Vista de la ventana principal de KioraUI.
Solo contiene lógica visual y reacciona a señales del ViewModel.
"""
from PySide6.QtWidgets import QMainWindow, QWidget, QPushButton, QVBoxLayout, QHBoxLayout, QSpacerItem, QSizePolicy
from PySide6.QtCore import Qt
from PySide6.QtGui import QPainter, QColor, QPen

class MainWindow(QMainWindow):
    def __init__(self, viewmodel):
        super().__init__()
        self.viewmodel = viewmodel
        
        # Configuración de ventana base
        self.setWindowTitle("Kiora")
        
        # Transparencia de la ventana al 3% (Opacidad 97%)
        self.setWindowOpacity(0.97)
        
        # Quitar la barra superior (Frameless)
        self.setWindowFlag(Qt.FramelessWindowHint)
        
        # Widget central
        self.central_widget = QWidget()
        self.setCentralWidget(self.central_widget)
        
        # Configurar el Layout para el botón de cerrar
        self.setup_ui()
        
        # Forzar maximización en el inicio
        self.showMaximized()

    def setup_ui(self):
        # Layout principal vertical
        main_layout = QVBoxLayout(self.central_widget)
        main_layout.setContentsMargins(20, 20, 20, 20)
        
        # Layout superior horizontal para el botón
        top_layout = QHBoxLayout()
        
        # Espaciador para empujar el botón completamente a la derecha
        spacer = QSpacerItem(40, 20, QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Minimum)
        top_layout.addItem(spacer)
        
        # Botón de cierre Sci-Fi
        self.close_btn = QPushButton("✕")
        self.close_btn.setFixedSize(40, 40)
        self.close_btn.setCursor(Qt.PointingHandCursor)
        self.close_btn.setStyleSheet("""
            QPushButton {
                background-color: transparent;
                color: #00FFCC; /* Sci-Fi Cyan */
                font-weight: bold;
                font-size: 20px;
                border: 1px solid #00FFCC;
                border-radius: 5px;
            }
            QPushButton:hover {
                background-color: #00FFCC;
                color: #0B131C;
            }
            QPushButton:pressed {
                background-color: #00CCAA;
                border: 1px solid #00CCAA;
            }
        """)
        
        # Conectar el botón al evento nativo de cierre de la ventana
        self.close_btn.clicked.connect(self.close)
        
        top_layout.addWidget(self.close_btn)
        
        # Añadir el layout superior al layout principal
        main_layout.addLayout(top_layout)
        
        # Empujar el resto del contenido hacia abajo (para futuros widgets)
        main_layout.addStretch()
        
    def paintEvent(self, event):
        """
        Sobrescribe el evento de pintado nativo para dibujar el fondo (#0B131C)
        y la cuadrícula de puntos pequeños.
        """
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)
        
        # 1. Pintar fondo sólido (Azul Abisal)
        bg_color = QColor("#0B131C")
        painter.fillRect(self.rect(), bg_color)
        
        # 2. Dibujar cuadrícula de puntos
        dot_color = QColor("#152A3D")  # Azul medio para los puntos
        dot_color.setAlpha(100)        # Transparencia del punto para no distraer
        
        pen = QPen(dot_color)
        pen.setWidth(2)
        painter.setPen(pen)
        
        spacing = 15 # Separación entre puntos en píxeles (Alta densidad)
        
        for x in range(0, self.width(), spacing):
            for y in range(0, self.height(), spacing):
                painter.drawPoint(x, y)
                
        painter.end()
