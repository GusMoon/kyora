from PySide6.QtCore import Qt
from PySide6.QtWidgets import QLabel, QListWidget

from core.matrix.motherboard.globalComponents import kyora_theme as kt
from core.matrix.motherboard.globalComponents.base_container import KioraBaseContainer


class ConfigurationPanel(KioraBaseContainer):
    """
    Panel de ajustes con el estilo de Kyora (globalKyoraUI).

    Reutiliza el comportamiento del contenedor base (arrastre, redimensionado y cierre)
    y le aplica el marco de modal: fondo `#121212`, borde `#444444`, radio 6 y cabecera
    transparente con el título del modal.
    """

    def __init__(self, parent=None):
        """
        Args:
            parent: Widget padre (la ventana principal).
        """
        super().__init__(title_text="CONFIGURATION SEQUENCE...", parent=parent)
        self.resize(350, 480)
        self._apply_frame_style()

        caption = QLabel("SECCIONES")
        caption.setStyleSheet(
            f"color: {kt.ACCENT}; font-family: '{kt.FONT}'; font-size: 10px; font-weight: bold; "
            "letter-spacing: 2px; background: transparent;"
        )
        self.body_layout.addWidget(caption)

        self.sections_list = QListWidget()
        self.sections_list.setFocusPolicy(Qt.NoFocus)
        self.sections_list.setStyleSheet(f"""
            QListWidget {{
                background-color: transparent;
                border: none;
                outline: 0;
                font-family: '{kt.FONT}';
                font-size: 12px;
                font-weight: bold;
                letter-spacing: 1px;
            }}
            QListWidget::item {{
                color: {kt.TEXT_SUB};
                background-color: transparent;
                border: 1px solid transparent;
                border-radius: {kt.RADIUS_CARD}px;
                padding: 12px 14px;
                margin-bottom: 6px;
            }}
            QListWidget::item:hover:!selected {{
                background-color: {kt.BG_CARD};
                border: 1px solid {kt.BORDER_SOFT};
                color: {kt.TEXT_BODY};
            }}
            QListWidget::item:selected {{
                background-color: {kt.ACCENT_TINT};
                border: 1px solid {kt.ACCENT};
                color: {kt.TEXT};
            }}
        """)

        self.sections_list.addItem("GENERAL CONFIG")
        self.sections_list.addItem("VOICE ENGINE PARAMETERS")
        self.sections_list.addItem("UI APPEARANCE")
        self.sections_list.addItem("EXTERNAL INTEGRATIONS")

        self.body_layout.addWidget(self.sections_list)

    def _apply_frame_style(self) -> None:
        """Aplica el marco de modal de Kyora sobre el contenedor base."""
        self.setStyleSheet(
            f"KioraBaseContainer {{ background-color: {kt.BG_APP}; "
            f"border: 1px solid {kt.BORDER}; border-radius: {kt.RADIUS_PANEL}px; }}"
        )
        self.header.setStyleSheet(
            f"QFrame {{ background-color: transparent; border: none; "
            f"border-bottom: 1px solid {kt.BORDER_FAINT}; }}"
        )
        self.title_label.setStyleSheet(
            f"QLabel {{ color: {kt.TEXT}; font-family: '{kt.FONT}'; font-size: 13px; "
            "font-weight: 900; letter-spacing: 2px; border: none; background: transparent; }"
        )
        self.close_btn.setStyleSheet(
            f"QPushButton {{ background: transparent; color: {kt.TEXT_SUB}; border: none; "
            "font-size: 13px; font-weight: bold; padding: 0px; } "
            f"QPushButton:hover {{ color: {kt.TEXT}; background-color: #2D2D2D; border-radius: 3px; }}"
        )
