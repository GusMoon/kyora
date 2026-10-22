"""La barra vertical de la izquierda: es la parte ancha del marco y muestra el estado que envía el núcleo.

Arriba, los escritorios. Abajo, la hora y los iconos de wifi, Bluetooth, calendario y apagar: cada uno abre su panel a
la derecha en cuanto el ratón pasa por encima (señal `panel_hover`). Los datos del equipo están en el panel de arriba.

Aquí no hay reglas de negocio: cada botón pide una acción al núcleo con `invoke(acción, **datos)`.
"""
import datetime

from PySide6.QtCore import (
    QEasingCurve,
    QPoint,
    QPointF,
    QRect,
    QRectF,
    QSize,
    Qt,
    QTimer,
    Signal,
)
from PySide6.QtGui import QColor, QFont, QPainter
from PySide6.QtWidgets import (
    QAbstractButton,
    QInputDialog,
    QMenu,
    QToolTip,
    QVBoxLayout,
    QWidget,
)

from kyora.ui import glyphs
from kyora.ui.anim import Tween
from kyora.ui.relief import frame_gradient, paint_raised_edge
from kyora.ui.shapes import bulge_pill_path, frame_path, hole_path
from kyora.ui.win import make_tool_window

WEEKDAYS = ("lun", "mar", "mié", "jue", "vie", "sáb", "dom")
MONTHS = ("ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic")


def font(theme, px, bold=False):
    f = QFont(theme.font_family)
    f.setPixelSize(px)
    f.setBold(bold)
    return f


class BarButton(QAbstractButton):
    """Botón cuadrado de la barra con un icono de línea fina. Activo: un cuadrado redondeado que lo resalta."""

    def __init__(self, theme, glyph, tooltip="", parent=None):
        super().__init__(parent)
        self.theme = theme
        self.glyph = glyph  # glyph(pintor, caja) dibuja el icono
        self.setToolTip(tooltip)
        self.active = False
        self.alert = False  # en dorado (el botón de salir, armado)
        self.badge = ""
        self.setCursor(Qt.PointingHandCursor)
        self.setFixedSize(theme.item_size, theme.item_size)
        self.setAttribute(Qt.WA_Hover)

    def sizeHint(self):
        return QSize(self.theme.item_size, self.theme.item_size)

    def paintEvent(self, _):
        t = self.theme
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        r = QRectF(self.rect()).adjusted(0.5, 0.5, -0.5, -0.5)
        if self.active or self.alert:
            p.setPen(Qt.NoPen)
            p.setBrush(QColor(t.capsule))
            p.drawRoundedRect(r, t.item_radius, t.item_radius)
        elif self.underMouse() or self.isDown():
            p.setPen(Qt.NoPen)
            p.setBrush(QColor(t.hover))
            p.drawRoundedRect(r, t.item_radius, t.item_radius)
        lit = self.active or self.underMouse()
        p.setPen(glyphs.pen(QColor(t.gold if self.alert else t.ink if lit else t.dim)))
        p.setBrush(Qt.NoBrush)
        self.glyph(p, QRectF(self.rect()).adjusted(7, 7, -7, -7))
        if self.badge:
            p.setFont(font(t, t.small_px - 1, bold=True))
            p.setPen(QColor(t.gold))
            p.drawText(self.rect().adjusted(0, 0, -1, 1), Qt.AlignRight | Qt.AlignBottom, self.badge)


