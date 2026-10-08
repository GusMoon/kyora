from PySide6.QtWidgets import QWidget, QHBoxLayout, QPushButton
from PySide6.QtCore import Qt, Signal

class TopNavigationBar(QWidget):
    option_selected = Signal(str)
    
    def __init__(self, parent=None):
        super().__init__(parent)
        layout = QHBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(50)
        
        self.buttons = {}
        self.options = ["EXPLORER", "MUSIC", "CONFIG"]
        
        for opt in self.options:
            btn = QPushButton(opt)
            btn.setCursor(Qt.PointingHandCursor)
            btn.setCheckable(True)
            self.buttons[opt] = btn
            layout.addWidget(btn)
            btn.clicked.connect(lambda checked, o=opt: self.select_option(o))
            
        self.select_option("EXPLORER")
        
    def select_option(self, option):
        for opt, btn in self.buttons.items():
            is_active = (opt == option)
            btn.setChecked(is_active)
            
            if is_active:
                btn.setStyleSheet("""
                    QPushButton {
                        background-color: transparent;
                        color: #4D94FF;
                        font-family: 'Space Grotesk', sans-serif;
                        font-size: 24px;
                        font-weight: bold;
                        border: none;
                        letter-spacing: 3px;
                    }
                """)
            else:
                btn.setStyleSheet("""
                    QPushButton {
                        background-color: transparent;
                        color: #384553;
                        font-family: 'Space Grotesk', sans-serif;
                        font-size: 14px;
                        font-weight: bold;
                        border: none;
                        letter-spacing: 2px;
                    }
                    QPushButton:hover {
                        color: #80BFFF;
                    }
                """)
        self.option_selected.emit(option)
