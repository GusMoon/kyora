# Log de Cambios: Refactorización de Capas de Interfaz

**Fecha y hora:** 2026-10-05 11:46:00

**Archivos afectados:**
*   `- c:\proyectos\kiora\core\application\*`
*   `- c:\proyectos\kiora\core\infrastructure\*`
*   `+ c:\proyectos\kiora\core\kioraUI\application\*`
*   `+ c:\proyectos\kiora\core\kioraUI\infrastructure\*`
*   `* c:\proyectos\kiora\main.py`
*   `* c:\proyectos\kiora\documentation\features\time_and_weather.md`
*   `* c:\proyectos\kiora\documentation\architecture\architecturaKioraUI.md`

**Explicación breve:**
Se ha refactorizado la estructura del proyecto para que todos los servicios e infraestructura que pertenecen puramente al manejo y datos de la UI se alojen dentro del dominio `core/kioraUI`. Esto evita colisiones futuras con la lógica de voz o motores core del proyecto.

**Cambios lógicos:**
- Se movieron las carpetas `application` e `infrastructure` hacia adentro de `core/kioraUI`.
- Se corrigieron las importaciones dependientes en `main.py`.
- Se documentó el nuevo flujo en `architecturaKioraUI.md`.

**Instalaciones:**
N/A

**Toggles:**
N/A
