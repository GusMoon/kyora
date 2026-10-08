import sys
import os

# Aseguramos que la raíz del proyecto esté en el PYTHONPATH
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from PySide6.QtWidgets import QApplication
from PySide6.QtGui import QFontDatabase, QFont
from core.kioraUI.infrastructure.services.weather_location_service import ApiWeatherLocationService
from core.kioraUI.application.use_cases.fetch_weather_location import FetchWeatherLocationUseCase
from core.kioraUI.viewmodels.main_viewmodel import MainViewModel
from core.kioraUI.views.main_window import MainWindow

def main():
    app = QApplication(sys.argv)
    
    # Cargar fuentes personalizadas
    font_path_space = os.path.join(os.path.dirname(os.path.abspath(__file__)), "core", "resources", "font", "Space_Grotesk", "SpaceGrotesk-VariableFont_wght.ttf")
    
    QFontDatabase.addApplicationFont(font_path_space)
    
    app.setFont(QFont("Space Grotesk", 10))
    
    # Ensamblado (Inyección de dependencias bajo Clean Architecture)
    weather_service = ApiWeatherLocationService()
    weather_use_case = FetchWeatherLocationUseCase(service=weather_service)
    
    viewmodel = MainViewModel(weather_use_case=weather_use_case)
    window = MainWindow(viewmodel=viewmodel)
    
    window.show()
    sys.exit(app.exec())

if __name__ == "__main__":
    main()
