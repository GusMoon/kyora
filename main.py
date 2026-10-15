import sys
import os

# Ocultar advertencias inofensivas de fuentes antiguas en Windows
os.environ["QT_LOGGING_RULES"] = "qt.qpa.fonts.warning=false"

# Directorio base compatible con ejecución normal y ejecutable PyInstaller
if getattr(sys, "frozen", False):
    BASE_DIR = getattr(sys, "_MEIPASS", os.path.dirname(sys.executable))
else:
    BASE_DIR = os.path.dirname(os.path.abspath(__file__))

# Aseguramos que el directorio base esté en el PYTHONPATH
if BASE_DIR not in sys.path:
    sys.path.insert(0, BASE_DIR)

from PySide6.QtWidgets import QApplication
from PySide6.QtGui import QFontDatabase, QFont, QIcon
from core.matrix.motherboard.motherboardRoot import MotherboardRoot

def main():
    # ID de modelo de usuario en Windows para asociar icono a la barra de tareas
    try:
        import ctypes
        ctypes.windll.shell32.SetCurrentProcessExplicitAppUserModelID("kiora.ai.secondbrain.v1")
    except Exception:
        pass

    app = QApplication(sys.argv)
    
    # Cargar fuentes personalizadas
    font_path = os.path.join(BASE_DIR, "core", "resources", "font", "prototype", "Prototype.ttf")
    if os.path.exists(font_path):
        QFontDatabase.addApplicationFont(font_path)
    
    app.setFont(QFont("Prototype", 10))

    # Establecer icono de la aplicación en la barra de tareas y ventanas
    icon_path = os.path.join(BASE_DIR, "core", "resources", "kiora.ico")
    if os.path.exists(icon_path):
        app.setWindowIcon(QIcon(icon_path))
    
    window = MotherboardRoot()
    if os.path.exists(icon_path):
        window.setWindowIcon(QIcon(icon_path))
    
    window.show()
    sys.exit(app.exec())

if __name__ == "__main__":
    main()
