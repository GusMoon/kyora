from PySide6.QtWidgets import QStyledItemDelegate, QStyle
from PySide6.QtCore import Qt, QSize, QRect, QPoint
from PySide6.QtGui import QPainter, QColor, QPen, QPainterPath, QFont, QIcon

class ExplorerDelegate(QStyledItemDelegate):
    def __init__(self, parent=None):
        super().__init__(parent)

    def paint(self, painter, option, index):
        painter.save()
        painter.setRenderHint(QPainter.Antialiasing)
        
        rect = option.rect
        is_selected = option.state & QStyle.State_Selected
        is_hovered = option.state & QStyle.State_MouseOver
        
        is_dir = True
        model = index.model()
        if hasattr(model, 'isDir'):
            is_dir = model.isDir(index)
            
        text = index.data(Qt.DisplayRole) or ""
        
        if is_dir:
            self._paint_folder(painter, rect, is_selected, is_hovered, text, index)
        else:
            self._paint_file(painter, rect, is_selected, is_hovered, text, index)
            
        painter.restore()
        
    def _paint_folder(self, painter, rect, is_selected, is_hovered, text, index):
        # We draw a folder icon that takes up a nice chunk of space
        w = 160
        h = 100
        # Align left like a tree, but with nice padding
        x = rect.x() + 25
        y = rect.y() + 10
        
        tab_w = 45
        tab_h = 15
        
        # Draw folder body
        poly = QPainterPath()
        poly.moveTo(x, y + tab_h)
        poly.lineTo(x + w - tab_w, y + tab_h)
        poly.lineTo(x + w - tab_w + 8, y)
        poly.lineTo(x + w, y)
        poly.lineTo(x + w, y + h)
        poly.lineTo(x, y + h)
        poly.closeSubpath()
        
        # Color palette
        bg_color = QColor(77, 148, 255, 45 if is_selected else (20 if is_hovered else 8))
        border_color = QColor("#4D94FF") if is_selected else QColor("#182533")
        
        painter.setBrush(bg_color)
        painter.setPen(QPen(border_color, 2 if is_selected else 1))
        painter.drawPath(poly)
        
        # Folder accent inside to give it depth
        painter.setPen(QPen(QColor("#4D94FF"), 1))
        painter.drawLine(x + 5, y + tab_h + 5, x + w - 5, y + tab_h + 5)
        
        # Text centered inside the folder
        font = QFont("Space Grotesk", 10, QFont.Bold)
        font.setLetterSpacing(QFont.AbsoluteSpacing, 1)
        painter.setFont(font)
        painter.setPen(QColor("#FFFFFF") if is_selected else QColor("#A0C0FF"))
        painter.drawText(QRect(x, y + tab_h, w, h - tab_h), Qt.AlignCenter, text.upper())
        
        # Number in bottom right corner of the folder
        row_idx = str(index.row() + 1).zfill(2)
        num_font = QFont("Space Grotesk", 8)
        painter.setFont(num_font)
        painter.setPen(QColor("#4D94FF"))
        painter.drawText(QRect(x, y, w - 8, h - 5), Qt.AlignBottom | Qt.AlignRight, row_idx)

    def _paint_file(self, painter, rect, is_selected, is_hovered, text, index):
        x = rect.x() + 25
        y = rect.y()
        w = rect.width() - 50
        h = rect.height()
        
        if is_selected or is_hovered:
            bg_color = QColor(77, 148, 255, 25 if is_selected else 10)
            painter.setBrush(bg_color)
            painter.setPen(Qt.NoPen)
            painter.drawRect(rect)
            
        # Draw document icon (Sci-fi)
        icon_w = 20
        icon_h = 24
        icon_x = x
        icon_y = y + (h - icon_h) // 2
        
        poly = QPainterPath()
        poly.moveTo(icon_x, icon_y)
        poly.lineTo(icon_x + icon_w - 6, icon_y)
        poly.lineTo(icon_x + icon_w, icon_y + 6)
        poly.lineTo(icon_x + icon_w, icon_y + icon_h)
        poly.lineTo(icon_x, icon_y + icon_h)
        poly.closeSubpath()
        
        painter.setBrush(Qt.NoBrush)
        painter.setPen(QPen(QColor("#4D94FF"), 1.5))
        painter.drawPath(poly)
        
        # Folded corner
        painter.drawLine(icon_x + icon_w - 6, icon_y, icon_x + icon_w - 6, icon_y + 6)
        painter.drawLine(icon_x + icon_w - 6, icon_y + 6, icon_x + icon_w, icon_y + 6)
        
        # Draw text
        text_x = icon_x + icon_w + 15
        font = QFont("Space Grotesk", 10, QFont.Bold if is_selected else QFont.Normal)
        font.setLetterSpacing(QFont.AbsoluteSpacing, 1)
        painter.setFont(font)
        painter.setPen(QColor("#FFFFFF") if is_selected else QColor("#A0C0FF"))
        
        if '.' in text:
            parts = text.rsplit('.', 1)
            name_part = parts[0]
            ext_part = '.' + parts[1]
            
            painter.drawText(QRect(text_x, y, w, h), Qt.AlignVCenter | Qt.AlignLeft, name_part)
            name_w = painter.fontMetrics().horizontalAdvance(name_part)
            
            painter.setPen(QColor("#4D94FF"))
            painter.drawText(QRect(text_x + name_w, y, w, h), Qt.AlignVCenter | Qt.AlignLeft, ext_part)
        else:
            painter.drawText(QRect(text_x, y, w, h), Qt.AlignVCenter | Qt.AlignLeft, text)

    def sizeHint(self, option, index):
        is_dir = True
        model = index.model()
        if hasattr(model, 'isDir'):
            is_dir = model.isDir(index)
            
        if is_dir:
            return QSize(250, 120)  # Enough space for the folder icon
        else:
            return QSize(250, 40)
