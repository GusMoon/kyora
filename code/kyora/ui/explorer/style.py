"""Hoja de estilos de los paneles: los tokens del tema sobre los widgets de Qt, con la rúbrica de DISEÑO.md."""
from PySide6.QtGui import QColor


def _css(color):
    """#aarrggbb (QColor) -> rgba() de las hojas de estilo de Qt (la misma de search.py: el buscador usa esta hoja,
    así que no puede importarla de allí)."""
    c = QColor(color)
    return f"rgba({c.red()}, {c.green()}, {c.blue()}, {c.alpha()})"


def _lighter(color, factor=118):
    return QColor(color).lighter(factor).name()


def raised(t):
    """Relieve de un botón o una píldora: degradado claro arriba, borde oscuro y el filete de luz arriba."""
    return (f"background: qlineargradient(x1:0, y1:0, x2:0, y2:1, stop:0 {t.plate_top}, stop:1 {t.plate_bottom});"
            f" border: 1px solid rgba(0, 0, 0, 170); border-top-color: {_css(t.plate_hi)};")


def well(t):
    """Hueco hundido de un campo: más oscuro, borde oscuro arriba y un filete claro abajo."""
    return (f"background: qlineargradient(x1:0, y1:0, x2:0, y2:1, stop:0 {t.frame_dark}, stop:1 {t.frame});"
            f" border: 1px solid rgba(0, 0, 0, 150); border-top-color: rgba(0, 0, 0, 220);"
            f" border-bottom-color: rgba(255, 255, 255, 30);")


def flat(t):
    """La excepción plana (tipo GNOME) de tareas y notas: relleno liso y un borde fino, sin degradado ni relieve."""
    edge = "rgba(255, 255, 255, 20)"
    plain = f"background: {t.plate_top}; border: 1px solid {edge};"
    return (
        f"QLineEdit {{ background: {t.frame_dark}; border: 1px solid {edge}; }}"
        f"QLineEdit:focus {{ border-color: {_css(t.gold_line)}; }}"
        f"QPushButton, #Pill {{ {plain} }}"
        f"QPushButton:hover, #Pill:hover {{ background: {t.plate_pick}; }}"
        f"QPushButton:pressed {{ background: {t.plate_bottom}; border-color: {edge}; }}"
        f"QPushButton#Accent {{ background: {t.gold}; border: 1px solid {t.gold}; }}"
        f"QPushButton#Accent:hover {{ background: {_lighter(t.gold, 110)}; }}"
        f"QDateTimeEdit {{ background: {t.frame_dark}; border: 1px solid {edge}; }}"
        # la tarea abierta: letra más contenida (Gustavo la quería menos grande; nunca por debajo de 15 px)
        f"QLineEdit#Title {{ font: 600 {t.font_px}px '{t.font_family}'; }}"
        f"QPlainTextEdit#Body {{ font: {t.font_px}px '{t.font_family}'; }}"
    )


def stylesheet(t, flat_style=False):
    """La hoja de los paneles; `flat_style`: con la excepción plana de tareas y notas (ver `flat`)."""
    f = f"{t.font_px}px '{t.font_family}'"
    return _base(t, f) + (flat(t) if flat_style else "")


