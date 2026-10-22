"""El buscador: sale del borde inferior del marco, con el campo para escribir abajo y las opciones subiendo encima.

Es una ventana transparente de tamaño fijo, pegada al borde inferior de la pantalla. Lo que se anima es la forma
que se pinta dentro (con las curvas cóncavas donde se une al marco): crece hacia arriba al abrirse y vuelve a crecer
a medida que aparecen resultados. Nunca cambia de tamaño una ventana, así que el movimiento es fluido y nada se desenfoca.
"""
import logging
import math
import time

from PySide6.QtCore import QEasingCurve, QEvent, QRectF, Qt, QTimer
from PySide6.QtGui import QColor, QPainter, QPainterPath, QPen
from PySide6.QtWidgets import QGraphicsOpacityEffect, QLineEdit, QWidget

from kyora.core.animation import lerp
from kyora.system.win32 import force_foreground
from kyora.ui.anim import Tween
from kyora.ui.bar import font
from kyora.ui.icons import app_icon
from kyora.ui.relief import frame_gradient, paint_raised_edge
from kyora.ui.shapes import mirror_vertical, popout_paths
from kyora.ui.win import hwnd_of, make_tool_window

log = logging.getLogger("kyora.ui")

ROW_H = 34
INPUT_H = 40
GAP = 8  # entre el campo y la lista de opciones
LIST_PAD = 6
QUERY_DELAY_MS = 30
BLUR_CHECK_MS = 200
LIST_MS = 150  # lo que tarda la lista en crecer o encogerse cuando cambian los resultados
SLOW_QUERY_MS = 50  # una búsqueda más lenta que esto se anota en kyora.log


