# Kiora Containers Guidelines

Esta documentación define las reglas, propiedades y estándares visuales que todos los contenedores (paneles, modales, ventanas flotantes) de KioraUI deben cumplir para asegurar la consistencia del diseño Sci-Fi del sistema.

## 1. Estructura y Herencia
Todos los contenedores deben heredar del componente base centralizado: `KioraBaseContainer` (ubicado en `core/kioraUI/views/global_ui/base_container.py`).
Esta clase ya provee la arquitectura necesaria:
- **Header**: Barra superior para identificar la sección.
- **Body**: Contenedor principal donde se inyectan los widgets hijos (`self.body_layout`).

## 2. Propiedades Visuales Estandarizadas
- **Transparencia y Glassmorphism**:
  - Los contenedores flotantes no deben ser completamente sólidos.
  - El fondo principal usa un gris oscuro con ligera transparencia (ej. `rgba(22, 22, 22, 0.95)`) para fundirse sutilmente con lo que haya debajo, reforzando la estética futurista.
- **Bordes**:
  - Todo contenedor está delimitado por un borde del color primario (Rojo Vino: `#A31F34`) de 1px.
- **Cabecera (Header)**:
  - Color de fondo: Primario con transparencia (ej. `rgba(163, 31, 52, 0.95)`).
  - Título (Nombre de Sección o Archivo): Siempre visible. Fuente `Segoe UI` o familia sans-serif Sci-Fi, `11px`, `bold` (800), con un espaciado de letras (`letter-spacing`) de 2px. Texto en mayúsculas.
  - Botón de cierre: Estilo minimalista ("✕"), sin bordes, que resalte con el hover.

## 3. Propiedades Dinámicas y Comportamiento
- **Nombres Dinámicos**: El título del contenedor (nombre de archivo, ruta actual o nombre de sección) se debe poder inyectar y modificar en tiempo real (mediante `set_title("NUEVO TITULO")`).
- **Arrastre (Drag & Drop)**: Los contenedores son flotantes e independientes. Se arrastran al hacer clic y mover el ratón desde cualquier parte de su superficie libre.
- **Redimensionamiento (Resize)**: Los contenedores pueden modificar su tamaño al acercar el puntero a cualquiera de sus 4 bordes o esquinas (donde el cursor cambiará de forma automáticamente). Tienen un tamaño mínimo predeterminado para evitar que se colapsen.
  - **Indicador Visual**: Se pinta automáticamente un pequeño triángulo blanco en la esquina inferior derecha como indicador visual de que la ventana se puede estirar.
- **Z-Index Dinámico**: Al hacer clic sobre un contenedor (por ejemplo, en su cabecera o bordes), este automáticamente se trae al frente (`raise_()`) para evitar ser tapado por otros paneles activos.

## Ejemplo de Uso

```python
from core.kioraUI.views.global_ui.base_container import KioraBaseContainer

class MyNewPanel(KioraBaseContainer):
    def __init__(self, parent=None):
        # Se inicializa definiendo el nombre de la sección
        super().__init__(title_text="MY AWESOME SECTION", parent=parent)
        
        # Todo el contenido va dentro de self.body_layout
        label = QLabel("Este contenido respetará las transparencias y bordes.")
        self.body_layout.addWidget(label)
```