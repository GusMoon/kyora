"""Reactor: componente circular sci-fi y navegador de Kyora.

Reposo: anillos, arcos y marcas animados, a tamaño reducido y con el centro vacío. Con
el ratón encima crece a su tamaño completo y aparece en el centro un núcleo que muestra
la opción elegida, rodeado por un anillo con las opciones de navegación
(``MODULES``). El anillo se gira arrastrándolo con el ratón o con su rueda; la opción que
queda abajo, sobre la sombra, es la elegida.

Con ``set_pinned(True)`` (directorio) se queda a tamaño completo, sin menú ni
interacción, y ``set_gaps`` le abre huecos libres de dibujo para el contenido que otro
componente escribe encima.

Con los módulos, tras girar el anillo (arrastre o rueda), la opción que queda abajo
llena unos anillos de progreso durante `HOLD_MS` y, al completarse, se activa sin soltar
ni pulsar nada. Cambiar de opción o volver a girar reinicia la cuenta.
"""
import math

from PySide6.QtCore import QEasingCurve, QPointF, QRectF, Qt, QTimer, QVariantAnimation, Signal
from PySide6.QtGui import (
    QColor, QConicalGradient, QCursor, QFont, QFontMetricsF, QPainter, QPainterPath, QPen,
)
from PySide6.QtWidgets import QWidget

import core.resources.icons.agenda as icon_agenda
import core.resources.icons.close as icon_close
import core.resources.icons.explorer as icon_explorer

BRIGHT = QColor(235, 238, 242)
MID = QColor(150, 155, 162)
DIM = QColor(90, 94, 100)
FAINT = QColor(255, 255, 255, 22)

INTRO_MS = 2400
TICK_MS = 16
SPIN_MS = 90000  # una vuelta completa de la rotación continua

REST_SCALE = 0.55        # tamaño del reactor en reposo respecto al completo
MENU_MS = 700            # duración de la transición reposo <-> menú
GROW_END = 0.45         # fracción de la transición en la que termina el crecimiento
RING_INNER = 33          # radio interior de la banda de opciones, en % del radio
RING_OUTER = 62          # radio exterior de la banda de opciones, en % del radio
SHADOW_SPAN = 34         # semiancho angular de la sombra de la opción elegida, en grados
FLASH_MS = 160           # duración del destello del núcleo al cambiar de opción
MENU_SPIN_IN = 120       # grados que giran las opciones al aparecer, hasta su posición
MENU_OPEN_AT = 0.9       # progreso de la transición desde el que la rueda recibe clics
WHEEL_FOLLOW = 0.3       # suavizado del giro de la rueda por cuadro (0..1)
WHEEL_STEP_DELTA = 120   # unidades de angleDelta de la rueda del ratón por paso
DRAG_THRESHOLD = 4       # píxeles que distinguen un arrastre de un clic
SELECTED_ANGLE = 270     # posición de la opción elegida (abajo)
OPTION_RADIUS = (RING_INNER + RING_OUTER) / 2  # radio al que se centran las opciones
OPTION_SIZE = 8          # radio del área de cada opción, en % del radio
OPTION_ICON_FACTOR = 0.34  # escala del icono por cada 1 % del radio
CORE_ICON_FACTOR = 0.5    # escala del icono del núcleo por cada 1 % del radio
CENTER_HIT = 27          # radio del núcleo que activa la opción elegida, en % del radio
HOLD_MS = 2000           # tiempo que una opción de módulo debe quedar abajo para ejecutarse
ALIGN_TOL = 0.1          # distancia de la rueda a una opción, en opciones, para contarla como abajo
CORE_LABEL_WIDTH = 50    # ancho máximo del nombre en el núcleo, en % del radio

# (id emitido, etiqueta, módulo del icono); se reparten por igual en la rueda
MODULES = (
    ("DIRECTORY", "DIRECTORIO", icon_explorer),
    ("CALENDAR", "CALENDARIO", icon_agenda),
    ("CLOSE", "CERRAR", icon_close),
)


def ease(t: float) -> float:
    """Suaviza un progreso 0..1 (salida cúbica)."""
    return 1 - (1 - t) ** 3


