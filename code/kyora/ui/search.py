"""El buscador (Win): sale del borde de arriba de la pantalla, en el mismo sitio y con la misma forma que el panel
superior, con el campo para escribir arriba y las opciones bajando debajo.

Es una ventana transparente de tamaño fijo, pegada al borde superior de la pantalla. Lo que se anima es la forma
que se pinta dentro: crece hacia abajo al abrirse y vuelve a crecer a medida que aparecen resultados. Nunca cambia de
tamaño una ventana, así que el movimiento es fluido y nada se desenfoca.

Sin prefijo busca ventanas, apps, carpetas y archivos. Prefijos que acotan la búsqueda: "<" solo aplicaciones,
"/" solo carpetas y "@" solo archivos. Además:
- Las tareas (Ctrl+Shift+T) abren directo el tablero Kanban, más ancho; el campo de arriba solo sirve para escribir una
  tarea nueva (Enter la crea) y, si está vacío, las flechas recorren el tablero. Al abrir una tarea el campo se va y el
  detalle ocupa su sitio (subtareas a la izquierda, descripción a la derecha); Esc vuelve al tablero. Las notas
  (Ctrl+Shift+N) también van aquí, más anchas. Sin ventanas aparte ni diálogos (borrar es pulsar dos veces).
- "/texto" busca carpetas y "@texto" solo archivos, en todo tu usuario y tus unidades. Enter en una carpeta la abre
  como árbol; Ctrl+Enter, en el Explorador de Windows.
- En el carrusel de ">wallpaper", ←/→ prueban el fondo (y los colores de Kyora), Enter lo deja y Esc vuelve al que
  había.
"""
import logging
import math
import os
import time

from PySide6.QtCore import QEasingCurve, QEvent, QRectF, Qt, QTimer
from PySide6.QtGui import QColor, QPainter
from PySide6.QtWidgets import QApplication, QGraphicsOpacityEffect, QLayout, QLineEdit, QWidget

from kyora.core.animation import lerp
from kyora.system.win32 import force_foreground
from kyora.ui.anim import Tween
from kyora.ui.bar import font
from kyora.search.folders import human_size
from kyora.ui.chat import ChatBoard, modal_open
from kyora.ui.explorer.preview import PreviewPane, kind_of
from kyora.ui.explorer.style import stylesheet
from kyora.ui.kanban import KanbanBoard
from kyora.ui.notes import NotesBoard
from kyora.ui.relief import frame_gradient, paint_soft_shadow
from kyora.ui.search_list import MAX_H as LIST_H
from kyora.ui.search_list import ResultList
from kyora.ui.search_tree import MAX_H as TREE_H
from kyora.ui.search_tree import TreeList
from kyora.ui.sectionbar import ROW_H, StatusRow
from kyora.ui.shapes import hanging_paths
from kyora.ui.task_detail import TaskDetail
from kyora.ui.wallpapers import HEIGHT as CAROUSEL_H
from kyora.ui.wallpapers import WallpaperCarousel
from kyora.ui.win import hwnd_of, make_tool_window

log = logging.getLogger("kyora.ui")

INPUT_H = 30
PLACEHOLDERS = {"": "Buscar  ·  < apps  ·  / carpetas  ·  @ archivos", "task": "Escribe aquí para crear una tarea nueva y pulsa Enter",
                "notes": "Notas", "chat": "Chat"}
GAP = 6  # entre el campo y la lista de opciones
PILL_BAND = ROW_H + GAP  # lo que ocupa arriba la píldora de secciones
SECTION_OF = {"list": "search", "tree": "search", "wallpapers": "search", "kanban": "task", "task": "task",
              "notes": "notes", "chat": "chat"}  # qué sección de la píldora está abierta según lo que se ve