class ResultList(QWidget):
    """Opciones encontradas, dibujadas a mano. La mejor está abajo, junto al campo, y las demás van subiendo.

    Si hay más de las que caben (la lista de atajos de "commands"), se desplaza para que la elegida siempre se vea.
    """

    def __init__(self, theme, on_launch):
        super().__init__()
        self.theme = theme
        self.on_launch = on_launch
        self.results = []
        self.note = ""
        self.selected = 0
        self._scroll = 0  # primera opción que se ve, contando desde abajo
        self.setMouseTracking(True)
        self.setCursor(Qt.PointingHandCursor)

    def set_results(self, results, note=""):
        self.results, self.note = results, note
        self.selected = min(self.selected, max(len(results) - 1, 0))
        self._scroll = 0
        self._follow()
        self.update()

    def _fits(self):
        return max(int((self.height() - 2 * LIST_PAD) // ROW_H), 1)

    def _follow(self):
        """Desplaza lo justo para que la opción elegida se vea."""
        self._scroll = min(max(self._scroll, self.selected - self._fits() + 1), self.selected)

    def resizeEvent(self, event):
        self._follow()
        super().resizeEvent(event)

    def wanted_height(self):
        """Alto que necesita la lista ahora: filas, o una sola línea de aviso, o nada."""
        rows = len(self.results) or (1 if self.note else 0)
        return rows * ROW_H + 2 * LIST_PAD if rows else 0

    def move(self, step):
        if self.results:
            self.selected = max(0, min(self.selected + step, len(self.results) - 1))
            self._follow()
            self.update()

    def wheelEvent(self, event):
        self.move(1 if event.angleDelta().y() > 0 else -1)  # la lista sube: la rueda hacia arriba sube
    def current(self):
        return self.results[self.selected] if self.results else None

    def _row_y(self, i):
        return self.height() - LIST_PAD - (i - self._scroll + 1) * ROW_H

    def _row_at(self, y):
        row = int((self.height() - LIST_PAD - y) // ROW_H) + self._scroll
        return row if self._scroll <= row < len(self.results) else None

    def mouseMoveEvent(self, event):
        row = self._row_at(event.position().y())
        if row is not None and row != self.selected:
            self.selected = row
            self.update()

    def mouseReleaseEvent(self, event):
        row = self._row_at(event.position().y())
        if event.button() == Qt.LeftButton and row is not None:
            self.on_launch(self.results[row])

    def paintEvent(self, _):
        t = self.theme
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        p.setClipRect(self.rect())
        box = QRectF(self.rect()).adjusted(0.5, 0.5, -0.5, -0.5)
        p.setPen(QPen(QColor(t.line), 1))
        p.setBrush(QColor("#08ffffff"))
        p.drawRoundedRect(box, 12, 12)
        if not self.results:
            p.setPen(QColor(t.dim))
            p.setFont(font(t, t.font_px))
            p.drawText(QRectF(0, self.height() - ROW_H - LIST_PAD, self.width(), ROW_H), Qt.AlignCenter, self.note)
            return
        for i, r in enumerate(self.results):
            if i < self._scroll:
                continue
            y = self._row_y(i)
            if y + ROW_H < 0:
                break
            row = QRectF(LIST_PAD, y, self.width() - 2 * LIST_PAD, ROW_H - 2)
            selected = i == self.selected
            if selected:
                p.setPen(QPen(QColor(t.gold_line), 1))
                p.setBrush(QColor(t.gold_soft))
                p.drawRoundedRect(row, 8, 8)
            command = r["kind"] == "command"
            badge = QRectF(row.left() + 8, row.center().y() - 11, 0 if command else 22, 22)  # icono real de la app
            if not command:
                icon = app_icon(r.get("exe", ""), r.get("hwnd", 0), 22, self.devicePixelRatioF())
                p.drawPixmap(int(badge.left()), int(badge.top()), icon)
            kind = {"window": "Ventana", "command": "Atajo"}.get(r["kind"], "App")  # etiqueta del tipo
            p.setFont(font(t, t.small_px))
            kind_w = p.fontMetrics().horizontalAdvance(kind) + 12
            tag = QRectF(row.right() - kind_w - 8, row.center().y() - 9, kind_w, 18)
            p.setPen(QPen(QColor(t.gold_line if selected else t.line), 1))
            p.setBrush(Qt.NoBrush)
            p.drawRoundedRect(tag, 5, 5)
            p.setPen(QColor(t.gold if selected else t.dim))
            p.drawText(tag, Qt.AlignCenter, kind)
            x = badge.right() + 10  # nombre y detalle
            p.setFont(font(t, t.font_px + 1, bold=True))
            name = p.fontMetrics().elidedText(r["name"], Qt.ElideRight, int(row.width() * 0.4))
            name_w = p.fontMetrics().horizontalAdvance(name)
            p.setPen(QColor(t.ink))
            p.drawText(QRectF(x, row.top(), name_w + 2, row.height()), Qt.AlignVCenter, name)
            p.setFont(font(t, t.font_px + 1))
            detail_w = max(tag.left() - (x + name_w + 10) - 8, 0)
            detail = p.fontMetrics().elidedText(r["detail"], Qt.ElideRight, int(detail_w))
            p.setPen(QColor(t.dim))
            p.drawText(QRectF(x + name_w + 10, row.top(), detail_w, row.height()), Qt.AlignVCenter, detail)


class SearchPopout(QWidget):
    def __init__(self, theme, screen_map, query, launch, close):
        """`query(texto)` devuelve {results, indexing}; `launch(resultado)` lo abre; `close(refocus)` pide cerrar."""
        super().__init__()
        make_tool_window(self)
        self.setWindowTitle("KyoraSearch")
        self.theme = theme
        self._query, self._launch, self._close = query, launch, close
        self.opened = False
        self._progress = 0.0  # 0 = escondido en el marco, 1 = abierto
        self._list_h = 0.0  # alto actual de la lista de opciones (crece y encoge)

        t = theme
        self._margin = t.joint_radius + 4
        self._pad = t.search_padding
        self._max_list = t.search_rows * ROW_H + 2 * LIST_PAD
        body_max = 2 * self._pad + INPUT_H + GAP + self._max_list
        width = t.search_width + 2 * self._margin
        height = body_max + t.frame_width + math.ceil(t.edge_shadow_size) + 2  # sitio para la sombra arriba
        g = screen_map.geometry
        self._screen_height = g.height()
        hole_center = g.x() + t.bar_width + (g.width() - t.bar_width - t.frame_width) / 2
        self.setGeometry(round(hole_center - width / 2), g.y() + g.height() - height, width, height)

        self._inner_x = self._margin + self._pad
        self._inner_w = t.search_width - 2 * self._pad
        self.edit = QLineEdit(self)
        self.edit.setPlaceholderText("Buscar aplicaciones y ventanas…")
        self.edit.setFont(font(t, t.font_px + 2))
        self.edit.setStyleSheet(
            f"QLineEdit {{ background: {_css(t.field)}; color: {t.ink}; border: 1px solid {_css(t.line)};"
            f" border-radius: 12px; padding: 0 14px; selection-background-color: {_css(t.gold_soft)}; }}"
            f"QLineEdit:focus {{ border-color: {_css(t.gold_line)}; }}"
        )
        self.edit.installEventFilter(self)
        self.list = ResultList(t, self._launch_result)
        self.list.setParent(self)
        self._fade = QGraphicsOpacityEffect(self.edit)
        self.edit.setGraphicsEffect(self._fade)
        self._fade.setOpacity(0.0)
        self._layout()
        self.edit.hide()
        self.list.hide()

        self._anim = Tween(self, self._set_progress, self._finished)
        self._rows = Tween(self, self._set_list_h)
        self._query_timer = QTimer(self)
        self._query_timer.setSingleShot(True)
        self._query_timer.timeout.connect(self._run_query)
        self.edit.textChanged.connect(lambda _: self._query_timer.start(QUERY_DELAY_MS))

    # ---------- colocación: el campo abajo y la lista subiendo encima ----------

    def _layout(self):
        t = self.theme
        input_y = self.height() - t.frame_width - self._pad - INPUT_H
        self.edit.setGeometry(self._inner_x, input_y, self._inner_w, INPUT_H)
        h = round(self._list_h)
        self.list.setGeometry(self._inner_x, input_y - GAP - h, self._inner_w, h)
        self.list.setVisible(h > 0)  # sigue visible mientras se encoge: si no, las opciones desaparecerían de golpe al cerrar

    def _body_height(self):
        """Alto de la pieza que sobresale del marco, en este instante."""
        base = (2 * self._pad + INPUT_H) * self._progress
        return base + (self._list_h + GAP if self._list_h > 0.5 else 0)

    # ---------- abrir y cerrar ----------

    def open(self):
        if self.opened:
            return
        self.opened = True
        self.edit.clear()
        self.list.selected = 0
        self.edit.show()
        self._fade.setOpacity(0.0)
        QTimer.singleShot(0, self._run_query)  # primero se ve el buscador; la primera consulta llega justo después
        self.show()
        self.raise_()
        self.activateWindow()
        force_foreground(hwnd_of(self))  # Windows solo deja el foco a quien lo tiene; se fuerza
        self.edit.setFocus()
        self._anim.start(self._progress, 1.0, int(self.theme.open_ms * (1 - self._progress)), QEasingCurve.OutCubic)

    def close_popout(self):
        if not self.opened:
            return
        self.opened = False
        self._query_timer.stop()
        self._rows.start(self._list_h, 0.0, self.theme.close_ms, QEasingCurve.InCubic)
        self._anim.start(self._progress, 0.0, int(self.theme.close_ms * self._progress), QEasingCurve.InCubic)

    def _set_progress(self, value):
        self._progress = float(value)
        # el campo aparece cuando la pieza ya ha crecido lo bastante para contenerlo
        self._fade.setOpacity(min(max((self._progress - 0.5) / 0.5, 0.0), 1.0))
        self._layout()
        self.update()

    def _set_list_h(self, value):
        self._list_h = float(value)
        self._layout()
        self.update()

    def _finished(self):
        if not self.opened:
            self.edit.hide()
            self.list.hide()
            self.hide()

    # ---------- búsqueda ----------

    def _run_query(self):
        if not self.opened:
            return
        started = time.perf_counter()
        reply = self._query(self.edit.text())
        took = (time.perf_counter() - started) * 1000
        if took > SLOW_QUERY_MS:
            log.info("La búsqueda tardó %.0f ms", took)
        results = reply["results"]
        note = "Indexando aplicaciones…" if reply["indexing"] else ("" if results else "Sin resultados")
        if not self.edit.text().strip() and not results:
            note = ""
        self.list.set_results(results, note)
        target = min(self.list.wanted_height(), self._max_list)
        self._rows.start(self._list_h, target, LIST_MS, QEasingCurve.OutCubic)

    def _launch_result(self, result):
        if result and result["kind"] != "command":  # los atajos solo se muestran
            self._launch(result)

    def eventFilter(self, obj, event):
        if obj is self.edit and event.type() == QEvent.KeyPress:
            key = event.key()
            if key == Qt.Key_Up:  # la lista sube: la flecha arriba sube a la siguiente opción
                self.list.move(1)
                return True
            if key == Qt.Key_Down:
                self.list.move(-1)
                return True
            if key in (Qt.Key_Return, Qt.Key_Enter):
                self._launch_result(self.list.current())
                return True
            if key == Qt.Key_Escape:
                self._close(True)
                return True
        return super().eventFilter(obj, event)

    def changeEvent(self, event):
        # Si el usuario pasa a otra ventana, la búsqueda se cierra sin quitarle el foco.
        if event.type() == QEvent.ActivationChange and self.opened and not self.isActiveWindow():
            QTimer.singleShot(BLUR_CHECK_MS, self._check_blur)
        super().changeEvent(event)

    def _check_blur(self):
        if self.opened and not self.isActiveWindow():
            self._close(False)

    def closeEvent(self, event):
        """Alt+F4 sobre el buscador solo lo repliega."""
        event.ignore()
        self._close(True)

    # ---------- pintura ----------

    def paintEvent(self, _):
        t = self.theme
        e = min(max(self._progress, 0.0), 1.0)
        width = t.search_width * lerp(t.search_start_width, 1.0, e)
        body = self._body_height()
        if body <= 0:  # escondido: solo quedaría la franja del marco, que ya pinta el marco de debajo
            return
        # se construye colgando del borde de arriba y se voltea: el buscador cuelga del borde de abajo
        fill, outline = popout_paths(
            self.width(), t.frame_width, self.width() / 2, width, body, t.joint_radius, t.corner_radius,
        )
        # solo se pinta la pieza y sus curvas: a los lados se ve el marco de debajo, que ya lleva su borde
        # (repintarlo duplicaría la línea oscura y taparía el filete)
        reach = width / 2 + min(t.joint_radius, body / 2)
        span = QRectF(self.width() / 2 - reach, 0, 2 * reach, self.height())
        clip = QPainterPath()
        clip.addRect(span)
        fill = mirror_vertical(fill, self.height()).intersected(clip)
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        p.fillPath(fill, frame_gradient(t, self._screen_height, self.y()))
        paint_raised_edge(p, fill, span, t, contour=mirror_vertical(outline, self.height()), shadow=True)


def _css(color):
    """#aarrggbb (QColor) -> rgba() de las hojas de estilo de Qt."""
    c = QColor(color)
    return f"rgba({c.red()}, {c.green()}, {c.blue()}, {c.alpha()})"