def _base(t, f):
    return (
        f"QWidget {{ color: {t.ink}; font: {f}; }}"
        f"#ExplorerBody, #ExplorerBody QWidget#Plain {{ background: transparent; }}"
        f"QListView, QTreeView, QListWidget, QPlainTextEdit, QTextBrowser, QScrollArea {{"
        f" background: transparent; border: 0; outline: 0; }}"
        f"QListView::item, QTreeView::item, QListWidget::item {{ border-radius: 8px; padding: 3px; }}"
        f"QListView::item:hover, QTreeView::item:hover, QListWidget::item:hover {{ background: {_css(t.hover)}; }}"
        f"QListView::item:selected, QTreeView::item:selected, QListWidget::item:selected {{"
        f" background: {_css(t.glass_hi)}; color: {t.ink}; border: 1px solid {_css(t.glass_hi)}; }}"
        f"QTreeView::branch:selected, QTreeView::branch:hover {{ background: transparent; }}"
        f"QListView::indicator {{ width: 14px; height: 14px; border: 1px solid {_css(t.glass_hi)}; border-radius: 4px;"
        f" background: {_css(t.field)}; }}"
        f"QListView::indicator:checked {{ background: {t.gold}; border-color: {t.gold}; }}"
        f"QHeaderView::section {{ background: transparent; color: {t.dim}; border: 0;"
        f" border-bottom: 1px solid {_css(t.line)}; padding: 4px 8px; }}"
        f"#Sidebar {{ background: {_css('#26000000')}; border-radius: 12px; }}"
        f"#Preview {{ background: {_css('#26000000')}; border-radius: 12px; }}"
        f"#Crumb {{ background: transparent; border: 0; border-radius: 8px; padding: 4px 8px; }}"
        f"#Crumb:hover {{ background: {_css(t.hover)}; }}"
        f"#Crumb[last=\"true\"] {{ font-weight: bold; }}"
        f"#PathBox {{ background: transparent; border: 0; }}"
        # rúbrica de DISEÑO.md: campos hundidos, botones en relieve
        f"QLineEdit {{ {well(t)} border-radius: 10px; padding: 6px 12px;"
        f" selection-background-color: {_css(t.gold_soft)}; }}"
        f"QLineEdit:focus {{ border-color: {_css(t.gold_line)}; border-top-color: rgba(0, 0, 0, 200); }}"
        f"QPushButton {{ {raised(t)} border-radius: 10px; padding: 6px 14px; }}"
        f"QPushButton:hover {{ background: qlineargradient(x1:0, y1:0, x2:0, y2:1, stop:0 {t.plate_pick},"
        f" stop:1 {t.plate_top}); }}"
        f"QPushButton:pressed {{ background: {t.plate_bottom}; border-top-color: rgba(0, 0, 0, 200); }}"
        f"QPushButton#Accent {{ color: {t.pick_ink}; font-weight: bold; border-color: rgba(0, 0, 0, 180);"
        f" background: qlineargradient(x1:0, y1:0, x2:0, y2:1, stop:0 {_lighter(t.gold)}, stop:1 {t.gold}); }}"
        f"QCheckBox {{ spacing: 8px; }}"
        f"QProgressBar {{ background: {_css(t.line)}; border: 0; border-radius: 4px; max-height: 8px; }}"
        f"QProgressBar::chunk {{ background: {t.gold}; border-radius: 4px; }}"
        f"QSlider::groove:horizontal {{ height: 6px; border-radius: 3px; background: {_css(t.line)}; }}"
        f"QSlider::sub-page:horizontal {{ border-radius: 3px; background: {t.gold}; }}"
        f"QSlider::handle:horizontal {{ width: 14px; margin: -5px 0; border-radius: 7px; background: {t.ink}; }}"
        f"QScrollBar:vertical, QScrollBar:horizontal {{ background: transparent; width: 10px; height: 10px; }}"
        f"QScrollBar::handle {{ background: {_css(t.line)}; border-radius: 5px; min-height: 30px; min-width: 30px; }}"
        f"QScrollBar::add-line, QScrollBar::sub-line {{ width: 0; height: 0; }}"
        f"QScrollBar::add-page, QScrollBar::sub-page {{ background: transparent; }}"
        f"QSplitter::handle {{ background: transparent; width: 8px; }}"
        f"#Dialog {{ background: {t.frame}; border: 1px solid {_css(t.gold_line)}; border-radius: 14px; }}"
        f"#Dim {{ color: {t.dim}; }}"
        f"#Chip {{ color: {t.gold}; border-color: {_css(t.gold_line)}; background: {_css(t.gold_soft)};"
        f" padding: 3px 10px; border-radius: 9px; }}"
        # ---------- panel de arriba: tarjetas, números y migas de pan, como la referencia ----------
        f"#CardTitle {{ font: 600 {t.font_px}px '{t.font_family}'; color: {t.ink}; }}"
        f"#BigNumber {{ font: {t.font_px}px '{t.font_family}'; color: {t.ink}; }}"
        f"#MidNumber {{ font: {t.font_px}px '{t.font_family}'; color: {t.ink}; }}"
        f"#SectionNumber {{ font: {t.font_px}px '{t.font_family}'; color: {t.ink}; }}"
        f"#Pill {{ {raised(t)} border-radius: 12px; padding: 5px 14px; }}"
        f"#Pill:hover {{ background: qlineargradient(x1:0, y1:0, x2:0, y2:1, stop:0 {t.plate_pick},"
        f" stop:1 {t.plate_top}); }}"
        f"#Pill:checked {{ {well(t)} color: {t.gold}; font-weight: bold; }}"
        f"#Clock {{ font: 300 {t.font_px}px '{t.font_family}'; color: {t.ink}; }}"
        f"#ClockSuffix {{ font: {t.font_px}px '{t.font_family}'; color: {t.dim}; }}"
        f"#DateLine {{ font: 600 {t.font_px}px '{t.font_family}'; color: {t.ink}; }}"
        f"#Heading {{ font: 600 {t.font_px}px '{t.font_family}'; color: {t.ink}; }}"
        f"#PageTitle {{ font: 600 {t.font_px}px '{t.font_family}'; color: {t.ink}; }}"
        # panel de la tarea: sin cajas (como la referencia), el texto es el contenido
        f"QLineEdit#Title {{ background: transparent; border: 0; padding: 2px 0; font: 600 {t.font_px}px '{t.font_family}'; }}"
        f"QLineEdit#Bare {{ background: transparent; border: 0; padding: 4px 0; color: {t.dim}; }}"
        f"QLineEdit#Bare:focus {{ color: {t.ink}; }}"
        f"QPlainTextEdit#Body {{ background: transparent; border: 0; font: {t.font_px}px '{t.font_family}'; color: {t.ink}; }}"
        f"QListWidget#Checklist::item {{ padding: 5px 2px; border-bottom: 1px solid rgba(255, 255, 255, 18);"
        f" border-radius: 0; }}"
        f"#Big {{ font: 600 {t.font_px}px '{t.font_family}'; color: {t.ink}; }}"
        f"#Ghost {{ background: transparent; border: 0; border-radius: 8px; padding: 4px 8px; color: {t.dim}; }}"
        f"#Ghost:hover {{ background: {_css(t.hover)}; color: {t.ink}; }}"
        f"QTextEdit, QPlainTextEdit#Source {{ background: transparent; border: 0; }}"
        f"QPlainTextEdit#Field {{ {well(t)} border-radius: 10px; padding: 4px 8px; }}"
        f"QPlainTextEdit#Field:focus {{ border-color: {_css(t.gold_line)}; }}"
        f"QDateTimeEdit {{ {well(t)} border-radius: 10px; padding: 5px 10px; }}"
        f"QDateTimeEdit::up-button, QDateTimeEdit::down-button {{ width: 0; border: 0; }}"
        f"#CrumbRoot {{ font: {t.font_px}px '{t.font_family}'; color: {t.dim}; }}"
        f"#CrumbLeaf {{ font: bold {t.font_px}px '{t.font_family}'; color: {t.ink}; }}"
        f"#Crumb {{ font: {t.font_px}px '{t.font_family}'; color: {t.dim}; }}"
        f"#Crumb[last=\"true\"] {{ color: {t.ink}; }}"
        f"#Divider {{ background: {t.card_line}; border: 0; }}"
    )
