from PySide6.QtWidgets import QTextEdit
from core.matrix.ecosystems.motherBoard.globalComponents.viewer_base import SciFiViewerBase
from core.matrix.ecosystems.motherBoard.globalComponents.styles import get_minimal_scrollbar_style

class TextViewerPanel(SciFiViewerBase):
    def __init__(self, parent=None):
        super().__init__(parent, "TEXT/CODE VIEWER SEQUENCE")
        self.resize(650, 550)
        
        self.text_edit = QTextEdit()
        self.text_edit.setLineWrapMode(QTextEdit.WidgetWidth)
        
        self.text_edit.setStyleSheet(get_minimal_scrollbar_style() + """
            QTextEdit {
                background-color: rgba(10, 17, 24, 0.95);
                color: #FFB84D;
                border: 1px solid #0099FF;
                padding: 35px 10px 10px 10px;
                font-family: 'Space Grotesk', monospace;
                font-size: 13px;
            }
        """)
        
        self.set_body_widget(self.text_edit)
        
        self.header.hide()
        self.body_layout.setContentsMargins(0, 0, 0, 0)
        self.setStyleSheet("KioraBaseContainer { background-color: transparent; border: none; }")
        
        self.close_btn.setParent(self)
        self.close_btn.setStyleSheet("""
            QPushButton { background-color: rgba(22, 22, 22, 0.8); color: #FFB84D; font-weight: bold; border: 1px solid #0099FF; }
            QPushButton:hover { background-color: #0099FF; }
        """)
        self.close_btn.show()
        
        from PySide6.QtCore import Qt
        self.text_edit.setContextMenuPolicy(Qt.CustomContextMenu)
        self.text_edit.customContextMenuRequested.connect(self._show_context_menu)
        self.current_path = ""
        self.is_editing = False
        
        from PySide6.QtGui import QShortcut, QKeySequence
        self.shortcut_save = QShortcut(QKeySequence("Ctrl+S"), self)
        self.shortcut_save.activated.connect(lambda: self._handle_menu_action("save"))
        
    def _update_style(self):
        border = "#0099FF" if self.is_editing else "#0099FF"
        self.text_edit.setStyleSheet(get_minimal_scrollbar_style() + f"""
            QTextEdit {{
                background-color: rgba(10, 17, 24, 0.95);
                color: #FFB84D;
                border: 1px solid {border};
                padding: 35px 10px 10px 10px;
                font-family: 'Space Grotesk', monospace;
                font-size: 13px;
            }}
        """)
        
    def load_text(self, path):
        self.current_path = path
        
        is_word = path.lower().endswith(('.doc', '.docx'))
        self.is_editing = not is_word
        self.text_edit.setReadOnly(is_word)
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
        is_word = self.current_path.lower().endswith(('.doc', '.docx'))
        
        actions = ["copy"]
        if not is_word:
            actions.append("save")
                
        from core.matrix.ecosystems.motherBoard.globalComponents.simple_dialogs import SciFiContextMenu
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
        elif action == "save":
            if not self.is_editing: return
            try:
                with open(self.current_path, 'w', encoding='utf-8') as f:
                    f.write(self.text_edit.toPlainText())
                # Mostrar pequeña notificacion o cambiar el color brevemente
                self.text_edit.setStyleSheet(get_minimal_scrollbar_style() + """
                    QTextEdit { background-color: rgba(10, 17, 24, 0.95); color: #FFB84D; border: 1px solid #00FF00; padding: 35px 10px 10px 10px; font-family: 'Space Grotesk', monospace; font-size: 13px; }
                """)
                from PySide6.QtCore import QTimer
                QTimer.singleShot(500, self._update_style)
            except Exception as e:
                self.text_edit.setPlainText(f"Error saving:\n{str(e)}")

    def resizeEvent(self, event):
        super().resizeEvent(event)
        self.close_btn.move(self.width() - self.close_btn.width() - 5, 5)
        self.close_btn.raise_()
