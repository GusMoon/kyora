"""La página de configuración: se abre con el botón de ajustes de la barra de arriba y cuelga del mismo panel superior.

Es más ancha que alta. A la izquierda, una **barra lateral** con las áreas (Atajos y Ejecutables, con su contador). A la
derecha, el contenido en **una sola lista con scroll vertical** (sin barra a la vista), ordenada en **secciones** con
su título y una línea de explicación, sin tarjetas:
- **Atajos:** un campo para filtrar (por teclas o por lo que hacen), el orden (por sección o por tecla principal) y,
  en cada fila, las teclas dibujadas a la izquierda y lo que hacen a la derecha.
- **Ejecutables:** cada uno con su explicación y un botón **Ejecutar** que pide confirmar ahí mismo ("¿Seguro? Sí · No"),
  porque algunos cierran o reinician Kyora.

Al desplazar la lista, los bordes de arriba y de abajo se oscurecen muy pegados al límite (así nada se ve cortado en
seco); el efecto solo aparece mientras se desplaza y se desvanece solo al parar.

Los atajos se pueden **cambiar**: al pasar el cursor por una fila sale "Editar"; se pulsa la combinación nueva y la
página avisa si no vale (la tecla Windows está bloqueada, la usan casi todas las apps, otro atajo de Kyora ya la tiene
o la ha cogido otro programa). Un grupo (las flechas, 1/2/3…) deja sus teclas quietas (atenuadas): solo se escribe lo previo, los modificadores. Se guarda en config.json y
vale al momento; "Restaurar" vuelve a los de fábrica.

Atajos tiene dos tipos de comando, junto al título: **Teclas** (lo de arriba) y **Páginas web**: una lista de páginas
con su nombre (lo que se escribe en el buscador) y su dirección, que se añaden, editan y borran ahí mismo (Borrar pide una
segunda pulsación). **Predeterminados** guarda lo que Kyora usa por defecto: hoy, el navegador con el que se abren esas
páginas (al pulsar se despliegan los instalados, o el predeterminado de Windows).

Fondos: las miniaturas se leen solo cuando se ven (en un hilo, ya reducidas) y se guardan pocas; las flechas mueven la
elección y el fondo solo cambia con Enter o con un clic.

Teclado: escribir filtra, ↑/↓ y RePág/AvPág desplazan, Tab cambia de área y Esc borra el filtro (o cierra).
"""
import os
import queue
import threading
from collections import OrderedDict

from PySide6.QtCore import (
    QEasingCurve,
    QObject,
    QPointF,
    QRectF,
    QSize,
    Qt,
    QTimer,
    Signal,
)
from PySide6.QtGui import (
    QColor,
    QFontMetrics,
    QImage,
    QImageReader,
    QLinearGradient,
    QPainter,
    QPainterPath,
    QPen,
    QPixmap,
)
from PySide6.QtWidgets import QLineEdit

from kyora import config as app_config
from kyora.core.commands import config_data, filter_cards, key_tokens, label_of
from kyora.core.hotkey_edit import apply_edit, normalize, split
from kyora.search import web as web_pages
from kyora.system.hotkeys import is_free
from kyora.ui import backdrop, glyphs
from kyora.ui.accent import dominant_colors, top_colors
from kyora.ui.anim import Tween
from kyora.ui.bar import accent, font
from kyora.ui.dock import DockPage
from kyora.ui.icons import app_icon

AREAS = (("Atajos", "Los comandos de Kyora, por sección o por la tecla con la que empiezan.", glyphs.keyboard),
         ("Ejecutables", "Reiniciar, actualizar, rescatar o cerrar Kyora y su arranque con Windows.", glyphs.terminal),
         ("Fondos", "Elige con las flechas y pulsa Enter (o haz clic) para ponerlo: los colores de Kyora lo siguen.", glyphs.picture),
         ("Rendimiento", "Gastar menos memoria y procesador en equipos justos.", glyphs.gauge),
         ("Predeterminados", "Lo que Kyora usa por defecto, como el navegador de las páginas web.", glyphs.globe))
ATAJOS, EJECUTABLES, FONDOS, RENDIMIENTO, PREDETERMINADOS = range(5)
MODES = (("section", "Por sección"), ("key", "Por tecla"))
KINDS = (("keys", "Teclas"), ("web", "Páginas web"))  # los dos tipos de comando de Atajos
SYSTEM_BROWSER = "Predeterminado de Windows"
WEB_NAME_W = 110  # el campo del nombre de una página, al editarla
WEB_MSG_H = 22  # la línea de aviso bajo una página que se edita
CHOICE_H = 40  # una fila de la lista de navegadores
SIDEBAR_W = 182
GAP = 16
PAD = 10
HEADER_H = 58  # título y explicación del área
CONTROLS_H = 38  # el filtro y el orden
HEAD_H = 54  # el título de una sección y su explicación
ROW_H = 38  # una fila de atajo: teclas a la izquierda, explicación a la derecha
EXEC_H = 58  # una fila de ejecutable (y de ajuste)
THUMB_W, THUMB_H, THUMB_GAP = 156, 88, 10  # las miniaturas de los fondos
SWATCH = 14  # los puntos de color de cada miniatura
THUMB_SCALE = 1.5  # se leen un poco más grandes que lo que se ven (pantallas con escala)
THUMB_CACHE = 48  # miniaturas en memoria como mucho (unas 300 KB cada una)
KEYS_W = 300  # la columna de las teclas
CAP_H = 22
EDIT_W = 64  # el botón "Editar" de una fila
EDGE_H = 34  # alto del oscurecimiento de los bordes al desplazar
EDGE_ALPHA = 245
EDGE_HOLD_MS = 650  # cuánto se queda el efecto después del último desplazamiento
EDGE_FADE_MS = 650  # y lo que tarda en desvanecerse


class Thumbs(QObject):
    """Lee las miniaturas de los fondos en un hilo, bajo demanda y de una en una. El JPEG se decodifica ya reducido, así
    que ni las fotos enormes gastan memoria ni bloquean la interfaz."""

    ready = Signal(str, QImage, object)  # (ruta, miniatura, los 4 colores que más se repiten)

    def __init__(self):
        super().__init__()
        self._queue = queue.Queue()
        self._asked = set()
        self._worker = None

    def request(self, path):
        if path in self._asked:
            return
        self._asked.add(path)
        self._queue.put(path)
        if self._worker is None:
            self._worker = threading.Thread(target=self._run, daemon=True, name="kyora-thumbs")
            self._worker.start()

    def forget(self, path):
        """La miniatura salió de la caché: si se vuelve a ver, se pide otra vez."""
        self._asked.discard(path)

    def _run(self):
        while True:
            path = self._queue.get()
            try:
                image = self._load(path)
                colors = top_colors(dominant_colors(image)) if not image.isNull() else []
                self.ready.emit(path, image, colors)
            except Exception:  # noqa: BLE001 - una imagen rota no debe parar a las demás
                self.ready.emit(path, QImage(), [])

    @staticmethod
    def _load(path):
        reader = QImageReader(path)
        reader.setAutoTransform(True)
        want = QSize(round(THUMB_W * THUMB_SCALE), round(THUMB_H * THUMB_SCALE))
        size = reader.size()
        if size.isValid():
            reader.setScaledSize(size.scaled(want, Qt.KeepAspectRatioByExpanding))
        image = reader.read()
        if image.isNull():
            return image
        left, top = (image.width() - want.width()) // 2, (image.height() - want.height()) // 2
        return image.copy(max(left, 0), max(top, 0), want.width(), want.height())


class _Field(QLineEdit):
    """Un campo de texto de la página; Esc avisa en vez de cerrar nada (cancela la edición de la página web)."""

    escaped = Signal()

    def keyPressEvent(self, event):
        if event.key() == Qt.Key_Escape:
            self.escaped.emit()
        else:
            super().keyPressEvent(event)


