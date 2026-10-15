from PySide6.QtWidgets import QStyledItemDelegate, QStyle
from PySide6.QtCore import Qt, QSize, QRect, QRectF
from PySide6.QtGui import QPainter, QColor, QPen, QPainterPath, QFont, QIcon

from core.matrix.motherboard.globalComponents import kyora_theme as kt


class SidebarDelegate(QStyledItemDelegate):
    """
    Delegate de los accesos rápidos del explorador, con el estilo de Kyora (globalKyoraUI):
    fila redondeada, número de posición y nombre; selección con acento durazno.

    `enable_3d` se conserva por compatibilidad con quien lo instancia y no tiene efecto.
    """

    def __init__(self, show_arrow=False, enable_3d=False, parent=None):
        super().__init__(parent)
        self.show_arrow = show_arrow
        self.enable_3d = enable_3d

    def paint(self, painter, option, index):
        painter.save()
        painter.setRenderHint(QPainter.Antialiasing)

        rect = option.rect
        is_selected = bool(option.state & QStyle.State_Selected)
        is_hovered = bool(option.state & QStyle.State_MouseOver)

        row = QRectF(rect.x() + 6, rect.y() + 2, rect.width() - 14, rect.height() - 4)
        if is_selected:
            fill, stroke = QColor(kt.ACCENT_TINT), QColor(kt.ACCENT)
        elif is_hovered:
            fill, stroke = QColor(kt.BG_CARD), QColor(kt.BORDER_SOFT)
        else:
            fill, stroke = QColor(0, 0, 0, 0), QColor(0, 0, 0, 0)
        painter.setBrush(fill)
        painter.setPen(QPen(stroke, 1))
        painter.drawRoundedRect(row, kt.RADIUS_CARD, kt.RADIUS_CARD)

        x = int(row.left())
        y = int(row.top())
        h = int(row.height())

        painter.setFont(QFont("Prototype", 8, QFont.Bold))
        painter.setPen(QColor(kt.TEXT_DIM))
        painter.drawText(QRect(x + 8, y, 22, h), Qt.AlignVCenter | Qt.AlignCenter,
                         str(index.row() + 1).zfill(2))

        text_x = x + 8 + 22 + 8
        is_dir = True
        model = index.model()
        if hasattr(model, "isDir"):
            is_dir = model.isDir(index)

        arrow_size = 4
        if self.show_arrow and is_dir:
            arrow_y = y + h // 2
            arrow_path = QPainterPath()
            arrow_path.moveTo(text_x, arrow_y - arrow_size)
            arrow_path.lineTo(text_x + arrow_size, arrow_y)
            arrow_path.lineTo(text_x, arrow_y + arrow_size)
            arrow_path.closeSubpath()
            painter.setPen(Qt.NoPen)
            painter.setBrush(QColor(kt.TEXT if is_selected else kt.TEXT_DIM))
            painter.drawPath(arrow_path)
            text_x += arrow_size + 8
        elif not is_dir:
            icon = index.data(Qt.DecorationRole)
            if icon and isinstance(icon, QIcon):
                icon.paint(painter, QRect(text_x, y + (h - 14) // 2, 14, 14), Qt.AlignCenter,
                           QIcon.Normal, QIcon.On)
                text_x += 14 + 8

        font = QFont("Prototype", 9, QFont.Bold if is_selected else QFont.Normal)
        font.setLetterSpacing(QFont.AbsoluteSpacing, 0.6)
        painter.setFont(font)
        painter.setPen(QColor(kt.TEXT if is_selected else kt.TEXT_BODY if is_hovered else kt.TEXT_SUB))
        text_rect = QRect(text_x, y, int(row.right()) - text_x - 8, h)
        text = painter.fontMetrics().elidedText(index.data(Qt.DisplayRole) or "", Qt.ElideRight,
                                                text_rect.width())
        painter.drawText(text_rect, Qt.AlignVCenter | Qt.AlignLeft, text)

        painter.restore()

    def sizeHint(self, option, index):
        return QSize(250, 36)
