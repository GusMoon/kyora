# Registro de Cambios: Ajuste Manual de Cronómetro, Campo de Fecha Limpio y Gestión Neutral de Categorías

**Fecha:** 13 de Octubre de 2026  
**Módulos Afectados:**
- `core/matrix/ecosystems/tasks/presentation/rootComponents/taskMetadata/general/task_create_dialog.py`
- `core/matrix/ecosystems/tasks/presentation/rootComponents/taskMetadata/general/task_detail_dialog.py`
- `core/matrix/ecosystems/tasks/presentation/rootComponents/taskMetadata/general/category_dialog.py`
- `core/matrix/ecosystems/tasks/presentation/rootComponents/taskMetadata/chronometer/timer_dialog.py`
- `core/matrix/ecosystems/tasks/presentation/rootComponents/taskMetadata/base_modal.py`
- `core/matrix/ecosystems/tasks/presentation/taskCard.py`
- `core/matrix/ecosystems/tasks/presentation/tasks_view.py`
- `core/matrix/ecosystems/tasks/presentation/tasks_viewmodel.py`
- `core/matrix/ecosystems/tasks/use_cases/manage_tasks.py`
- `core/matrix/ecosystems/tasks/infrastructure/sqlite_task_repository.py`
- `core/matrix/ecosystems/motherBoard/globalComponents/icons/trash.py`
- `core/matrix/ecosystems/motherBoard/globalComponents/icons/__init__.py`

---

## 1. Resumen de Modificaciones

### 1.1. Ajuste Manual en Inputs del Cronómetro (Sin Flechitas)
- **Eliminación de Subcontroles de Incremento/Decremento:**
  - Se configuró `setButtonSymbols(QSpinBox.NoButtons)` y la regla QSS `QSpinBox::up-button, QSpinBox::down-button { width: 0px; height: 0px; border: none; background: transparent; }` en `TaskCreateDialog`, `TaskDetailDialog` y `TimerDurationDialog`.
  - Se centró el texto numérico con `setAlignment(Qt.AlignCenter)` y se optimizó el ancho a 65px para evitar colisiones y permitir que el usuario ingrese las horas y minutos de forma manual y limpia directamente con el teclado.

### 1.2. Eliminación del Botón / Recuadro Gris en Fecha de Entrega
- **Supresión de `QDateEdit::drop-down`:**
  - Se eliminó el botón de despliegue nativo derecho configurando su ancho y alto en 0px (`width: 0px; height: 0px; border: none; background: transparent;`) tanto en `base_modal.py` como en los diálogos individuales.
  - Ya no se reserva ningún espacio para botón en el extremo derecho del input; la fecha ocupa el espacio limpio y continuo.
  - La apertura del calendario se controla exclusivamente a través del botón con icono de calendario ubicado al lado izquierdo, mapeando la posición global de apertura directamente en pantalla.

### 1.3. Categorías Monocromáticas (Sin Colores) y Soporte Completo de Edición y Eliminación
- **Eliminación de Colores:**
  - Se eliminaron las paletas de color y selectores cromáticos en `CategoryCreateDialog`.
  - El modal de categoría ahora es compacto, enfocado en el nombre de la clasificación.
  - Los badges en las tarjetas Kanban (`TaskCard`) y los elementos de los combo boxes se presentan en estilo monocromático Sci-Fi (`#CCCCCC` con fondo `#1A1A1A` y borde `#383838`), sin viñetas de colores saturados.
- **Edición y Eliminación de Categorías:**
  - Se incorporaron los botones `✎ EDITAR` y `btn_delete_cat` en la fila de selección de categorías de `TaskCreateDialog` y `TaskDetailDialog`.
  - Dichos botones se muestran dinámicamente cuando hay una categoría real seleccionada (distinta de `[Sin categoría]`).
  - **Editar:** Abre `CategoryCreateDialog` en modo edición para renombrar la categoría y actualizarla inmediatamente en la base de datos y la interfaz.
  - **Eliminar:** Muestra confirmación Sci-Fi y desvincula las tareas de dicha categoría (`category_id = NULL`) antes de borrar el registro, conservando intactas todas las tareas.

### 1.4. Icono Sci-Fi de Bote de Basura (`trash.py`)
- **Nuevo Icono Vectorial:**
  - Se creó el módulo `core/matrix/ecosystems/motherBoard/globalComponents/icons/trash.py` con las funciones `draw`, `get_trash_pixmap` y `get_trash_icon`.
  - Geometría de alta precisión inspirada en la referencia: asa superior, tapa extendida, contenedor cónico con biseles inferiores y doble ranura vertical de desintegración.
  - Soporta estados dinámicos (color neutral `#888888` en reposo y alerta roja Sci-Fi `#FF5555` en hover).
  - Integrado en `btn_delete_cat` en los modales de creación y detalle para la eliminación de categorías.
