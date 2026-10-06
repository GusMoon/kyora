import math
from PySide6.QtWidgets import QWidget, QVBoxLayout, QHBoxLayout, QLabel, QLineEdit, QPushButton, QGraphicsBlurEffect, QFrame, QAbstractButton
from PySide6.QtCore import Qt, QPoint, QSize
from PySide6.QtGui import QPainter, QColor, QBrush, QPen, QPolygon

class SciFiOverlayBase(QWidget):
    def __init__(self, parent_widget, widget_to_blur):
        super().__init__(parent_widget)
        self.widget_to_blur = widget_to_blur
        self.setGeometry(parent_widget.rect())
        
        self.blur = QGraphicsBlurEffect()
        self.blur.setBlurRadius(15)
        
        if hasattr(self.widget_to_blur, 'viewport'):
            self.actual_blur_target = self.widget_to_blur.viewport()
        else:
            self.actual_blur_target = self.widget_to_blur
            
        self.actual_blur_target.setGraphicsEffect(self.blur)
        
    def close_overlay(self):
        self.actual_blur_target.setGraphicsEffect(None)
        self.hide()
        self.deleteLater()
        
    def paintEvent(self, event):
        painter = QPainter(self)
        painter.fillRect(self.rect(), QColor(0, 0, 0, 160))

class HexButton(QAbstractButton):
    def __init__(self, action_type="", is_center=False, parent=None):
        super().__init__(parent)
        self.action_type = action_type
        self.is_center = is_center
        self.setFixedSize(90, 90) if is_center else self.setFixedSize(85, 85)
        self.hovered = False

    def enterEvent(self, event):
        self.hovered = True
        self.update()
        super().enterEvent(event)

    def leaveEvent(self, event):
        self.hovered = False
        self.update()
        super().leaveEvent(event)

    def paintEvent(self, event):
        from PySide6.QtCore import QPointF
        from PySide6.QtGui import QPolygonF
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)
        
        w = self.width()
        h = self.height()
        cx = w / 2
        cy = h / 2
        r = min(w, h) / 2 - 2
        
        # Pointy top hexagon
        pts = []
        for i in range(6):
            angle_deg = 60 * i + 30
            angle_rad = math.pi / 180 * angle_deg
            pts.append(QPointF(cx + r * math.cos(angle_rad), cy + r * math.sin(angle_rad)))
            
        C = QPointF(cx, cy)
        V0, V1, V2, V3, V4, V5 = pts[0], pts[1], pts[2], pts[3], pts[4], pts[5]
        
        face_top = QPolygonF([C, V3, V4, V5])
        face_left = QPolygonF([C, V1, V2, V3])
        face_right = QPolygonF([C, V5, V0, V1])
        
        if self.is_center:
            base_color = QColor("#80BFFF") if self.hovered else QColor("#182533")
            color_top = base_color.lighter(120)
            color_left = base_color
            color_right = base_color.darker(120)
        else:
            base_color = QColor("#4D94FF") if self.hovered else QColor("#060A0F")
            color_top = base_color.lighter(130) if self.hovered else QColor("#222222")
            color_left = base_color if self.hovered else QColor("#060A0F")
            color_right = base_color.darker(130) if self.hovered else QColor("#0A0A0A")
            
        painter.setPen(Qt.NoPen)
        painter.setBrush(QBrush(color_top))
        painter.drawPolygon(face_top)
        
        painter.setBrush(QBrush(color_left))
        painter.drawPolygon(face_left)
        
        painter.setBrush(QBrush(color_right))
        painter.drawPolygon(face_right)
        
        border_color = QColor("#FFFFFF") if self.hovered else QColor("#4D94FF")
        if not self.is_center and not self.hovered:
            border_color = QColor("#4A4A4A")
            
        painter.setPen(QPen(border_color, 1.5))
        poly = QPolygonF(pts)
        painter.drawPolygon(poly)
        painter.drawLine(C, V1)
        painter.drawLine(C, V3)
        painter.drawLine(C, V5)
        
        if self.is_center:
            icon_color = QColor("#FFFFFF") if self.hovered else QColor("#4D94FF")
            painter.setPen(QPen(icon_color, 1.5, Qt.SolidLine))
            painter.drawEllipse(C, 11, 11)
            painter.drawLine(C.x() - 5, C.y() - 5, C.x() + 5, C.y() + 5)
            painter.drawLine(C.x() + 5, C.y() - 5, C.x() - 5, C.y() + 5)
        else:
            painter.setBrush(QBrush(QColor(0,0,0, 120)))
            painter.setPen(Qt.NoPen)
            painter.drawEllipse(C, 22, 22)
            
            painter.translate(C)
            painter.setPen(QPen(QColor("#FFFFFF"), 2))
            painter.setBrush(Qt.NoBrush)
            
            if self.action_type == "new_folder":
                painter.drawRect(-10, -5, 20, 14)
                painter.drawLine(-10, -5, -5, -10)
                painter.drawLine(-5, -10, 2, -10)
                painter.drawLine(2, -10, 5, -5)
                painter.drawLine(-4, 2, 4, 2)
                painter.drawLine(0, -2, 0, 6)
            elif self.action_type == "new_file":
                painter.drawRect(-9, -10, 18, 20)
                painter.drawLine(4, -10, 9, -5)
                painter.drawLine(4, -10, 4, -5)
                painter.drawLine(4, -5, 9, -5)
                painter.drawLine(-4, 1, 4, 1)
                painter.drawLine(0, -3, 0, 5)
            elif self.action_type == "rename":
                painter.drawRect(-10, -7, 20, 14)
                painter.drawLine(-6, -2, 4, -2)
                painter.drawLine(-6, 2, -2, 2)
                painter.drawLine(6, -5, 6, 5)
            elif self.action_type == "delete":
                painter.drawRect(-6, -5, 12, 12)
                painter.drawLine(-9, -5, 9, -5)
                painter.drawLine(-4, -5, -4, -8)
                painter.drawLine(4, -5, 4, -8)
                painter.drawLine(-4, -8, 4, -8)
                painter.drawLine(-3, -1, -3, 4)
                painter.drawLine(3, -1, 3, 4)
            elif self.action_type == "copy":
                painter.drawRect(-8, -8, 11, 11)
                painter.drawRect(-3, -3, 11, 11)
            elif self.action_type == "edit":
                painter.drawLine(-8, 8, 5, -5)
                painter.drawLine(5, -5, 9, -1)
                painter.drawLine(9, -1, -4, 12)
                painter.drawLine(-4, 12, -8, 8)
            elif self.action_type == "save":
                painter.drawLine(-8, 0, -3, 5)
                painter.drawLine(-3, 5, 8, -8)
                
            painter.translate(-C)
            
            # Dibujar texto de la acción
            painter.setPen(QPen(QColor("#FFFFFF") if self.hovered else QColor("#CCCCCC"), 1))
            from PySide6.QtGui import QFont
            painter.setFont(QFont("Segoe UI", 7, QFont.Bold))
            text = self.action_type.replace("_", " ").upper()
            painter.drawText(int(C.x() - 40), int(C.y() + 30), 80, 15, Qt.AlignCenter, text)

