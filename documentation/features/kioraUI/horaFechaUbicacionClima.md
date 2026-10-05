# Feature: Reloj y Clima

Esta funcionalidad se encarga de mantener un reloj digital principal en pantalla, así como de auto-ubicar al usuario basándose en su IP para obtener el clima actual, sin necesidad de configuración previa.

## Arquitectura

*   **View (`main_window.py`):** Utiliza tres `QLabel` (time, date, weather) con estilo minimalista/Sci-Fi para presentar la información. Escucha las señales que el ViewModel emite.
*   **ViewModel (`main_viewmodel.py`):** Instancia un `QTimer` que corre 1 vez por segundo, formateando y emitiendo la hora exacta y la fecha. Además, arranca un worker asíncrono para pedir la ubicación.
*   **Worker (`weather_worker.py`):** Instancia de `QThread` diseñada específicamente para absorber el tiempo de espera de la solicitud HTTP a la API, previniendo cuelgues o *freezes* en la interfaz.
*   **Use Case (`core/kioraUI/application/use_cases/fetch_weather_location.py`):** Envuelve el servicio de infraestructura para respetar la Clean Architecture.
*   **Service (`core/kioraUI/infrastructure/services/weather_location_service.py`):** Realiza llamadas HTTP limpias (usando `urllib` estándar para no agregar peso) a `ip-api.com` (Ubicación) y `open-meteo.com` (Temperatura).

## Ventajas Técnicas
*   Cero dependencias adicionales de terceros (como `requests`), manteniendo Kiora ligero.
*   Hilos secundarios mantienen Kiora a 60fps constantes, cumpliendo con las `pyside6Guidelines`.
