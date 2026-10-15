from PySide6.QtWidgets import QStyledItemDelegate, QStyle
from PySide6.QtCore import Qt, QSize, QRect, QRectF, QSortFilterProxyModel
from PySide6.QtGui import QPainter, QColor, QPen, QPainterPath, QFont

from core.matrix.motherboard.globalComponents import kyora_theme as kt


# --- Paleta (globalKyoraUI) ---
CARD_FILL = QColor(kt.BG_CARD)
CARD_FILL_HOVER = QColor(kt.BG_CARD_HOVER)
CARD_FILL_SELECTED = QColor(kt.ACCENT_TINT)
CARD_STROKE = QColor(kt.BORDER_SOFT)
CARD_STROKE_HOVER = QColor(kt.BORDER_HOVER)
CARD_STROKE_SELECTED = QColor(kt.ACCENT)

TEXT_NORMAL = QColor(kt.TEXT_BODY)
TEXT_SELECTED = QColor(kt.TEXT)
TEXT_NUMBER = QColor(kt.TEXT_DIM)
TEXT_EXTENSION = QColor(kt.TEXT_DIM)
BADGE_FILL = QColor(kt.BG_BADGE)
BADGE_STROKE = QColor("#383838")

# --- Dimensiones ---
FOLDER_W = 92
FOLDER_H = 70
FOLDER_CELL_W = 110
FOLDER_CELL_H = 90
FILE_ROW_H = 32
RADIUS = kt.RADIUS_CARD


