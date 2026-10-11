# Kiora Redesign - Nueva Paleta de Colores

Para lograr un diseño más limpio, enfocado y profesional, hemos simplificado los estilos visuales de Kiora. **Se han retirado completamente los tonos azules y amarillos.**

## 1. Paleta de Colores Activa (Monocromática + Acento)

### Fondos y Contenedores
*   **Base Principal:** `#121212` (Negro Oscuro)
    *   *Uso:* Fondo sólido de la ventana principal y fondo absoluto.
*   **Fondo de Contenedores:** `#161616` a `#1A1A1A`
    *   *Uso:* Fondo de paneles internos, listas y componentes modulares.
*   **Fondo Claro (Hover):** `#1E1E1E` a `#2A2A2A`
    *   *Uso:* Elementos activos, hover states ligeros o input boxes.

### Bordes y Líneas
*   **Borde Primario:** `#444444`
    *   *Uso:* Contornos de ventanas flotantes, divisores principales e inputs.
*   **Borde Secundario/Hover:** `#555555` a `#666666`
    *   *Uso:* Elementos sobre los que el usuario interactúa, hover en botones.
*   **Divisores Suaves:** `#333333`
    *   *Uso:* Líneas separadoras sutiles.

### Tipografía y Textos
*   **Texto Principal:** `#FFFFFF` (Blanco)
    *   *Uso:* Títulos, información clave, y lectura (Reemplaza a los antiguos amarillos y azules).
*   **Texto Secundario:** `#E0E0E0` (Gris Claro)
    *   *Uso:* Subtítulos, textos de apoyo.
*   **Texto Desactivado / Terciario:** `#A0A0A0`
    *   *Uso:* Índices, labels de estado, textos con menor jerarquía.

### Acentos Estratégicos
*   **Acento Sci-Fi:** `#A31F34` (Rojo Vino)
    *   *Uso:* Elementos críticos, botones de acción principal e indicadores de estado fuerte (Reemplaza al rojo base `#eb5757`).

## 2. Elementos Eliminados
Con el fin de limpiar la interfaz, **se han removido por completo** los siguientes elementos:
*   Tonos Azules (`#0099FF`, `#80BFFF`, etc).
*   Tonos Amarillos/Naranjas (`#FFB84D`).
*   Transparencia en la ventana principal (`opacity`) y todos los contenedores hijos.
*   Puntos de cuadrícula (Grid), sombras superpuestas y líneas decorativas de fondo.
