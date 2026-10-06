from PySide6.QtWidgets import QListWidget
from core.kioraUI.views.global_ui.base_container import KioraBaseContainer

class ConfigurationPanel(KioraBaseContainer):
    def __init__(self, parent=None):
        super().__init__(title_text="CONFIGURATION SEQUENCE...", parent=parent)
        self.resize(350, 480)
        
        self.sections_list = QListWidget()
        self.sections_list.setStyleSheet("""
            QListWidget {
                background-color: transparent;
                border: none;
                color: #D96600;
                font-family: 'Segoe UI', sans-serif;
                font-size: 13px;
                font-weight: 600;
                letter-spacing: 1px;
                outline: 0;
            }
            QListWidget::item {
                padding: 15px;
                border-bottom: 1px solid #182533;
                margin-bottom: 4px;
            }
            QListWidget::item:selected {
                background-color: rgba(217, 102, 0, 0.15);
                color: #FFFFFF;
                border-left: 4px solid #D96600;
            }
            QListWidget::item:hover:!selected {
                background-color: rgba(58, 35, 38, 0.4);
            }
        """)
        
        self.sections_list.addItem("GENERAL CONFIG")
        self.sections_list.addItem("VOICE ENGINE PARAMETERS")
        self.sections_list.addItem("UI APPEARANCE")
        self.sections_list.addItem("EXTERNAL INTEGRATIONS")
        
        self.body_layout.addWidget(self.sections_list)