class ExplorerDelegate(QStyledItemDelegate):
    """
    Delegate del explorador con el estilo de tarjeta de Kyora (globalKyoraUI):
    - Carpetas: tarjeta con solapa, nombre centrado en mayúsculas y número abajo a la derecha.
    - Archivos: fila a lo ancho con insignia de extensión y nombre.
    Selección con acento durazno; hover con borde más claro.
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

        # Efecto de profundidad: los ítems se encogen al acercarse a los bordes mientras hay scroll
        if self.view is not None:
            viewport_h = self.view.viewport().height()
            item_cy = rect.y() + rect.height() / 2.0
            margin = max(60.0, rect.height() * 1.5)

            v_scroll = self.view.verticalScrollBar()
            scroll_y = v_scroll.value()
            scroll_max = v_scroll.maximum()
            factor = 1.0

            if item_cy < margin:
                amount_out = min(margin - item_cy, float(scroll_y))
                if amount_out > 0:
                    factor = 1.0 - (amount_out / margin)
            elif item_cy > viewport_h - margin:
                dist_to_edge = margin - (viewport_h - item_cy)
                amount_out = min(dist_to_edge, float(scroll_max - scroll_y))
                if amount_out > 0:
                    factor = 1.0 - (amount_out / margin)

            if factor < 1.0:
                factor = max(0.0, min(1.0, factor))
                factor = factor * factor * (3 - 2 * factor)
                scale = 0.6 + 0.4 * factor
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
        if isinstance(model, QSortFilterProxyModel):
            source_idx = model.mapToSource(index)
            return model.sourceModel().isDir(source_idx)
        return model.isDir(index) if hasattr(model, "isDir") else True

    @staticmethod
    def folder_path(x, y, w, h):
        """
        Silueta de carpeta: cuerpo redondeado con una solapa a la izquierda.

        Args:
            x: Coordenada izquierda.
            y: Coordenada superior.
            w: Ancho.
            h: Alto.

        Returns:
            QPainterPath: Trazado unificado de solapa y cuerpo.
        """
        tab_w = w * 0.4
        drop = 6
        path = QPainterPath()
        path.setFillRule(Qt.WindingFill)
        path.addRoundedRect(QRectF(x, y, tab_w, drop + RADIUS * 2), RADIUS, RADIUS)
        path.addRoundedRect(QRectF(x, y + drop, w, h - drop), RADIUS, RADIUS)
        return path.simplified()

    def _paint_folder(self, painter, rect, is_selected, is_hovered, text, index):
        x = rect.x() + (rect.width() - FOLDER_W) / 2
        y = rect.y() + (rect.height() - FOLDER_H) / 2
        path = self.folder_path(x, y, FOLDER_W, FOLDER_H)

        if is_selected:
            fill, stroke = CARD_FILL_SELECTED, CARD_STROKE_SELECTED
        elif is_hovered:
            fill, stroke = CARD_FILL_HOVER, CARD_STROKE_HOVER
        else:
            fill, stroke = CARD_FILL, CARD_STROKE

        painter.setBrush(fill)
        painter.setPen(QPen(stroke, 1))
        painter.drawPath(path)

        font = QFont("Prototype", 9)
        font.setBold(True)
        font.setLetterSpacing(QFont.AbsoluteSpacing, 0.6)
        painter.setFont(font)
        painter.setPen(TEXT_SELECTED if is_selected else TEXT_NORMAL)
        text_rect = QRect(int(x) + 6, int(y) + 16, FOLDER_W - 12, FOLDER_H - 32)
        elided = painter.fontMetrics().elidedText(text.upper(), Qt.ElideRight, text_rect.width())
        painter.drawText(text_rect, Qt.AlignCenter, elided)

        painter.setFont(QFont("Prototype", 8))
        painter.setPen(TEXT_NUMBER)
        num_rect = QRect(int(x), int(y), FOLDER_W - 8, FOLDER_H - 5)
        painter.drawText(num_rect, Qt.AlignBottom | Qt.AlignRight, str(index.row() + 1).zfill(2))

    def _paint_file(self, painter, rect, is_selected, is_hovered, text, index):
        x = rect.x() + 12
        y = rect.y()
        w = rect.width() - 24
        h = rect.height()

        if is_selected or is_hovered:
            row = QRectF(rect.adjusted(4, 2, -4, -2))
            painter.setBrush(CARD_FILL_SELECTED if is_selected else CARD_FILL)
            painter.setPen(QPen(CARD_STROKE_SELECTED if is_selected else CARD_STROKE, 1))
            painter.drawRoundedRect(row, RADIUS, RADIUS)
            if is_selected:
                painter.setPen(Qt.NoPen)
                painter.setBrush(CARD_STROKE_SELECTED)
                painter.drawRect(QRectF(row.left() + 1, row.top() + 4, 3, row.height() - 8))

        current_x = x + 10

        # 1. Número de posición
        num_font = QFont("Prototype", 8, QFont.Bold)
        painter.setFont(num_font)
        painter.setPen(TEXT_NUMBER)
        num_w = painter.fontMetrics().horizontalAdvance("00") + 4
        painter.drawText(QRect(int(current_x), int(y), int(num_w), int(h)), Qt.AlignCenter,
                         str(index.row() + 1).zfill(2))
        current_x += num_w + 10

        # 2. Insignia con la extensión
        badge_w, badge_h = 38, 18
        badge = QRectF(current_x, y + (h - badge_h) / 2, badge_w, badge_h)
        painter.setBrush(BADGE_FILL)
        painter.setPen(QPen(BADGE_STROKE, 1))
        painter.drawRoundedRect(badge, 3, 3)

        ext_str = "DOC"
        if "." in text:
            ext_str = text.rsplit(".", 1)[1].upper()[:4]
        painter.setFont(QFont("Prototype", 7, QFont.Bold))
        painter.setPen(TEXT_NORMAL)
        painter.drawText(badge, Qt.AlignCenter, ext_str)
        current_x += badge_w + 12

        # 3. Nombre y extensión
        text_w = x + w - current_x
        font = QFont("Prototype", 9, QFont.Bold if is_selected else QFont.Normal)
        font.setLetterSpacing(QFont.AbsoluteSpacing, 0.6)
        painter.setFont(font)
        fm = painter.fontMetrics()
        name_color = TEXT_SELECTED if is_selected else TEXT_NORMAL

        if "." in text:
            name_part, ext = text.rsplit(".", 1)
            ext_part = "." + ext
            ext_w = fm.horizontalAdvance(ext_part)
            name_part = fm.elidedText(name_part, Qt.ElideRight, max(0, int(text_w - ext_w)))
            painter.setPen(name_color)
            painter.drawText(QRect(int(current_x), int(y), int(text_w), int(h)),
                             Qt.AlignVCenter | Qt.AlignLeft, name_part)
            name_w = fm.horizontalAdvance(name_part)
            painter.setPen(TEXT_EXTENSION)
            painter.drawText(QRect(int(current_x + name_w), int(y), int(ext_w + 4), int(h)),
                             Qt.AlignVCenter | Qt.AlignLeft, ext_part)
        else:
            painter.setPen(name_color)
            painter.drawText(QRect(int(current_x), int(y), int(text_w), int(h)),
                             Qt.AlignVCenter | Qt.AlignLeft, fm.elidedText(text, Qt.ElideRight, int(text_w)))

    # -------------------------------------------------------------- sizeHint
    def sizeHint(self, option, index):
        if self._is_dir(index):
            w = FOLDER_CELL_W
            if self.view is not None:
                vp_w = self.view.viewport().width()
                # 40 px de margen de seguridad para que siempre quepan 3 sin saltar de línea
                w = max(95, int((vp_w - 40) / 3))
            return QSize(w, FOLDER_CELL_H)

        row_w = 400
        if self.view is not None:
            spacing = self.view.spacing() if hasattr(self.view, "spacing") else 0
            row_w = max(200, self.view.viewport().width() - spacing * 2 - 2)
        return QSize(row_w, FILE_ROW_H)
