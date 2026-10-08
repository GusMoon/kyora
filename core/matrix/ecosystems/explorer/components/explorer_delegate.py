from PySide6.QtWidgets import QStyledItemDelegate, QStyle
from PySide6.QtCore import Qt, QSize, QRect, QRectF
from PySide6.QtGui import QPainter, QColor, QPen, QPainterPath, QFont


# --- Paleta ---
FOLDER_STROKE = QColor("#0099FF")        # Cyan brillante (referencia)
FOLDER_STROKE_NORMAL = QColor("#0088CC") # Cyan oscuro
FOLDER_FILL = QColor(0, 80, 255, 60)         # Fondo azul verdadero translúcido
FOLDER_FILL_HOVER = QColor(0, 120, 255, 90)  # Fondo azul verdadero más brillante
FOLDER_FILL_SELECTED = QColor(0, 150, 255, 140) # Fondo azul verdadero intenso
FOLDER_TEXT = QColor("#A0C0FF")
FOLDER_TEXT_SELECTED = QColor("#FFB84D")
FOLDER_NUM = QColor("#FFB84D")           # Naranja brillante

FILE_BG_HOVER = QColor("#101C29")
FILE_BG_SELECTED = QColor("#16304D")
FILE_ACCENT = QColor("#0099FF")
FILE_TEXT = QColor("#A0C0FF")
FILE_TEXT_SELECTED = QColor("#FFB84D")
NUM_COLOR = QColor("#FFB84D")            # Naranja brillante para archivos

# --- Dimensiones ---
FOLDER_W = 92
FOLDER_H = 70
FOLDER_CELL_W = 110
FOLDER_CELL_H = 90
FILE_ROW_H = 32


