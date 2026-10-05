"""
Punto de entrada de Kiora.
Inicia la aplicación, crea el ViewModel, la View y conecta dependencias.
"""
import sys
import os

# Aseguramos que la raíz del proyecto esté en el PYTHONPATH
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from PySide6.QtWidgets import QApplication
from core.kioraUI.viewmodels.main_viewmodel import MainViewModel
from core.kioraUI.views.main_window import MainWindow

def main():
    app = QApplication(sys.argv)
    
    # 1. Inyección de dependencias y ensamblado (Arquitectura Limpia)
    viewmodel = MainViewModel()
    window = MainWindow(viewmodel=viewmodel)
    
    # 2. Mostrar GUI
    window.show()
    
    # 3. Iniciar Loop de eventos
    sys.exit(app.exec())

if __name__ == "__main__":
    main()
