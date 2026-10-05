"""
ViewModel principal de KioraUI.
Coordina el estado de la aplicación y la interacción con los casos de uso.
"""
from PySide6.QtCore import QObject, Signal

class MainViewModel(QObject):
    # Señales para notificar a la vista sobre cambios de estado
    status_changed = Signal(str)
    
    def __init__(self):
        super().__init__()
        # Estado interno
        self._is_loading = False
