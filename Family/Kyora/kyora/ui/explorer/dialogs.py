"""Diálogos del explorador: renombrar, confirmar y "ya existe un archivo con ese nombre".

Son pequeñas tarjetas sin marco dentro del explorador (con su borde de acento), modales para que el teclado vaya
a ellas. Mientras están abiertas el explorador no se cierra al perder el foco (ver EdgePopout._owns_focus).
"""
import os

from PySide6.QtCore import Qt
from PySide6.QtWidgets import (
    QCheckBox,
    QDialog,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QPushButton,
    QVBoxLayout,
    QWidget,
)


class _Card(QDialog):
    def __init__(self, parent, title):
        super().__init__(parent, Qt.FramelessWindowHint | Qt.Dialog)
        self.setAttribute(Qt.WA_TranslucentBackground)
        self.setModal(True)
        self.card = QWidget(self)
        self.card.setObjectName("Dialog")
        self.card.setAttribute(Qt.WA_StyledBackground)  # un QWidget sin esto no pinta el fondo de la hoja de estilos
        outer = QVBoxLayout(self)
        outer.setContentsMargins(0, 0, 0, 0)
        outer.addWidget(self.card)
        self.layout_ = QVBoxLayout(self.card)
        self.layout_.setContentsMargins(20, 18, 20, 18)
        self.layout_.setSpacing(12)
        heading = QLabel(title)
        heading.setStyleSheet("font-weight: bold;")
        self.layout_.addWidget(heading)
        self.setMinimumWidth(420)

    def buttons(self, *specs):
        """specs: (texto, función, acento). Devuelve los botones en orden."""
        row = QHBoxLayout()
        row.addStretch(1)
        made = []
        for text, fn, accent in specs:
            b = QPushButton(text)
            b.setCursor(Qt.PointingHandCursor)
            if accent:
                b.setObjectName("Accent")
                b.setDefault(True)
            b.clicked.connect(fn)
            row.addWidget(b)
            made.append(b)
        self.layout_.addLayout(row)
        return made

    def show_centered(self):
        parent = self.parentWidget()
        self.adjustSize()
        if parent is not None:
            center = parent.mapToGlobal(parent.rect().center())
            self.move(center.x() - self.width() // 2, center.y() - self.height() // 2)
        return self.exec()


def ask_name(parent, title, current, select_stem=True):
    """Pide un nombre. Devuelve el texto o None si se cancela. Selecciona el nombre sin la extensión."""
    card = _Card(parent, title)
    edit = QLineEdit(current)
    card.layout_.addWidget(edit)
    card.buttons(("Cancelar", card.reject, False), ("Aceptar", card.accept, True))
    stem = os.path.splitext(current)[0] if select_stem and not current.startswith(".") else current
    edit.setSelection(0, len(stem) or len(current))
    edit.returnPressed.connect(card.accept)
    edit.setFocus()
    return edit.text().strip() if card.show_centered() == QDialog.Accepted else None


def confirm(parent, title, text, action):
    """Pregunta antes de algo destructivo. True si se acepta."""
    card = _Card(parent, title)
    label = QLabel(text)
    label.setObjectName("Dim")
    label.setWordWrap(True)
    card.layout_.addWidget(label)
    _, ok = card.buttons(("Cancelar", card.reject, False), (action, card.accept, True))
    ok.setFocus()
    return card.show_centered() == QDialog.Accepted


def ask_conflict(parent, name):
    """Ya existe `name` en el destino. Devuelve (elección, aplicar a todos); elección = replace / both / skip."""
    card = _Card(parent, f"Ya existe «{name}» aquí")
    label = QLabel("Si lo reemplazas, el que había va a la Papelera.")
    label.setObjectName("Dim")
    card.layout_.addWidget(label)
    every = QCheckBox("Hacer lo mismo con los demás repetidos")
    card.layout_.addWidget(every)
    choice = ["skip"]

    def pick(value):
        choice[0] = value
        card.accept()

    card.buttons(("Omitir", lambda: pick("skip"), False), ("Reemplazar", lambda: pick("replace"), False),
                 ("Conservar ambos", lambda: pick("both"), True))
    card.show_centered()
    return choice[0], every.isChecked()
