"""Todo el diseño de Kyora: colores, medidas, curvas y tiempos. Es la única fuente de diseño.

Las medidas están en píxeles lógicos de Qt (con la pantalla al 125 % un píxel lógico son 1,25 físicos).
Colores tomados del fondo de pantalla de Gustavo: azul marino profundo con dorado paja de acento;
el dorado se reserva para lo activo, lo seleccionado y lo que tiene el foco.
"""
from dataclasses import dataclass, replace


@dataclass(frozen=True)
class Theme:
    # ---------- colores (#rrggbb o #aarrggbb, como los entiende QColor) ----------
    frame: str = "#101010"  # el marco, la barra y el buscador son una sola pieza de gris muy oscuro neutro
    frame_edge: str = "#1fffffff"  # borde fino del buscador que sale del marco
    ink: str = "#e8e8e8"
    dim: str = "#9a9a9a"
    warn: str = "#e07a5f"  # uso alto (CPU, RAM o disco por encima de `warn_at`)
    hover: str = "#14ffffff"
    field: str = "#4d000000"
    line: str = "#1fffffff"
    # acento: se sustituye por el color principal del fondo de pantalla (ver with_accent); "gold" es el nombre histórico
    gold: str = "#e3b25a"
    gold_soft: str = "#29e3b25a"
    gold_line: str = "#80e3b25a"

    # ---------- marco ----------
    bar_width: int = 48  # la barra vertical de la izquierda es la parte ancha del marco (48 = px enteros a 125 %)
    frame_width: int = 8  # grosor del marco arriba, a la derecha y abajo
    hole_radius: int = 16  # esquinas interiores redondeadas del hueco donde viven las ventanas

    # ---------- ventanas dentro del hueco ----------
    window_gap: int = 6  # separación pequeña entre ventanas del mosaico (≈ 8 px a 125 %)
    window_margin_single: int = 12  # margen con el marco con una sola ventana (15 px reales a 125 %; el doble de su sombra)
    window_margin_multi: int = 12  # y con varias: el mosaico se separa del marco, pero no entre ventanas

    # ---------- relieve del marco (skeuomorfismo moderno) ----------
    frame_light: str = "#151515"  # parte alta del marco (le da la luz): siempre gris muy oscuro
    frame_dark: str = "#0a0a0a"  # parte baja
    # el hueco y las piezas que sobresalen (buscador, cápsulas, paneles) llevan el mismo borde; el interior, con sombra
    edge_dark: str = "#b3000000"  # línea oscura fina por fuera: más oscura que el filete aunque el fondo sea claro
    edge_light: str = "#40ffffff"  # filete de luz por dentro, igual en todo el contorno
    edge_shadow_size: float = 6.0  # sombra corta y suave que el borde interior proyecta sobre el fondo
    edge_shadow_alpha: float = 0.35  # su opacidad pegada al borde; igual en los 4 lados
    edge_width: float = 1.6
    capsule: str = "#1c1c1c"  # fondo de las cápsulas (escritorios) y tarjetas: un gris algo más claro que el marco
    panel_radius: float = 8.0  # esquinas del panel de espera (Alt+E): las mismas que las ventanas de Windows 11
    capsule_pressed: str = "#111111"  # píldora hundida del elemento activo
    dots_pill: str = "#050505"  # píldora de los escritorios
    dot_busy: str = "#d6d6d6"  # escritorio con ventanas
    dot_empty: str = "#3a3a3a"  # escritorio vacío
    dot_active: str = "#ffffff"  # círculo grande del escritorio activo (con su número en `dots_pill`)

    # ---------- barra lateral ----------
    font_family: str = "Segoe UI"
    mono_family: str = "Consolas"  # letra de los textos del panel de espera (Alt+E)
    font_px: int = 13  # tamaño mínimo acordado para la barra
    small_px: int = 11
    item_size: int = 32  # alto y ancho de cada botón de la barra
    item_radius: int = 8
    gauge_size: int = 30  # anillos de CPU, RAM y disco
    warn_at: int = 90  # % a partir del cual un anillo se pinta con `warn`

    # ---------- buscador: sale del borde superior del marco ----------
    search_width: int = 560
    search_rows: int = 6  # opciones que caben a la vez encima del campo de escritura
    search_start_width: float = 1.0  # ancho al nacer, como fracción del final: sale ya con su tamaño real
    joint_radius: int = 22  # curvas cóncavas (radio invertido) donde el buscador se une al marco
    corner_radius: int = 18  # esquinas inferiores del buscador
    search_padding: int = 14
    open_ms: int = 240  # con OutQuint: arranca con soltura y se asienta despacio, sin rebote
    close_ms: int = 180  # con InOutCubic: suave al empezar y al terminar
    morph_ms: int = 220  # el panel de la barra se transforma de una página a otra
    content_fade_ms: int = 90

    # ---------- panel superior (Win+I/E/T/B/K): Lobby, Archivos, Tareas, Segundo Cerebro y Kyora ----------
    hub_width: float = 0.68  # fracción del ancho del hueco
    hub_height: float = 0.74  # fracción del alto del hueco
    card: str = "#161616"  # tarjeta exterior
    card_inner: str = "#0e0e0e"  # fondo de la mini barra de secciones
    card_line: str = "#2a2a2a"  # borde fino de las píldoras
    card_radius: float = 18.0
    # placas de cristal (como la referencia): degradado suave, borde casi invisible y un filete de luz arriba
    glass_top: str = "#1e2023"
    glass_bottom: str = "#15161a"
    glass_edge: str = "#14ffffff"
    glass_hi: str = "#24ffffff"  # resaltado suave (la hora de AHORA, lo elegido en las listas)
    pick_bg: str = "#f2f2f2"  # lo elegido en claro con tinta oscura (hoy, la tarea abierta, la sección activa)
    pick_ink: str = "#141414"
    positive: str = "#3fb37f"  # cambios a mejor (como el +12 % de la referencia)
    nav_active_top: str = "#3a3a3a"  # píldora en relieve de la sección activa
    nav_active_bottom: str = "#2a2a2a"
    bar_chart: str = "#4a4d52"  # barras de la gráfica; la actual va más clara
    explorer_font_px: int = 15  # el resto de la interfaz usa 15 px como mínimo (la barra es la excepción)
    explorer_icon: int = 48  # iconos de la vista en cuadrícula
    explorer_sidebar: int = 230  # lugares y árbol de carpetas
    explorer_preview: int = 340  # vista previa (Espacio)

    # ---------- contorno de la ventana activa ----------
    focus_color: str = "#e3b25a"
    focus_width: float = 1.5  # sin borde fijo: solo se ve la luz que gira
    focus_glow: float = 9.0  # halo de la luz neón alrededor del borde
    focus_core: str = "#f4f0ff"  # núcleo casi blanco de la luz neón (se tiñe un poco del acento)
    focus_glow_alpha: float = 0.45  # intensidad de esa luz pegada al borde
    focus_tail: float = 0.5  # largo de la cola de la luz, como fracción de la vuelta: casi medio borde iluminado
    focus_spin_ms: int = 3200  # lo que tarda la luz en dar una vuelta completa al borde
    focus_gap: float = -1.0  # justo sobre el píxel del borde de la ventana: pegadas, por fuera pisaría a la vecina
    focus_radius: float = 8.0  # esquina de las ventanas de Windows 11 (Kyora deja su borde como lo dibuja Windows)
    focus_rest: float = 0.85  # opacidad final: al cambiar de ventana aparece con un fundido, sin deslizarse ni destellar
    focus_fade_ms: int = 90

    # ---------- resaltado del hueco destino al arrastrar ----------
    drop_color: str = "#4fe3b25a"
    drop_line: str = "#c0e3b25a"
    drop_radius: float = 10.0

    def with_accent(self, color):
        """Copia del tema con `color` (#rrggbb) como acento en la selección, el contorno y el arrastre."""
        rgb = color.lstrip("#")
        return replace(
            self, gold=f"#{rgb}", gold_soft=f"#29{rgb}", gold_line=f"#80{rgb}", focus_color=f"#{rgb}",
            drop_color=f"#4f{rgb}", drop_line=f"#c0{rgb}",
        )

    def margins(self):
        """(separación entre ventanas, margen con una ventana, margen con varias), en píxeles lógicos."""
        return self.window_gap, self.window_margin_single, self.window_margin_multi

    def insets(self):
        """(izquierda, arriba, derecha, abajo) que ocupa el marco alrededor del hueco, en píxeles lógicos."""
        return self.bar_width, self.frame_width, self.frame_width, self.frame_width


THEME = Theme()