class RadialContextMenu(SciFiOverlayBase):
    def __init__(self, parent_widget, widget_to_blur, center_pos, actions, on_action):
        super().__init__(parent_widget, widget_to_blur)
        
        # Override center_pos to always be the exact center of the parent
        center_pos = QPoint(parent_widget.width() // 2, parent_widget.height() // 2)
        
        self.on_action = on_action
        
        self.btn_cancel = HexButton(is_center=True, parent=self)
        self.btn_cancel.clicked.connect(self.close_overlay)
        
        self.buttons = []
        radius = 110
        
        if len(actions) == 4:
            angles_deg = [240, 300, 120, 60]
        elif len(actions) == 2:
            angles_deg = [180, 0]
        else:
            angle_step = 360 / len(actions) if actions else 1
            angles_deg = [i * angle_step - 90 for i in range(len(actions))]
            
        for i, action in enumerate(actions):
            btn = HexButton(action_type=action, parent=self)
            btn.clicked.connect(lambda checked, a=action: self.select_action(a))
            angle_rad = math.radians(angles_deg[i])
            x = center_pos.x() + radius * math.cos(angle_rad) - btn.width()/2
            y = center_pos.y() + radius * math.sin(angle_rad) - btn.height()/2
            
            x = max(10, min(x, self.width() - btn.width() - 10))
            y = max(10, min(y, self.height() - btn.height() - 10))
            btn.move(int(x), int(y))
            self.buttons.append((btn, center_pos))
            
        cx = max(10, min(center_pos.x() - self.btn_cancel.width()/2, self.width() - self.btn_cancel.width() - 10))
        cy = max(10, min(center_pos.y() - self.btn_cancel.height()/2, self.height() - self.btn_cancel.height() - 10))
        self.btn_cancel.move(int(cx), int(cy))
        self.center_btn_pos = QPoint(int(cx + self.btn_cancel.width()/2), int(cy + self.btn_cancel.height()/2))

    def select_action(self, action):
        self.close_overlay()
        self.on_action(action)
        
    def paintEvent(self, event):
        from PySide6.QtCore import QPointF
        super().paintEvent(event)
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)
        
        painter.setPen(QPen(QColor("#4A4A4A"), 1.5, Qt.SolidLine))
        for btn, _ in self.buttons:
            painter.drawLine(self.center_btn_pos, btn.geometry().center())
            
        painter.setPen(QPen(QColor("#FFFFFF"), 3, Qt.SolidLine))
        for btn, _ in self.buttons:
            cx, cy = self.center_btn_pos.x(), self.center_btn_pos.y()
            bx, by = btn.geometry().center().x(), btn.geometry().center().y()
            dx, dy = bx - cx, by - cy
            dist = math.hypot(dx, dy)
            if dist > 0:
                ux, uy = dx / dist, dy / dist
                p1 = QPointF(cx + ux * 28, cy + uy * 28)
                p2 = QPointF(cx + ux * 38, cy + uy * 38)
                painter.drawLine(p1, p2)
            
    def mousePressEvent(self, event):
        self.close_overlay()