class DesktopDots(QWidget):
    """Escritorios en una píldora vertical: un punto por escritorio y el activo abultado, grande y con su número.

    El abultamiento se desliza al cambiar de escritorio y los demás puntos se apartan para dejarle sitio.
    """

    HALF = 9  # media anchura de la píldora
    BULGE = 16  # radio del abultamiento del escritorio activo
    FILLET = 6  # radio de las curvas cóncavas donde el abultamiento se une a la píldora
    ACTIVE = 11  # radio del círculo blanco con el número
    DOT = 3.5
    ROW = 18  # alto de la fila de un punto
    BIG_ROW = 2 * (BULGE + 4)  # alto de la fila del activo
    PLUS = 24  # fila del botón "+", debajo de la píldora

    def __init__(self, theme, on_switch, on_menu, on_add):
        super().__init__()
        self.theme = theme
        self._on_switch, self._on_menu, self._on_add = on_switch, on_menu, on_add
        self.desktops = []
        self._pos = 0.0  # índice (con decimales mientras se anima) donde está el abultamiento
        self._hover = -1
        self._tween = Tween(self, self._set_pos)
        self.setMouseTracking(True)
        self.setCursor(Qt.PointingHandCursor)
        self.setFixedWidth(2 * (self.BULGE + 4))

    def _rows(self):
        """Alto de cada fila para la posición actual del abultamiento (suman siempre lo mismo)."""
        grow = self.BIG_ROW - self.ROW
        return [self.ROW + grow * max(0.0, 1 - abs(i - self._pos)) for i in range(len(self.desktops))]

    def _centers(self):
        y, centers = float(self.HALF), []
        for h in self._rows():
            centers.append(y + h / 2)
            y += h
        return centers

    def _pill_bottom(self):
        return self.HALF + self.ROW * (len(self.desktops) - 1) + self.BIG_ROW + self.HALF

    def set_desktops(self, desktops):
        old = next((i for i, d in enumerate(self.desktops) if d["active"]), None)
        self.desktops = desktops
        self.setFixedHeight(round(self._pill_bottom() + self.PLUS))
        new = next((i for i, d in enumerate(desktops) if d["active"]), 0)
        if old is None or old >= len(desktops):
            self._set_pos(new)
        else:
            self._tween.start(self._pos, new, 220, QEasingCurve.OutCubic)
        self.update()

    def _set_pos(self, value):
        self._pos = float(value)
        self.update()

    def _bulge_y(self):
        centers = self._centers()
        if not centers:
            return 0.0
        low = min(int(self._pos), len(centers) - 1)
        high = min(low + 1, len(centers) - 1)
        return centers[low] + (centers[high] - centers[low]) * (self._pos - low)

    def _index_at(self, y):
        if y >= self._pill_bottom():
            return len(self.desktops)  # el botón "+"
        centers = self._centers()
        if not centers:
            return -1
        return min(range(len(centers)), key=lambda i: abs(centers[i] - y))

    def mouseMoveEvent(self, event):
        i = self._index_at(event.position().y())
        if i != self._hover:
            self._hover = i
            self.setToolTip(self._tip(i))
            self.update()

    def leaveEvent(self, _):
        self._hover = -1
        self.update()

    def _tip(self, i):
        if i == len(self.desktops):
            return "Nuevo escritorio"
        if 0 <= i < len(self.desktops):
            d = self.desktops[i]
            n = d["count"]
            windows = f"{n} ventana{'s' if n != 1 else ''}" if n else "vacío"
            return f"{d['name']} · {windows}" + chr(10) + "Clic derecho: renombrar o cerrar"
        return ""

    def mouseReleaseEvent(self, event):
        i = self._index_at(event.position().y())
        if i < 0:
            return
        if i == len(self.desktops):
            if event.button() == Qt.LeftButton:
                self._on_add()
        elif event.button() == Qt.LeftButton:
            self._on_switch(self.desktops[i]["index"])
        elif event.button() == Qt.RightButton:
            self._on_menu(self.desktops[i], event.globalPosition().toPoint())

    def paintEvent(self, _):
        t = self.theme
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        cx = self.width() / 2
        if self.desktops:
            bulge_y = self._bulge_y()
            pill = bulge_pill_path(cx, 0, self._pill_bottom(), self.HALF, bulge_y, self.BULGE, self.FILLET)
            p.fillPath(pill, QColor(t.dots_pill))
            paint_raised_edge(p, pill, QRectF(self.rect()), t)
            p.setPen(Qt.NoPen)
            for i, (d, y) in enumerate(zip(self.desktops, self._centers())):
                if d["active"]:
                    continue
                p.setBrush(QColor(t.dot_busy if d["count"] else t.dot_empty))
                r = self.DOT + (1 if i == self._hover else 0)
                p.drawEllipse(QPointF(cx, y), r, r)
            active = next((i for i, d in enumerate(self.desktops) if d["active"]), 0)
            p.setBrush(QColor(t.dot_active))
            p.drawEllipse(QPointF(cx, bulge_y), self.ACTIVE, self.ACTIVE)
            p.setPen(QColor(t.dots_pill))
            p.setFont(font(t, t.font_px, bold=True))
            box = QRectF(cx - self.ACTIVE, bulge_y - self.ACTIVE, 2 * self.ACTIVE, 2 * self.ACTIVE)
            p.drawText(box, Qt.AlignCenter, str(active + 1))  # numeración desde arriba: 1, 2, 3…
        plus = QRectF(0, self._pill_bottom() + 2, self.width(), self.PLUS - 2)
        p.setPen(QColor(t.ink if self._hover == len(self.desktops) else t.dim))
        p.setFont(font(t, t.font_px + 2))
        p.drawText(plus, Qt.AlignCenter, "+")


