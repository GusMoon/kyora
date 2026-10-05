from PySide6.QtCore import QThread, Signal

class WeatherWorker(QThread):
    finished_ok = Signal(str, str) # location, temp
    
    def __init__(self, use_case):
        super().__init__()
        self.use_case = use_case
        
    def run(self):
        loc, temp = self.use_case.execute()
        self.finished_ok.emit(loc, temp)
