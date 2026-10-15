from PySide6.QtWidgets import (QWidget, QVBoxLayout, QHBoxLayout, QPushButton, 
                                 QLabel, QTextEdit, QDateEdit, QLineEdit, QScrollArea, QFrame)
from PySide6.QtCore import Qt, QDate, QPointF
from PySide6.QtGui import QPainter, QColor

from core.matrix.motherboard.globalComponents.viewer_base import SciFiViewerBase
from core.matrix.motherboard.globalComponents.styles import get_minimal_scrollbar_style
from core.resources.icons.target import draw as draw_target

class AutoResizeTextEdit(QTextEdit):
    def __init__(self, parent=None, min_height=30):
        super().__init__(parent)
        self.min_height_val = min_height
        self.textChanged.connect(self.adjust_height)
        self.setVerticalScrollBarPolicy(Qt.ScrollBarAlwaysOff)
        
    def adjust_height(self):
        # Prevent oscillation by only resizing if target height differs
        doc_height = self.document().size().height()
        margins = self.contentsMargins()
        h = int(doc_height + margins.top() + margins.bottom() + 10)
        h = max(h, self.min_height_val)
        
        if self.maximumHeight() != h:
            self.setMinimumHeight(h)
            self.setMaximumHeight(h)

class DynamicSubtaskWidget(QFrame):
    def __init__(self, title="", desc="", is_done=False, parent=None):
        super().__init__(parent)
        self.setStyleSheet("background-color: #242424; border: 1px solid #333; border-radius: 4px;")
        
        # Tamaño fijo para evitar saltos o comportamientos desagradables
        self.setFixedHeight(85)
        
        layout = QVBoxLayout(self)
        layout.setContentsMargins(10, 8, 10, 8)
        layout.setSpacing(5)
        
        top_layout = QHBoxLayout()
        self.checkbox = QPushButton("✔" if is_done else "")
        self.checkbox.setFixedSize(24, 24)
        self.checkbox.setCheckable(True)
        self.checkbox.setChecked(is_done)
        self.checkbox.clicked.connect(self._toggle_check)
        self._style_check()
        
        self.title_input = QLineEdit(title)
        self.title_input.setPlaceholderText("Subtask title...")
        self.title_input.setStyleSheet("background: transparent; color: #FFF; font-weight: bold; border: none; font-family: 'Prototype'; font-size: 14px;")
        
        self.btn_delete = QPushButton("✕")
        self.btn_delete.setFixedSize(24, 24)
        self.btn_delete.setStyleSheet("QPushButton { background: transparent; color: #888; border: none; font-weight: bold; } QPushButton:hover { color: #FFF; }")
        self.btn_delete.clicked.connect(self.deleteLater)
        
        top_layout.addWidget(self.checkbox)
        top_layout.addWidget(self.title_input)
        top_layout.addWidget(self.btn_delete)
        layout.addLayout(top_layout)
        
        self.desc_input = QTextEdit()
        self.desc_input.setPlaceholderText("Subtask description (optional)...")
        self.desc_input.setStyleSheet("""
            QTextEdit {
                background: transparent;
                color: #AAA;
                border: none;
                font-family: 'Prototype';
                font-size: 11px;
            }
        """)
        self.desc_input.setVerticalScrollBarPolicy(Qt.ScrollBarAsNeeded)
        if desc:
            self.desc_input.setPlainText(desc)
            
        layout.addWidget(self.desc_input)
        
    def _toggle_check(self):
        is_done = self.checkbox.isChecked()
        self.checkbox.setText("✔" if is_done else "")
        self._style_check()
        
    def _style_check(self):
        if self.checkbox.isChecked():
            self.checkbox.setStyleSheet("QPushButton { background-color: #444; color: #FFF; border: 1px solid #666; border-radius: 4px; }")
        else:
            self.checkbox.setStyleSheet("QPushButton { background-color: #1A1A1A; color: transparent; border: 1px solid #444; border-radius: 4px; }")

    def get_data(self):
        return {
            "title": self.title_input.text().strip(),
            "desc": self.desc_input.toPlainText().strip(),
            "is_done": self.checkbox.isChecked()
        }

from PySide6.QtCore import Signal

