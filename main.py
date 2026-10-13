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
from core.matrix.infrastructure.services.weather_location_service import ApiWeatherLocationService
from core.matrix.application.use_cases.fetch_weather_location import FetchWeatherLocationUseCase
from core.matrix.viewmodels.main_viewmodel import MainViewModel
from core.matrix.ecosystems.rootView import MainWindow

def main():
    # ID de modelo de usuario en Windows para asociar icono a la barra de tareas
    try:
        import ctypes
        ctypes.windll.shell32.SetCurrentProcessExplicitAppUserModelID("kiora.ai.secondbrain.v1")
    except Exception:
        pass

    app = QApplication(sys.argv)
    
    # Cargar fuentes personalizadas
    font_path_space = os.path.join(BASE_DIR, "core", "resources", "font", "Space_Grotesk", "SpaceGrotesk-VariableFont_wght.ttf")
    if os.path.exists(font_path_space):
        QFontDatabase.addApplicationFont(font_path_space)
    
    app.setFont(QFont("Space Grotesk", 10))

    # Establecer icono de la aplicación en la barra de tareas y ventanas
    icon_path = os.path.join(BASE_DIR, "core", "resources", "kiora.ico")
    if os.path.exists(icon_path):
        app.setWindowIcon(QIcon(icon_path))
    
    # Ensamblado (Inyección de dependencias bajo Clean Architecture)
    weather_service = ApiWeatherLocationService()
    weather_use_case = FetchWeatherLocationUseCase(service=weather_service)
    
    viewmodel = MainViewModel(weather_use_case=weather_use_case)
    window = MainWindow(viewmodel=viewmodel)
    if os.path.exists(icon_path):
        window.setWindowIcon(QIcon(icon_path))
    
    window.show()
    sys.exit(app.exec())

if __name__ == "__main__":
    main()