def unit(width: float, height: float) -> float:
    """1 % del radio completo de un reactor dibujado en un widget de ese tamaño, en píxeles."""
    return (min(width, height) / 2 - 2) / 100.0


class Reactor(QWidget):
    """Widget circular con anillos, arcos, marcas y puntos.

    Al crearse reproduce una animación de entrada en la que cada elemento aparece
    por etapas; luego los arcos y las marcas giran lentamente.
    Se dibuja proporcional al lado menor del widget con fondo transparente.

    Cuando la entrada termina y el cursor está dentro de su círculo, aparece, con
    animación, en el centro un núcleo con la opción elegida rodeado por un anillo con una
    opción por elemento; al salir se reproduce al revés. Arrastrar el anillo o usar la
    rueda del ratón lo gira; pulsar el núcleo o la opción de abajo la activa.

    Las opciones se reparten por todo el círculo y la rueda envuelve.

    Signals:
        option_selected(str): id de la opción activada.
    """

    option_selected = Signal(str)

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setMouseTracking(True)
        self._pinned = False            # fijo a tamaño completo, sin menú (directorio)
        self._hide_menu = False         # el menú se cierra tras soltar el fijado y no debe verse
        self._gaps = None               # QPainterPath de huecos libres de dibujo, o None
        self._intro = 0.0
        self._spin = 0.0
        self._menu = 0.0                # progreso lineal 0..1 de la transición al menú
        self._selected = 0              # índice de la rueda (sin envolver) de la opción elegida
        self._wheel = 0.0               # posición suavizada de la rueda, en unidades de opción
        self._wheel_delta = 0           # angleDelta acumulado de la rueda del ratón
        self._press = None              # posición del botón pulsado, si lo hay
        self._press_angle = 0.0         # ángulo del cursor respecto al centro en el último evento
        self._dragging = False
        self._current = 0               # opción elegida (la más cercana a la posición de la rueda)
        self._flash = 0.0               # destello 1..0 del núcleo al cambiar de opción
        self._hold = 0.0                # progreso 0..1 de la cuenta de la opción que está abajo
        self._rotated = False           # el usuario ha girado el anillo desde que se abrió el menú

        self._tick_timer = QTimer(self, interval=TICK_MS)
        self._tick_timer.timeout.connect(self._tick)
        self._tick_timer.start()

        self._intro_anim = QVariantAnimation(self, startValue=0.0, endValue=1.0, duration=INTRO_MS)
        self._intro_anim.setEasingCurve(QEasingCurve.Linear)
        self._intro_anim.valueChanged.connect(self._on_intro)
        self._intro_anim.start()

        self._spin_anim = QVariantAnimation(self, startValue=0.0, endValue=360.0, duration=SPIN_MS)
        self._spin_anim.setLoopCount(-1)
        self._spin_anim.valueChanged.connect(self._on_spin)
        self._spin_anim.start()

    def _on_intro(self, value) -> None:
        self._intro = float(value)
        self.update()

    def _on_spin(self, value) -> None:
        self._spin = float(value)
        self.update()

    def set_pinned(self, pinned: bool) -> None:
        """Fija el reactor a tamaño completo sin menú ni interacción, o lo suelta.

        Al soltarlo vuelve a su tamaño de reposo (o abre el menú si el cursor está encima).
        """
        if pinned == self._pinned:
            return
        self._pinned = pinned
        self._hide_menu = not pinned
        self._press = None
        self._dragging = False
        self._hold = 0.0
        self._rotated = False
        self.update()

    def set_gaps(self, gaps) -> None:
        """Deja libres de anillos, arcos y marcas las zonas de ``gaps``.

        Args:
            gaps: ``QPainterPath`` en coordenadas del widget, o None para quitarlos.
        """
        if gaps != self._gaps:
            self._gaps = gaps
            self.update()

    def _radius_px(self) -> float:
        """Radio del reactor completo, en píxeles."""
        return unit(self.width(), self.height()) * 100

    def _offset(self, index: int) -> float:
        """Distancia con signo de la opción ``index`` a la elegida, envuelta en -n/2..n/2."""
        n = len(MODULES)
        return (index - self._wheel + n / 2) % n - n / 2

    def _option_center(self, index: int, turn: float = 0.0) -> QPointF:
        """Centro en píxeles de la opción ``index`` sobre el anillo de opciones, girado ``turn`` grados."""
        u = self._radius_px() / 100.0
        center = QPointF(self.width() / 2, self.height() / 2)
        angle = SELECTED_ANGLE - self._offset(index) * 360.0 / len(MODULES) + turn
        return self._polar(center, OPTION_RADIUS * u, angle)

    def _cursor_angle(self, pos: QPointF) -> float:
        """Ángulo en grados del punto ``pos`` respecto al centro (0 = derecha, y positivo arriba)."""
        return math.degrees(math.atan2(self.height() / 2 - pos.y(), pos.x() - self.width() / 2))

    def _selected_hit(self, pos: QPointF) -> bool:
        """Si ``pos`` cae en el núcleo o en la opción elegida, que la activan."""
        if self._menu < MENU_OPEN_AT or not self._interactive():
            return False
        u = self._radius_px() / 100.0
        core = QPointF(self.width() / 2, self.height() / 2)
        if math.hypot(pos.x() - core.x(), pos.y() - core.y()) <= CENTER_HIT * u:
            return True
        c = self._option_center(self._current)
        return math.hypot(pos.x() - c.x(), pos.y() - c.y()) <= OPTION_SIZE * u * 1.4

    def _interactive(self) -> bool:
        """Si el menú se ve y recibe gestos."""
        return not self._pinned and not self._hide_menu

    def _update_menu(self, local: QPointF, dist: float) -> None:
        """Abre o cierra el menú según el cursor y avanza la transición y la rueda."""
        # Solo se abre con la entrada terminada y sobre el círculo reducido; una vez abierto,
        # el círculo completo lo mantiene. Fijado, está siempre abierto.
        reach = self._radius_px() * (1.0 if self._menu > 0 else REST_SCALE)
        is_open = self._pinned or (self.underMouse() and dist <= reach and self._intro >= 1.0)
        step = 16.0 / MENU_MS * (1 if is_open else -1)
        nxt = min(1.0, max(0.0, self._menu + step))
        changed = nxt != self._menu
        self._menu = nxt

        current = round(self._wheel) % len(MODULES)
        if current != self._current:
            self._current = current
            self._flash = 1.0
            self._hold = 0.0
        if self._menu == 0:
            self._rotated = False
            self._hide_menu = False
        # La cuenta solo corre tras girar el anillo, para que la opción inicial no se ejecute sola.
        counting = (self._interactive() and self._rotated and self._menu >= MENU_OPEN_AT
                    and abs(self._wheel - round(self._wheel)) < ALIGN_TOL)
        if counting:
            self._hold = min(1.0, self._hold + 16.0 / HOLD_MS)
            changed = True
            if self._hold >= 1.0:
                self._hold = 0.0
                self._rotated = False
                self._press = None
                self._dragging = False
                self.option_selected.emit(MODULES[self._current][0])
        elif self._hold:
            self._hold = 0.0
            changed = True
        if self._flash > 0:
            self._flash = max(0.0, self._flash - 16.0 / FLASH_MS)
            changed = True

        gap = self._selected - self._wheel
        if gap and not self._dragging:
            self._wheel = self._selected if abs(gap) < 0.003 else self._wheel + gap * WHEEL_FOLLOW
            changed = True

        if not self._interactive():
            cursor = Qt.ArrowCursor
        elif self._dragging:
            cursor = Qt.ClosedHandCursor
        elif is_open and self._selected_hit(local):
            cursor = Qt.PointingHandCursor
        elif is_open and self._menu >= MENU_OPEN_AT:
            cursor = Qt.OpenHandCursor
        else:
            cursor = Qt.ArrowCursor
        self.setCursor(cursor)
        if changed:
            self.update()

    def mousePressEvent(self, event) -> None:
        """Empieza un posible arrastre del anillo."""
        if event.button() == Qt.LeftButton and self._menu >= MENU_OPEN_AT and self._interactive():
            self._press = event.position()
            self._press_angle = self._cursor_angle(self._press)
            self._dragging = False
            return
        super().mousePressEvent(event)

    def mouseMoveEvent(self, event) -> None:
        """Gira el anillo siguiendo el movimiento del cursor alrededor del centro."""
        if self._press is None:
            super().mouseMoveEvent(event)
            return
        pos = event.position()
        if not self._dragging:
            if math.hypot(pos.x() - self._press.x(), pos.y() - self._press.y()) < DRAG_THRESHOLD:
                return
            self._dragging = True
            self._rotated = True
        angle = self._cursor_angle(pos)
        delta = (angle - self._press_angle + 180) % 360 - 180  # tramo corto, sin saltos en ±180
        self._press_angle = angle
        self._wheel += delta / (360.0 / len(MODULES))
        self.update()

    def mouseReleaseEvent(self, event) -> None:
        """Termina el arrastre dejando la opción más cercana abajo, o activa con un clic."""
        if self._press is None:
            super().mouseReleaseEvent(event)
            return
        if self._dragging:
            self._selected = round(self._wheel)
        elif self._selected_hit(event.position()):
            self.option_selected.emit(MODULES[self._current][0])
        self._press = None
        self._dragging = False

    def wheelEvent(self, event) -> None:
        """Gira la rueda un paso por cada muesca del ratón; hacia arriba retrocede."""
        if self._menu < MENU_OPEN_AT or not self._interactive():
            super().wheelEvent(event)
            return
        self._wheel_delta += event.angleDelta().y()
        steps = int(self._wheel_delta / WHEEL_STEP_DELTA)
        if steps:
            self._wheel_delta -= steps * WHEEL_STEP_DELTA
            self._selected = round(self._wheel) - steps
            self._rotated = True
        event.accept()

    def _tick(self) -> None:
        """Avanza el estado del menú según la posición del cursor (incluso fuera de la ventana)."""
        local = self.mapFromGlobal(QCursor.pos())
        dist = math.hypot(local.x() - self.width() / 2, local.y() - self.height() / 2)
        self._update_menu(QPointF(local), dist)

    def replay_intro(self) -> None:
        """Reinicia la animación de entrada."""
        self._intro_anim.stop()
        self._intro_anim.start()

    # ---- helpers de dibujo -------------------------------------------------
    def _stage(self, start: float, end: float) -> float:
        """Progreso suavizado 0..1 de una etapa que ocurre entre start y end de la intro."""
        if end <= start:
            return 1.0
        return ease(min(1.0, max(0.0, (self._intro - start) / (end - start))))

    @staticmethod
    def _pen(color: QColor, width: float, alpha: float = 1.0) -> QPen:
        col = QColor(color)
        col.setAlpha(int(col.alpha() * alpha))
        pen = QPen(col, width)
        pen.setCapStyle(Qt.FlatCap)
        return pen

    @staticmethod
    def _tint(color: QColor, alpha: float) -> QColor:
        col = QColor(color)
        col.setAlpha(int(col.alpha() * min(1.0, max(0.0, alpha))))
        return col

    @staticmethod
    def _arc(p: QPainter, c: QPointF, r: float, start: float, span: float) -> None:
        if span == 0:
            return
        p.drawArc(QRectF(c.x() - r, c.y() - r, 2 * r, 2 * r), int(start * 16), int(span * 16))

    @staticmethod
    def _polar(c: QPointF, r: float, deg: float) -> QPointF:
        a = math.radians(deg)
        return QPointF(c.x() + r * math.cos(a), c.y() - r * math.sin(a))

    # ---- pintado -----------------------------------------------------------
    def paintEvent(self, event) -> None:
        """Dibuja el reactor centrado en el widget según el progreso de la animación."""
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        c = QPointF(self.width() / 2, self.height() / 2)
        u0 = unit(self.width(), self.height())  # 1% del radio completo
        grow = ease(min(1.0, self._menu / GROW_END))
        u = u0 * (REST_SCALE + (1 - REST_SCALE) * grow)  # crece al abrirse el menú
        spin = self._spin
        fade = 1.0

        # Las zonas de ``set_gaps`` quedan libres de anillos, arcos y marcas.
        if self._gaps is not None:
            clip = QPainterPath()
            clip.addRect(QRectF(self.rect()))
            p.setClipPath(clip.subtracted(self._gaps))

        # 1. Círculos finos exteriores: se trazan dando la vuelta.
        for i, r in enumerate((96, 92)):
            si = self._stage(0.05 * i, 0.4 + 0.05 * i) * fade
            p.setPen(self._pen(DIM if i else MID, 1, si))
            self._arc(p, c, r * u, 90 + 20 * i, 360 * si)

        # 2. Anillo principal.
        s = self._stage(0.15, 0.5)
        p.setPen(self._pen(MID, 1, s))
        self._arc(p, c, 80 * u, 90, 360 * s)
        p.setPen(self._pen(BRIGHT, 1.6, s))
        self._arc(p, c, 78 * u, 90, 360 * s)

        # 3. Arcos gruesos opuestos sobre el círculo exterior; el arco fino que los
        # acompaña gira en sentido contrario.
        s = self._stage(0.35, 0.8) * fade
        p.setPen(self._pen(BRIGHT, 3 * u, s))
        self._arc(p, c, 94 * u, 100 + spin * 0.5, 70 * s)
        self._arc(p, c, 94 * u, 285 + spin * 0.5, 55 * s)
        p.setPen(self._pen(MID, 1.2, s))
        self._arc(p, c, 99 * u, 190 - spin * 0.8, 85 * s)
        self._arc(p, c, 99 * u, 10 - spin * 0.8, 60 * s)

        # 4. Marcas de graduación dentro del anillo principal: aparecen en barrido.
        s = self._stage(0.5, 0.9) * fade
        shown = int(120 * s)
        offset = spin * 0.2
        for i in range(shown):
            deg = i * 3 + offset
            major = i % 5 == 0
            p.setPen(self._pen(MID if major else DIM, 1))
            r_in = (69 if major else 71) * u
            p.drawLine(self._polar(c, r_in, deg), self._polar(c, 75 * u, deg))

        # 5. Tres puntos junto al círculo exterior en cuatro posiciones.
        s = self._stage(0.7, 1.0) * fade
        p.setPen(Qt.NoPen)
        p.setBrush(self._tint(BRIGHT, s))
        for base in (80, 215, 270, 35):
            for j in (-1, 0, 1):
                p.drawEllipse(self._polar(c, 99 * u, base + j * 2.5 + spin * 0.1), 1.2, 1.2)

        p.setClipping(False)

        # 6. Menú: núcleo con la opción elegida y rueda de opciones.
        if self._menu > 0 and self._interactive():
            self._draw_menu(p, c, u0)
            self._draw_hold(p, c, u, u0)
        p.end()

    def _draw_hold(self, p: QPainter, c: QPointF, u: float, u0: float) -> None:
        """Rellena en el sentido del reloj tres anillos mientras cuenta la opción que está abajo."""
        if self._hold <= 0:
            return
        p.setBrush(Qt.NoBrush)
        for radius, width in ((78 * u, 3.0), (RING_OUTER * u0, 2.5), (CENTER_HIT * u0, 2.5)):
            p.setPen(self._pen(BRIGHT, width))
            self._arc(p, c, radius, 90, -360 * self._hold)

    def _draw_menu(self, p: QPainter, c: QPointF, u0: float) -> None:
        """Dibuja el núcleo con la opción elegida y la banda de opciones, en el centro del reactor.

        Aparece por etapas, cuando el reactor ya ha crecido: el núcleo se abre, la banda
        se expande desde él y las opciones giran hasta su sitio. Al cerrarse el menú se
        reproduce al revés.

        Args:
            p: QPainter activo.
            c: centro del reactor y del núcleo.
            u0: 1 % del radio del reactor en reposo, en píxeles.
        """
        def stage(start: float, end: float) -> float:
            return ease(min(1.0, max(0.0, (self._menu - start) / (end - start))))

        e_core = stage(0.3, 0.7)
        e_band = stage(0.4, 0.85)
        e_icons = stage(0.55, 1.0)

        core = CENTER_HIT * u0 * (0.6 + 0.4 * e_core)
        # Anillo fino alrededor del núcleo; el destello lo ilumina al cambiar de opción.
        p.setBrush(Qt.NoBrush)
        p.setPen(self._pen(DIM, 1, e_core))
        p.drawEllipse(c, core, core)
        if self._flash > 0:
            reach = core * (1 + 0.1 * (1 - self._flash))
            p.setPen(self._pen(BRIGHT, 2.5, self._flash * e_core))
            p.drawEllipse(c, reach, reach)

        # Banda de opciones: un anillo relleno que crece desde el núcleo hasta su tamaño.
        inner = (CENTER_HIT + (RING_INNER - CENTER_HIT) * e_band) * u0
        outer = (CENTER_HIT + (RING_OUTER - CENTER_HIT) * e_band) * u0
        ring = QPainterPath()
        ring.addEllipse(c, outer, outer)
        ring.addEllipse(c, inner, inner)  # regla par-impar: el interior queda hueco
        p.setPen(Qt.NoPen)
        p.setBrush(QColor(255, 255, 255, int(22 * e_band)))
        p.drawPath(ring)
        p.setBrush(Qt.NoBrush)
        p.setPen(self._pen(MID, 1.2, e_band))
        p.drawEllipse(c, outer, outer)
        p.drawEllipse(c, inner, inner)

        # Sombra: solo sobre la banda, en el tramo de la opción elegida.
        box_out = QRectF(c.x() - outer, c.y() - outer, 2 * outer, 2 * outer)
        box_in = QRectF(c.x() - inner, c.y() - inner, 2 * inner, 2 * inner)
        band = QPainterPath()
        band.arcMoveTo(box_out, SELECTED_ANGLE - SHADOW_SPAN)
        band.arcTo(box_out, SELECTED_ANGLE - SHADOW_SPAN, 2 * SHADOW_SPAN)
        band.arcTo(box_in, SELECTED_ANGLE + SHADOW_SPAN, -2 * SHADOW_SPAN)
        band.closeSubpath()
        shade = QConicalGradient(c, (SELECTED_ANGLE - SHADOW_SPAN) % 360)
        fraction = 2 * SHADOW_SPAN / 360.0
        shade.setColorAt(0.0, QColor(255, 255, 255, 0))
        shade.setColorAt(fraction / 2, QColor(255, 255, 255, int(80 * e_icons)))
        shade.setColorAt(fraction, QColor(255, 255, 255, 0))
        shade.setColorAt(1.0, QColor(255, 255, 255, 0))
        p.setPen(Qt.NoPen)
        p.setBrush(shade)
        p.drawPath(band)

        # Núcleo: icono y nombre de la opción elegida; el cambio es inmediato.
        _, label, icon = MODULES[self._current]
        title = QFont("Prototype", max(5, int(3.6 * u0)))
        title.setBold(True)
        title.setLetterSpacing(QFont.AbsoluteSpacing, 1.5)
        icon.draw(p, QPointF(c.x(), c.y() - 6 * u0), CORE_ICON_FACTOR * u0 * (0.6 + 0.4 * e_core),
                  self._tint(BRIGHT, e_core))
        p.setFont(title)
        p.setPen(self._tint(BRIGHT, e_core))
        label = QFontMetricsF(title).elidedText(label, Qt.ElideRight, CORE_LABEL_WIDTH * u0)
        p.drawText(QRectF(c.x() - 27 * u0, c.y() + 8 * u0, 54 * u0, 10 * u0), Qt.AlignCenter, label)

        # Banda: las opciones giran hasta su posición mientras aparecen; la elegida, más grande.
        if e_icons <= 0:
            return
        turn = -MENU_SPIN_IN * (1 - e_icons)
        for i, (_, _, option_icon) in enumerate(MODULES):
            pos = self._option_center(i, turn)
            chosen = i == self._current
            scale = OPTION_ICON_FACTOR * u0 * (1.2 if chosen else 0.95) * (0.5 + 0.5 * e_icons)
            option_icon.draw(p, pos, scale, self._tint(BRIGHT if chosen else MID, e_icons))
