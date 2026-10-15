"""
Diálogo modal Sci-Fi para crear y editar categorías de tareas (sin selección de colores).
"""
from typing import Dict, Optional
from PySide6.QtWidgets import (
    QVBoxLayout, QHBoxLayout, QLabel, QLineEdit,
    QPushButton, QWidget
)
from PySide6.QtCore import Qt

from ..base_modal import SciFiBaseModal


class CategoryCreateDialog(SciFiBaseModal):
    """
    Diálogo modal simplificado para crear o editar categorías sin colores.
    """

    def __init__(self, parent=None, title: str = "CREAR CATEGORÍA", initial_name: str = ""):
        super().__init__(parent, width=380, height=190)
        self.dialog_title = title
        self.initial_name = initial_name
        self._setup_ui()

    def _setup_ui(self):
        root = QVBoxLayout(self)
        root.setContentsMargins(18, 14, 18, 16)
        root.setSpacing(10)

        # Encabezado
        header = QHBoxLayout()
        title_lbl = QLabel(self.dialog_title)
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
        lbl_name.setStyleSheet("font-size: 11px; font-weight: bold; color: #CCCCCC; font-family: 'Prototype';")
        root.addWidget(lbl_name)

        self.input_name = QLineEdit(self.initial_name)
        self.input_name.setPlaceholderText("Ej. Materias, Proyectos, Trabajo...")
        self.input_name.setFixedHeight(30)
        self.input_name.returnPressed.connect(self._on_save_clicked)
        root.addWidget(self.input_name)

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
                font-family: 'Prototype';
                border-radius: 4px;
            }
            QPushButton:hover {
                color: #FFFFFF;
                border-color: #555555;
            }
        """)
        btn_cancel.clicked.connect(self.reject)
        btn_layout.addWidget(btn_cancel)

        btn_save = QPushButton("GUARDAR")
        btn_save.setStyleSheet("""
            QPushButton {
                background-color: #A31F34;
                border: 1px solid #C42B42;
                color: #FFFFFF;
                font-weight: bold;
                font-family: 'Prototype';
                padding: 6px 18px;
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
        self.input_name.setFocus()
        self.input_name.selectAll()

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
            "color": "#888888"
        }