class SciFiInputDialog(SciFiOverlayBase):
    def __init__(self, parent_widget, widget_to_blur, title, placeholder, default_text, on_accept):
        super().__init__(parent_widget, widget_to_blur)
        self.on_accept = on_accept
        
        layout = QVBoxLayout(self)
        layout.setAlignment(Qt.AlignCenter)
        
        box = QFrame()
        box.setFixedSize(300, 150)
        box.setStyleSheet("QFrame { background-color: rgba(22, 22, 22, 0.95); border: 2px solid #4D94FF; }")
        box_layout = QVBoxLayout(box)
        
        lbl = QLabel(title)
        lbl.setStyleSheet("color: #FFFFFF; font-family: 'Segoe UI'; font-weight: 800; letter-spacing: 1px; border: none; background: transparent;")
        
        self.input_field = QLineEdit(default_text)
        self.input_field.setPlaceholderText(placeholder)
        self.input_field.setStyleSheet("QLineEdit { background-color: #000000; color: #FFFFFF; border: 1px solid #80BFFF; padding: 8px; font-family: 'Consolas'; font-size: 12px; }")
        
        btn_layout = QHBoxLayout()
        btn_ok = QPushButton("CONFIRM")
        btn_cancel = QPushButton("CANCEL")
        btn_style = "QPushButton { background-color: #182533; color: #FFFFFF; font-weight: bold; border: 1px solid #4D94FF; padding: 6px; } QPushButton:hover { background-color: #4D94FF; }"
        btn_ok.setStyleSheet(btn_style)
        btn_cancel.setStyleSheet(btn_style)
        
        btn_ok.clicked.connect(self.accept)
        btn_cancel.clicked.connect(self.close_overlay)
        self.input_field.returnPressed.connect(self.accept)
        
        btn_layout.addWidget(btn_ok)
        btn_layout.addWidget(btn_cancel)
        
        box_layout.addWidget(lbl)
        box_layout.addWidget(self.input_field)
        box_layout.addLayout(btn_layout)
        
        layout.addWidget(box)
        self.input_field.setFocus()
        self.input_field.selectAll()

    def accept(self):
        text = self.input_field.text()
        self.close_overlay()
        self.on_accept(text)

class SciFiConfirmDialog(SciFiOverlayBase):
    def __init__(self, parent_widget, widget_to_blur, title, message, on_confirm):
        super().__init__(parent_widget, widget_to_blur)
        self.on_confirm = on_confirm
        
        layout = QVBoxLayout(self)
        layout.setAlignment(Qt.AlignCenter)
        
        box = QFrame()
        box.setFixedSize(300, 150)
        box.setStyleSheet("QFrame { background-color: rgba(22, 22, 22, 0.95); border: 2px solid #4D94FF; }")
        box_layout = QVBoxLayout(box)
        
        lbl = QLabel(title)
        lbl.setStyleSheet("color: #FFFFFF; font-family: 'Segoe UI'; font-weight: 800; letter-spacing: 1px; border: none; background: transparent;")
        
        msg = QLabel(message)
        msg.setWordWrap(True)
        msg.setStyleSheet("color: #CCCCCC; font-family: 'Segoe UI'; border: none; background: transparent;")
        
        btn_layout = QHBoxLayout()
        btn_ok = QPushButton("EXECUTE")
        btn_cancel = QPushButton("ABORT")
        btn_style = "QPushButton { background-color: #182533; color: #FFFFFF; font-weight: bold; border: 1px solid #4D94FF; padding: 6px; } QPushButton:hover { background-color: #4D94FF; }"
        btn_ok.setStyleSheet(btn_style)
        btn_cancel.setStyleSheet(btn_style)
        
        btn_ok.clicked.connect(self.confirm)
        btn_cancel.clicked.connect(self.close_overlay)
        
        btn_layout.addWidget(btn_ok)
        btn_layout.addWidget(btn_cancel)
        
        box_layout.addWidget(lbl)
        box_layout.addWidget(msg)
        box_layout.addLayout(btn_layout)
        
        layout.addWidget(box)

    def confirm(self):
        self.close_overlay()
        self.on_confirm()
