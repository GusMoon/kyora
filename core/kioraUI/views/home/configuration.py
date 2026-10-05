from PySide6.QtWidgets import QFrame, QVBoxLayout, QHBoxLayout, QLabel, QPushButton, QListWidget
from PySide6.QtCore import Qt, QPoint

class ConfigurationPanel(QFrame):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setFixedSize(350, 480)
        self.user_moved = False  # Bandera para saber si el usuario movió el panel
        
        # Fondo oscuro y borde exterior rojo vino
        self.setStyleSheet("""
            QFrame {
                background-color: #161616;
                border: 1px solid #A31F34;
            }
        """)
        
        main_layout = QVBoxLayout(self)
        main_layout.setContentsMargins(0, 0, 0, 0)
        main_layout.setSpacing(0)
        
        # --- HEADER (Barra de Título Sci-Fi) ---
        self.header = QFrame()
        self.header.setFixedHeight(35)
        self.header.setStyleSheet("""
            QFrame {
                background-color: #A31F34;
                border: none;
                border-bottom: 2px solid #7A1727;
            }
        """)
        
        header_layout = QHBoxLayout(self.header)
        header_layout.setContentsMargins(15, 0, 10, 0)
        
        title = QLabel("CONFIGURATION SEQUENCE...")
        title.setStyleSheet("""
            QLabel {
                color: #FFFFFF;
                font-family: 'Segoe UI', sans-serif;
                font-size: 11px;
                font-weight: 800;
                letter-spacing: 2px;
                border: none;
                background: transparent;
            }
        """)
        
        header_layout.addWidget(title)
        header_layout.addStretch()
        
        self.close_btn = QPushButton("✕")
        self.close_btn.setFixedSize(24, 24)
        self.close_btn.setCursor(Qt.PointingHandCursor)
        self.close_btn.setStyleSheet("""
            QPushButton {
                background-color: transparent;
                color: #FFFFFF;
                font-weight: bold;
                font-size: 14px;
                border: none;
            }
            QPushButton:hover {
                color: #161616;
            }
        """)
        self.close_btn.clicked.connect(self.hide)
        
        header_layout.addWidget(self.close_btn)
        
        # --- BODY (Área de Listado) ---
        body_frame = QFrame()
        body_frame.setStyleSheet("border: none; background-color: transparent;")
        body_layout = QVBoxLayout(body_frame)
        body_layout.setContentsMargins(25, 25, 25, 25)
        
        self.sections_list = QListWidget()
        self.sections_list.setStyleSheet("""
            QListWidget {
                background-color: transparent;
                border: none;
                color: #A31F34;
                font-family: 'Segoe UI', sans-serif;
                font-size: 13px;
                font-weight: 600;
                letter-spacing: 1px;
                outline: 0;
            }
            QListWidget::item {
                padding: 15px;
                border-bottom: 1px solid #3A2326;
                margin-bottom: 4px;
            }
            QListWidget::item:selected {
                background-color: rgba(163, 31, 52, 0.15);
                color: #FFFFFF;
                border-left: 4px solid #A31F34;
            }
            QListWidget::item:hover:!selected {
                background-color: rgba(58, 35, 38, 0.4);
            }
        """)
        
        self.sections_list.addItem("GENERAL CONFIG")
        self.sections_list.addItem("VOICE ENGINE PARAMETERS")
        self.sections_list.addItem("UI APPEARANCE")
        self.sections_list.addItem("EXTERNAL INTEGRATIONS")
        
        body_layout.addWidget(self.sections_list)
        
        # Ensamblar contenedor
        main_layout.addWidget(self.header)
        main_layout.addWidget(body_frame)

    # --- LÓGICA DE MOVIMIENTO (DRAG & DROP) ---
    def mousePressEvent(self, event):
        if event.button() == Qt.LeftButton:
            self._drag_pos = event.globalPosition().toPoint()
            event.accept()

    def mouseMoveEvent(self, event):
        if hasattr(self, '_drag_pos') and event.buttons() == Qt.LeftButton:
            self.user_moved = True # Desactivar el centrado forzoso de la ventana
            new_pos = event.globalPosition().toPoint()
            diff = new_pos - self._drag_pos
            self._drag_pos = new_pos
            
            # Calcular nueva posición absoluta
            next_pos = self.pos() + diff
            
            # Limitar posición a los bordes internos del padre (KioraUI)
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
