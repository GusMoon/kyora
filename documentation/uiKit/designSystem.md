# KioraUI Design System

Este documento centraliza los lineamientos visuales, colores y formas que conforman la identidad gráfica de Kiora, previniendo que los desarrolladores usen valores "mágicos" dentro del código fuente.

## 1. Paleta de Colores

*   **Background Principal:** `#1E1E1E` (Gris Oscuro)
    *   *Uso:* Color sólido de base para las ventanas y paneles principales.
*   **Puntos de Cuadrícula (Grid):** `#3A2326` (Gris Vino)
    *   *Uso:* Textura de fondo decorativa para dar un aspecto tecnológico/analítico al panel.
*   **Acento (Sci-Fi):** `#A31F34` (Rojo Vino)
    *   *Uso:* Elementos interactivos, botones de cierre, tipografía del reloj e indicadores.

## 2. Texturas y Fondos
*   **Grid (Malla):** La separación oficial de los puntos decorativos de la cuadrícula es de **15 píxeles** (alta densidad). 

## 3. Estilo de la Ventana (Window Frame)
*   **Bordes:** `Frameless` (Sin bordes del sistema operativo).
*   **Estado:** `Maximized` por defecto (Nunca minimizable para mantener presencia como overlay principal).
*   **Transparencia:** `3%` de transparencia total (`Opacity = 0.97`). Esto otorga a Kiora una sutil fusión con el escritorio sin perder legibilidad.

## 4. Iconografía de Interfaz
Se utilizan glifos del sistema o polígonos dibujados mediante `QPainter` en lugar de emojis para mantener pureza visual.

*   **Carpetas (Explorador):** Amarillo Sci-Fi (`#E8B923`) con resplandor superior (`#FFE47A`).
*   **Archivos (Explorador):** Gris Neutro (`#A0A0A0`) simulando una hoja con doblez claro (`#D0D0D0`).
