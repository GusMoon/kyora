from PySide6.QtWidgets import QStyledItemDelegate, QStyle
from PySide6.QtCore import Qt, QSize, QRect, QPoint
from PySide6.QtGui import QPainter, QColor, QPen, QPainterPath, QFont, QIcon
import math

class SidebarDelegate(QStyledItemDelegate):
    def __init__(self, show_arrow=False, enable_3d=False, parent=None):
        super().__init__(parent)
        self.show_arrow = show_arrow
        self.enable_3d = enable_3d

    def paint(self, painter, option, index):
        painter.save()
        painter.setRenderHint(QPainter.Antialiasing)
        
        rect = option.rect
        is_selected = option.state & QStyle.State_Selected
        is_hovered = option.state & QStyle.State_MouseOver
        
        # 3D Wheel effect
        widget = option.widget
        if widget and self.enable_3d:
            viewport_h = widget.height()
            center_y = rect.center().y()
            norm_y = center_y / viewport_h
            
            scale_xy = 1.0
            opacity = 1.0
            shift_x = 0.0
            edge_threshold = 0.05
            
            if norm_y < edge_threshold:
                falloff = (edge_threshold - norm_y) / edge_threshold
                scale_xy = max(0.9, 1.0 - (falloff * 0.1))
                opacity = max(0.6, 1.0 - (falloff * 0.4))
                shift_x = -falloff * 15.0
            elif norm_y > (1.0 - edge_threshold):
                falloff = (norm_y - (1.0 - edge_threshold)) / edge_threshold
                scale_xy = max(0.9, 1.0 - (falloff * 0.1))
                opacity = max(0.6, 1.0 - (falloff * 0.4))
                shift_x = -falloff * 15.0
                
            if scale_xy != 1.0 or opacity != 1.0 or shift_x != 0.0:
                painter.setOpacity(opacity)
                painter.translate(rect.center())
                painter.translate(shift_x, 0)
                painter.scale(scale_xy, scale_xy)
                painter.translate(-rect.center())
            
        primary_color = QColor("#FFB84D") if is_selected else QColor("#A0C0FF")
        glow_color = QColor("#0099FF")
        bg_color = QColor(0, 153, 255, 45 if is_selected else (15 if is_hovered else 0))
        border_color = QColor("#0099FF") if is_selected else QColor("#182533")
        
        margin = 2
        h_margin = 8
        
        if is_selected:
            h_margin += 12 # Desplazamiento a la derecha

        x = rect.x() + h_margin
        y = rect.y() + margin
        w = rect.width() - 32  # Ancho constante para permitir desplazamiento a la derecha
        h = rect.height() - margin * 2
        
        chamfer = 8
        poly = QPainterPath()
        poly.moveTo(x + chamfer, y)
        poly.lineTo(x + w, y)
        poly.lineTo(x + w, y + h)
        poly.lineTo(x, y + h)
        poly.lineTo(x, y + chamfer)
        poly.closeSubpath()
        
        # Background
        painter.setBrush(bg_color)
        painter.setPen(Qt.NoPen)
        painter.drawPath(poly)
        
        # Fondo sólido del lado derecho (no transparente)
        right_block_w = 12
        right_block_color = QColor("#0099FF") if is_selected else QColor("#182533")
        painter.setBrush(right_block_color)
        painter.drawRect(x + w - right_block_w, y, right_block_w, h)
        
        # Border
        pen = QPen(border_color, 2 if is_selected else 1)
        painter.setPen(pen)
        painter.setBrush(Qt.NoBrush)
        painter.drawPath(poly)
        
        # Número a la izquierda
        row_idx = str(index.row() + 1).zfill(2)
        num_font = QFont("Space Grotesk", 9)
        painter.setFont(num_font)
        painter.setPen(QColor("#FFB84D"))
        num_rect = QRect(x + chamfer, y, 22, h)
        painter.drawText(num_rect, Qt.AlignVCenter | Qt.AlignCenter, row_idx)
        
        arrow_size = 4
        arrow_x = x + chamfer + 28
        arrow_y = y + h // 2
        
        is_dir = True
        model = index.model()
        if hasattr(model, 'isDir'):
            is_dir = model.isDir(index)
        
        text_x = arrow_x
        if self.show_arrow and is_dir:
            arrow_path = QPainterPath()
            arrow_path.moveTo(arrow_x, arrow_y - arrow_size)
            arrow_path.lineTo(arrow_x + arrow_size, arrow_y)
            arrow_path.lineTo(arrow_x, arrow_y + arrow_size)
            arrow_path.closeSubpath()
            
            painter.setPen(Qt.NoPen)
            painter.setBrush(QColor("#FFB84D") if is_selected else QColor("#80BFFF"))
            painter.drawPath(arrow_path)
            text_x += arrow_size + 8
        elif not is_dir:
            icon = index.data(Qt.DecorationRole)
            if icon and isinstance(icon, QIcon):
                icon_rect = QRect(arrow_x, y + (h - 14) // 2, 14, 14)
                icon.paint(painter, icon_rect, Qt.AlignCenter, QIcon.Normal, QIcon.On)
                text_x += 14 + 8
        elif self.show_arrow:
            text_x += arrow_size + 8
            
        text = index.data(Qt.DisplayRole)
        
        font = QFont("Space Grotesk", 9, QFont.Bold if is_selected else QFont.Normal)
        font.setLetterSpacing(QFont.AbsoluteSpacing, 1)
        painter.setFont(font)
        painter.setPen(primary_color)
        text_rect = QRect(text_x, y, w - (text_x - x) - right_block_w - 5, h)
        painter.drawText(text_rect, Qt.AlignVCenter | Qt.AlignLeft, text)
        
        painter.restore()

    def sizeHint(self, option, index):
        return QSize(250, 36)
