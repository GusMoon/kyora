# Registro de Cambios: Actualización de Interacciones y Descripción en TaskCard

**Fecha:** 2026-10-11  
**Autor:** Antigravity  
**Archivo afectado:** [`core/matrix/ecosystems/tasks/presentation/taskCard.py`](file:///c:/secondBrain/proyectos/kiora/core/matrix/ecosystems/tasks/presentation/taskCard.py)

---

## 1. Resumen de Requerimientos
1. **Vista Principal (Compacta):**
   - Se removió la vista previa truncada de la descripción (`[+ Ver más]`) de la vista principal del card.
   - La tarjeta mantiene una altura uniforme de 68px cuando está cerrada, mostrando título, subtareas, fecha y el indicador `▼ Descripción`.
2. **Vista Extendida (1 Clic):**
   - Al dar un solo clic en la tarjeta (si posee descripción), se expande para mostrar la descripción completa.
   - El alto del contenedor se calcula dinámicamente con `QFontMetrics` adaptándose al texto (rango de 65px a 180px).
   - Si la descripción excede la altura máxima, integra un `QScrollArea` con la barra de scroll minimalista de Kiora para navegación fluida.
   - El texto se amplió de 11px a 12px con interlineado de 1.45, mejorando la legibilidad sin alterar proporciones.
3. **Apertura de Metadatos (2 Clics / Doble Clic):**
   - Se implementó un timer de desacoplamiento de 220ms (`QTimer`) en `mouseReleaseEvent`:
     - 1 clic: Dispara la expansión/colapso de la descripción tras el timeout.
     - 2 clics (doble clic): Cancela el timer de 1 clic y emite `open_requested`, abriendo de inmediato el modal de metadatos `TaskDetailDialog` de [`taskMetadata`](file:///c:/secondBrain/proyectos/kiora/core/matrix/ecosystems/tasks/presentation/rootComponents/taskMetadata).
     - EventFilter en el área de scroll para asegurar que el doble clic sobre la descripción también abra el modal.

---

## 2. Verificación
- Se verificó la importación y sintaxis de [`taskCard.py`](file:///c:/secondBrain/proyectos/kiora/core/matrix/ecosystems/tasks/presentation/taskCard.py) con Python sin errores (código de salida 0).
