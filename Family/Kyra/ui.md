# Diseño: estilo LCD monocromo para CCS

Este documento describe el diseño visual de la pantalla. Los colores se eligen en la app, así que aquí se describen por su función y su relación entre sí, no por valor.

## 1. Idea general

Una pantalla de PC vintage: superficie tipo LCD monocromo, con contenido en una sola tinta oscura sobre un fondo apagado. Sin brillos, sin gradientes llamativos y sin color de acento.

**No es** una pantalla 8-bit de colores vivos.

## 2. Colores por función

- **Fondo de la pantalla:** un tono verde-grisáceo apagado, claro pero no blanco. Es el color dominante.
- **Tinta:** un verde casi negro, con el contraste suficiente para leerse sobre el fondo. Es el único color del contenido.
- **Bisel:** un gris metálico, algo más oscuro que la superficie, que enmarca la pantalla. Puede tener un leve cambio de tono de arriba hacia abajo.
- **Fondo exterior:** un tono muy oscuro, casi negro, que hace resaltar el dispositivo.

**Regla:** la pantalla usa solo dos colores de contenido, la tinta y el fondo. Ningún elemento usa un color adicional.

## 3. Superficie

- La pantalla es rectangular, con esquinas casi rectas.
- Encima del contenido hay una cuadrícula fina de píxeles que cubre toda la superficie. Debe ser apenas visible, como la textura de un LCD real.
- El borde interior tiene una sombra leve, como si el cristal tuviera profundidad.

## 4. Trazos y gráficos

- Todos los gráficos son de trazo, no de relleno. Las formas se ven como líneas de una sola tinta.
- Los bordes se ven escalonados, como en una pantalla de baja resolución, no suavizados.
- Las formas en 3D se representan solo con aristas visibles (wireframe).
- Las esferas se representan con una trama punteada, no con sombreado.
- Los iconos se construyen con bloques simples y claros.
- No hay curvas suaves ni sombras difusas en el contenido.

## 5. Tipografía

- **Familia:** monoespaciada, con aspecto de terminal o de código. No uses fuentes sans-serif ni serif.
- **Etiquetas y acciones:** mayúsculas, en negrita, con el espaciado entre letras ampliado.
- **Mensajes de estado o del sistema:** minúsculas, monoespaciada, en cursiva y en un tamaño menor. [Suposición: tomado de la referencia de "error detection...", a resolución baja.]
- **Color del texto:** siempre la tinta.

## 6. Qué evitar

- Colores fuera de la paleta de dos tonos más el bisel.
- Iconos con relleno de color.
- Bordes redondeados en el contenido de la pantalla. El bisel exterior sí puede tener esquinas redondeadas.
- Sombras de texto, brillos o reflejos.
- Animaciones suaves. Si hay movimiento, debe ser por pasos.

## 7. Estado

- **Pantalla base:** definida en este documento.
- **Interactividad:** no definida. Se asume pantalla decorativa. [Suposición]
- **Fuente exacta de código:** pendiente de confirmar. [Suposición]