"""Reactor: componente circular sci-fi, anillos dibujados con QPainter y animados."""
import math
import random

from PySide6.QtCore import QEasingCurve, QPointF, QRectF, Qt, QTimer, QVariantAnimation
from PySide6.QtGui import QColor, QCursor, QPainter, QPen, QPolygonF
from PySide6.QtWidgets import QWidget

BRIGHT = QColor(235, 238, 242)
MID = QColor(150, 155, 162)
DIM = QColor(90, 94, 100)
FAINT = QColor(255, 255, 255, 22)

INTRO_MS = 3400
ICON_INTRO_END = 0.45   # el búho se dibuja primero, en esta fracción de la entrada
RINGS_INTRO_START = 0.35  # los anillos empiezan cuando el búho casi termina
LOOK_FOLLOW = 0.22      # suavizado de la mirada por cuadro (0..1)
LOOK_TICK_MS = 16
SPIN_MS = 90000  # una vuelta completa de la rotación continua

# Búho central, diseñado en píxeles de la referencia (dos aros, cejas y pico) y escalado.
# Origen en el punto medio entre los ojos; y positivo hacia abajo.
OWL_HALF_WIDTH = 42        # semiancho del búho, en % del radio del reactor
OWL_EYE_X = 65.0           # distancia del centro de cada ojo al eje
OWL_RING_R = 36.5          # radio de la línea central del aro del ojo
OWL_RING_W = 17.0          # grosor del aro
OWL_BROW_R = 71.0          # radio de la línea central de la ceja (concéntrica al ojo)
OWL_BROW_W = 14.0
OWL_BROW_TIP = 127.0       # ángulo (°) del extremo exterior de la ceja
OWL_BROW_JOIN = 33.5       # ángulo (°) donde la ceja llega al centro y se une con la otra
OWL_BEAK_Y = 48.0          # centro del pico
OWL_BEAK_HALF = 8.0
OWL_EXTENT = OWL_EYE_X + OWL_BROW_R + OWL_BROW_W / 2   # semiancho total en píxeles de referencia
OWL_Y_SHIFT = 11.0         # baja el dibujo para que quede centrado en vertical
OWL_LOOK_RANGE = 4.0       # desplazamiento máximo de cada ojo al mirar


def _ease(t: float) -> float:
    """Suaviza un progreso 0..1 (salida cúbica)."""
    return 1 - (1 - t) ** 3


