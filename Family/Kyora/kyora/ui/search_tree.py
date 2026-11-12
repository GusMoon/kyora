"""El árbol de `>tree` en el buscador: tus carpetas de siempre y las unidades, que se despliegan con →.

↑/↓ se mueven, → (o Enter en una carpeta) despliega, ← pliega o sube a la carpeta de arriba, Enter en un archivo lo
abre y Ctrl+Enter abre la carpeta en el Explorador de Windows. Los hijos se piden al núcleo al desplegar.
"""
from PySide6.QtCore import QRectF, Qt
from PySide6.QtGui import QColor, QPainter, QPainterPath
from PySide6.QtWidgets import QWidget

from kyora.ui import glyphs
from kyora.ui.bar import font
from kyora.ui.explorer import file_icons

ROW = 32
PAD = 6
INDENT = 18
MAX_H = 360


class TreeList(QWidget):
    def __init__(self, theme, children, on_open, on_pick=None):
        """`children(ruta)` da las filas de una carpeta; `on_open(fila, ctrl)` abre un archivo o carpeta; `on_pick(fila)`,
        si se da, atiende el clic (sin Ctrl) en un archivo, que se previsualiza antes de abrirse. Enter abre directo."""
        super().__init__()
        self.theme = theme
        self._children, self._on_open, self._on_pick = children, on_open, on_pick
        self.nodes = []  # [{row, depth, open, kids}] en el orden en que se ven
        self.selected = 0
        self._scroll = 0
        self.setMouseTracking(True)
        self.setCursor(Qt.PointingHandCursor)

    # ---------- datos ----------

    def set_roots(self, roots, expand=False, expanded=()):
        """`expand`: despliega la primera; `expanded`: los `id` de las raíces que ya salen desplegadas."""
        self.nodes = [{"row": r, "depth": 0, "open": False} for r in roots]
        self.selected, self._scroll = 0, 0
        if expand and self.nodes:
            self._expand(0)
        i = 0
        while i < len(self.nodes):
            if self.nodes[i]["depth"] == 0 and self.nodes[i]["row"]["id"] in expanded:
                self._expand(i)
            i += 1
        self.update()

    def _expand(self, i):
        node = self.nodes[i]
        if not node["row"].get("is_dir") or node["open"]:
            return
        kids = [{"row": r, "depth": node["depth"] + 1, "open": False} for r in self._children(node["row"]["id"])]
        node["open"] = True
        self.nodes[i + 1:i + 1] = kids

    def _collapse(self, i):
        node = self.nodes[i]
        end = i + 1
        while end < len(self.nodes) and self.nodes[end]["depth"] > node["depth"]:
            end += 1
        del self.nodes[i + 1:end]
        node["open"] = False

    def wanted_height(self):
        return min(max(len(self.nodes), 1) * ROW + 2 * PAD, MAX_H)

    def current(self):
        return self.nodes[self.selected]["row"] if self.nodes else None

    # ---------- teclas ----------

    def move(self, step):
        if self.nodes:
            self.selected = max(0, min(self.selected + step, len(self.nodes) - 1))
            self._follow()
            self.update()

    def right(self):
        if self.nodes:
            node = self.nodes[self.selected]
            if node["row"].get("is_dir") and not node["open"]:
                self._expand(self.selected)
            elif node["open"] and self.selected + 1 < len(self.nodes):
                self.selected += 1
            self._follow()
            self.update()

    def left(self):
        if not self.nodes:
            return
        node = self.nodes[self.selected]
        if node["open"]:
            self._collapse(self.selected)
        else:  # a la carpeta de arriba
            for i in range(self.selected - 1, -1, -1):
                if self.nodes[i]["depth"] < node["depth"]:
                    self.selected = i
                    break
        self._follow()
        self.update()

    def enter(self, ctrl=False):
        if not self.nodes:
            return
        node = self.nodes[self.selected]
        if node["row"].get("is_dir") and not ctrl:
            self._collapse(self.selected) if node["open"] else self._expand(self.selected)
            self.update()
        else:
            self._on_open(node["row"], ctrl)

    # ---------- desplazamiento y ratón ----------

    def _fits(self):
        return max(int((self.height() - 2 * PAD) // ROW), 1)

    def _follow(self):
        self._scroll = min(max(self._scroll, self.selected - self._fits() + 1), self.selected)

    def resizeEvent(self, event):
        self._follow()
        super().resizeEvent(event)

    def wheelEvent(self, event):
        self.move(-1 if event.angleDelta().y() > 0 else 1)

    def _row_at(self, y):
        i = int((y - PAD) // ROW) + self._scroll
        return i if 0 <= i < len(self.nodes) else None

    def mouseMoveEvent(self, event):
        i = self._row_at(event.position().y())
        if i is not None and i != self.selected:
            self.selected = i
            self.update()

    def mouseReleaseEvent(self, event):
        i = self._row_at(event.position().y())
        if i is not None and event.button() == Qt.LeftButton:
            self.selected = i
            ctrl = bool(event.modifiers() & Qt.ControlModifier)
            row = self.nodes[i]["row"]
            if self._on_pick and not ctrl and not row.get("is_dir"):
                self.update()
                self._on_pick(row)
            else:
                self.enter(ctrl=ctrl)

    # ---------- pintura ----------

    def paintEvent(self, _):
        t = self.theme
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        p.setClipRect(self.rect())
        if not self.nodes:
            p.setPen(QColor(t.dim))
            p.setFont(font(t, 13))
            p.drawText(QRectF(self.rect()), Qt.AlignCenter, "Nada aquí")
            return
        icons = file_icons.shared()
        for i in range(self._scroll, min(len(self.nodes), self._scroll + self._fits() + 1)):
            node, row = self.nodes[i], self.nodes[i]["row"]
            y = PAD + (i - self._scroll) * ROW
            box = QRectF(PAD, y, self.width() - 2 * PAD, ROW - 2)
            if i == self.selected:
                p.setPen(Qt.NoPen)  # la elegida: algo más clara, plana
                p.setBrush(QColor(255, 255, 255, 18))
                p.drawRoundedRect(box, 8, 8)
            x = box.left() + 8 + node["depth"] * INDENT
            if row.get("is_dir"):  # el triángulo de desplegar
                p.setPen(glyphs.pen(QColor(t.dim), 1.4))
                cy = box.center().y()
                arrow = QPainterPath()
                if node["open"]:
                    arrow.moveTo(x, cy - 2)
                    arrow.lineTo(x + 4, cy + 2)
                    arrow.lineTo(x + 8, cy - 2)
                else:
                    arrow.moveTo(x + 2, cy - 4)
                    arrow.lineTo(x + 6, cy)
                    arrow.lineTo(x + 2, cy + 4)
                p.drawPath(arrow)
            icon = icons.folder() if row.get("is_dir") else icons.file()
            icon.paint(p, QRectF(x + 12, box.center().y() - 10, 20, 20).toRect())
            p.setFont(font(t, 14, bold=i == self.selected))
            p.setPen(QColor(t.ink))
            detail = "" if row.get("is_dir") and not row.get("drive") else row.get("detail", "").split(" · ")[0]
            p.setFont(font(t, 13))
            detail_w = p.fontMetrics().horizontalAdvance(detail) + 10 if detail else 0
            p.setFont(font(t, 14, bold=i == self.selected))
            left = x + 40
            name = p.fontMetrics().elidedText(row["name"], Qt.ElideMiddle, int(box.right() - left - detail_w - 8))
            p.drawText(QRectF(left, box.top(), box.right() - left, box.height()), Qt.AlignVCenter, name)
            if detail:
                p.setFont(font(t, 13))
                p.setPen(QColor(t.dim))
                p.drawText(QRectF(box.right() - detail_w - 6, box.top(), detail_w, box.height()),
                           Qt.AlignVCenter | Qt.AlignRight, detail)
        if len(self.nodes) > self._fits():  # dónde vamos, si no cabe todo
            frac = self._scroll / max(len(self.nodes) - self._fits(), 1)
            track = self.height() - 2 * PAD
            handle = max(track * self._fits() / len(self.nodes), 24)
            p.setPen(Qt.NoPen)
            p.setBrush(QColor(t.line))
            p.drawRoundedRect(QRectF(self.width() - 5, PAD + (track - handle) * frac, 3, handle), 1.5, 1.5)