class WifiIcon(QWidget):
    """Barras de señal del wifi; al pasar el ratón (o al pulsar) abre el panel de redes."""

    def __init__(self, theme, on_hover=None):
        super().__init__()
        self.theme = theme
        self.wifi = {"available": False}
        self._on_hover = on_hover
        self.setFixedSize(theme.item_size, 26)
        self.setCursor(Qt.PointingHandCursor)

    def enterEvent(self, event):
        if self._on_hover:
            self._on_hover(self)
        super().enterEvent(event)

    def mouseReleaseEvent(self, event):
        if event.button() == Qt.LeftButton and self._on_hover:
            self._on_hover(self)

    def set_wifi(self, wifi):
        self.wifi = wifi
        self.update()

    def paintEvent(self, _):
        t = self.theme
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        connected = self.wifi.get("connected")
        lit = max(1, -(-int(self.wifi.get("signal", 0)) // 25)) if connected else 0
        x0 = (self.width() - 4 * 5) // 2
        for i in range(4):
            h = 5 + i * 4
            p.setPen(Qt.NoPen)
            p.setBrush(QColor(t.ink if i < lit else t.line))
            p.drawRoundedRect(QRectF(x0 + i * 5, self.height() - 2 - h, 3, h), 1, 1)


class Clock(QWidget):
    """Hora y minutos en dos líneas, como pide una barra vertical."""

    def __init__(self, theme):
        super().__init__()
        self.theme = theme
        self.setFixedSize(theme.item_size, 38)
        self._timer = QTimer(self)
        self._timer.setSingleShot(True)
        self._timer.timeout.connect(self.tick)
        self.tick()

    def tick(self):
        now = datetime.datetime.now()
        self.setToolTip(f"{WEEKDAYS[now.weekday()]}, {now.day} {MONTHS[now.month - 1]} {now.year}")
        self.update()
        self._timer.start((60 - now.second) * 1000 - now.microsecond // 1000 + 50)  # al cambiar el minuto

    def paintEvent(self, _):
        t = self.theme
        now = datetime.datetime.now()
        p = QPainter(self)
        p.setPen(QColor(t.ink))
        p.setFont(font(t, t.font_px + 1, bold=True))
        p.drawText(QRectF(0, 0, self.width(), 19), Qt.AlignCenter, f"{now.hour:02d}")
        p.setPen(QColor(t.dim))
        p.setFont(font(t, t.font_px + 1))
        p.drawText(QRectF(0, 19, self.width(), 19), Qt.AlignCenter, f"{now.minute:02d}")


class HoverIcon(BarButton):
    """Icono de la barra que abre su panel en cuanto el ratón entra (sin esperar) y al pulsarlo."""

    def __init__(self, theme, glyph, tooltip, on_hover):
        super().__init__(theme, glyph, tooltip)
        self._on_hover = on_hover
        self.clicked.connect(lambda: self._on_hover(self))

    def enterEvent(self, event):
        self._on_hover(self)
        super().enterEvent(event)


class SideBar(QWidget):
    # (nombre del panel, y del centro del icono, zona global de su fila): el panel se abre al pasar el ratón y se
    # cierra cuando el ratón sale de él y de esa zona
    panel_hover = Signal(str, int, QRect)

    def __init__(self, theme, screen_map, invoke):
        super().__init__()
        make_tool_window(self)
        self.setWindowTitle("KyoraBar")
        self.theme = theme
        self.invoke = invoke
        g = screen_map.geometry
        self._screen_width = g.width()
        self._screen_height = g.height()  # el degradado del marco abarca toda la pantalla
        self.setGeometry(g.x(), g.y(), theme.bar_width, g.height())
        self.setFixedWidth(theme.bar_width)  # si se ensancha tapa la curva de las esquinas izquierdas del hueco

        self.dots = DesktopDots(theme, self._switch, self._desktop_menu, lambda: invoke("desktop.create"))
        layout = QVBoxLayout(self)
        margin = (theme.bar_width - self.dots.width()) // 2  # los escritorios son la pieza más ancha
        layout.setContentsMargins(margin, theme.frame_width + 6, margin, theme.frame_width + 6)
        layout.setSpacing(6)
        layout.addWidget(self.dots, 0, Qt.AlignHCenter)

        layout.addStretch(1)

        self.clock = Clock(theme)
        self.wifi = WifiIcon(theme, lambda widget: self._hovered("wifi", widget))
        self.bluetooth = HoverIcon(theme, glyphs.bluetooth, "", lambda w: self._hovered("bluetooth", w))
        self.calendar = HoverIcon(theme, glyphs.calendar, "", lambda w: self._hovered("calendar", w))
        self.power = HoverIcon(theme, glyphs.power, "", lambda w: self._hovered("power", w))
        for widget in (self.clock, self.wifi, self.bluetooth, self.calendar, self.power):
            layout.addWidget(widget, 0, Qt.AlignHCenter)

    # ---------- estado que llega del núcleo ----------

    def on_state(self, state):
        self.dots.set_desktops(state["desktops"])
        self.wifi.set_wifi(state["wifi"])

    @staticmethod
    def _center_y(widget):
        return widget.mapToGlobal(widget.rect().center()).y()

    def zone(self):
        """El grupo de iconos de abajo a lo ancho de toda la barra: moverse entre ellos (o hasta el panel) no lo
        cierra; el panel solo se transforma."""
        top = self.clock.mapToGlobal(QPoint(0, 0)).y()
        bottom = self.power.mapToGlobal(QPoint(0, self.power.height())).y()
        return QRect(self.mapToGlobal(QPoint(0, 0)).x(), top - 4, self.width(), bottom - top + 8)

    def _hovered(self, name, widget):
        self.panel_hover.emit(name, self._center_y(widget), self.zone())

    def power_anchor(self):
        """y del centro del botón de apagar: de ahí sale su panel también con Win+X."""
        return self._center_y(self.power)

    def _switch(self, index):
        self.invoke("desktop.switch", index=index)

    def _desktop_menu(self, desktop, global_pos):
        menu = QMenu(self)
        rename = menu.addAction("Renombrar…")
        close = menu.addAction("Cerrar (sus ventanas pasan al anterior)") if len(self.dots.desktops) > 1 else None
        create = menu.addAction("Nuevo escritorio")
        chosen = menu.exec(global_pos)
        if chosen is rename:
            name, ok = QInputDialog.getText(self, "Renombrar escritorio", "Nombre:", text=desktop["name"])
            if ok and name.strip() and name.strip() != desktop["name"]:
                self.invoke("desktop.rename", index=desktop["index"], name=name.strip()[:20])
        elif chosen is not None and chosen is close:
            self.invoke("desktop.close", index=desktop["index"])
        elif chosen is create:
            self.invoke("desktop.create")

    # ---------- avisos ----------

    def toast(self, message):
        QToolTip.showText(self.mapToGlobal(QPoint(self.width() + 6, self.height() - 120)), message, self)

    def paintEvent(self, _):
        t = self.theme
        p = QPainter(self)
        p.fillRect(self.rect(), frame_gradient(t, self._screen_height))
        # la barra tapa el lado izquierdo del hueco: repite ahí el filete del borde del marco
        w, h, insets = self._screen_width, self._screen_height, t.insets()
        paint_raised_edge(
            p, frame_path(w, h, insets, t.hole_radius), QRectF(self.rect()), t,
            contour=hole_path(w, h, insets, t.hole_radius),
        )

    def closeEvent(self, event):
        """Alt+F4 sobre la barra cierra Kyora de forma ordenada (devuelve las ventanas)."""
        event.ignore()
        self.invoke("app.quit")
