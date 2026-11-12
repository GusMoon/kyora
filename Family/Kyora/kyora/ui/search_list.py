"""La lista de resultados del buscador, como la referencia: una caja gris oscura (la misma de las tareas) con los
resultados agrupados por secciones (Ventanas, Aplicaciones, Carpetas…), cada uno con su icono y dos líneas (nombre y
detalle), directo sobre el fondo oscuro del panel y sin pie de teclas. De arriba abajo, como se lee: el mejor
resultado, arriba. Si hay más de los que caben, se desplaza para que el elegido siempre se vea.
"""
from PySide6.QtCore import QRectF, Qt
from PySide6.QtGui import QColor, QPainter
from PySide6.QtWidgets import QWidget

from kyora.ui.bar import font
from kyora.ui.explorer import file_icons
from kyora.ui.icons import app_icon

ROW_H = 34
HEAD_H = 22
PAD = 6
ICON = 20
MAX_H = 320
SECTIONS = {"window": "Ventanas", "web": "Páginas", "app": "Aplicaciones", "complete": "Comandos", "config": "Opciones de Kyora",
            "command": "Atajos"}


def section_of(r):
    """A qué sección va un resultado."""
    if r["kind"] == "path":
        return "Unidades" if r.get("drive") else ("Carpetas" if r.get("is_dir") else "Archivos")
    return SECTIONS.get(r["kind"], "Resultados")


def kind_label(r):
    if r["kind"] == "path":
        return "Unidad" if r.get("drive") else ("Carpeta" if r.get("is_dir") else "Archivo")
    return {"window": "Ventana", "web": "Página", "command": "Atajo", "complete": "Comando", "config": "Kyora"}.get(r["kind"], "App")


