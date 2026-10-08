from PySide6.QtWidgets import QDialog, QVBoxLayout, QHBoxLayout, QLabel, QLineEdit, QPushButton, QWidget, QFrame
from PySide6.QtCore import Qt

class SciFiDialogBase(QDialog):
    def __init__(self, parent=None, title=""):
        super().__init__(parent)
        self.setWindowFlags(Qt.FramelessWindowHint | Qt.Dialog)
        self.resize(350, 150)
        
        # Un pequeño hack para que el fondo redondeado funcione bien sin esquinas negras
        self.setAttribute(Qt.WA_TranslucentBackground)
        
        self.setStyleSheet("""
            QDialog {
                background-color: #0A1118;
                border: 2px solid #0099FF;
                border-radius: 5px;
            }
            QLabel {
                color: #FFB84D;
                font-family: 'Space Grotesk';
                font-size: 14px;
                background-color: transparent;
            }
            QLabel#Title {
                color: #0099FF;
                font-weight: bold;
                font-size: 16px;
                letter-spacing: 2px;
            }
            QLineEdit {
                background-color: #182533;
                border: 1px solid #0099FF;
                color: #FFB84D;
                padding: 5px;
                font-family: 'Space Grotesk';
                font-size: 13px;
            }
            QPushButton {
                background-color: transparent;
                color: #0099FF;
                border: 1px solid #0099FF;
                padding: 6px 15px;
                font-weight: bold;
                font-family: 'Space Grotesk';
                border-radius: 2px;
            }
            QPushButton:hover {
                background-color: #0099FF;
                color: #0A1118;
            }
        """)

class SciFiInputDialog(SciFiDialogBase):
    def __init__(self, parent=None, title="", label_text="", default_text=""):
        super().__init__(parent, title)
        
        layout = QVBoxLayout(self)
        layout.setContentsMargins(20, 20, 20, 20)
        layout.setSpacing(10)
        
        title_lbl = QLabel(title)
        title_lbl.setObjectName("Title")
        
        lbl = QLabel(label_text)
        
        self.input_field = QLineEdit(default_text)
        
        btn_layout = QHBoxLayout()
        btn_layout.addStretch()
        
        btn_cancel = QPushButton("CANCELAR")
        btn_accept = QPushButton("ACEPTAR")
        
        btn_cancel.clicked.connect(self.reject)
        btn_accept.clicked.connect(self.accept)
        
        btn_layout.addWidget(btn_cancel)
        btn_layout.addWidget(btn_accept)
        
        layout.addWidget(title_lbl)
        layout.addWidget(lbl)
        layout.addWidget(self.input_field)
        layout.addStretch()
        layout.addLayout(btn_layout)
        
        self.input_field.setFocus()
        self.input_field.selectAll()
        
    def get_text(self):
        return self.input_field.text()

class SciFiConfirmDialog(SciFiDialogBase):
    def __init__(self, parent=None, title="", message=""):
        super().__init__(parent, title)
        
        layout = QVBoxLayout(self)
        layout.setContentsMargins(20, 20, 20, 20)
        layout.setSpacing(10)
        
        title_lbl = QLabel(title)
        title_lbl.setObjectName("Title")
        
        lbl = QLabel(message)
        lbl.setWordWrap(True)
        
        btn_layout = QHBoxLayout()
        btn_layout.addStretch()
        
        btn_cancel = QPushButton("CANCELAR")
        btn_accept = QPushButton("ACEPTAR")
        
        btn_cancel.clicked.connect(self.reject)
        btn_accept.clicked.connect(self.accept)
        
        btn_layout.addWidget(btn_cancel)
        btn_layout.addWidget(btn_accept)
        
        layout.addWidget(title_lbl)
        layout.addWidget(lbl)
        layout.addStretch()
        layout.addLayout(btn_layout)

class SciFiContextMenu(QWidget):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowFlags(Qt.Popup | Qt.FramelessWindowHint | Qt.NoDropShadowWindowHint)
        self.setAttribute(Qt.WA_TranslucentBackground)
        
        self.main_layout = QVBoxLayout(self)
        self.main_layout.setContentsMargins(0, 0, 0, 0)
        self.main_layout.setSpacing(0)
        
        self.container = QFrame(self)
        self.container.setStyleSheet("""
            QFrame {
                background-color: rgba(10, 17, 24, 0.95);
                border: 1px solid #0099FF;
                border-radius: 4px;
            }
            QPushButton {
                background-color: transparent;
                color: #FFB84D;
                border: none;
                border-radius: 0px;
                padding: 10px 30px 10px 15px;
                text-align: left;
                font-family: 'Space Grotesk';
                font-size: 13px;
            }
            QPushButton:hover {
                background-color: rgba(0, 153, 255, 0.25);
                color: #0099FF;
                border-left: 3px solid #0099FF;
                padding-left: 12px;
            }
        """)
        self.container_layout = QVBoxLayout(self.container)
        self.container_layout.setContentsMargins(4, 4, 4, 4)
        self.container_layout.setSpacing(2)
        
        self.main_layout.addWidget(self.container)
        
    def add_action(self, text, callback):
        btn = QPushButton(text)
        def on_click():
            self.hide()
            callback()
        btn.clicked.connect(on_click)
        self.container_layout.addWidget(btn)

class SciFiFileEditDialog(SciFiDialogBase):
    def __init__(self, parent=None, title="", label_text="", default_name="", default_ext=""):
        super().__init__(parent, title)
        
        layout = QVBoxLayout(self)
        layout.setContentsMargins(20, 20, 20, 20)
        layout.setSpacing(10)
        
        title_lbl = QLabel(title)
        title_lbl.setObjectName("Title")
        
        lbl = QLabel(label_text)
        
        inputs_layout = QHBoxLayout()
        self.name_field = QLineEdit(default_name)
        self.name_field.setPlaceholderText("Nombre")
        
        self.ext_field = QLineEdit(default_ext)
        self.ext_field.setPlaceholderText("Extensión (ej. txt)")
        self.ext_field.setMaximumWidth(100)
        
        inputs_layout.addWidget(self.name_field)
        
        dot_lbl = QLabel(".")
        inputs_layout.addWidget(dot_lbl)
        
        inputs_layout.addWidget(self.ext_field)
        
        btn_layout = QHBoxLayout()
        btn_layout.addStretch()
        
        btn_cancel = QPushButton("CANCELAR")
        btn_accept = QPushButton("ACEPTAR")
        
        btn_cancel.clicked.connect(self.reject)
        btn_accept.clicked.connect(self.accept)
        
        btn_layout.addWidget(btn_cancel)
        btn_layout.addWidget(btn_accept)
        
        layout.addWidget(title_lbl)
        layout.addWidget(lbl)
        layout.addLayout(inputs_layout)
        layout.addStretch()
        layout.addLayout(btn_layout)
        
        self.name_field.setFocus()
        self.name_field.selectAll()
        
    def get_full_name(self):
        name = self.name_field.text().strip()
        ext = self.ext_field.text().strip()
        if ext.startswith('.'):
            ext = ext[1:]
        if ext:
            return f"{name}.{ext}"
        return name

