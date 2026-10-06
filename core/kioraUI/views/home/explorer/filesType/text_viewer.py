from PySide6.QtWidgets import QTextEdit
from core.kioraUI.views.global_ui.viewer_base import SciFiViewerBase
from core.kioraUI.views.global_ui.styles import get_minimal_scrollbar_style

class TextViewerPanel(SciFiViewerBase):
    def __init__(self, parent=None):
        super().__init__(parent, "TEXT/CODE VIEWER SEQUENCE")
        self.resize(650, 550)
        
        self.text_edit = QTextEdit()
        self.text_edit.setReadOnly(True)
        self.text_edit.setLineWrapMode(QTextEdit.NoWrap)
        
        self.text_edit.setStyleSheet(get_minimal_scrollbar_style() + """
            QTextEdit {
                background-color: #0A1118;
                color: #FFFFFF;
                border: 1px solid #182533;
                padding: 10px;
                font-family: 'Consolas', 'Courier New', monospace;
                font-size: 13px;
            }
        """)
        
        self.set_body_widget(self.text_edit)
        
        from PySide6.QtCore import Qt
        self.text_edit.setContextMenuPolicy(Qt.CustomContextMenu)
        self.text_edit.customContextMenuRequested.connect(self._show_context_menu)
        self.current_path = ""
        self.is_editing = False
        
    def _update_style(self):
        border = "#4D94FF" if self.is_editing else "#182533"
        self.text_edit.setStyleSheet(get_minimal_scrollbar_style() + f"""
            QTextEdit {{
                background-color: #0A1118;
                color: #FFFFFF;
                border: 1px solid {border};
                padding: 10px;
                font-family: 'Consolas', 'Courier New', monospace;
                font-size: 13px;
            }}
        """)
        
    def load_text(self, path):
        self.current_path = path
        self.is_editing = False
        self.text_edit.setReadOnly(True)
        self._update_style()
        
        if path.lower().endswith('.docx'):
            try:
                import docx
                doc = docx.Document(path)
                content = "\n".join([p.text for p in doc.paragraphs])
                self.text_edit.setPlainText(content)
                self.title_label.setText("DOCX VIEWER")
            except Exception as e:
                self.text_edit.setPlainText(f"Error reading docx: {str(e)}")
            return
            
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

    def _show_context_menu(self, pos):
        is_word = self.current_path.lower().endswith('.docx')
        
        actions = ["copy"]
        if not is_word:
            if self.is_editing:
                actions.append("save")
            else:
                actions.append("edit")
                
        from core.kioraUI.views.global_ui.simple_dialogs import SciFiContextMenu
        menu = SciFiContextMenu(self.text_edit)
        
        for action in actions:
            menu.add_action(action.upper(), lambda a=action: self._handle_menu_action(a))
            
        menu.move(self.text_edit.viewport().mapToGlobal(pos))
        menu.show()

    def _handle_menu_action(self, action):
        if action == "copy":
            if not self.text_edit.textCursor().hasSelection():
                self.text_edit.selectAll()
            self.text_edit.copy()
        elif action == "edit":
            self.is_editing = True
            self.text_edit.setReadOnly(False)
            self._update_style()
        elif action == "save":
            try:
                with open(self.current_path, 'w', encoding='utf-8') as f:
                    f.write(self.text_edit.toPlainText())
                self.is_editing = False
                self.text_edit.setReadOnly(True)
                self._update_style()
            except Exception as e:
                self.text_edit.setPlainText(f"Error saving:\n{str(e)}")
