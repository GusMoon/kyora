from PySide6.QtCore import QObject, Signal, QTimer
from datetime import datetime
from core.matrix.workers.weather_worker import WeatherWorker

class MainViewModel(QObject):
    time_updated = Signal(str)
    date_updated = Signal(str)
    weather_updated = Signal(str, str)
    
    def __init__(self, weather_use_case):
        super().__init__()
        self.weather_use_case = weather_use_case
        self._worker = None
        
        # Timer para el reloj (1 vez por segundo)
        self.timer = QTimer()
        self.timer.timeout.connect(self.update_clock)
        self.timer.start(1000)
        self.update_clock() # Actualizar instantáneamente al arrancar
        
        # Petición inicial asíncrona de clima y ubicación
        self.fetch_weather()
        
    def update_clock(self):
        now = datetime.now()
        # Formato de hora (ej: 03:28)
        self.time_updated.emit(now.strftime("%H:%M"))
        
        # Formato de fecha básico (En un proyecto completo se usaría locale)
        self.date_updated.emit(now.strftime("%d/%m/%Y"))
        
    def fetch_weather(self):
        # Lanzamos el worker en segundo plano para no congelar la UI
        self._worker = WeatherWorker(self.weather_use_case)
        self._worker.finished_ok.connect(self._on_weather_fetched)
        self._worker.start()
        
    def _on_weather_fetched(self, loc, temp):
        self.weather_updated.emit(loc, temp)