QUERY_DELAY_MS = 30
BLUR_CHECK_MS = 200
LIST_MS = 170  # lo que tarda la lista en crecer o encogerse cuando cambian los resultados
SLOW_QUERY_MS = 50  # una búsqueda más lenta que esto se anota en kyora.log
WIDE = 1000  # ancho del buscador en el Kanban y en las notas
WIDE_MS = 220  # lo que tarda en ensancharse o volver
BOARD_H = 560  # alto del Kanban y de las notas
TASK_H = 470  # alto del detalle de una tarea
TASK_W = 940  # y su ancho: subtareas a la izquierda, descripción a la derecha
WIDE_MODES = ("kanban", "notes")
CHAT_W = 700  # el chat es más estrecho que el Kanban: una columna de burbujas
CHAT_SIDE_W = 316  # lo que se suma al ancho cuando el chat abre a la derecha su árbol de archivos
PV_SHARE = 0.42  # con la vista previa abierta, la lista ocupa esta parte del ancho y la vista previa el resto
PV_GAP = 10
PV_H = 340  # alto mínimo de la vista previa (un PDF o una imagen necesitan sitio)
PV_OPEN_DELAY = 0.7  # segundos tras previsualizar en los que otro clic en el mismo archivo aún no lo abre
PV_FOCUS_GRACE = 1.5  # segundos tras previsualizar en los que perder el foco no cierra el buscador (lo recupera)