class ExplorerDelegate(QStyledItemDelegate):
    """
    Delegate del explorador:
    - Carpetas: silueta sci-fi outline, pestaña a la izquierda, texto centrado, número abajo a la derecha.
    - Archivos: fila a lo ancho.
    """

    def __init__(self, view=None, parent=None):
        super().__init__(parent)
        self.view = view

    # ------------------------------------------------------------------ paint
    def paint(self, painter, option, index):
        painter.save()
        painter.setRenderHint(QPainter.Antialiasing)

        rect = option.rect
        is_selected = bool(option.state & QStyle.State_Selected)
        is_hovered = bool(option.state & QStyle.State_MouseOver)
        text = index.data(Qt.DisplayRole) or ""

        # --- Efecto 3D de profundidad al hacer scroll en los extremos ---
        if self.view is not None:
            viewport_h = self.view.viewport().height()
            item_cy = rect.y() + rect.height() / 2.0
            
            # Margen proporcional al tamaño del ítem para que afecte igual a carpetas y archivos
            margin = max(60.0, rect.height() * 1.5)
            
            v_scroll = self.view.verticalScrollBar()
            scroll_y = v_scroll.value()
            scroll_max = v_scroll.maximum()
            
            scale = 1.0
            opacity = 1.0
            factor = 1.0
            
            if item_cy < margin:
                dist_to_edge = margin - item_cy
                # Limitamos el efecto a la cantidad que se ha hecho scroll (evita que el primer ítem se vea afectado si estamos hasta arriba)
                amount_out = min(dist_to_edge, float(scroll_y))
                if amount_out > 0:
                    factor = 1.0 - (amount_out / margin)
            elif item_cy > viewport_h - margin:
                dist_to_edge = margin - (viewport_h - item_cy)
                scroll_remaining = scroll_max - scroll_y
                # Limitamos el efecto a lo que falta por hacer scroll (evita afectar los últimos ítems si estamos hasta abajo)
                amount_out = min(dist_to_edge, float(scroll_remaining))
                if amount_out > 0:
                    factor = 1.0 - (amount_out / margin)
                
            if factor < 1.0:
                factor = max(0.0, min(1.0, factor))
                factor = factor * factor * (3 - 2 * factor) # Suavizado ease in/out
                scale = 0.6 + 0.4 * factor
                opacity = 0.1 + 0.9 * factor
                
                painter.setOpacity(opacity)
                painter.translate(rect.x() + rect.width() / 2.0, item_cy)
                painter.scale(scale, scale)
                painter.translate(-(rect.x() + rect.width() / 2.0), -item_cy)

        if self._is_dir(index):
            self._paint_folder(painter, rect, is_selected, is_hovered, text, index)
        else:
            self._paint_file(painter, rect, is_selected, is_hovered, text, index)

        painter.restore()

    @staticmethod
    def _is_dir(index):
        model = index.model()
        from PySide6.QtCore import QSortFilterProxyModel
        if isinstance(model, QSortFilterProxyModel):
            source_idx = model.mapToSource(index)
            return model.sourceModel().isDir(source_idx)
        return model.isDir(index) if hasattr(model, "isDir") else True

    @staticmethod
    def folder_path(x, y, w, h):
        """
        Silueta Sci-Fi: pestaña a la izquierda, borde biselado.
        """
        tab_w = w * 0.4
        chamfer = 6
        drop = 5

        path = QPainterPath()
        path.moveTo(x + chamfer, y)
        path.lineTo(x + tab_w - chamfer, y)
        path.lineTo(x + tab_w, y + drop)
        path.lineTo(x + w, y + drop)
        path.lineTo(x + w, y + h - chamfer)
        path.lineTo(x + w - chamfer, y + h)
        path.lineTo(x + chamfer, y + h)
        path.lineTo(x, y + h - chamfer)
        path.lineTo(x, y + chamfer)
        path.closeSubpath()
        return path

    def _paint_folder(self, painter, rect, is_selected, is_hovered, text, index):
        x = rect.x() + (rect.width() - FOLDER_W) / 2
        y = rect.y() + (rect.height() - FOLDER_H) / 2

        path = self.folder_path(x, y, FOLDER_W, FOLDER_H)

        if is_selected:
            fill = FOLDER_FILL_SELECTED
            stroke = FOLDER_STROKE
            pen_w = 2
        elif is_hovered:
            fill = FOLDER_FILL_HOVER
            stroke = FOLDER_STROKE
            pen_w = 1.5
        else:
            fill = FOLDER_FILL
            stroke = FOLDER_STROKE_NORMAL
            pen_w = 1.5

        painter.setBrush(fill)
        painter.setPen(QPen(stroke, pen_w))
        painter.drawPath(path)
        
        # Detalles sci-fi internos
        painter.setPen(QPen(stroke, 1))
        painter.drawLine(x + 5, y + 10, x + FOLDER_W * 0.35, y + 10)

        # Nombre centrado
        font = QFont("Space Grotesk", 9)
        if is_selected:
            font.setBold(True)
        painter.setFont(font)
        painter.setPen(FOLDER_TEXT_SELECTED if is_selected else FOLDER_TEXT)
        text_rect = QRect(int(x) + 5, int(y) + 15, FOLDER_W - 10, FOLDER_H - 30)
        elided = painter.fontMetrics().elidedText(text.upper(), Qt.ElideRight, text_rect.width())
        painter.drawText(text_rect, Qt.AlignCenter, elided)

        # Número en la esquina inferior derecha
        num_font = QFont("Space Grotesk", 8)
        painter.setFont(num_font)
        painter.setPen(FOLDER_NUM)
        num_rect = QRect(int(x), int(y), FOLDER_W - 6, FOLDER_H - 4)
        painter.drawText(num_rect, Qt.AlignBottom | Qt.AlignRight, str(index.row() + 1).zfill(2))

    def _paint_file(self, painter, rect, is_selected, is_hovered, text, index):
        x = rect.x() + 12
        y = rect.y()
        w = rect.width() - 24
        h = rect.height()

        if is_selected or is_hovered:
            painter.setPen(Qt.NoPen)
            painter.setBrush(FILE_BG_SELECTED if is_selected else FILE_BG_HOVER)
            painter.drawRect(rect.adjusted(4, 2, -4, -2))
            if is_selected:
                painter.setBrush(FILE_ACCENT)
                painter.drawRect(rect.x() + 4, rect.y() + 2, 3, rect.height() - 4)

        current_x = x + 10
        
        # 1. Número
        num_str = str(index.row() + 1).zfill(2)
        num_font = QFont("Space Grotesk", 8, QFont.Bold)
        painter.setFont(num_font)
        painter.setPen(NUM_COLOR)
        num_w = painter.fontMetrics().horizontalAdvance("00") + 4
        painter.drawText(QRect(int(current_x), int(y), int(num_w), int(h)), Qt.AlignCenter, num_str)
        current_x += num_w + 6
        
        # 2. Primera línea vertical
        painter.setPen(QPen(FILE_ACCENT, 2))
        line1_y = y + 6
        line_h = h - 12
        painter.drawLine(int(current_x), int(line1_y), int(current_x), int(line1_y + line_h))
        current_x += 10
        
        # 3. Figura (cuadrada) con esquina inferior derecha biselada
        box_w = 26
        box_h = 24
        box_y = y + (h - box_h) // 2
        
        chamfer = 6
        path = QPainterPath()
        path.moveTo(current_x, box_y)
        path.lineTo(current_x + box_w, box_y)
        path.lineTo(current_x + box_w, box_y + box_h - chamfer)
        path.lineTo(current_x + box_w - chamfer, box_y + box_h)
        path.lineTo(current_x, box_y + box_h)
        path.closeSubpath()
        
        # Fondo y borde de la figura
        painter.setBrush(QColor("#0A1118") if not is_selected else QColor("#16304D"))
        painter.setPen(QPen(FILE_ACCENT, 1.5))
        painter.drawPath(path)
        
        # Texto de extensión dentro de la figura
        ext_str = "doc"
        if "." in text:
            ext_str = "." + text.rsplit(".", 1)[1].lower()[:4]
            
        info_font = QFont("Space Grotesk", 7, QFont.Bold)
        painter.setFont(info_font)
        painter.setPen(FILE_ACCENT)
        painter.drawText(QRect(int(current_x), int(box_y), int(box_w), int(box_h)), Qt.AlignCenter, ext_str)
        
        current_x += box_w + 10
        
        # 4. Segunda línea vertical
        painter.setPen(QPen(FILE_ACCENT, 2))
        painter.drawLine(int(current_x), int(line1_y), int(current_x), int(line1_y + line_h))
        current_x += 10
        
        # 5. Nombre + extensión
        text_w = x + w - current_x
        font = QFont("Space Grotesk", 9, QFont.Bold if is_selected else QFont.Normal)
        font.setLetterSpacing(QFont.AbsoluteSpacing, 1)
        painter.setFont(font)
        fm = painter.fontMetrics()

        if "." in text:
            name_part, ext = text.rsplit(".", 1)
            ext_part = "." + ext
            ext_w = fm.horizontalAdvance(ext_part)
            name_part = fm.elidedText(name_part, Qt.ElideRight, max(0, int(text_w - ext_w)))
            painter.setPen(FILE_TEXT_SELECTED if is_selected else FILE_TEXT)
            painter.drawText(QRect(int(current_x), int(y), int(text_w), int(h)), Qt.AlignVCenter | Qt.AlignLeft, name_part)
            name_w = fm.horizontalAdvance(name_part)
            painter.setPen(FILE_ACCENT)
            painter.drawText(QRect(int(current_x + name_w), int(y), int(ext_w + 4), int(h)), Qt.AlignVCenter | Qt.AlignLeft, ext_part)
        else:
            painter.setPen(FILE_TEXT_SELECTED if is_selected else FILE_TEXT)
            painter.drawText(QRect(int(current_x), int(y), int(text_w), int(h)), Qt.AlignVCenter | Qt.AlignLeft,
                             fm.elidedText(text, Qt.ElideRight, int(text_w)))

    # -------------------------------------------------------------- sizeHint
    def sizeHint(self, option, index):
        if self._is_dir(index):
            w = FOLDER_CELL_W
            if self.view is not None:
                vp_w = self.view.viewport().width()
                # Restamos 40px como margen de seguridad para garantizar que siempre quepan 3 sin saltar de línea
                w = max(95, int((vp_w - 40) / 3))
            return QSize(w, FOLDER_CELL_H)

        row_w = 400
        if self.view is not None:
            spacing = self.view.spacing() if hasattr(self.view, "spacing") else 0
            row_w = max(200, self.view.viewport().width() - spacing * 2 - 2)
        return QSize(row_w, FILE_ROW_H)