class Reactor(QWidget):
    """Widget circular con anillos, arcos, marcas y puntos.

    Al crearse reproduce una animación de entrada: primero se dibuja el búho
    central y después aparece cada elemento del reactor por etapas; luego los
    arcos y las marcas giran lentamente y los ojos del búho siguen al cursor.
    Se dibuja proporcional al lado menor del widget con fondo transparente.
    """

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setAttribute(Qt.WA_TransparentForMouseEvents)
        rng = random.Random(7)  # semilla fija: los puntos no cambian entre repintados
        self._dots = [
            (rng.uniform(0, 360), rng.choice((83, 86, 90, 93)), rng.choice((0.4, 0.7, 1.0)))
            for _ in range(70)
        ]
        self._intro = 0.0
        self._spin = 0.0
        self._look = QPointF(0.0, 0.0)  # mirada suavizada, componentes en -1..1

        self._look_timer = QTimer(self, interval=LOOK_TICK_MS)
        self._look_timer.timeout.connect(self._update_look)
        self._look_timer.start()

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

    def _update_look(self) -> None:
        """Acerca la mirada al cursor (incluso fuera de la ventana) con suavizado."""
        local = self.mapFromGlobal(QCursor.pos())
        dx = local.x() - self.width() / 2
        dy = local.y() - self.height() / 2
        dist = math.hypot(dx, dy)
        if dist < 1:
            target = QPointF(0.0, 0.0)
        else:
            # Cerca del búho la mirada se mueve proporcional; lejos, se satura.
            strength = min(1.0, dist / (min(self.width(), self.height()) * 0.3))
            target = QPointF(dx / dist * strength, dy / dist * strength)
        nxt = self._look + (target - self._look) * LOOK_FOLLOW
        if abs(nxt.x() - self._look.x()) > 0.001 or abs(nxt.y() - self._look.y()) > 0.001:
            self._look = nxt
            self.update()

    def replay_intro(self) -> None:
        """Reinicia la animación de entrada."""
        self._intro_anim.stop()
        self._intro_anim.start()

    # ---- helpers de dibujo -------------------------------------------------
    def _stage(self, start: float, end: float) -> float:
        """Progreso suavizado 0..1 de una etapa que ocurre entre start y end de la intro."""
        if end <= start:
            return 1.0
        # La entrada de los anillos corre en el tramo posterior a la del búho.
        t = (self._intro - RINGS_INTRO_START) / (1.0 - RINGS_INTRO_START)
        return _ease(min(1.0, max(0.0, (t - start) / (end - start))))

    @staticmethod
    def _pen(color: QColor, width: float, alpha: float = 1.0) -> QPen:
        col = QColor(color)
        col.setAlpha(int(col.alpha() * alpha))
        pen = QPen(col, width)
        pen.setCapStyle(Qt.FlatCap)
        return pen

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
        u = (min(self.width(), self.height()) / 2 - 2) / 100.0  # 1% del radio
        spin = self._spin

        # 1. Banda exterior tenue y círculos finos: se trazan dando la vuelta.
        s = self._stage(0.0, 0.35)
        p.setPen(self._pen(FAINT, 7 * u, s))
        self._arc(p, c, 90 * u, 90, 360 * s)
        for i, r in enumerate((97, 92, 70, 58, 46)):
            si = self._stage(0.03 * i, 0.3 + 0.03 * i)
            p.setPen(self._pen(DIM, 1, si))
            self._arc(p, c, r * u, 90 + 20 * i, 360 * si)

        # 2. Anillo principal.
        s = self._stage(0.15, 0.5)
        p.setPen(self._pen(MID, 1, s))
        self._arc(p, c, 80 * u, 90, 360 * s)
        p.setPen(self._pen(BRIGHT, 1.6, s))
        self._arc(p, c, 78 * u, 90, 360 * s)

        # 3. Arcos exteriores arriba y abajo: crecen desde el centro de cada uno.
        s = self._stage(0.35, 0.6)
        for mid in (90, 270):
            p.setPen(self._pen(DIM, 3 * u / 2 + 1, s))
            self._arc(p, c, 100 * u, mid - 20 * s, 40 * s)
            p.setPen(self._pen(BRIGHT, 2, s))
            self._arc(p, c, 100 * u, mid - 6 * s, 12 * s)

        # 4. Arcos gruesos: giran con la rotación continua.
        s = self._stage(0.45, 0.8)
        p.setPen(self._pen(MID, 3 * u, s))
        self._arc(p, c, 74 * u, 62 + spin, 56 * s)
        self._arc(p, c, 74 * u, 215 + spin, 32 * s)
        p.setPen(self._pen(BRIGHT, 2 * u, s))
        self._arc(p, c, 74 * u, 75 + spin, 30 * s)
        self._arc(p, c, 74 * u, 300 + spin, 28 * s)
        p.setPen(self._pen(DIM, 4 * u, s))
        self._arc(p, c, 64 * u, 160 - spin * 1.5, 40 * s)
        self._arc(p, c, 64 * u, 340 - spin * 1.5, 40 * s)

        # 5. Marcas de graduación: aparecen en barrido y giran muy despacio.
        s = self._stage(0.55, 0.9)
        shown = int(120 * s)
        offset = spin * 0.2
        for i in range(shown):
            deg = i * 3 + offset
            major = i % 5 == 0
            p.setPen(self._pen(MID if major else DIM, 1))
            r_in = (84 if major else 85.5) * u
            p.drawLine(self._polar(c, r_in, deg), self._polar(c, 87.5 * u, deg))

        # 6. Puntos dispersos: aparecen escalonados y orbitan lento.
        s = self._stage(0.7, 1.0)
        p.setPen(Qt.NoPen)
        total = len(self._dots)
        for i, (deg, radius, size) in enumerate(self._dots):
            appear = min(1.0, max(0.0, s * 1.6 - i / total * 0.6))
            if appear <= 0:
                continue
            p.setBrush(QColor(235, 238, 242, int((110 + 120 * size) * appear)))
            p.drawEllipse(self._polar(c, radius * u, deg + spin * 0.5), size * 1.3, size * 1.3)

        # 7. Búho en el centro, justo dentro del círculo fino de 46. Es lo primero en
        # dibujarse; los ojos siguen al cursor.
        self._draw_owl(p, c, u, min(1.0, self._intro / ICON_INTRO_END))
        p.end()

    def _draw_owl(self, p: QPainter, c: QPointF, u: float, progress: float) -> None:
        """Dibuja el búho: dos aros (ojos), dos cejas concéntricas que se unen y el pico.

        Args:
            p: QPainter activo.
            c: centro del reactor.
            u: 1 % del radio del reactor, en píxeles.
            progress: avance 0..1 de la entrada: aros, luego cejas, luego pico.
        """
        if progress <= 0:
            return
        k = OWL_HALF_WIDTH * u / OWL_EXTENT   # píxeles de pantalla por píxel de diseño
        origin = QPointF(c.x(), c.y() + OWL_Y_SHIFT * k)

        def stage(start: float, end: float) -> float:
            return _ease(min(1.0, max(0.0, (progress - start) / (end - start))))

        look_x = self._look.x() * OWL_LOOK_RANGE * k
        look_y = self._look.y() * OWL_LOOK_RANGE * k

        # Aros de los ojos: se trazan dando la vuelta y se mueven hacia el cursor.
        rings = stage(0.0, 0.45)
        p.setBrush(Qt.NoBrush)
        p.setPen(self._pen(MID, OWL_RING_W * k))
        for sign in (-1, 1):
            ec = QPointF(origin.x() + sign * OWL_EYE_X * k + look_x, origin.y() + look_y)
            self._arc(p, ec, OWL_RING_R * k, 90, 360 * rings)

        # Cejas: arcos concéntricos a cada ojo, de la punta exterior hasta el centro.
        brows = stage(0.35, 0.8)
        span = (OWL_BROW_TIP - OWL_BROW_JOIN) * brows
        p.setPen(self._pen(MID, OWL_BROW_W * k))
        for sign in (-1, 1):
            ec = QPointF(origin.x() + sign * OWL_EYE_X * k, origin.y())
            if sign < 0:   # izquierda: de la punta (127 grados) hacia el centro, sentido horario
                self._arc(p, ec, OWL_BROW_R * k, OWL_BROW_TIP, -span)
            else:          # derecha: espejo, de 53 grados en sentido antihorario
                self._arc(p, ec, OWL_BROW_R * k, 180 - OWL_BROW_TIP, span)

        # Pico: rombo que crece desde su centro.
        beak = stage(0.7, 1.0)
        if beak > 0:
            half = OWL_BEAK_HALF * k * beak
            bc = QPointF(origin.x(), origin.y() + OWL_BEAK_Y * k)
            p.setPen(Qt.NoPen)
            p.setBrush(MID)
            p.drawPolygon(QPolygonF([
                QPointF(bc.x(), bc.y() - half), QPointF(bc.x() + half, bc.y()),
                QPointF(bc.x(), bc.y() + half), QPointF(bc.x() - half, bc.y()),
            ]))
