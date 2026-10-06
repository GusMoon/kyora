from PySide6.QtWidgets import QWidget
from core.kioraUI.views.global_ui.base_container import KioraBaseContainer

class SciFiViewerBase(KioraBaseContainer):
    def __init__(self, parent=None, title="VIEWER"):
        super().__init__(title_text=title, parent=parent)
        
    def set_body_widget(self, widget):
        self.body_layout.addWidget(widget)
