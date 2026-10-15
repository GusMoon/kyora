from datetime import date

from PySide6.QtCore import QTimer
from PySide6.QtGui import QColor, QPainter
from PySide6.QtWidgets import QApplication, QFrame, QLabel, QTextEdit, QVBoxLayout, QWidget

from core.matrix.motherboard.ecosystems.logbook.domain.date_navigation import shift_date
from core.matrix.motherboard.ecosystems.logbook.presentation.logbook_viewmodel import LogbookViewModel
from core.matrix.motherboard.ecosystems.logbook.presentation.rootComponents import book_theme as theme
from core.matrix.motherboard.ecosystems.logbook.presentation.rootComponents.book_widget import BookWidget
from core.matrix.motherboard.ecosystems.logbook.presentation.rootComponents.date_page import DatePage

AUTOSAVE_DELAY_MS = 800


class LogbookView(QWidget):
    """
    Vista principal del ecosistema de bitácora, presentada como un libro abierto
    que ocupa toda la ventana.

    Página izquierda: la fecha en grande; al desplazar sobre el día, el mes o el
    año se navega rápido. Página derecha: hoja de escritura. Al cambiar de día la
    hoja gira sobre el lomo. Guarda automáticamente tras una breve pausa.
    """

    def __init__(self, viewmodel: LogbookViewModel, parent=None):
        """
        Args:
            viewmodel: ViewModel que provee el estado de la vista.
            parent: Widget padre (la ventana principal).
        """
        super().__init__(parent)
        self.viewmodel = viewmodel
        self._current_date = date.today().isoformat()
        self._has_loaded = False
        self._loading = False
        self._dirty = False

        self.resize(850, 550)
        self.move(15, 15)

        self._save_timer = QTimer(self)
        self._save_timer.setSingleShot(True)
        self._save_timer.setInterval(AUTOSAVE_DELAY_MS)
        self._save_timer.timeout.connect(self.flush)

        self._setup_ui()
        self._connect_signals()

    def paintEvent(self, event):
        painter = QPainter(self)
        painter.fillRect(self.rect(), QColor(18, 18, 18, 240))

    # ------------------------------------------------------------------ UI
    def _setup_ui(self) -> None:
        """Construye el libro con sus dos páginas."""
        outer = QVBoxLayout(self)
        outer.setContentsMargins(0, 0, 0, 0)
        self.book = BookWidget()
        outer.addWidget(self.book)

        self.date_page = DatePage()
        self.book.left_layout.addWidget(self.date_page)

        self.editor = QTextEdit()
        self.editor.setFrameShape(QFrame.NoFrame)
        self.editor.setAcceptRichText(False)
        self.editor.setPlaceholderText("Escribe lo que quieras recordar de este día...")
        self.editor.setStyleSheet(
            f"QTextEdit {{ background: transparent; color: {theme.TEXT_BODY}; "
            f"font-family: '{theme.FONT_FAMILY}'; font-size: 15px; "
            f"selection-background-color: {theme.ACCENT}; selection-color: #0A0A0A; }}"
        )
        self.book.right_layout.addWidget(self.editor, 1)

        self.status_label = QLabel("")
        self.status_label.setStyleSheet(
            f"color: {theme.TEXT_MUTED}; font-family: '{theme.FONT_FAMILY}'; font-size: 12px; "
            "letter-spacing: 1px; background: transparent;"
        )
        self.book.right_layout.addWidget(self.status_label)

    def _connect_signals(self) -> None:
        """Conecta la vista con el ViewModel y con los controles propios."""
        self.editor.textChanged.connect(self._mark_dirty)
        self.date_page.step_requested.connect(self._on_step_requested)

        self.viewmodel.entry_loaded.connect(self._on_entry_loaded)
        self.viewmodel.save_succeeded.connect(lambda _d: self.status_label.setText("GUARDADO"))
        self.viewmodel.logbook_error.connect(self._on_error)

        app = QApplication.instance()
        if app is not None:
            app.aboutToQuit.connect(self.flush)

    # ------------------------------------------------------------- actions
    def open_today(self) -> None:
        """Abre la entrada del día actual sin animación (al entrar al ecosistema)."""
        self.open_date(date.today().isoformat(), animate=False)

    def open_date(self, entry_date: str, animate: bool = True) -> None:
        """
        Abre la entrada de una fecha guardando antes la que estaba en edición.

        Si la hoja ya está girando (navegación rápida con scroll), el cambio es
        inmediato para no acumular animaciones.

        Args:
            entry_date: Fecha ISO (AAAA-MM-DD).
            animate: Si es True y la vista está visible, la hoja gira al cambiar de día.
        """
        self.flush()
        can_animate = (
            animate and self._has_loaded and self.isVisible()
            and entry_date != self._current_date and self.book.width() > 0
            and not self.book.flip_overlay.is_running()
        )
        if not can_animate:
            self.book.flip_overlay.stop()
            self.viewmodel.open_date(entry_date)
            return

        forward = entry_date > self._current_date
        old_pages = self.book.grab_pages()
        self.viewmodel.open_date(entry_date)
        if self._current_date != entry_date:
            return  # la carga falló; no hay hoja nueva que mostrar
        new_pages = self.book.grab_pages()
        self.book.flip_overlay.start(
            forward, self.book.left_paper_rect(), self.book.right_paper_rect(), old_pages, new_pages
        )

    def _on_step_requested(self, unit: str, direction: int) -> None:
        """Mueve la fecha un día, mes o año hacia adelante o atrás."""
        current = date.fromisoformat(self._current_date)
        try:
            target = shift_date(current, unit, direction)
        except (ValueError, OverflowError):
            return
        self.open_date(target.isoformat())

    def flush(self) -> None:
        """Guarda de inmediato los cambios pendientes, si los hay."""
        self._save_timer.stop()
        if not self._dirty:
            return
        self._dirty = False
        self.status_label.setText("GUARDANDO...")
        self.viewmodel.save_content(self._current_date, self.editor.toPlainText())

    def hideEvent(self, event):
        self.flush()
        super().hideEvent(event)

    def _mark_dirty(self) -> None:
        """Marca cambios pendientes y reinicia el temporizador de guardado."""
        if self._loading:
            return
        self._dirty = True
        self.status_label.setText("SIN GUARDAR")
        self._save_timer.start()

    # ------------------------------------------------------ viewmodel slots
    def _on_entry_loaded(self, entry_date: str, content: str) -> None:
        """Muestra la entrada cargada sin disparar el guardado automático."""
        # La fecha activa solo cambia cuando la carga tuvo éxito, para no guardar
        # el texto de un día sobre otro si la lectura falla.
        self._current_date = entry_date
        self._has_loaded = True
        self._loading = True
        self.editor.setPlainText(content)
        self._loading = False
        self._dirty = False

        self.date_page.set_date(date.fromisoformat(entry_date))
        self.status_label.setText("" if content else "AÚN NO HAY ENTRADA PARA ESTE DÍA")

    def _on_error(self, message: str) -> None:
        """Informa el error sin ocultar que el texto sigue sin guardarse."""
        self._dirty = True
        self.status_label.setText(message)
