from PySide6.QtWidgets import QTextEdit
from core.kioraUI.views.global_ui.viewer_base import SciFiViewerBase
from core.kioraUI.views.global_ui.styles import get_minimal_scrollbar_style

class TextViewerPanel(SciFiViewerBase):
    def __init__(self, parent=None):
        super().__init__(parent, "TEXT/CODE VIEWER SEQUENCE")
        self.setFixedSize(650, 550)
        
        self.text_edit = QTextEdit()
        self.text_edit.setReadOnly(True)
        self.text_edit.setLineWrapMode(QTextEdit.NoWrap)
        
        self.text_edit.setStyleSheet(get_minimal_scrollbar_style() + """
            QTextEdit {
                background-color: #1E1E1E;
                color: #FFFFFF;
                border: 1px solid #3A2326;
                padding: 10px;
                font-family: 'Consolas', 'Courier New', monospace;
                font-size: 13px;
            }
        """)
        
        self.set_body_widget(self.text_edit)
        
    def load_text(self, path):
        try:
            with open(path, 'r', encoding='utf-8') as f:
                content = f.read()
            self.text_edit.setPlainText(content)
            filename = path.replace("\\", "/").split('/')[-1].upper()
            self.title_label.setText(f"CODE VIEWER: {filename}")
        except UnicodeDecodeError:
            self.text_edit.setPlainText("ERROR: ARCHIVO BINARIO NO PUEDE MOSTRARSE COMO TEXTO.")
            self.title_label.setText("CODE VIEWER: BINARY ERROR")
        except Exception as e:
            self.text_edit.setPlainText(f"ERROR DECODING FILE:\n{str(e)}")
