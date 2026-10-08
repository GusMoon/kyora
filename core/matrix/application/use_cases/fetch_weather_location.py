class FetchWeatherLocationUseCase:
    def __init__(self, service):
        self.service = service
        
    def execute(self):
        """
        Ejecuta la regla de negocio para obtener los datos de entorno.
        Retorna: (location: str, temperature: str)
        """
        return self.service.get_current_data()