class ConfigPage(DockPage):
    size = (720, 580)  # (ancho, alto): alta y no tan ancha (en la esquina de abajo a la derecha crece hacia arriba)

    def __init__(self, theme, invoke, data):
        """`data()` -> {"commands": {"section": [...], "key": [...]}, "executables": [...]}, con secciones {title, info,
        rows}; `invoke(acción, **datos)` ejecuta un ejecutable."""
        super().__init__()
        self.theme, self._invoke, self._data_fn = theme, invoke, data
        self.data = {"commands": {"section": [], "key": []}, "executables": [], "hotkeys": {}, "wallpapers": [],
                     "options": [], "web": {"shortcuts": [], "browser": "", "chosen": "", "default": "", "browsers": []}}
        self.area, self.mode, self.kind = ATAJOS, "section", "keys"
        self._web_edit = None  # la página que se escribe: {"index": posición (la de "añadir" es la última), "message"}
        self._web_del = None  # la página que espera la segunda pulsación de "Borrar"
        self._browser_open = False  # la lista de navegadores de Predeterminados está desplegada
        self.scroll = 0
        self._content = 0
        self._confirm = None  # (sección, ejecutable) que espera el "Sí"
        self._hover = None
        self._thumbs = OrderedDict()  # ruta -> QPixmap (las más recientes)
        self._swatches = {}  # ruta -> sus 4 colores que más se repiten
        self._loader = Thumbs()
        self._loader.ready.connect(self._thumb_ready)
        self._sel = 0  # el fondo elegido con las flechas (no se pone hasta pulsar Enter o hacer clic)
        self._cellx = {}
        self._loaded = False
        self._editing = None  # la fila que se edita: {group, row, candidate, message, ok, held}
        self._reset_ask = False  # "Restaurar" pidió confirmación
        self._edge = 0.0  # cuánto se ve el oscurecimiento de los bordes (0 a 1)
        self._edge_fade = Tween(self, self._set_edge)
        self._edge_hold = QTimer(self)
        self._edge_hold.setSingleShot(True)
        self._edge_hold.setInterval(EDGE_HOLD_MS)
        self._edge_hold.timeout.connect(lambda: self._edge_fade.start(self._edge, 0.0, EDGE_FADE_MS, QEasingCurve.InOutSine))
        self.filter = QLineEdit(self)
        self.filter.setPlaceholderText("Filtrar atajos…")
        self.filter.setClearButtonEnabled(True)
        self.filter.textChanged.connect(self._filtered)
        self.web_name = _Field(self)
        self.web_name.setPlaceholderText("Nombre")
        self.web_url = _Field(self)
        self.web_url.setPlaceholderText("Dirección (youtube.com)")
        for field in (self.web_name, self.web_url):
            field.hide()
            field.returnPressed.connect(self._web_save)
            field.escaped.connect(self._web_cancel)
        self.retheme(theme)
        self.setFocusPolicy(Qt.StrongFocus)
        self.setMouseTracking(True)

    def retheme(self, theme):
        self.theme = theme
        self.filter.setStyleSheet(
            f"QLineEdit {{ background: {theme.frame_dark}; color: {theme.ink}; border: 1px solid rgba(255, 255, 255, 26);"
            f" border-radius: 16px; padding: 0 14px; selection-background-color: {theme.gold_soft}; }}"
            f"QLineEdit:focus {{ border-color: {theme.gold}; }}")
        for field in (self.web_name, self.web_url):
            field.setStyleSheet(
                f"QLineEdit {{ background: {theme.frame_dark}; color: {theme.ink}; border: 1px solid rgba(255, 255, 255, 26);"
                f" border-radius: 14px; padding: 0 12px; selection-background-color: {theme.gold_soft}; }}"
                f"QLineEdit:focus {{ border-color: {theme.gold}; }}")

    def resizeEvent(self, event):
        super().resizeEvent(event)
        self._arrange()

    # ---------- datos ----------

    def activate(self):
        if not self._loaded:  # la primera vez; después se conserva (abrir la página es instantáneo)
            self.data = self._data_fn()
            self._loaded = True
        self.scroll = 0
        self._confirm = None
        self._editing = None
        self._reset_ask = False
        self._web_edit = self._web_del = None
        self._browser_open = False
        self._edge = 0.0
        self.filter.clear()
        self._arrange()
        self.update()

    def focus_first(self):
        (self.filter if self._filtering() else self).setFocus()

    def _filtering(self):
        """El campo de filtro solo está en Atajos > Teclas."""
        return self.area == ATAJOS and self.kind == "keys"

    def _area_groups(self, area):
        if area == PREDETERMINADOS:
            return self._defaults_groups()
        return (self.data["commands"]["section"], self.data["executables"], self.data.get("wallpapers", []),
                self.data.get("options", []))[area]

    def _groups(self):
        if self.area == ATAJOS:
            if self.kind == "web":
                return self._web_groups()
            return filter_cards(self.data["commands"][self.mode], self.filter.text())
        return self._area_groups(self.area)

    def _count(self, area):
        if area == PREDETERMINADOS:
            return 1
        return sum(len(g["rows"]) for g in self._area_groups(area))

    def _row_h(self):
        return {ATAJOS: ROW_H, EJECUTABLES: EXEC_H, FONDOS: THUMB_H, RENDIMIENTO: EXEC_H, PREDETERMINADOS: EXEC_H}[self.area]

    def _row_height(self, row):
        """El alto de una fila: el de su área, salvo la lista de navegadores (más baja) y la página que se escribe (con su
        línea de aviso)."""
        if self.area == PREDETERMINADOS and row.get("choice"):
            return CHOICE_H
        if self._is_web_edit(row):
            return ROW_H + WEB_MSG_H
        return self._row_h()

    # ---------- páginas web y navegador (los datos viajan en data["web"]) ----------

    def _web(self):
        return self.data.setdefault("web", {"shortcuts": [], "browser": "", "chosen": "", "default": "", "browsers": []})

    def _web_groups(self):
        shortcuts = self._web()["shortcuts"]
        rows = [{"keys": s["name"], "text": s["url"], "index": i} for i, s in enumerate(shortcuts)]
        rows.append({"keys": "Añadir página", "text": "", "index": len(shortcuts), "add": True})
        return [{"title": "Páginas web", "count": len(shortcuts), "rows": rows,
                 "info": "El nombre es lo que escribes en el buscador; la dirección, lo que se abre."}]

    def _is_web_edit(self, row):
        return (self._web_edit is not None and self.area == ATAJOS and self.kind == "web"
                and row.get("index") == self._web_edit["index"])

    def _browser_name(self, exe):
        """El nombre de un navegador por su .exe (el de la lista de instalados, o el del archivo)."""
        norm = os.path.normcase(exe)
        found = next((b["name"] for b in self._web()["browsers"] if os.path.normcase(b["exe"]) == norm), "")
        return found or os.path.splitext(os.path.basename(exe))[0].capitalize()

    def _defaults_groups(self):
        web = self._web()
        chosen = web["chosen"]
        current = self._browser_name(chosen) if chosen else SYSTEM_BROWSER
        rows = [{"keys": "Navegador", "text": current, "main": True}]
        if self._browser_open:
            rows.append({"keys": SYSTEM_BROWSER, "text": "El que tengas puesto en Windows", "exe": "", "choice": True,
                         "on": not chosen})
            rows += [{"keys": b["name"], "text": b["exe"], "exe": b["exe"], "choice": True,
                      "on": os.path.normcase(b["exe"]) == os.path.normcase(chosen)} for b in web["browsers"]]
        return [{"title": "Páginas web", "count": None, "rows": rows,
                 "info": "Con este navegador se abren las páginas que buscas en el buscador."}]

    # ---------- geometría ----------

    def _content_x(self):
        return SIDEBAR_W + GAP

    def _content_w(self):
        return self.width() - self._content_x() - PAD

    def _list_top(self):
        return HEADER_H + (CONTROLS_H + 8 if self._filtering() else 4)

    def _list_h(self):
        return self.height() - self._list_top()

    def _arrange(self):
        """Coloca el campo de filtro (solo en Atajos > Teclas) y los de la página web que se escribe."""
        self.filter.setVisible(self._filtering())
        modes_w = sum(self._mode_widths())
        self.filter.setGeometry(self._content_x(), HEADER_H, int(self._content_w() - modes_w - 8), CONTROLS_H - 6)
        self._place_fields()

    def _place_fields(self):
        """Los dos campos de la página web que se escribe van encima de su fila; si no se ve entera, se esconden."""
        shown = False
        if self._web_edit is not None and self.area == ATAJOS and self.kind == "web":
            top, bottom = self._list_top(), self._list_top() + self._list_h()
            for kind, _group, row, y in self._items():
                if kind == "row" and self._is_web_edit(row):
                    at = top + y - self.scroll
                    if at >= top and at + ROW_H <= bottom:
                        shown = True
                        x = self._content_x()
                        url_x = x + WEB_NAME_W + 6
                        save = self._row_buttons(at)["save"]
                        self.web_name.setGeometry(int(x), int(at + 5), WEB_NAME_W, 28)
                        self.web_url.setGeometry(int(url_x), int(at + 5), int(save.left() - 8 - url_x), 28)
        self.web_name.setVisible(shown)
        self.web_url.setVisible(shown)

    def _kind_rects(self):
        """Las dos píldoras de tipo de Atajos (Teclas, Páginas web), junto al título."""
        metrics = QFontMetrics(font(self.theme, bold=True))
        rects, x = [], self._content_x() + 92
        for key, name in KINDS:
            width = metrics.horizontalAdvance(name) + 30
            rects.append((key, QRectF(x, 5, width - 4, 24)))
            x += width
        return rects

    def _mode_widths(self):
        metrics = QFontMetrics(font(self.theme, bold=True))
        return [metrics.horizontalAdvance(name) + 30 for _, name in MODES]

    def _mode_rects(self):
        rects, x = [], self.width() - PAD
        for (key, _name), width in reversed(list(zip(MODES, self._mode_widths()))):
            x -= width
            rects.append((key, QRectF(x, HEADER_H + 1, width - 4, CONTROLS_H - 8)))
        return list(reversed(rects))

    def _sidebar_rects(self):
        return [QRectF(10, 54 + i * 50, SIDEBAR_W - 20, 42) for i in range(len(AREAS))]

    def _wall_rows(self):
        return [row for group in self.data["wallpapers"] for row in group["rows"]]

    def _cols(self):
        return max(int((self._content_w() + THUMB_GAP) // (THUMB_W + THUMB_GAP)), 1)

    def _thumb_ready(self, path, image, colors):
        if not image.isNull():
            self._thumbs[path] = QPixmap.fromImage(image)
            self._swatches[path] = colors
            while len(self._thumbs) > THUMB_CACHE:
                old, _ = self._thumbs.popitem(last=False)
                self._swatches.pop(old, None)
                self._loader.forget(old)
            self.update()

    def _select(self, index):
        """Mueve la elección con las flechas y la deja a la vista; el fondo no cambia hasta Enter o clic."""
        rows = self._wall_rows()
        if not rows:
            return
        self._sel = min(max(index, 0), len(rows) - 1)
        y = HEAD_H + (self._sel // self._cols()) * (THUMB_H + THUMB_GAP)
        if y < self.scroll:
            self.scroll = y - HEAD_H
        elif y + THUMB_H > self.scroll + self._list_h():
            self.scroll = y + THUMB_H - self._list_h() + THUMB_GAP
        self.scroll = int(min(max(self.scroll, 0), self._limit()))
        self._scrolled()

    def _use(self, row):
        """Poner ese fondo (clic o Enter): Kyora cambia el de Windows y sus colores lo siguen."""
        self._invoke(row["action"], **row["payload"])
        for other in self._wall_rows():
            other["current"] = other is row

    def _items(self):
        """[(tipo, grupo, fila, y)] de la lista entera (y relativa al principio, sin desplazamiento) y su alto total."""
        items, y = [], 0
        for group in self._groups():
            items.append(("head", group, None, y))
            y += HEAD_H
            if self.area == FONDOS:  # una cuadrícula de miniaturas
                cols = self._cols()
                for n, row in enumerate(group["rows"]):
                    self._cellx[id(row)] = (n % cols) * (THUMB_W + THUMB_GAP)
                    items.append(("cell", group, row, y + (n // cols) * (THUMB_H + THUMB_GAP)))
                y += -(-len(group["rows"]) // cols) * (THUMB_H + THUMB_GAP)
                continue
            for row in group["rows"]:
                items.append(("row", group, row, y))
                y += self._row_height(row)
            y += 8
        self._content = y
        return items

    def _limit(self):
        self._items()
        return max(self._content - self._list_h(), 0)

    # ---------- desplazamiento y efecto de los bordes ----------

    def _set_edge(self, value):
        self._edge = float(value)
        self.update()

    def _scrolled(self):
        """Algo se desplazó: los bordes se oscurecen al momento y, un poco después de parar, se desvanecen."""
        self._edge_fade.stop()
        self._edge_hold.stop()
        self._edge = 1.0
        self._edge_hold.start()
        self.update()

    def _scroll_by(self, delta):
        limit = self._limit()
        new = int(min(max(self.scroll + delta, 0), limit))
        if new != self.scroll:
            self.scroll = new
            self._scrolled()

    def wheelEvent(self, event):
        self._scroll_by(-event.angleDelta().y() / 2)

    def _filtered(self):
        self.scroll = 0
        self.update()

    def _set_area(self, area):
        if area != self.area:
            if area == FONDOS:  # la lista de fondos se vuelve a leer al entrar (puede haber imágenes nuevas)
                self.data["wallpapers"] = self._data_fn()["wallpapers"]
                self._sel = max(next((i for i, r in enumerate(self._wall_rows()) if r["current"]), 0), 0)
            elif area == PREDETERMINADOS:  # los navegadores instalados se vuelven a leer al entrar
                self.data["web"] = self._data_fn().get("web", self._web())
            self.area, self.scroll, self._confirm = area, 0, None
            self._editing, self._reset_ask = None, False
            self._web_edit = self._web_del = None
            self._browser_open = False
            self.filter.clear()
            self._arrange()
            self.focus_first()
            self.update()

    def _set_mode(self, mode):
        if mode != self.mode:
            self.mode, self.scroll = mode, 0
            self.update()

    def _set_kind(self, kind):
        if kind != self.kind:
            self.kind, self.scroll = kind, 0
            self._editing, self._reset_ask = None, False
            self._web_edit = self._web_del = None
            self._arrange()
            self.focus_first()
            self.update()

    # ---------- páginas web y navegador: acciones ----------

    def _reveal(self, index):
        """Desplaza lo justo para que la página `index` se vea entera."""
        for kind, _group, row, y in self._items():
            if kind == "row" and row.get("index") == index:
                height = self._row_height(row)
                if y < self.scroll:
                    self.scroll = y
                elif y + height > self.scroll + self._list_h():
                    self.scroll = y + height - self._list_h() + 8
                self.scroll = int(min(max(self.scroll, 0), self._limit()))
                return

    def _web_start(self, index):
        """Escribir una página (la que ya está en `index`, o una nueva si es la posición de "añadir")."""
        shortcuts = self._web()["shortcuts"]
        entry = shortcuts[index] if index < len(shortcuts) else {"name": "", "url": ""}
        self._web_edit, self._web_del = {"index": index, "message": ""}, None
        self.web_name.setText(entry["name"])
        self.web_url.setText(entry["url"])
        self._reveal(index)
        self._place_fields()
        self.web_name.setFocus()
        self.web_name.selectAll()
        self.update()

    def _web_cancel(self):
        self._web_edit = None
        self._place_fields()
        self.setFocus()
        self.update()

    def _web_save(self):
        edit = self._web_edit
        if edit is None:
            return
        items = [dict(s) for s in self._web()["shortcuts"]]
        entry = {"name": self.web_name.text().strip(), "url": self.web_url.text().strip()}
        if edit["index"] < len(items):
            items[edit["index"]] = entry
        else:
            items.append(entry)
        try:
            cleaned = web_pages.clean(items)
        except ValueError as err:
            edit["message"] = str(err)
            self.update()
            return
        self._web()["shortcuts"] = cleaned
        self._web_cancel()
        self._invoke("config.set_web_shortcuts", items=cleaned)

    def _web_delete(self, index):
        shortcuts = self._web()["shortcuts"]
        if index >= len(shortcuts):
            return
        kept = [s for i, s in enumerate(shortcuts) if i != index]
        self._web()["shortcuts"], self._web_del, self._web_edit = kept, None, None
        self._place_fields()
        self.scroll = int(min(self.scroll, self._limit()))
        self.update()
        self._invoke("config.set_web_shortcuts", items=kept)

    def _pick_browser(self, exe):
        web = self._web()
        web["chosen"], web["browser"] = exe, exe or web.get("default", "")
        self._browser_open = False
        self.update()
        self._invoke("config.set_default_browser", exe=exe)

    # ---------- ratón y teclado ----------

    @staticmethod
    def _button_rects(x_right, y):
        """Los botones de un ejecutable: (Sí, No, Ejecutar), a la derecha de su fila."""
        run = QRectF(x_right - 92, y + 15, 92, 28)
        no = QRectF(x_right - 48, y + 15, 48, 28)
        yes = QRectF(x_right - 48 - 6 - 54, y + 15, 54, 28)
        return yes, no, run

    def _reset_rects(self):
        """El botón "Restaurar" (o su confirmación Sí / No), arriba a la derecha del contenido."""
        right = self.width() - PAD
        if not self._reset_ask:
            return {"reset": QRectF(right - 96, 8, 96, 26)}
        return {"reset_yes": QRectF(right - 120, 8, 56, 26), "reset_no": QRectF(right - 60, 8, 56, 26)}

    def _row_buttons(self, y):
        """Los botones de una fila de atajo: Editar, o Guardar y Cancelar mientras se edita."""
        right = self.width() - PAD - 6
        return {"edit": QRectF(right - EDIT_W, y + 5, EDIT_W, 28), "cancel": QRectF(right - 86, y + 5, 86, 28),
                "save": QRectF(right - 86 - 6 - 80, y + 5, 80, 28)}

    def _hit(self, pos):
        """('area', i) | ('mode', clave) | ('run'|'yes'|'no', grupo, fila) | None."""
        for i, rect in enumerate(self._sidebar_rects()):
            if rect.contains(pos):
                return ("area", i)
        if pos.x() < self._content_x():
            return None
        if self.area == ATAJOS:
            for key, rect in self._kind_rects():
                if rect.contains(pos):
                    return ("kind", key)
        if self._filtering():
            for key, rect in self._mode_rects():
                if rect.contains(pos):
                    return ("mode", key)
            for name, rect in self._reset_rects().items():
                if rect.contains(pos):
                    return (name,)
        if self.area == ATAJOS and self.kind == "web" and pos.y() >= self._list_top():
            return self._hit_web(pos)
        if self.area == PREDETERMINADOS and pos.y() >= self._list_top():
            for kind, group, row, y in self._items():
                top = self._list_top() + y - self.scroll
                if kind == "row" and top <= pos.y() < top + self._row_height(row):
                    return ("browser_pick" if row.get("choice") else "browser_main", group, row)
        if self._filtering() and pos.y() >= self._list_top():
            for kind, group, row, y in self._items():
                top = self._list_top() + y - self.scroll
                if kind != "row" or not top <= pos.y() < top + ROW_H:
                    continue
                editing = self._editing is not None and self._editing["row"] is row
                buttons = self._row_buttons(top)
                for name in (("save", "cancel") if editing else ("edit",) if row["editable"] else ()):
                    if buttons[name].contains(pos) and (name != "save" or self._editing["ok"]):
                        return (name, group, row)
                return ("row", group, row)
        if self.area == FONDOS and pos.y() >= self._list_top():
            for kind, group, row, y in self._items():
                top = self._list_top() + y - self.scroll
                left = self._content_x() + self._cellx.get(id(row), 0)
                if kind == "cell" and QRectF(left, top, THUMB_W, THUMB_H).contains(pos):
                    return ("use", group, row)
        if self.area == RENDIMIENTO and pos.y() >= self._list_top():
            for kind, group, row, y in self._items():
                top = self._list_top() + y - self.scroll
                if kind == "row" and top <= pos.y() < top + self._row_h():
                    return ("toggle", group, row)
        if self.area == EJECUTABLES and pos.y() >= self._list_top():
            for kind, group, row, y in self._items():
                if kind != "row":
                    continue
                top = self._list_top() + y - self.scroll
                if not top <= pos.y() < top + EXEC_H:
                    continue
                yes, no, run = self._button_rects(self.width() - PAD - 6, top)
                pending = self._confirm == (group["title"], row["keys"])
                for name, rect, active in (("yes", yes, pending), ("no", no, pending), ("run", run, not pending)):
                    if active and rect.contains(pos):
                        return (name, group, row)
        return None

    def _web_buttons(self, top):
        """Los botones de una página web: Editar y Borrar (a la derecha de su fila)."""
        right = self.width() - PAD - 6
        return {"web_del": QRectF(right - 78, top + 5, 78, 28), "web_edit": QRectF(right - 78 - 6 - EDIT_W, top + 5, EDIT_W, 28)}

    def _hit_web(self, pos):
        """Atajos > Páginas web: ('web_edit'|'web_del'|'web_save'|'web_cancel'|'web_add'|'web_row', grupo, fila) | None."""
        for kind, group, row, y in self._items():
            top = self._list_top() + y - self.scroll
            if kind != "row" or not top <= pos.y() < top + self._row_height(row):
                continue
            if self._is_web_edit(row):
                buttons = self._row_buttons(top)
                for name, key in (("save", "web_save"), ("cancel", "web_cancel")):
                    if buttons[name].contains(pos):
                        return (key, group, row)
            elif row.get("add"):
                return ("web_add", group, row)
            else:
                for name, rect in self._web_buttons(top).items():
                    if rect.contains(pos):
                        return (name, group, row)
            return ("web_row", group, row)
        return None

    def mouseMoveEvent(self, event):
        hit = self._hit(event.position())
        if not hit:
            hover = None
        elif len(hit) == 1:
            hover = (hit[0], None, None)
        else:
            hover = (hit[0], hit[1] if hit[0] in ("area", "mode", "kind") else hit[1]["title"],
                     hit[2]["keys"] if len(hit) > 2 else None)
        if hover != self._hover:
            self._hover = hover
            self.update()
        self.setCursor(Qt.PointingHandCursor if hit and hit[0] not in ("row", "web_row") else Qt.ArrowCursor)

    def leaveEvent(self, _):
        self._hover = None
        self.update()

    def mouseReleaseEvent(self, event):
        hit = self._hit(event.position())
        if event.button() != Qt.LeftButton:
            return
        if not hit:
            if self._editing is not None or self._reset_ask or self._web_del is not None:
                self._editing, self._reset_ask, self._web_del = None, False, None
                self.update()
            return
        kind = hit[0]
        if kind not in ("edit", "save", "cancel", "row") and self._editing is not None:
            self._editing = None
        if self._web_del is not None and not (kind == "web_del" and hit[2]["index"] == self._web_del):
            self._web_del = None  # cualquier otra pulsación anula el "¿Borrar?"
            self.update()
        if kind == "kind":
            self._set_kind(hit[1])
        elif kind == "web_add" or kind == "web_edit":
            self._web_start(hit[2]["index"])
        elif kind == "web_save":
            self._web_save()
        elif kind == "web_cancel":
            self._web_cancel()
        elif kind == "web_del":
            if self._web_del == hit[2]["index"]:
                self._web_delete(hit[2]["index"])
            else:
                self._web_del = hit[2]["index"]
                self.update()
        elif kind == "web_row":
            pass
        elif kind == "browser_main":
            self._browser_open = not self._browser_open
            self.scroll = int(min(self.scroll, self._limit()))
            self.update()
        elif kind == "browser_pick":
            self._pick_browser(hit[2]["exe"])
        elif kind == "edit":
            self._start_edit(hit[1], hit[2])
        elif kind == "save":
            self._save_edit()
        elif kind == "cancel":
            self._editing = None
            self.update()
        elif kind == "use":
            self._sel = self._wall_rows().index(hit[2])
            self._use(hit[2])
            self.update()
        elif kind == "toggle":
            row = hit[2]
            row["value"] = not row["value"]
            self._invoke("config.set_option", key=row["option"], value=row["value"])
            self.update()
        elif kind in ("reset", "reset_no"):
            self._reset_ask = kind == "reset"
            self.update()
        elif kind == "reset_yes":
            self._reset_ask = False
            self._store(app_config.default_hotkeys(), "config.reset_hotkeys")
        elif kind == "area":
            self._set_area(hit[1])
        elif kind == "mode":
            self._set_mode(hit[1])
        elif kind == "run":
            self._confirm = (hit[1]["title"], hit[2]["keys"])
            self.update()
        elif kind == "no":
            self._confirm = None
            self.update()
        else:
            self._confirm = None
            self.close_requested.emit()
            self._invoke(hit[2]["action"], **hit[2].get("payload", {}))

    def focusNextPrevChild(self, forward):
        return False if self._editing is not None else super().focusNextPrevChild(forward)  # Tab también se puede pulsar

    @staticmethod
    def key_name(event):
        """El nombre (como en config.json) de la tecla pulsada, o None si no se puede usar en un atajo."""
        vk = event.nativeVirtualKey()
        if 0x30 <= vk <= 0x39 or 0x41 <= vk <= 0x5A:
            return chr(vk).lower()
        key = event.key()
        if Qt.Key_A <= key <= Qt.Key_Z or Qt.Key_0 <= key <= Qt.Key_9:
            return chr(key).lower()
        named = {Qt.Key_Left: "left", Qt.Key_Right: "right", Qt.Key_Up: "up", Qt.Key_Down: "down",
                 Qt.Key_Space: "space", Qt.Key_Return: "enter", Qt.Key_Enter: "enter", Qt.Key_Tab: "tab",
                 Qt.Key_Escape: "esc", Qt.Key_PageUp: "pageup", Qt.Key_PageDown: "pagedown",
                 Qt.Key_Backspace: "backspace", Qt.Key_Delete: "delete", Qt.Key_Minus: "minus"}
        if key in named:
            return named[key]
        if Qt.Key_F1 <= key <= Qt.Key_F12:
            return f"f{key - Qt.Key_F1 + 1}"
        return None

    @staticmethod
    def _held(modifiers):
        return [name for name, flag in (("ctrl", Qt.ControlModifier), ("shift", Qt.ShiftModifier), ("alt", Qt.AltModifier),
                                        ("win", Qt.MetaModifier)) if modifiers & flag]

    def _start_edit(self, group, row):
        self._editing = {"group": group, "row": row, "candidate": None, "message": "", "ok": False, "held": []}
        self.setFocus()
        self.update()

    def _fixed_tokens(self, row):
        """Las teclas de un grupo que no se tocan (←/→/↑/↓, 1/2/3, T/N…): lo que queda tras quitar los modificadores."""
        return [("fixed", text) for kind, text in key_tokens(row["keys"]) if kind == "cap" and text not in _MOD_NAMES.values()]

    def _try_group(self, mods):
        """En un grupo se escribe solo lo previo a la tecla (los modificadores): se valida con la primera tecla del grupo."""
        edit = self._editing
        hotkeys = self.data["hotkeys"]
        if not mods:
            edit.update(candidate=None, ok=False, message="Pulsa los modificadores nuevos (Ctrl, Mayús, Alt).")
            return
        first = edit["row"]["combos"][0].split("+")[-1]
        combo = normalize("+".join([*mods, first]))
        new, message = apply_edit(hotkeys, edit["row"]["combos"], combo, label=lambda c: label_of(hotkeys, c),
                                  is_free=is_free)
        edit.update(candidate=combo, ok=new is not None, message=message, new=new)

    def _capture(self, event):
        """Pulsa la combinación nueva: se valida al momento. Enter la guarda y Esc cancela (sin modificadores). En un grupo
        (las flechas, 1/2/3…) las teclas se quedan: solo se pulsan los modificadores nuevos."""
        edit, key = self._editing, event.key()
        mods = self._held(event.modifiers())
        group = len(edit["row"]["combos"]) > 1
        own = {Qt.Key_Control: "ctrl", Qt.Key_Shift: "shift", Qt.Key_Alt: "alt", Qt.Key_Meta: "win"}
        if key in (*own, Qt.Key_AltGr):
            if key in own and own[key] not in mods:  # según el sistema, la propia tecla pulsada no viene en los modificadores
                mods = [m for m in ("ctrl", "shift", "alt", "win") if m in (*mods, own[key])]
            edit["held"] = mods
            if group:
                self._try_group(mods)
            self.update()
            return
        if not mods and key == Qt.Key_Escape:
            self._editing = None
        elif not mods and key in (Qt.Key_Return, Qt.Key_Enter) and edit["ok"]:
            self._save_edit()
            return
        elif group:
            self._try_group(mods)  # la tecla que se pulse con ellos da igual: se conservan las del grupo
        else:
            name = self.key_name(event)
            if name is None:
                edit.update(candidate=None, ok=False, message="Esa tecla no se puede usar en un atajo.")
            else:
                combo = normalize("+".join([*mods, name]))
                hotkeys = self.data["hotkeys"]
                new, message = apply_edit(hotkeys, edit["row"]["combos"], combo, label=lambda c: label_of(hotkeys, c),
                                          is_free=is_free)
                edit.update(candidate=combo, ok=new is not None, message=message, new=new, held=[])
        self.update()

    def _save_edit(self):
        edit = self._editing
        if edit is None or not edit["ok"]:
            return
        self._editing = None
        self._store(edit["new"], "config.set_hotkeys")

    def _store(self, hotkeys, action):
        """Guarda los atajos nuevos: la página se refresca ya y Kyora los registra y los escribe en config.json."""
        self.data.update(config_data(hotkeys))  # solo los atajos: lo demás (fondos, ajustes, páginas) se conserva
        self.update()
        if action == "config.set_hotkeys":
            self._invoke(action, hotkeys=hotkeys)
        else:
            self._invoke(action)

    def keyPressEvent(self, event):
        key = event.key()
        if self._editing is not None:
            self._capture(event)
            return
        if key in (Qt.Key_Tab, Qt.Key_Backtab):
            self._set_area((self.area + 1) % len(AREAS))
        elif self.area == FONDOS and key in (Qt.Key_Left, Qt.Key_Right, Qt.Key_Up, Qt.Key_Down):
            step = {Qt.Key_Left: -1, Qt.Key_Right: 1, Qt.Key_Up: -self._cols(), Qt.Key_Down: self._cols()}[key]
            self._select(self._sel + step)
        elif self.area == FONDOS and key in (Qt.Key_Return, Qt.Key_Enter) and self._wall_rows():
            self._use(self._wall_rows()[min(self._sel, len(self._wall_rows()) - 1)])
            self.update()
        elif key in (Qt.Key_Up, Qt.Key_Down):
            self._scroll_by(60 if key == Qt.Key_Down else -60)
        elif key in (Qt.Key_PageUp, Qt.Key_PageDown):
            self._scroll_by(self._list_h() * (0.85 if key == Qt.Key_PageDown else -0.85))
        elif key == Qt.Key_Escape:
            if self.filter.text():
                self.filter.clear()
            elif self._web_edit is not None:
                self._web_cancel()
            else:
                self.close_requested.emit()
        else:
            super().keyPressEvent(event)

    # ---------- pintura ----------

    def paintEvent(self, _):
        t = self.theme
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        self._paint_sidebar(p)
        p.setFont(font(t, bold=True))
        p.setPen(QColor(t.ink))
        name, info, _glyph = AREAS[self.area]
        if self.area == ATAJOS and self.kind == "web":
            info = "Escribe el nombre de una página en el buscador y se abre en tu navegador."
        p.drawText(QRectF(self._content_x(), 6, self._content_w(), 24), Qt.AlignVCenter, name)
        p.setFont(font(t))
        p.setPen(QColor(t.dim))
        p.drawText(QRectF(self._content_x(), 30, self._content_w(), 22), Qt.AlignVCenter,
                   QFontMetrics(font(t)).elidedText(info, Qt.ElideRight, int(self._content_w())))
        if self.area == ATAJOS:
            self._paint_kinds(p)
        if self._filtering():
            self._paint_modes(p)
            self._paint_reset(p)
        top, height = self._list_top(), self._list_h()
        p.save()
        p.setClipRect(QRectF(self._content_x() - 2, top, self._content_w() + 4, height))
        items = self._items()
        self.scroll = min(self.scroll, self._limit())
        for kind, group, row, y in items:
            ry = top + y - self.scroll
            if ry + (HEAD_H if kind == "head" else self._row_height(row) if kind == "row" else self._row_h()) < top \
                    or ry > top + height:
                continue
            if kind == "cell":
                self._paint_cell(p, row, QRectF(self._content_x() + self._cellx[id(row)], ry, THUMB_W, THUMB_H))
            elif kind == "head":
                self._paint_head(p, group, ry, first=y == 0)
            elif self.area == ATAJOS and self.kind == "web":
                self._paint_web(p, group, row, QRectF(self._content_x(), ry, self._content_w(), self._row_height(row)))
            elif self.area == ATAJOS:
                self._paint_shortcut(p, group, row, QRectF(self._content_x(), ry, self._content_w(), ROW_H))
            elif self.area == EJECUTABLES:
                self._paint_executable(p, group, row, ry)
            elif self.area == PREDETERMINADOS:
                self._paint_default(p, group, row, ry)
            else:
                self._paint_option(p, group, row, ry)
        if not items:
            p.setFont(font(t))
            p.setPen(QColor(t.dim))
            p.drawText(QRectF(self._content_x(), top + 20, self._content_w(), 40), Qt.AlignCenter,
                       "Ningún atajo coincide con lo que escribiste" if self.filter.text() and self.area == ATAJOS
                       else "Pon imágenes en la carpeta Imágenes\\wallpapers y vuelve a abrir esta página"
                       if self.area == FONDOS else "Nada que enseñar")
        self._paint_edges(p, top, height)
        p.restore()
        self._place_fields()  # los campos de la página web que se escribe siguen a su fila al desplazar

    def _paint_edges(self, p, top, height):
        """El oscurecimiento de los bordes de la lista: solo al desplazar, y solo donde hay más contenido."""
        if self._edge <= 0.01:
            return
        color = QColor(backdrop.PANEL_GRAY)
        x, w = self._content_x() - 2, self._content_w() + 4
        for at_top, shown in ((True, self.scroll > 0), (False, self.scroll < self._limit())):
            if not shown:
                continue
            y = top if at_top else top + height - EDGE_H
            fade = QLinearGradient(0, y, 0, y + EDGE_H)
            near, far = (0, 1) if at_top else (1, 0)  # el extremo pegado al borde es el más oscuro
            solid, clear = QColor(color), QColor(color)
            solid.setAlpha(round(EDGE_ALPHA * self._edge))
            clear.setAlpha(0)
            fade.setColorAt(near, solid)
            fade.setColorAt(far, clear)
            p.fillRect(QRectF(x, y, w, EDGE_H), fade)

    def _paint_sidebar(self, p):
        t = self.theme
        p.setPen(Qt.NoPen)
        p.setBrush(QColor(0, 0, 0, 46))
        p.drawRoundedRect(QRectF(0, 0, SIDEBAR_W, self.height()), 16, 16)
        p.setFont(font(t, bold=True))
        p.setPen(QColor(t.dim))
        p.drawText(QRectF(18, 14, SIDEBAR_W - 30, 26), Qt.AlignVCenter, "Configuración")
        for i, rect in enumerate(self._sidebar_rects()):
            on = i == self.area
            hover = self._hover == ("area", i, None)
            if on or hover:
                p.setPen(Qt.NoPen)
                p.setBrush(QColor(t.gold_soft) if on else QColor(255, 255, 255, 14))
                p.drawRoundedRect(rect, 12, 12)
            color = accent(t, on) if on else QColor(t.ink if hover else t.dim)
            p.setPen(glyphs.pen(color, 1.5))
            p.setBrush(Qt.NoBrush)
            AREAS[i][2](p, QRectF(rect.left() + 12, rect.center().y() - 9, 18, 18))
            p.setFont(font(t, bold=on))
            p.setPen(color)
            counted = i != PREDETERMINADOS  # Predeterminados no lleva contador: su nombre es el más largo
            p.drawText(QRectF(rect.left() + 40, rect.top(), rect.width() - (80 if counted else 46), rect.height()),
                       Qt.AlignVCenter, AREAS[i][0])
            if counted:
                p.setFont(font(t))
                p.setPen(QColor(t.dim))
                p.drawText(QRectF(rect.right() - 40, rect.top(), 30, rect.height()), Qt.AlignVCenter | Qt.AlignRight,
                           str(self._count(i)))

    def _paint_modes(self, p):
        t = self.theme
        for key, rect in self._mode_rects():
            on = key == self.mode
            p.setPen(QPen(QColor(255, 255, 255, 42 if on else 22), 1))
            p.setBrush(QColor(255, 255, 255, 26) if on else Qt.NoBrush)
            p.drawRoundedRect(rect, rect.height() / 2, rect.height() / 2)
            p.setFont(font(t, bold=on))
            p.setPen(QColor(t.ink) if on else QColor(t.dim))
            p.drawText(rect, Qt.AlignCenter, dict(MODES)[key])

    def _paint_kinds(self, p):
        """Teclas | Páginas web: los dos tipos de comando de Atajos, junto al título."""
        t = self.theme
        for key, rect in self._kind_rects():
            on = key == self.kind
            hover = self._hover == ("kind", key, None)
            p.setPen(QPen(QColor(t.gold) if on else QColor(255, 255, 255, 34 if hover else 22), 1))
            p.setBrush(QColor(t.gold_soft) if on else QColor(255, 255, 255, 14) if hover else Qt.NoBrush)
            p.drawRoundedRect(rect, rect.height() / 2, rect.height() / 2)
            p.setFont(font(t, bold=on))
            p.setPen(accent(t, True) if on else QColor(t.ink if hover else t.dim))
            p.drawText(rect, Qt.AlignCenter, dict(KINDS)[key])

    def _pill(self, p, rect, label, strong=False, hover=False, warn=False):
        t = self.theme
        color = QColor(t.warn) if warn else QColor(t.gold)
        p.setPen(QPen(color if strong else QColor(255, 255, 255, 40), 1))
        p.setBrush(QColor(t.gold_soft) if strong else QColor(255, 255, 255, 24 if hover else 12))
        p.drawRoundedRect(rect, rect.height() / 2, rect.height() / 2)
        p.setFont(font(t, bold=True))
        p.setPen(accent(t, True) if strong else QColor(t.ink if hover else t.dim))
        p.drawText(rect, Qt.AlignCenter, label)

    def _paint_reset(self, p):
        """"Restaurar" los atajos de fábrica, con confirmación ahí mismo."""
        if self._reset_ask:
            p.setFont(font(self.theme))
            p.setPen(QColor(self.theme.warn))
            p.drawText(QRectF(self.width() - PAD - 340, 8, 212, 26), Qt.AlignVCenter | Qt.AlignRight, "¿Volver a los atajos de fábrica?")
        for name, rect in self._reset_rects().items():
            label = {"reset": "Restaurar", "reset_yes": "Sí", "reset_no": "No"}[name]
            self._pill(p, rect, label, strong=name == "reset_yes", hover=self._hover == (name, None, None))

    def _paint_head(self, p, group, y, first):
        """El título de una sección, con su explicación debajo y una línea fina que la separa de la anterior."""
        t = self.theme
        x, w = self._content_x(), self._content_w()
        if not first:
            p.setPen(QPen(QColor(255, 255, 255, 18), 1))
            p.drawLine(x, int(y - 4), int(x + w), int(y - 4))
        p.setFont(font(t, bold=True))
        p.setPen(QColor(t.ink))
        p.drawText(QRectF(x, y + 8, w - 50, 22), Qt.AlignVCenter, group["title"])
        p.setFont(font(t))
        p.setPen(QColor(t.dim))
        count = group.get("count", len(group["rows"]))
        if count is not None:
            p.drawText(QRectF(x, y + 8, w, 22), Qt.AlignVCenter | Qt.AlignRight, str(count))
        p.drawText(QRectF(x, y + 30, w, 20), Qt.AlignVCenter,
                   QFontMetrics(font(t)).elidedText(group["info"], Qt.ElideRight, int(w)))

    def _paint_caps(self, p, tokens, x, y, limit):
        """Dibuja unas teclas desde x; devuelve dónde acaba."""
        t = self.theme
        metrics = QFontMetrics(font(t, bold=True))
        for kind, text in tokens:
            if kind in ("cap", "fixed"):
                width = max(metrics.horizontalAdvance(text) + 16, CAP_H + 4)
                if x + width > limit:
                    break  # no cabe: se corta antes de pisar la explicación
                cap = QRectF(x, y, width, CAP_H)
                p.setPen(QPen(QColor(255, 255, 255, 46), 1))
                p.setBrush(QColor(255, 255, 255, 18))
                p.drawRoundedRect(cap, 6, 6)
                p.setPen(QPen(QColor(0, 0, 0, 90), 2))  # el borde de abajo, más oscuro: se ve la tecla elevada
                p.drawLine(int(cap.left() + 5), int(cap.bottom() + 1), int(cap.right() - 5), int(cap.bottom() + 1))
                p.setFont(font(t, bold=True))
                p.setPen(QColor(t.dim) if kind == "fixed" else accent(t, True))  # las que no se tocan, atenuadas
                p.drawText(cap, Qt.AlignCenter, text)
                x += width + 5
            else:
                p.setFont(font(t))
                p.setPen(QColor(t.dim))
                width = QFontMetrics(font(t)).horizontalAdvance(text) + 6
                if x + width > limit:
                    break
                p.drawText(QRectF(x + 2, y, width, CAP_H), Qt.AlignCenter, text)
                x += width + 4
        return x

    def _paint_shortcut(self, p, group, row, box):
        """Las teclas dibujadas como teclas a la izquierda y, a la derecha, lo que hacen (o la edición en curso)."""
        t = self.theme
        y = box.top() + (box.height() - CAP_H) / 2
        left = box.left() + KEYS_W + 12
        buttons = self._row_buttons(box.top())
        if self._editing is not None and self._editing["row"] is row:
            self._paint_editing(p, row, box, y, buttons)
            return
        hovered = self._hover is not None and self._hover[0] in ("row", "edit") and self._hover[1:] == (group["title"], row["keys"])
        self._paint_caps(p, key_tokens(row["keys"]), box.left() + 2, y, box.left() + KEYS_W)
        right = box.right() - (EDIT_W + 10 if row["editable"] else 0)
        p.setFont(font(t))
        p.setPen(QColor(t.dim))
        p.drawText(QRectF(left, box.top(), right - left, box.height()), Qt.AlignVCenter,
                   QFontMetrics(font(t)).elidedText(row["text"], Qt.ElideRight, int(right - left)))
        if row["editable"] and hovered:
            self._pill(p, buttons["edit"], "Editar", hover=self._hover[0] == "edit")

    def _paint_editing(self, p, row, box, y, buttons):
        """La fila mientras se cambia: la combinación que se pulsa (o la pista), el aviso y Guardar / Cancelar."""
        t = self.theme
        edit = self._editing
        left = box.left() + KEYS_W + 12
        group = len(row["combos"]) > 1
        if group and (edit["candidate"] or edit["held"]):  # los modificadores que se pulsan + las teclas que se quedan
            mods = split(edit["candidate"])[0] if edit["candidate"] else edit["held"]
            tokens = [("cap", _MOD_NAMES[m]) for m in mods] + self._fixed_tokens(row)
            self._paint_caps(p, tokens, box.left() + 2, y, box.left() + KEYS_W)
        elif edit["candidate"]:
            self._paint_caps(p, _pretty(edit["candidate"]), box.left() + 2, y, box.left() + KEYS_W)
        elif edit["held"]:
            self._paint_caps(p, [("cap", _MOD_NAMES[m]) for m in edit["held"]], box.left() + 2, y, box.left() + KEYS_W)
        else:
            p.setFont(font(t, bold=True))
            p.setPen(accent(t, True))
            hint = "Pulsa solo los modificadores (Ctrl, Mayús, Alt)…" if group else "Pulsa la combinación nueva…"
            p.drawText(QRectF(box.left() + 2, box.top(), KEYS_W, box.height()), Qt.AlignVCenter, hint)
        message = edit["message"] or ("Enter guarda · Esc cancela" if edit["ok"] else
                                      "Las teclas se quedan; cambia lo previo." if group else "")
        p.setFont(font(t))
        p.setPen(QColor(t.warn) if edit["message"] else QColor(t.dim))
        right = buttons["save"].left() - 8
        p.drawText(QRectF(left, box.top(), right - left, box.height()), Qt.AlignVCenter,
                   QFontMetrics(font(t)).elidedText(message, Qt.ElideRight, int(right - left)))
        self._pill(p, buttons["save"], "Guardar", strong=edit["ok"], hover=self._hover and self._hover[0] == "save")
        self._pill(p, buttons["cancel"], "Cancelar", hover=self._hover and self._hover[0] == "cancel")

    def _paint_web(self, p, group, row, box):
        """Una página web: el icono del navegador, su nombre (lo que se escribe en el buscador) y su dirección; al pasar el
        cursor, Editar y Borrar (dos pulsaciones). La última fila es "Añadir página"."""
        t = self.theme
        if self._is_web_edit(row):
            self._paint_web_editing(p, box)
            return
        hover = self._hover[0] if self._hover is not None and self._hover[1:] == (group["title"], row["keys"]) else ""
        if row.get("add"):
            self._pill(p, QRectF(box.left(), box.top() + 5, 150, 28), "+ Añadir página", hover=hover == "web_add")
            return
        icon = app_icon(self._web()["browser"], 0, 20, self.devicePixelRatioF())
        p.drawPixmap(int(box.left() + 2), int(box.top() + (ROW_H - 20) / 2), icon)
        armed = self._web_del == row["index"]
        buttons = self._web_buttons(box.top())
        right = (buttons["web_edit"].left() - 10) if hover.startswith("web_") or armed else box.right()
        name_x = box.left() + 32
        p.setFont(font(t, bold=True))
        p.setPen(accent(t, True))
        name = QFontMetrics(font(t, bold=True)).elidedText(row["keys"], Qt.ElideRight, WEB_NAME_W + 20)
        p.drawText(QRectF(name_x, box.top(), WEB_NAME_W + 20, ROW_H), Qt.AlignVCenter, name)
        url_x = name_x + WEB_NAME_W + 30
        p.setFont(font(t))
        p.setPen(QColor(t.dim))
        p.drawText(QRectF(url_x, box.top(), max(right - url_x, 0), ROW_H), Qt.AlignVCenter,
                   QFontMetrics(font(t)).elidedText(row["text"], Qt.ElideRight, int(max(right - url_x, 0))))
        if hover.startswith("web_") or armed:
            self._pill(p, buttons["web_edit"], "Editar", hover=hover == "web_edit")
            self._pill(p, buttons["web_del"], "¿Borrar?" if armed else "Borrar", strong=armed, warn=armed,
                       hover=hover == "web_del")

    def _paint_web_editing(self, p, box):
        """La página que se escribe: los campos (nombre y dirección) van encima; aquí, Guardar, Cancelar y el aviso."""
        t = self.theme
        edit = self._web_edit
        buttons = self._row_buttons(box.top())
        self._pill(p, buttons["save"], "Guardar", strong=True, hover=self._hover is not None and self._hover[0] == "web_save")
        self._pill(p, buttons["cancel"], "Cancelar", hover=self._hover is not None and self._hover[0] == "web_cancel")
        p.setFont(font(t))
        p.setPen(QColor(t.warn) if edit["message"] else QColor(t.dim))
        message = edit["message"] or "Enter guarda · Esc cancela · el nombre es lo que escribes en el buscador"
        p.drawText(QRectF(box.left() + 4, box.top() + ROW_H, box.width() - 4, WEB_MSG_H), Qt.AlignVCenter,
                   QFontMetrics(font(t)).elidedText(message, Qt.ElideRight, int(box.width() - 4)))

    def _paint_default(self, p, group, row, y):
        """Predeterminados > Navegador: el elegido (con su icono) y, al pulsar, la lista de los instalados."""
        t = self.theme
        web = self._web()
        left = self._content_x() + 2
        hover = self._hover == ("browser_main" if row.get("main") else "browser_pick", group["title"], row["keys"])
        dpr = self.devicePixelRatioF()
        if row.get("main"):
            right = self.width() - PAD - 6
            pill = QRectF(right - 92, y + 15, 92, 28)
            p.drawPixmap(int(left), int(y + 15), app_icon(web["browser"], 0, 28, dpr))
            p.setFont(font(t, bold=True))
            p.setPen(accent(t, True))
            p.drawText(QRectF(left + 40, y + 7, pill.left() - left - 54, 22), Qt.AlignVCenter, row["keys"])
            p.setFont(font(t))
            p.setPen(QColor(t.dim))
            p.drawText(QRectF(left + 40, y + 29, pill.left() - left - 54, 22), Qt.AlignVCenter,
                       QFontMetrics(font(t)).elidedText(row["text"], Qt.ElideRight, int(pill.left() - left - 54)))
            self._pill(p, pill, "Cerrar" if self._browser_open else "Cambiar", hover=hover)
            return
        box = QRectF(left + 38, y + 2, self.width() - PAD - 6 - left - 38, CHOICE_H - 4)
        if hover or row["on"]:
            p.setPen(Qt.NoPen)
            p.setBrush(QColor(255, 255, 255, 18 if hover else 10))
            p.drawRoundedRect(box, 9, 9)
        icon = app_icon(row["exe"] or web.get("default", ""), 0, 20, dpr)
        p.drawPixmap(int(box.left() + 10), int(box.center().y() - 10), icon)
        text_x = box.left() + 40
        p.setFont(font(t, bold=row["on"]))
        p.setPen(accent(t, True) if row["on"] else QColor(t.ink))
        name_w = QFontMetrics(font(t, bold=True)).horizontalAdvance(row["keys"]) + 12
        p.drawText(QRectF(text_x, box.top(), name_w, box.height()), Qt.AlignVCenter, row["keys"])
        p.setFont(font(t))
        p.setPen(QColor(t.dim))
        room = box.right() - 34 - (text_x + name_w)
        if room > 40:
            p.drawText(QRectF(text_x + name_w, box.top(), room, box.height()), Qt.AlignVCenter,
                       QFontMetrics(font(t)).elidedText(row["text"], Qt.ElideMiddle, int(room)))
        if row["on"]:  # la marca de lo elegido
            p.setPen(glyphs.pen(accent(t, True), 1.8))
            c = box.right() - 20
            mid = box.center().y()
            p.drawLine(QPointF(c - 6, mid), QPointF(c - 2, mid + 4))
            p.drawLine(QPointF(c - 2, mid + 4), QPointF(c + 6, mid - 5))

    def _paint_cell(self, p, row, rect):
        """La miniatura de un fondo: se lee la primera vez que se ve. Borde de énfasis en el elegido con las flechas, la
        etiqueta "En uso" en el que está puesto y, en el elegido, su nombre abajo."""
        t = self.theme
        path = row["payload"]["path"]
        shape = QPainterPath()
        shape.addRoundedRect(rect, 10, 10)
        pixmap = self._thumbs.get(path)
        if pixmap is None:
            self._loader.request(path)
        else:
            self._thumbs.move_to_end(path)  # la más reciente: la última en salir de la caché
        p.save()
        p.setClipPath(shape)
        if pixmap is not None:
            p.drawPixmap(rect.toRect(), pixmap)
        else:
            p.fillRect(rect, QColor(255, 255, 255, 12))
        chosen = self._wall_rows().index(row) == self._sel
        if chosen:
            veil = QLinearGradient(rect.left(), rect.bottom() - 30, rect.left(), rect.bottom())
            veil.setColorAt(0, QColor(0, 0, 0, 0))
            veil.setColorAt(1, QColor(0, 0, 0, 190))
            p.fillRect(QRectF(rect.left(), rect.bottom() - 30, rect.width(), 30), veil)
            p.setFont(font(t))
            p.setPen(QColor(255, 255, 255, 235))
            room = rect.width() - 16 - (len(self._swatches.get(path, ())) * (SWATCH + 4) + 4)
            p.drawText(rect.adjusted(8, 0, -8, -5), Qt.AlignBottom | Qt.AlignLeft,
                       QFontMetrics(font(t)).elidedText(row["keys"], Qt.ElideRight, int(max(room, 20))))
        p.restore()
        self._paint_swatches(p, rect, self._swatches.get(path, ()))
        hover = self._hover == ("use", "wallpapers", row["keys"]) or self._hover and self._hover[0] == "use" \
            and self._hover[2] == row["keys"]
        p.setPen(QPen(QColor(t.gold) if chosen else QColor(255, 255, 255, 70 if hover else 28), 2 if chosen else 1))
        p.setBrush(Qt.NoBrush)
        p.drawRoundedRect(rect.adjusted(1, 1, -1, -1), 10, 10)
        if row["current"]:
            tag = QRectF(rect.left() + 6, rect.top() + 6, 54, 20)
            p.setPen(Qt.NoPen)
            p.setBrush(QColor(t.gold))
            p.drawRoundedRect(tag, 10, 10)
            p.setFont(font(t, bold=True))
            p.setPen(QColor(t.pick_ink))
            p.drawText(tag, Qt.AlignCenter, "En uso")

    def _paint_swatches(self, p, rect, colors):
        """Los colores que más se repiten del fondo, como puntos abajo a la derecha de su miniatura (del que más al que
        menos, de izquierda a derecha)."""
        if not colors:
            return
        p.save()
        p.setRenderHint(QPainter.Antialiasing)
        x = rect.right() - 6 - len(colors) * (SWATCH + 4) + 4
        y = rect.bottom() - 6 - SWATCH
        for color in colors:
            dot = QRectF(x, y, SWATCH, SWATCH)
            p.setPen(QPen(QColor(0, 0, 0, 150), 1))
            p.setBrush(QColor(color))
            p.drawEllipse(dot)
            p.setPen(QPen(QColor(255, 255, 255, 90), 1))
            p.setBrush(Qt.NoBrush)
            p.drawEllipse(dot.adjusted(1, 1, -1, -1))
            x += SWATCH + 4
        p.restore()

    def _paint_option(self, p, group, row, y):
        """Un ajuste de rendimiento: su nombre, qué hace y un interruptor."""
        t = self.theme
        left = self._content_x() + 2
        switch = QRectF(self.width() - PAD - 6 - 48, y + 14, 48, 26)
        hover = self._hover == ("toggle", group["title"], row["keys"])
        text_w = switch.left() - left - 14
        p.setFont(font(t, bold=True))
        p.setPen(accent(t, True) if row["value"] else QColor(t.ink))
        p.drawText(QRectF(left, y + 7, text_w, 22), Qt.AlignVCenter, row["keys"])
        p.setFont(font(t))
        p.setPen(QColor(t.dim))
        p.drawText(QRectF(left, y + 29, text_w, 22), Qt.AlignVCenter,
                   QFontMetrics(font(t)).elidedText(row["text"], Qt.ElideRight, int(text_w)))
        p.setPen(QPen(QColor(t.gold) if row["value"] else QColor(255, 255, 255, 44), 1))
        p.setBrush(QColor(t.gold_soft) if row["value"] else QColor(255, 255, 255, 22 if hover else 12))
        p.drawRoundedRect(switch, 13, 13)
        knob = switch.adjusted(3, 3, -3, -3)
        knob.setWidth(knob.height())
        if row["value"]:
            knob.moveRight(switch.right() - 3)
        p.setPen(Qt.NoPen)
        p.setBrush(accent(t, True) if row["value"] else QColor(t.dim))
        p.drawEllipse(knob)

    def _paint_executable(self, p, group, row, y):
        t = self.theme
        left = self._content_x() + 2
        x_right = self.width() - PAD - 6
        yes, no, run = self._button_rects(x_right, y)
        pending = self._confirm == (group["title"], row["keys"])
        text_w = (yes.left() if pending else run.left()) - left - 14
        p.setFont(font(t, bold=True))
        p.setPen(accent(t, True))
        p.drawText(QRectF(left, y + 7, text_w, 22), Qt.AlignVCenter,
                   QFontMetrics(font(t, bold=True)).elidedText(row["keys"], Qt.ElideRight, int(text_w)))
        p.setFont(font(t))
        p.setPen(QColor(t.warn) if pending else QColor(t.dim))
        text = "¿Seguro? Esto puede cerrar o reiniciar Kyora." if pending else row["text"]
        p.drawText(QRectF(left, y + 29, text_w, 22), Qt.AlignVCenter,
                   QFontMetrics(font(t)).elidedText(text, Qt.ElideRight, int(text_w)))
        buttons = (("yes", yes, "Sí", True), ("no", no, "No", False)) if pending else (("run", run, "Ejecutar", False),)
        for name, rect, label, strong in buttons:
            hover = self._hover == (name, group["title"], row["keys"])
            p.setPen(QPen(QColor(t.gold) if strong else QColor(255, 255, 255, 40), 1))
            p.setBrush(QColor(t.gold_soft) if strong else QColor(255, 255, 255, 24 if hover else 12))
            p.drawRoundedRect(rect, rect.height() / 2, rect.height() / 2)
            p.setFont(font(t, bold=True))
            p.setPen(accent(t, True) if strong else QColor(t.ink))
            p.drawText(rect, Qt.AlignCenter, label)


_MOD_NAMES = {"ctrl": "Ctrl", "shift": "Shift", "alt": "Alt", "win": "Win"}
_KEY_NAMES = {"left": "←", "right": "→", "up": "↑", "down": "↓", "space": "Espacio", "esc": "Esc", "enter": "Enter",
              "tab": "Tab", "pageup": "RePág", "pagedown": "AvPág", "backspace": "Retroceso", "delete": "Supr",
              "minus": "-"}


def _pretty(combo):
    """'ctrl+alt+pageup' -> [('cap', 'Ctrl'), ('cap', 'Alt'), ('cap', 'RePág')]."""
    return [("cap", _MOD_NAMES.get(part, _KEY_NAMES.get(part, part.upper()))) for part in combo.split("+")]
