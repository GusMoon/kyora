"""
Diálogo modal Sci-Fi para definir, confirmar o modificar el tiempo disponible
antes de iniciar una sesión de cronómetro (TAR-036, TAR-037).
"""
from typing import Optional
from PySide6.QtWidgets import (
    QVBoxLayout, QHBoxLayout, QLabel, QSpinBox,
    QPushButton, QWidget, QFrame
)
from PySide6.QtCore import Qt

from .base_modal import SciFiBaseModal


class TimerDurationDialog(SciFiBaseModal):
    """
    Diálogo para solicitar o confirmar el tiempo disponible antes de iniciar el cronómetro.
    """

    def __init__(self, parent=None, initial_minutes: Optional[int] = None, task_title: str = ""):
        super().__init__(parent, width=420, height=310)
        self.initial_minutes = initial_minutes or 25
        self.task_title = task_title
        self._setup_ui()

    def _setup_ui(self):
        root = QVBoxLayout(self)
        root.setContentsMargins(18, 14, 18, 16)
        root.setSpacing(12)

        # Encabezado
        header = QHBoxLayout()
        title_lbl = QLabel("DEFINIR TIEMPO DE TRABAJO")
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

        if self.task_title:
            task_info = QLabel(f"Tarea: {self.task_title.upper()}")
            task_info.setStyleSheet("color: #FFAA77; font-size: 11px; font-weight: bold; font-family: 'Space Grotesk';")
            task_info.setWordWrap(True)
            root.addWidget(task_info)

        prompt_lbl = QLabel("¿Cuánto tiempo dispones para esta sesión?")
        prompt_lbl.setStyleSheet("color: #CCCCCC; font-size: 12px;")
        root.addWidget(prompt_lbl)

        # Spinboxes para Horas y Minutos
        time_card = QFrame()
        time_card.setStyleSheet("""
            QFrame {
                background-color: #171717;
                border: 1px solid #2A2A2A;
                border-radius: 5px;
                padding: 4px;
            }
        """)
        time_layout = QHBoxLayout(time_card)
        time_layout.setContentsMargins(12, 10, 12, 10)
        time_layout.setSpacing(12)

        # Horas
        h_box = QVBoxLayout()
        h_box.setSpacing(4)
        h_lbl = QLabel("HORAS:")
        h_lbl.setStyleSheet("color: #888888; font-size: 10px; font-weight: bold;")
        self.spin_hours = QSpinBox()
        self.spin_hours.setRange(0, 23)
        self.spin_hours.setFixedHeight(32)
        self.spin_hours.setStyleSheet("""
            QSpinBox {
                background-color: #222222;
                border: 1px solid #3A3A3A;
                color: #FFFFFF;
                font-size: 14px;
                font-weight: bold;
                border-radius: 4px;
                padding: 4px;
            }
            QSpinBox:focus {
                border-color: #FFAA77;
            }
        """)
        h_box.addWidget(h_lbl)
        h_box.addWidget(self.spin_hours)
        time_layout.addLayout(h_box)

        # Minutos
        m_box = QVBoxLayout()
        m_box.setSpacing(4)
        m_lbl = QLabel("MINUTOS:")
        m_lbl.setStyleSheet("color: #888888; font-size: 10px; font-weight: bold;")
        self.spin_mins = QSpinBox()
        self.spin_mins.setRange(0, 59)
        self.spin_mins.setFixedHeight(32)
        self.spin_mins.setStyleSheet("""
            QSpinBox {
                background-color: #222222;
                border: 1px solid #3A3A3A;
                color: #FFFFFF;
                font-size: 14px;
                font-weight: bold;
                border-radius: 4px;
                padding: 4px;
            }
            QSpinBox:focus {
                border-color: #FFAA77;
            }
        """)
        m_box.addWidget(m_lbl)
        m_box.addWidget(self.spin_mins)
        time_layout.addLayout(m_box)

        # Inicializar valores
        init_h = self.initial_minutes // 60
        init_m = self.initial_minutes % 60
        if init_h == 0 and init_m == 0:
            init_m = 25
        self.spin_hours.setValue(init_h)
        self.spin_mins.setValue(init_m)

        root.addWidget(time_card)

        # Error / advertencia
        self.lbl_error = QLabel("")
        self.lbl_error.setStyleSheet("color: #FF5555; font-size: 11px;")
        root.addWidget(self.lbl_error)

        root.addStretch()

        # Botones de acción
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

        btn_start = QPushButton("INICIAR CRONÓMETRO")
        btn_start.setStyleSheet("""
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
        btn_start.clicked.connect(self._on_start_clicked)
        btn_layout.addWidget(btn_start)

        root.addLayout(btn_layout)

    def _on_start_clicked(self):
        total = self.get_duration_minutes()
        if total <= 0:
            self.lbl_error.setText("La duración debe ser de al menos 1 minuto.")
            return
        self.accept()

    def get_duration_minutes(self) -> int:
        return (self.spin_hours.value() * 60) + self.spin_mins.value()