class SearchPopout(QWidget):
    def __init__(self, theme, screen_map, query, launch, close, set_wallpaper=lambda path: None,
                 children=lambda path: [], act=lambda kind, id: None, call=None, roots=lambda: ([], ())):
        """`query(texto)` devuelve {results, indexing} (o un modo: "tree", "tasks", "notes", "wallpapers");
        `launch(resultado, ctrl)` lo abre; `close(refocus)` pide cerrar; `set_wallpaper(ruta)` pone un fondo (el
        carrusel); `children(ruta)` da lo que hay en una carpeta (el árbol); `act(tipo, id)` hace algo al momento sin
        cerrar el buscador (crear, terminar o borrar una tarea) y devuelve {ok, data}; `call(acción, **datos)` es el
        núcleo, para el detalle de la tarea, el Kanban y las notas."""
        super().__init__()
        make_tool_window(self)
        self.setWindowTitle("KyoraSearch")
        self.theme = theme
        self._query, self._launch, self._close, self._set_wallpaper = query, launch, close, set_wallpaper
        self._act = act
        self._wall_original = None  # el fondo que había al abrir el carrusel (Esc vuelve a él)
        self._wall_applied = None  # el último que se puso desde el carrusel
        self._mode_word = ""  # cómo se abrió: "", "task" (Ctrl+Shift+T) o "notes" (Ctrl+Shift+N)
        self.mode = "list"  # qué se ve encima del campo: list, tree, task, kanban, notes o wallpapers
        self._bandf = 1.0  # 1 = el campo se ve encima del contenido; 0 = el detalle de una tarea lo ha reemplazado
        self._armed = None  # la opción de ">config" que espera el segundo Enter
        self.opened = False
        self._progress = 0.0  # 0 = escondido en el marco, 1 = abierto
        self._list_h = 0.0  # alto actual de la lista de opciones (crece y encoge)
        self._pv_path = None  # el archivo que se está previsualizando a la derecha (clic otra vez = abrirlo)
        self._pv_at = 0.0  # cuándo se empezó a previsualizar

        t = theme
        shadow = math.ceil(t.dock_shadow_size) + 4
        self._margin = shadow + t.dock_tab
        self._pad = t.search_padding
        self._max_list = LIST_H
        body_max = 2 * self._pad + PILL_BAND + INPUT_H + GAP + max(self._max_list, CAROUSEL_H, TREE_H, BOARD_H, TASK_H)
        g = screen_map.geometry
        self._wide = max(min(WIDE, g.width() - 2 * self._margin - 40), t.search_width)  # nunca más que la pantalla
        self._width = self._width_to = float(t.search_width)  # ancho de la pieza (más en el Kanban y en ">notes")
        width = self._wide + 2 * self._margin  # la ventana ya es de las anchas: lo que se anima es lo pintado
        height = body_max + shadow  # sitio para la sombra de abajo
        self._screen_height = g.height()
        self.setGeometry(round(g.x() + (g.width() - width) / 2), g.y(), width, height)  # cuelga del borde de arriba
        self.on_section = lambda name: None  # lo pone la interfaz: abre la sección que se pulsó en la píldora
        self.pill = StatusRow(t)  # las secciones de arriba: no desaparece al entrar en una (la abierta se destaca)
        self.pill.setParent(self)
        self.pill.run.connect(self._section)
        self.pill.resized.connect(self._place_pill)
        self.pill.go.connect(lambda _: self._section("music"))
        self.pill.hide()
        self.edit = QLineEdit(self)
        self.edit.setPlaceholderText(PLACEHOLDERS[""])
        self.edit.setFont(font(t, 13))
        self.retheme(t)
        self.edit.installEventFilter(self)
        self.list = ResultList(t, self._launch_result, on_pick=self._pick)
        self.list.setParent(self)
        self.carousel = WallpaperCarousel(t)
        self.carousel.setParent(self)
        self.carousel.picked.connect(self._try_wallpaper)
        self.carousel.hide()
        self.tree = TreeList(t, children, lambda row, ctrl: self._launch(row, ctrl), on_pick=self._pick)
        self.tree.setParent(self)
        self.tree.hide()
        self.preview = PreviewPane(t)  # la vista previa del archivo elegido, a la derecha de la lista o del árbol
        self.preview.setParent(self)
        self.preview.layout().setSizeConstraint(QLayout.SetNoConstraint)  # el tamaño lo manda el buscador, no el visor
        self.preview.setStyleSheet(stylesheet(t, flat_style=True))
        self.preview.hide()
        call = call or (lambda action, **payload: {"ok": False, "error": {"message": "Sin núcleo"}})
        self._core = call
        self.detail = TaskDetail(t, call)  # el detalle de una tarea, aquí mismo
        self.detail.setParent(self)
        self.detail.hide()
        self.detail.back.connect(self._detail_back)
        self.detail.deleted.connect(self._detail_back)
        self.detail.created.connect(lambda task_id: self._show_detail(task_id, select=True))
        self.kanban = KanbanBoard(t, call)
        self.kanban.setParent(self)
        self.kanban.hide()
        self.kanban.open_task.connect(self._show_detail)
        self.notes = NotesBoard(t, call, escape=lambda: self._close(True))
        self.notes.setParent(self)
        self.notes.hide()
        self.chat = ChatBoard(t, call, escape=lambda: self._close(True), children=children, roots=roots)
        self.chat.setParent(self)
        self.chat.hide()
        self.chat.side_changed.connect(lambda: self.mode == "chat" and self._show("chat", BOARD_H))  # el árbol cambia el ancho
        self._fade = QGraphicsOpacityEffect(self.edit)
        self.edit.setGraphicsEffect(self._fade)
        self._fade.setOpacity(0.0)
        self._layout()
        self.edit.hide()
        self.list.hide()

        self._anim = Tween(self, self._set_progress, self._finished)
        self._rows = Tween(self, self._set_list_h)
        self._widen = Tween(self, self._set_width)
        self._band_anim = Tween(self, self._set_band)
        self._focus_select = False
        self._query_timer = QTimer(self)
        self._query_timer.setSingleShot(True)
        self._query_timer.timeout.connect(self._run_query)
        self.edit.textChanged.connect(lambda _: (self._hide_preview(), self._query_timer.start(QUERY_DELAY_MS)))

    # ---------- colocación: el campo arriba y la lista bajando debajo ----------

    def _section(self, name):
        """Se pulsó una sección de la píldora. La abierta no hace nada (dentro de una tarea, vuelve al tablero)."""
        if name == SECTION_OF.get(self.mode):
            if self.mode == "task":
                self._detail_back()
            return
        self.on_section(name)

    def _place_pill(self):
        """La píldora, centrada arriba (cambia de ancho cuando una sección se expande)."""
        inner_w = round(self._width - 2 * self._pad)  # el mismo ancho y sitio que el campo de escritura
        self.pill.setGeometry(round((self.width() - inner_w) / 2), self._pad, inner_w, ROW_H)
        self.pill.set_fill(inner_w)

    def _layout(self):
        self._place_pill()
        input_y = self._pad + PILL_BAND
        inner_w = round(self._width - 2 * self._pad)
        inner_x = round((self.width() - inner_w) / 2)  # centrado: crece hacia los dos lados
        self.edit.setGeometry(inner_x, input_y, inner_w, INPUT_H)
        h = round(self._list_h)
        area = (inner_x, input_y + round((INPUT_H + GAP) * self._bandf), inner_w, h)
        pv = self._previewing()
        left_w = round(inner_w * PV_SHARE) if pv else inner_w
        # sigue visible mientras se encoge: si no, las opciones desaparecerían de golpe al cerrar
        for mode, widget in self._areas().items():
            widget.setGeometry(area[0], area[1], left_w if mode == self.mode else inner_w, h)
            widget.setVisible(h > 0 and mode == self.mode)
        self.preview.setGeometry(inner_x + left_w + PV_GAP, area[1], max(inner_w - left_w - PV_GAP, 1), h)
        self.preview.setVisible(h > 0 and pv)

    def _set_band(self, value):
        """El campo se va (al abrir una tarea) o vuelve (al salir de ella): el contenido sube o baja con él."""
        self._bandf = float(value)
        self._apply_fade()
        self._layout()
        self.update()

    def _apply_fade(self):
        """El campo aparece cuando la pieza ya ha crecido lo bastante para contenerlo, y se apaga al abrir una tarea."""
        self._fade.setOpacity(min(max((self._progress - 0.5) / 0.5, 0.0), 1.0) * self._bandf)
        self.edit.setVisible(self._bandf > 0.02 and self.opened)
        self.pill.setVisible(self.opened and self._progress > 0.5)

    def _areas(self):
        return {"list": self.list, "tree": self.tree, "task": self.detail, "kanban": self.kanban,
                "notes": self.notes, "chat": self.chat, "wallpapers": self.carousel}

    def _show(self, mode, height):
        """Cambia lo que se ve y lleva el área al alto (y al ancho) que necesita."""
        if mode != "wallpapers" and self._wall_original is not None:  # se borró ">wallpaper": el fondo se queda
            self.carousel.stop()
            self._wall_original = None
        if self.mode == "notes" and mode != "notes":  # se sale de las notas: se guarda lo escrito
            self.notes.leave()
        if self.mode == "task" and mode != "task":
            self.detail.flush()
        self.mode = mode
        if mode not in ("list", "tree"):
            self._hide_preview()
        self.pill.set_active(SECTION_OF.get(mode, "search"))
        target = 0.0 if mode in ("task", "chat") else 1.0  # el detalle de una tarea y el chat no llevan campo encima
        if target != self._bandf:
            self._band_anim.start(self._bandf, target, LIST_MS, QEasingCurve.OutQuint)
        self._layout()
        self._rows.start(self._list_h, self._fit_h(height), LIST_MS, QEasingCurve.OutQuint)
        chat_w = CHAT_W + (CHAT_SIDE_W if self.chat.tree_open else 0)  # con el árbol de archivos abierto, más ancho
        width = {"task": min(TASK_W, self._wide), "chat": min(chat_w, self._wide)}.get(mode, self.theme.search_width)
        if mode in WIDE_MODES or self._previewing():
            width = self._wide
        if width != self._width_to:
            self._width_to = width
            self._widen.start(self._width, width, WIDE_MS, QEasingCurve.OutQuint)

    # ---------- vista previa de un archivo ----------

    def _previewing(self):
        return bool(self._pv_path) and self.mode in ("list", "tree")

    def _fit_h(self, height):
        """Con la vista previa abierta el área no baja de lo que ella necesita."""
        return max(height, PV_H) if self._previewing() else height

    def _hide_preview(self):
        if self._pv_path:
            self._pv_path = None
            self.preview.stop()
            self.preview.hide()

    def _pick(self, result):
        """Clic en un archivo: se previsualiza a la derecha; otro clic sobre el mismo lo abre."""
        path = result.get("id")
        if not path:
            return
        if path == self._pv_path:
            if time.monotonic() - self._pv_at >= PV_OPEN_DELAY:  # un doble clic de costumbre no se salta la vista previa
                self._launch(result, False)
            return
        self._preview(result)

    def _send_to_chat(self, row):
        """Ctrl+Enter en el árbol: manda el archivo elegido al chat sin abrirlo ni cerrar el buscador. True si era un archivo."""
        if not row or row.get("kind") != "path" or row.get("is_dir"):
            return False
        reply = self._core("chat.send", text="", paths=[row["id"]])
        name = row.get("name") or os.path.basename(row["id"])
        self.chat.notify.emit(f"Enviado al chat · {name}" if reply.get("ok") else reply["error"]["message"])
        return True

    def _preview_key(self, result):
        """→ sobre un archivo: lo previsualiza (nunca lo abre; para eso está Enter). True si era un archivo."""
        if not result or result.get("kind") != "path" or result.get("is_dir"):
            return False
        if result["id"] != self._pv_path:
            self._preview(result)
        return True

    def _preview(self, result):
        path = result["id"]
        self._pv_at = time.monotonic()
        self._pv_path = path
        started = time.perf_counter()
        try:
            info = human_size(os.path.getsize(path))
        except OSError:
            info = ""
        if self.mode == "tree":  # el atajo se enseña ahí mismo (la rúbrica lo pide)
            info = f"{info} · Enter abre · Ctrl+Enter lo envía al chat" if info else "Enter abre · Ctrl+Enter lo envía al chat"
        try:
            self.preview.show_path(path, info)
        except Exception:  # noqa: BLE001 - la vista previa no debe dejar el buscador a medias
            log.exception("La vista previa de %s falló", path)
        self._show(self.mode, self.tree.wanted_height() if self.mode == "tree"
                   else min(self.list.wanted_height(), self._max_list))
        log.info("Vista previa de %s (%s) en %.0f ms", os.path.basename(path), kind_of(path) or "sin visor",
                 (time.perf_counter() - started) * 1000)

    def _set_width(self, value):
        if abs(float(value) - self._width) < 0.5 and float(value) != self._width_to:
            return
        self._width = float(value)
        self._layout()
        self.update()

    def _body_height(self):
        """Alto de la pieza que sobresale del marco, en este instante."""
        base = (2 * self._pad + PILL_BAND + INPUT_H * self._bandf) * self._progress
        return base + (self._list_h + GAP * self._bandf if self._list_h > 0.5 else 0)

    # ---------- abrir y cerrar ----------

    def open(self, mode=""):
        """`mode`: "" (el buscador), "task" (Ctrl+Shift+T: abre directo el Kanban) o "notes" (Ctrl+Shift+N)."""
        self._mode_word = mode
        self._hide_preview()
        self.edit.setPlaceholderText(PLACEHOLDERS.get(mode, PLACEHOLDERS[""]))
        if self.opened:  # ya abierto: cambia de modo sin cerrarse
            self.edit.clear()
            self._run_query()
            return
        self.opened = True
        self._wall_original = self._wall_applied = None
        self.mode = "list"
        self.pill.set_active("search")
        self._band_anim.stop()
        self._bandf = 1.0
        self._widen.stop()
        self._width = self._width_to = float(self.theme.search_width)
        self._layout()
        self.edit.clear()
        self.list.selected = 0
        self.edit.show()
        self._fade.setOpacity(0.0)
        QTimer.singleShot(0, self._run_query)  # primero se ve el buscador; la primera consulta llega justo después
        # la animación arranca antes que nada que dependa de Windows: si el foco falla, el buscador se ve igual
        self._anim.start(self._progress, 1.0, int(self.theme.open_ms * (1 - self._progress)), QEasingCurve.OutCubic)
        self.show()
        self.raise_()
        self.activateWindow()
        try:
            force_foreground(hwnd_of(self))  # Windows solo deja el foco a quien lo tiene; se fuerza
        except Exception:
            log.exception("No se pudo dar el foco al buscador")
        self.edit.setFocus()

    def close_popout(self):
        if not self.opened:
            return
        self.opened = False
        self._hide_preview()
        self._query_timer.stop()
        self._band_anim.stop()
        self.carousel.stop()
        self.detail.flush()
        self.notes.leave()
        self._rows.start(self._list_h, 0.0, self.theme.close_ms, QEasingCurve.InCubic)
        self._anim.start(self._progress, 0.0, int(self.theme.close_ms * self._progress), QEasingCurve.InCubic)

    def _set_progress(self, value):
        if abs(float(value) - self._progress) < 0.0005 and value not in (0.0, 1.0):
            return  # sin cambio que se vea: no se repinta (cada fotograma cuesta unos milisegundos)
        self._progress = float(value)
        # el campo aparece cuando la pieza ya ha crecido lo bastante para contenerlo
        self._apply_fade()
        self._layout()
        self.update()

    def _set_list_h(self, value):
        if abs(float(value) - self._list_h) < 0.5 and value != 0.0:
            return  # menos de medio píxel: no se ve, no se repinta
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
        reply = self._query(self.edit.text(), self._mode_word)
        took = (time.perf_counter() - started) * 1000
        if took > SLOW_QUERY_MS:
            log.info("La búsqueda tardó %.0f ms", took)
        mode = reply.get("mode", "list")
        if mode == "wallpapers":
            if self._wall_original is None:
                self._wall_original = self._wall_applied = reply.get("current") or ""
            self.carousel.set_images(reply["images"], self._wall_applied or reply.get("current", ""))
            self._show("wallpapers", CAROUSEL_H)
            return
        if mode == "tree":
            if self.mode != "tree":  # al seguir escribiendo no se pliega lo desplegado
                self.tree.set_roots(reply["roots"], expanded=reply.get("expanded", ()))
            self._show("tree", self.tree.wanted_height())
            return
        if mode == "tasks":  # las tareas: directo el tablero Kanban (el campo solo sirve para crear una nueva)
            if self.mode != "kanban":
                self.kanban.reload()
                self._show("kanban", BOARD_H)
            return
        if mode == "notes":
            if self.mode != "notes":  # al entrar: la pila, lista para escribir
                self._show("notes", BOARD_H)
                self.notes.open()
            return
        if mode == "chat":
            if self.mode != "chat":  # al entrar: lo guardado y el compositor listo
                self._show("chat", BOARD_H)
                self.chat.open()
            return
        self._armed = None
        results = reply["results"]
        indexing = reply.get("indexing_text", "Indexando aplicaciones…")
        note = indexing if reply["indexing"] else ("" if results else "Sin resultados")
        if not self.edit.text().strip() and not results:
            note = ""
        self.list.set_results(results, note)
        self._show("list", min(self.list.wanted_height(), self._max_list))

    def _launch_result(self, result, files=False):
        if not result or result["kind"] == "command":  # los atajos solo se muestran
            return
        if result["kind"] == "config" and self._armed != result["id"]:  # reinicia o cierra Kyora: Enter dos veces
            self._armed = result["id"]
            result["detail"] = "Pulsa Enter otra vez para hacerlo"
            self.list.update()
            return
        self._armed = None
        if result["kind"] == "complete":  # ">ta" -> ">task"
            self._type(result["id"])
        elif result["kind"] == "path" and result.get("is_dir") and not files:
            self.tree.set_roots([result], expand=True)  # una carpeta de "/": se abre como árbol
            self._show("tree", self.tree.wanted_height())
        else:
            self._launch(result, files)

    def _create_task(self):
        """Enter en el campo del tablero con algo escrito: crea esa tarea y la abre para completarla."""
        name = self.edit.text().strip()
        if not name:
            return
        reply = self._act("task_new", name)
        if reply and reply.get("ok"):
            self.edit.clear()
            self._show_detail(reply["data"], select=False)

    def _show_detail(self, task_id, select=False):
        """Abrir una tarea (clic, Enter, o recién creada): sustituye al campo, con las subtareas a un lado y la descripción
        al otro."""
        if self.detail.show_task(int(task_id)):
            self._focus_select = select
            self._show("task", TASK_H)
            self.detail.focus_name(select)

    def _detail_back(self):
        """Esc en el detalle (o la tarea se borró): de vuelta al tablero, con lo que haya cambiado, y el campo otra vez."""
        self.kanban.reload()
        self._show("kanban", BOARD_H)
        self.edit.setFocus()

    def _type(self, text):
        self.edit.setText(text)
        self.edit.setCursorPosition(len(text))
        self.list.selected = 0

    # ---------- fondos de pantalla ----------

    def _try_wallpaper(self, path):
        if path and path != self._wall_applied:
            self._wall_applied = path
            self._set_wallpaper(path)

    def _wall_keep(self):
        """Enter: se queda el fondo elegido (si aún no se había puesto, se pone ya)."""
        self.carousel.stop()
        self._try_wallpaper(self.carousel.current())
        self._wall_original = None
        self._close(True)

    def _wall_back(self):
        """Esc: vuelve el fondo (y los colores) de antes de abrir el carrusel."""
        self.carousel.stop()
        if self._wall_original and self._wall_applied != self._wall_original:
            self._set_wallpaper(self._wall_original)
        self._wall_original = None
        self._close(True)

    def eventFilter(self, obj, event):
        if obj is self.edit and event.type() == QEvent.KeyPress and self._wall_original is not None:
            key = event.key()
            if key in (Qt.Key_Left, Qt.Key_Right):
                self.carousel.step(-1 if key == Qt.Key_Left else 1)
                return True
            if key in (Qt.Key_Return, Qt.Key_Enter):
                self._wall_keep()
                return True
            if key == Qt.Key_Escape:
                self._wall_back()
                return True
        if obj is self.edit and event.type() == QEvent.KeyPress and self.mode == "tree":
            key, ctrl = event.key(), bool(event.modifiers() & Qt.ControlModifier)
            if key in (Qt.Key_Up, Qt.Key_Down):  # de arriba abajo, como se lee
                self.tree.move(-1 if key == Qt.Key_Up else 1)
                return True
            if key == Qt.Key_Right and self._preview_key(self.tree.current()):  # → en un archivo: vista previa
                return True
            if key in (Qt.Key_Left, Qt.Key_Right):
                (self.tree.left if key == Qt.Key_Left else self.tree.right)()
                self._rows.start(self._list_h, self._fit_h(self.tree.wanted_height()), LIST_MS, QEasingCurve.OutCubic)
                return True
            if key in (Qt.Key_Return, Qt.Key_Enter):
                if ctrl and self._send_to_chat(self.tree.current()):  # Ctrl+Enter sobre un archivo: al chat
                    return True
                self.tree.enter(ctrl)
                self._rows.start(self._list_h, self._fit_h(self.tree.wanted_height()), LIST_MS, QEasingCurve.OutCubic)
                return True
            if key == Qt.Key_Escape:
                self._close(True)
                return True
        if obj is self.edit and event.type() == QEvent.KeyPress and self.mode == "kanban" and self._kanban_key(event):
            return True
        if obj is self.edit and event.type() == QEvent.KeyPress and self.mode in ("task", "kanban", "notes", "chat"):
            key = event.key()
            if key == Qt.Key_Escape:
                if self.mode == "task":
                    self.detail.go_back()
                else:
                    self._close(True)
                return True
            if key in (Qt.Key_Up, Qt.Key_Down, Qt.Key_Return, Qt.Key_Enter):  # la lista de opciones no se ve
                return True
        if obj is self.edit and event.type() == QEvent.KeyPress:
            key = event.key()
            if key == Qt.Key_Up:  # la lista se lee de arriba abajo
                self.list.move(-1)
                return True
            if key == Qt.Key_Down:
                self.list.move(1)
                return True
            # → con el cursor al final de lo escrito, sobre un archivo: vista previa (si no, mueve el cursor como siempre)
            if (key == Qt.Key_Right and self.edit.cursorPosition() == len(self.edit.text())
                    and self._preview_key(self.list.current())):
                return True
            if key in (Qt.Key_Return, Qt.Key_Enter):
                self._launch_result(self.list.current(), files=bool(event.modifiers() & Qt.ControlModifier))
                return True
            if key == Qt.Key_Escape:
                self._close(True)
                return True
        return super().eventFilter(obj, event)

    def _kanban_key(self, event):
        """Los comandos del tablero de tareas (solo valen aquí): flechas para elegir (←/→ solo con el campo vacío, para no
        quitarle el cursor al que escribe), Enter abre la elegida (o crea la tarea si hay algo escrito), Ctrl+←/→ la
        pasan de estado, Ctrl+Enter la termina o reabre y Ctrl+Supr la borra (dos veces)."""
        key, ctrl = event.key(), bool(event.modifiers() & Qt.ControlModifier)
        empty = not self.edit.text()
        if ctrl and key in (Qt.Key_Left, Qt.Key_Right):
            self.kanban.shift_status(-1 if key == Qt.Key_Left else 1)
        elif ctrl and key in (Qt.Key_Return, Qt.Key_Enter):
            self.kanban.toggle_done()
        elif ctrl and key == Qt.Key_Delete:
            self.kanban.arm_delete()
        elif key in (Qt.Key_Up, Qt.Key_Down):
            self.kanban.move_sel(0, -1 if key == Qt.Key_Up else 1)
        elif key in (Qt.Key_Left, Qt.Key_Right) and empty:
            self.kanban.move_sel(-1 if key == Qt.Key_Left else 1, 0)
        elif key in (Qt.Key_Return, Qt.Key_Enter):
            self._create_task() if not empty else self.kanban.open_selected()
        else:
            return False
        return True

    def changeEvent(self, event):
        # Si el usuario pasa a otra ventana, la búsqueda se cierra sin quitarle el foco.
        if event.type() == QEvent.ActivationChange and self.opened and not self.isActiveWindow():
            QTimer.singleShot(BLUR_CHECK_MS, self._check_blur)
        super().changeEvent(event)

    def _check_blur(self):
        if QApplication.activePopupWidget() is not None or modal_open():  # el menú de la fecha; el diálogo de archivos
            return
        if self.opened and not self.isActiveWindow():
            owner, who, hidden_own = foreground_owner()
            # la vista previa puede llevarse el foco sin querer: PDFium crea ventanas ocultas ("GDI+ Hook Window", "IME")
            # al abrir un PDF. Eso no es irse a otra ventana: el buscador lo recupera y sigue abierto.
            just_picked = time.monotonic() - self._pv_at < PV_FOCUS_GRACE
            if owner == hwnd_of(self) or hidden_own or just_picked:
                log.info("El buscador recupera el foco (lo tenía %s)", who)
                self.activateWindow()
                try:
                    force_foreground(hwnd_of(self))
                except Exception:  # noqa: BLE001
                    log.exception("No se pudo devolver el foco al buscador")
                return
            log.info("El buscador se cierra: el foco pasó a %s", who)
            self._close(False)

    def closeEvent(self, event):
        """Alt+F4 sobre el buscador solo lo repliega."""
        event.ignore()
        self._close(True)

    # ---------- pintura ----------

    def retheme(self, theme):
        """Colores nuevos (el fondo cambió): el campo de escritura se rehace con ellos."""
        t = theme
        self.edit.setStyleSheet(
            f"QLineEdit {{ background: {_css(t.field)}; color: {t.ink}; border: 1px solid {_css(t.line)};"
            f" border-radius: 8px; padding: 0 10px; selection-background-color: {_css(t.gold_soft)}; }}"
            f"QLineEdit:focus {{ border-color: {_css(t.gold_line)}; }}"
        )
        if hasattr(self, "preview"):
            self.preview.setStyleSheet(stylesheet(t, flat_style=True))

    def paintEvent(self, _):
        t = self.theme
        e = min(max(self._progress, 0.0), 1.0)
        width = self._width * lerp(t.search_start_width, 1.0, e)
        body = self._body_height()
        if body <= 0:  # escondido: solo quedaría la franja del marco, que ya pinta el marco de debajo
            return
        # la misma pieza suelta del panel superior: cuelga del borde de arriba con las esquinas de abajo redondeadas
        start = (self.width() - width) / 2
        fill, outline = hanging_paths(start, start + width, body, t.dock_corner, joint=t.dock_tab)
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        p.fillPath(fill, frame_gradient(t, self._screen_height, self.y(), self.x()))
        paint_soft_shadow(p, fill, QRectF(self.rect()), t, contour=outline)



def foreground_owner():
    """(ventana raíz dueña de la que tiene el foco, "clase «título»", ¿es una ventana oculta de este proceso?) para
    saber a quién se fue el foco."""
    try:
        import ctypes
        from ctypes import wintypes

        user32 = ctypes.windll.user32
        hwnd = user32.GetForegroundWindow()
        if not hwnd:
            return 0, "nadie", False
        owner = user32.GetAncestor(hwnd, 3)  # GA_ROOTOWNER
        name, title = ctypes.create_unicode_buffer(128), ctypes.create_unicode_buffer(128)
        user32.GetClassNameW(hwnd, name, 128)
        user32.GetWindowTextW(hwnd, title, 128)
        pid = wintypes.DWORD()
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
        hidden_own = pid.value == os.getpid() and not user32.IsWindowVisible(hwnd)
        return owner or hwnd, f"{name.value} «{title.value}»", hidden_own
    except Exception:  # noqa: BLE001 - fuera de Windows (las pruebas)
        return 0, "desconocido", False


def _css(color):
    """#aarrggbb (QColor) -> rgba() de las hojas de estilo de Qt."""
    c = QColor(color)
    return f"rgba({c.red()}, {c.green()}, {c.blue()}, {c.alpha()})"
