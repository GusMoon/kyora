"""
Diálogo modal Sci-Fi para crear y registrar una nueva categoría personalizada.
Permite definir nombre y seleccionar un color distintivo del catálogo Sci-Fi de Kiora.
"""
from typing import Optional, Dict
from PySide6.QtWidgets import (
    QVBoxLayout, QHBoxLayout, QLabel, QLineEdit,
    QPushButton, QWidget, QFrame
)
from PySide6.QtCore import Qt, Signal
from PySide6.QtGui import QColor

from .base_modal import SciFiBaseModal


SCI_FI_PALETTE = [
    ("#FFAA77", "Naranja Kiora"),
    ("#A31F34", "Vino Primario"),
    ("#00F5D4", "Cian Neón"),
    ("#00BBF9", "Azul Eléctrico"),
    ("#9B5DE5", "Púrpura Cuántico"),
    ("#F15BB5", "Magenta Neón"),
    ("#FEE440", "Ámbar Solar"),
    ("#52B788", "Verde Esmeralda"),
    ("#80ED99", "Menta"),
    ("#E63946", "Rojo Carmesí"),
]


class CategoryCreateDialog(SciFiBaseModal):
    """
    Diálogo para registrar una categoría personalizada (TAR-027).
    """

    def __init__(self, parent=None):
        super().__init__(parent, width=440, height=320)
        self.selected_color = SCI_FI_PALETTE[0][0]
        self.color_buttons = []
        self._setup_ui()

    def _setup_ui(self):
        root = QVBoxLayout(self)
        root.setContentsMargins(18, 14, 18, 16)
        root.setSpacing(12)

        # Encabezado
        header = QHBoxLayout()
        title_lbl = QLabel("CREAR CATEGORÍA PERSONALIZADA")
        title_lbl.setObjectName("Title")
        header.addWidget(title_lbl)
        header.addStretch()

        btn_close = QPushButton("✕")
        btn_close.setFixedSize(22, 22)
        btn_close.setCursor(Qt.PointingHandCursor)
        btn_close.setStyleSheet("""
            QPushButton {
                background: transparent;
                color: #888888;
                border: none;
                font-weight: bold;
                font-size: 13px;
            }
            QPushButton:hover {
                color: #FFFFFF;
                background-color: #2D2D2D;
                border-radius: 3px;
            }
        """)
        btn_close.clicked.connect(self.reject)
        header.addWidget(btn_close)
        root.addLayout(header)

        # Campo: Nombre de categoría
        lbl_name = QLabel("NOMBRE DE LA CATEGORÍA *:")
        lbl_name.setStyleSheet("font-size: 11px; font-weight: bold; color: #CCCCCC;")
        root.addWidget(lbl_name)

        self.input_name = QLineEdit()
        self.input_name.setPlaceholderText("Ej. Materias, Proyectos, Trabajo...")
        self.input_name.textChanged.connect(self._update_preview)
        root.addWidget(self.input_name)

        # Paleta de colores
        lbl_color = QLabel("COLOR DISTINTIVO:")
        lbl_color.setStyleSheet("font-size: 11px; font-weight: bold; color: #CCCCCC;")
        root.addWidget(lbl_color)

        palette_frame = QWidget()
        palette_layout = QHBoxLayout(palette_frame)
        palette_layout.setContentsMargins(0, 0, 0, 0)
        palette_layout.setSpacing(8)

        for hex_code, color_name in SCI_FI_PALETTE:
            btn_col = QPushButton()
            btn_col.setFixedSize(26, 26)
            btn_col.setCursor(Qt.PointingHandCursor)
            btn_col.setToolTip(color_name)
            btn_col.clicked.connect(lambda _, c=hex_code: self._select_color(c))
            self.color_buttons.append((hex_code, btn_col))
            palette_layout.addWidget(btn_col)

        root.addWidget(palette_frame)
        self._refresh_color_buttons()

        # Previsualización
        preview_box = QHBoxLayout()
        preview_box.setSpacing(8)
        lbl_prev_title = QLabel("VISTA PREVIA:")
        lbl_prev_title.setStyleSheet("font-size: 10px; color: #777777; font-weight: bold;")
        preview_box.addWidget(lbl_prev_title)

        self.preview_badge = QLabel("● CATEGORÍA")
        self.preview_badge.setFixedHeight(24)
        preview_box.addWidget(self.preview_badge)
        preview_box.addStretch()
        root.addLayout(preview_box)

        # Error label
        self.lbl_error = QLabel("")
        self.lbl_error.setStyleSheet("color: #FF5555; font-size: 11px;")
        root.addWidget(self.lbl_error)

        root.addStretch()

        # Acciones
        btn_layout = QHBoxLayout()
        btn_layout.addStretch()

        btn_cancel = QPushButton("CANCELAR")
        btn_cancel.setStyleSheet("""
            QPushButton {
                background: transparent;
                border: 1px solid #333333;
                color: #888888;
                padding: 6px 14px;
                font-size: 11px;
                border-radius: 4px;
            }
            QPushButton:hover {
                color: #FFFFFF;
                border-color: #555555;
            }
        """)
        btn_cancel.clicked.connect(self.reject)
        btn_layout.addWidget(btn_cancel)

        btn_save = QPushButton("GUARDAR CATEGORÍA")
        btn_save.setStyleSheet("""
            QPushButton {
                background-color: #A31F34;
                border: 1px solid #C42B42;
                color: #FFFFFF;
                font-weight: bold;
                padding: 6px 16px;
                font-size: 11px;
                border-radius: 4px;
            }
            QPushButton:hover {
                background-color: #B9263D;
            }
        """)
        btn_save.clicked.connect(self._on_save_clicked)
        btn_layout.addWidget(btn_save)

        root.addLayout(btn_layout)
        self._update_preview()
        self.input_name.setFocus()

    def _select_color(self, hex_code: str):
        self.selected_color = hex_code
        self._refresh_color_buttons()
        self._update_preview()

    def _refresh_color_buttons(self):
        for hex_code, btn in self.color_buttons:
            is_active = (hex_code == self.selected_color)
            border = "2px solid #FFFFFF" if is_active else "1px solid #333333"
            scale_css = "border-radius: 13px;"
            btn.setStyleSheet(f"""
                QPushButton {{
                    background-color: {hex_code};
                    border: {border};
                    {scale_css}
                }}
                QPushButton:hover {{
                    border: 2px solid #FFAA77;
                }}
            """)

    def _update_preview(self):
        text = self.input_name.text().strip().upper() or "NOMBRE"
        self.preview_badge.setText(f"● {text}")
        self.preview_badge.setStyleSheet(f"""
            QLabel {{
                color: {self.selected_color};
                font-size: 11px;
                font-weight: bold;
                font-family: 'Space Grotesk';
                background-color: #1A1A1A;
                border: 1px solid {self.selected_color};
                border-radius: 4px;
                padding: 2px 8px;
            }}
        """)

    def _on_save_clicked(self):
        name = self.input_name.text().strip()
        if not name:
            self.lbl_error.setText("Ingresa un nombre para la categoría.")
            self.input_name.setFocus()
            return

        self.accept()

    def get_data(self) -> Dict[str, str]:
        return {
            "name": self.input_name.text().strip(),
            "color": self.selected_color
        }
