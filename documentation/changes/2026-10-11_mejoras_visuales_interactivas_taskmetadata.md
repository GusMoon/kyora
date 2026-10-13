# Registro de Cambios: Mejoras Visuales e Interactivas en taskMetadata

**Fecha:** 2026-10-11  
**Autor:** Antigravity  
**Alcance:** [`core/matrix/ecosystems/tasks/presentation/rootComponents/taskMetadata/`](file:///c:/secondBrain/proyectos/kiora/core/matrix/ecosystems/tasks/presentation/rootComponents/taskMetadata)

---

## 1. Resumen de Requerimientos Implementados

1. **Sección Fecha de Entrega:**
   - Se removió el texto `"Fecha límite:"`.
   - Se incorporó un icono de calendario `📅` al lado del selector de fecha.
   - Se actualizaron las opciones predeterminadas a 6 botones distribuidos en 2 filas organizadas: `+1 DÍA`, `+3 DÍAS`, `+5 DÍAS`, `+7 DÍAS`, `+15 DÍAS` y `+30 DÍAS`.

2. **Encabezado del Modal:**
   - Se removió el icono de arrastre (`⋮⋮`) y la etiqueta de estado (`[PENDING]`).
   - El título superior se simplificó limpiamente a `"DETALLES DE LA TAREA"` (y `"CREAR NUEVA TAREA"` en el modal de creación).

3. **Panel de Descripción y Efecto de Desplazamiento (Scroll Fade):**
   - El encabezado se simplificó de `"● DESCRIPCIÓN & NOTAS EXTENSAS"` a `"● DESCRIPCIÓN"`.
   - Se creó el componente [`FadingScrollTextEdit`](file:///c:/secondBrain/proyectos/kiora/core/matrix/ecosystems/tasks/presentation/rootComponents/taskMetadata/fading_text_edit.py), el cual proyecta un efecto de desvanecimiento dinámico (gradiente superior e inferior en tono `#0A0A0A`) **exclusivamente durante el desplazamiento** con rueda o barra de scroll. Mientras no se hace scroll, el efecto desaparece por completo permitiendo ver el texto nítido hasta los bordes.

4. **Subtareas:**
   - El checkbox de completado ahora renderiza de forma garantizada y centrada el icono `✓`.
   - La descripción de la subtarea utiliza un editor multilínea que adapta dinámicamente su altura al contenido (36px a 125px con scroll).
   - Se agregó un control de apertura y cierre (`▾ Nota` / `▲ Ocultar`) para colapsar y desplegar la descripción para que no estorbe si no se necesita ver.

5. **Redimensionamiento en 8 Direcciones:**
   - En [`SciFiBaseModal`](file:///c:/secondBrain/proyectos/kiora/core/matrix/ecosystems/tasks/presentation/rootComponents/taskMetadata/base_modal.py) se implementó redimensionamiento libre desde cualquier borde o esquina (superior, inferior, laterales y las 4 esquinas diagonales).
   - Se fijó `setMinimumSize(920, 550)`, impidiendo que la ventana se haga más pequeña que sus dimensiones originales, pero permitiendo agrandarla libremente.

---

## 2. Archivos Afectados
- [`base_modal.py`](file:///c:/secondBrain/proyectos/kiora/core/matrix/ecosystems/tasks/presentation/rootComponents/taskMetadata/base_modal.py)
- [`subtask_item.py`](file:///c:/secondBrain/proyectos/kiora/core/matrix/ecosystems/tasks/presentation/rootComponents/taskMetadata/subtask_item.py)
- [`fading_text_edit.py`](file:///c:/secondBrain/proyectos/kiora/core/matrix/ecosystems/tasks/presentation/rootComponents/taskMetadata/fading_text_edit.py) *(nuevo componente)*
- [`task_detail_dialog.py`](file:///c:/secondBrain/proyectos/kiora/core/matrix/ecosystems/tasks/presentation/rootComponents/taskMetadata/task_detail_dialog.py)
- [`task_create_dialog.py`](file:///c:/secondBrain/proyectos/kiora/core/matrix/ecosystems/tasks/presentation/rootComponents/taskMetadata/task_create_dialog.py)
- [`taskMetadataMain.py`](file:///c:/secondBrain/proyectos/kiora/core/matrix/ecosystems/tasks/presentation/rootComponents/taskMetadata/taskMetadataMain.py)
- [`__init__.py`](file:///c:/secondBrain/proyectos/kiora/core/matrix/ecosystems/tasks/presentation/rootComponents/taskMetadata/__init__.py)