class ResultList(QWidget):
    def __init__(self, theme, on_launch, on_pick=None):
        """`on_launch(resultado)` abre el elegido; `on_pick(resultado)`, si se da, atiende el clic en un archivo (que
        se previsualiza antes de abrirse); Enter sigue abriendo directo."""
        super().__init__()
        self.theme = theme
        self.on_launch = on_launch
        self.on_pick = on_pick
        self.results = []
        self.note = ""
        self.selected = 0
        self._entries = []  # [(y, alto, "head", texto) | (y, alto, "row", índice)] en coordenadas del contenido
        self._content = 0
        self._scroll = 0
        self.setMouseTracking(True)
        self.setCursor(Qt.PointingHandCursor)

    # ---------- datos ----------

    def set_results(self, results, note=""):
        """Los resultados, agrupados por sección en el orden en que aparece cada una (dentro, su propio orden)."""
        order = []
        for r in results:
            if section_of(r) not in order:
                order.append(section_of(r))
        self.results = sorted(results, key=lambda r: order.index(section_of(r)))
        self.note = note
        self.selected = min(self.selected, max(len(results) - 1, 0))
        y, last = PAD, None
        self._entries = []
        for i, r in enumerate(self.results):
            if section_of(r) != last:
                last = section_of(r)
                self._entries.append((y, HEAD_H, "head", last))
                y += HEAD_H
            self._entries.append((y, ROW_H, "row", i))
            y += ROW_H
        self._content = y + PAD
        self._scroll = 0
        self._follow()
        self.update()

    def wanted_height(self):
        """Alto que necesita la lista ahora: secciones y filas más el pie, o una sola línea de aviso, o nada."""
        if self.results:
            return min(self._content + 0, MAX_H)
        return 2 * PAD + ROW_H if self.note else 0

    def current(self):
        return self.results[self.selected] if self.results else None

    def _view_h(self):
        return max(self.height(), 1)

    def _row_entry(self, i):
        return next(e for e in self._entries if e[2] == "row" and e[3] == i)

    def _follow(self):
        """Desplaza lo justo para que la fila elegida (y su título de sección, si es la primera) se vea."""
        if not self.results:
            return
        y, h, _, _ = self._row_entry(self.selected)
        first = next((e for e in self._entries if e[2] == "head" and e[0] + HEAD_H == y), None)
        top = first[0] if first else y
        self._scroll = max(0, min(self._scroll, self._content - self._view_h()))
        if top < self._scroll:
            self._scroll = top
        elif y + h + PAD > self._scroll + self._view_h():
            self._scroll = y + h + PAD - self._view_h()
        self._scroll = max(0, self._scroll)

    def resizeEvent(self, event):
        self._follow()
        super().resizeEvent(event)

    # ---------- teclas y ratón ----------

    def move(self, step):
        if self.results:
            self.selected = max(0, min(self.selected + step, len(self.results) - 1))
            self._follow()
            self.update()

    def wheelEvent(self, event):
        self.move(-1 if event.angleDelta().y() > 0 else 1)

    def _row_at(self, pos):
        if pos.y() >= self._view_h():
            return None
        y = pos.y() + self._scroll
        return next((e[3] for e in self._entries if e[2] == "row" and e[0] <= y < e[0] + e[1]), None)

    def mouseMoveEvent(self, event):
        row = self._row_at(event.position())
        if row is not None and row != self.selected:
            self.selected = row
            self.update()

    def mouseReleaseEvent(self, event):
        row = self._row_at(event.position())
        if event.button() == Qt.LeftButton and row is not None:
            result = self.results[row]
            if self.on_pick and result["kind"] == "path" and not result.get("is_dir"):
                self.selected = row
                self.update()
                self.on_pick(result)
            else:
                self.on_launch(result)

    # ---------- pintura ----------

    def paintEvent(self, _):
        t = self.theme
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        if not self.results:
            p.setPen(QColor(t.dim))
            p.setFont(font(t, 12))
            p.drawText(QRectF(self.rect()), Qt.AlignCenter, self.note)
            return
        p.save()
        p.setClipRect(QRectF(0, 1, self.width(), self._view_h() - 1))
        for y, h, kind, data in self._entries:
            top = y - self._scroll
            if top + h < 0 or top > self._view_h():
                continue
            if kind == "head":
                p.setFont(font(t, 11, bold=True))
                p.setPen(QColor(t.dim))
                p.drawText(QRectF(PAD + 8, top, self.width() - 2 * PAD, h), Qt.AlignVCenter, data)
            else:
                self._paint_row(p, QRectF(PAD, top, self.width() - 2 * PAD, h), self.results[data], data == self.selected)
        p.restore()

    def _paint_row(self, p, row, r, selected):
        t = self.theme
        if selected:  # la elegida: algo más clara, sin relieve (como las tareas)
            p.setPen(Qt.NoPen)
            p.setBrush(QColor(255, 255, 255, 18))
            p.drawRoundedRect(row.adjusted(0, 1, 0, -1), 7, 7)
        textless = r["kind"] in ("command", "complete", "config")  # sin icono: atajos, comandos y opciones
        x = row.left() + 9
        if not textless:
            badge = QRectF(x, row.center().y() - ICON / 2, ICON, ICON)
            if r["kind"] == "path":  # carpetas y archivos: los iconos propios de Kyora
                icons = file_icons.shared()
                (icons.folder() if r.get("is_dir") else icons.file()).paint(p, badge.toRect())
            else:
                icon = app_icon(r.get("exe", ""), r.get("hwnd", 0), ICON, self.devicePixelRatioF())
                p.drawPixmap(int(badge.left()), int(badge.top()), icon)
            x = badge.right() + 10
        width = row.right() - x - 8
        p.setFont(font(t, 12, bold=True))
        p.setPen(QColor(t.gold if selected and textless else t.ink))
        name = p.fontMetrics().elidedText(r["name"], Qt.ElideRight, int(width))
        p.drawText(QRectF(x, row.top() + 3, width, 16), Qt.AlignVCenter, name)
        p.setFont(font(t, 11))
        p.setPen(QColor(t.warn if r["detail"].startswith("Pulsa Enter") else t.dim))
        detail = p.fontMetrics().elidedText(r["detail"], Qt.ElideRight, int(width))
        p.drawText(QRectF(x, row.top() + 18, width, 14), Qt.AlignVCenter, detail)
