# Log de Cambios: Funcionalidad de Reloj, Fecha y Clima

**Fecha y hora:** 2026-10-05 11:40:00

**Archivos afectados:**
*   `+ c:\proyectos\kiora\core\infrastructure\services\weather_location_service.py`
*   `+ c:\proyectos\kiora\core\application\use_cases\fetch_weather_location.py`
*   `+ c:\proyectos\kiora\core\kioraUI\workers\weather_worker.py`
*   `+ c:\proyectos\kiora\documentation\features\time_and_weather.md`
*   `* c:\proyectos\kiora\core\kioraUI\viewmodels\main_viewmodel.py`
*   `* c:\proyectos\kiora\core\kioraUI\views\main_window.py`
*   `* c:\proyectos\kiora\main.py`

**Explicación breve:**
Se ha añadido la primera gran funcionalidad interactiva de la pantalla base de Kiora. Ahora muestra un reloj digital de gran tamaño inspirado en interfaces holográficas Sci-Fi, la fecha, y un panel de detección automática que localiza la ciudad/país mediante IP e inyecta la temperatura actual (usando Open-Meteo).

**Cambios lógicos:**
- Se implementó Clean Architecture pura creando el servicio de infraestructura de APIs y pasándolo mediante inyección de dependencias a través del `UseCase` hacia el `ViewModel` en el archivo raíz `main.py`.
- Se creó `WeatherWorker` (`QThread`) como un trabajador asíncrono, protegiendo totalmente la interfaz de usuario contra congelamientos por demoras en la red, logrando así el 100% de cumplimiento de nuestras normativas.
- Se añadió un `QTimer` en el ViewModel que despacha señales con el estado horario formateado hacia la Vista.

**Instalaciones:**
Ninguna. Se resolvió la petición de red utilizando el módulo estándar `urllib.request`.

**Toggles:**
N/A