class TaskViewerPanel(SciFiViewerBase):
    task_saved = Signal()

    def __init__(self, parent=None):
        super().__init__(parent, "")
        self.resize(900, 650)
        
        self.current_path = ""
        self.status = "pending"
        
        self.main_container = QWidget()
        self.main_container.setStyleSheet("background-color: transparent;")
        
        main_layout = QVBoxLayout(self.main_container)
        main_layout.setContentsMargins(15, 15, 15, 15)
        main_layout.setSpacing(15)
        
        content_layout = QHBoxLayout()
        content_layout.setSpacing(20)
        
        # --- Left Column: Dates & Subtasks ---
        left_col = QWidget()
        left_layout = QVBoxLayout(left_col)
        left_layout.setContentsMargins(0, 0, 0, 0)
        left_layout.setSpacing(15)
        
        dates_widget = QWidget()
        dates_layout = QVBoxLayout(dates_widget)
        dates_layout.setContentsMargins(0, 0, 0, 0)
        
        self.lbl_start = QLabel("Start Date:")
        self.lbl_start.setStyleSheet("color: #FFFFFF; font-family: 'Prototype'; font-weight: bold;")
        self.date_start = QDateEdit(QDate.currentDate())
        self.date_start.setCalendarPopup(True)
        self._style_date_edit(self.date_start)
        
        self.lbl_end = QLabel("End Date:")
        self.lbl_end.setStyleSheet("color: #FFFFFF; font-family: 'Prototype'; font-weight: bold;")
        self.date_end = QDateEdit(QDate.currentDate().addDays(7))
        self.date_end.setCalendarPopup(True)
        self._style_date_edit(self.date_end)
        
        dates_row = QHBoxLayout()
        dates_row.addWidget(self.lbl_start)
        dates_row.addWidget(self.date_start)
        dates_row.addSpacing(15)
        dates_row.addWidget(self.lbl_end)
        dates_row.addWidget(self.date_end)
        dates_row.addStretch()
        dates_layout.addLayout(dates_row)
        
        left_layout.addWidget(dates_widget)
        
        # Subtasks
        subtasks_header = QHBoxLayout()
        self.lbl_tasks = QLabel("Subtasks:")
        self.lbl_tasks.setStyleSheet("color: #FFFFFF; font-family: 'Prototype'; font-weight: bold;")
        
        self.btn_add_subtask = QPushButton("+ ADD")
        self.btn_add_subtask.setStyleSheet("QPushButton { background: transparent; color: #888; font-weight: bold; border: 1px solid #444; border-radius: 4px; padding: 2px 10px; } QPushButton:hover { color: #FFF; background: #333; }")
        self.btn_add_subtask.clicked.connect(lambda: self._add_subtask_widget())
        
        subtasks_header.addWidget(self.lbl_tasks)
        subtasks_header.addWidget(self.btn_add_subtask)
        subtasks_header.addStretch()
        left_layout.addLayout(subtasks_header)
        
        self.subtasks_scroll = QScrollArea()
        self.subtasks_scroll.setWidgetResizable(True)
        self.subtasks_scroll.setStyleSheet(get_minimal_scrollbar_style() + "QScrollArea { border: none; background: transparent; }")
        
        self.subtasks_container = QWidget()
        self.subtasks_container.setStyleSheet("background: transparent;")
        self.subtasks_layout = QVBoxLayout(self.subtasks_container)
        self.subtasks_layout.setContentsMargins(0, 0, 10, 0)
        self.subtasks_layout.setSpacing(10)
        self.subtasks_layout.setAlignment(Qt.AlignTop)
        
        self.subtasks_scroll.setWidget(self.subtasks_container)
        left_layout.addWidget(self.subtasks_scroll)
        
        # --- Right Column: Description ---
        right_col = QWidget()
        right_layout = QVBoxLayout(right_col)
        right_layout.setContentsMargins(0, 0, 0, 0)
        
        self.lbl_desc = QLabel("Description:")
        self.lbl_desc.setStyleSheet("color: #FFFFFF; font-family: 'Prototype'; font-weight: bold;")
        
        self.desc_edit = QTextEdit()
        self.desc_edit.setStyleSheet(get_minimal_scrollbar_style() + """
            QTextEdit {
                background-color: #1A1A1A;
                color: #FFFFFF;
                border: 1px solid #444444;
                padding: 10px;
                font-family: 'Prototype';
                font-size: 13px;
                border-radius: 4px;
            }
        """)
        
        right_layout.addWidget(self.lbl_desc)
        right_layout.addWidget(self.desc_edit)
        
        content_layout.addWidget(left_col, 1)  # Proportion 1
        content_layout.addWidget(right_col, 1) # Proportion 1 (Equal width, or 50/50)
        
        main_layout.addLayout(content_layout)
        
        # --- Buttons ---
        btn_layout = QHBoxLayout()
        btn_layout.addStretch()
        
        self.btn_save = QPushButton("SAVE")
        self.btn_save.setStyleSheet("""
            QPushButton { 
                background-color: #A31F34; 
                color: #FFFFFF; 
                border: none; 
                padding: 10px 25px; 
                font-family: 'Prototype';
                font-weight: bold; 
                border-radius: 4px;
            }
            QPushButton:hover { background-color: #B9263D; }
        """)
        self.btn_save.clicked.connect(self.save_task)
        btn_layout.addWidget(self.btn_save)
        
        main_layout.addLayout(btn_layout)
        
        self.set_body_widget(self.main_container)

    def _style_date_edit(self, widget):
        widget.setStyleSheet("""
            QDateEdit {
                background-color: #1A1A1A;
                color: #FFFFFF;
                border: 1px solid #444444;
                padding: 6px;
                font-family: 'Prototype';
                border-radius: 4px;
            }
            QDateEdit::drop-down {
                border: none;
            }
        """)

    def _add_subtask_widget(self, title="", desc="", is_done=False):
        widget = DynamicSubtaskWidget(title, desc, is_done)
        self.subtasks_layout.addWidget(widget)

    def load_task(self, path):
        self.current_path = path
        
        import os
        filename = os.path.basename(path).replace(".task", "")
        self.set_title(filename)
        
        self.desc_edit.clear()
        self.date_start.setDate(QDate.currentDate())
        self.date_end.setDate(QDate.currentDate().addDays(7))
        self.status = "pending"
        
        while self.subtasks_layout.count():
            child = self.subtasks_layout.takeAt(0)
            if child.widget():
                child.widget().deleteLater()
        
        try:
            with open(path, 'r', encoding='utf-8') as f:
                content = f.read()
            self._parse_markdown(content)
        except Exception as e:
            pass

    def _parse_markdown(self, content):
        lines = content.split('\n')
        
        in_desc = False
        in_tasks = False
        desc_lines = []
        
        current_subtask_title = ""
        current_subtask_is_done = False
        current_subtask_desc_lines = []
        
        def commit_subtask():
            if current_subtask_title:
                self._add_subtask_widget(
                    current_subtask_title, 
                    "\n".join(current_subtask_desc_lines).strip(), 
                    current_subtask_is_done
                )

        for line in lines:
            line_s = line.strip()
            
            if line_s.startswith('Status:'):
                self.status = line_s.replace('Status:', '').strip()
            elif line_s.startswith('Start Date:'):
                try:
                    d_str = line_s.replace('Start Date:', '').strip()
                    self.date_start.setDate(QDate.fromString(d_str, "yyyy-MM-dd"))
                except: pass
            elif line_s.startswith('End Date:'):
                try:
                    d_str = line_s.replace('End Date:', '').strip()
                    self.date_end.setDate(QDate.fromString(d_str, "yyyy-MM-dd"))
                except: pass
            elif line_s == 'Description:':
                in_desc = True
                in_tasks = False
            elif line_s == 'Tasks:':
                in_desc = False
                in_tasks = True
            elif in_desc:
                desc_lines.append(line_s)
            elif in_tasks:
                if line_s.startswith("- ["):
                    commit_subtask()
                    current_subtask_is_done = "- [x]" in line_s.lower()
                    current_subtask_title = line_s.split("]", 1)[1].strip()
                    current_subtask_desc_lines = []
                else:
                    if current_subtask_title and line_s:
                        current_subtask_desc_lines.append(line_s)
                    elif current_subtask_title and not line_s:
                        current_subtask_desc_lines.append("")
        
        commit_subtask()
        self.desc_edit.setPlainText('\n'.join(desc_lines).strip())
        self.desc_edit.adjust_height()

    def _generate_markdown(self):
        lines = []
        lines.append(f"Status: {self.status}")
        lines.append(f"Start Date: {self.date_start.date().toString('yyyy-MM-dd')}")
        lines.append(f"End Date: {self.date_end.date().toString('yyyy-MM-dd')}")
        lines.append("")
        
        desc = self.desc_edit.toPlainText().strip()
        if desc:
            lines.append("Description:")
            lines.append(desc)
            lines.append("")
            
        lines.append("Tasks:")
        for i in range(self.subtasks_layout.count()):
            widget = self.subtasks_layout.itemAt(i).widget()
            if isinstance(widget, DynamicSubtaskWidget):
                data = widget.get_data()
                mark = "x" if data["is_done"] else " "
                lines.append(f"- [{mark}] {data['title']}")
                if data["desc"]:
                    for d_line in data["desc"].split('\n'):
                        lines.append(f"  {d_line}")
                
        return '\n'.join(lines)

    def save_task(self):
        if not self.current_path: return
        try:
            with open(self.current_path, 'w', encoding='utf-8') as f:
                f.write(self._generate_markdown())
            
            self.task_saved.emit()
            
            self.btn_save.setText("SAVED!")
            self.btn_save.setStyleSheet("""
                QPushButton { background-color: #1F3A24; color: #52B788; border: none; padding: 10px 25px; font-weight: bold; border-radius: 4px; }
            """)
            from PySide6.QtCore import QTimer
            QTimer.singleShot(1000, lambda: (self.btn_save.setText("SAVE"), self.btn_save.setStyleSheet("""
                QPushButton { background-color: #A31F34; color: #FFFFFF; border: none; padding: 10px 25px; font-weight: bold; border-radius: 4px; }
                QPushButton:hover { background-color: #B9263D; }
            """)))
        except Exception as e:
            pass
