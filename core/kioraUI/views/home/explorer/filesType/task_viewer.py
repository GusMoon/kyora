from PySide6.QtWidgets import (QWidget, QVBoxLayout, QHBoxLayout, QPushButton, 
                                 QLabel, QTextEdit, QTreeWidget, QTreeWidgetItem, QDateEdit, QInputDialog)
from PySide6.QtCore import Qt, QDate
from core.kioraUI.views.global_ui.viewer_base import SciFiViewerBase
from core.kioraUI.views.global_ui.styles import get_minimal_scrollbar_style
from core.kioraUI.views.global_ui.simple_dialogs import SciFiInputDialog, SciFiConfirmDialog
import re

class TaskViewerPanel(SciFiViewerBase):
    def __init__(self, parent=None):
        super().__init__(parent, "TASK VIEWER")
        self.resize(700, 600)
        
        self.current_path = ""
        
        self.main_container = QWidget()
        layout = QVBoxLayout(self.main_container)
        layout.setContentsMargins(10, 10, 10, 10)
        layout.setSpacing(10)
        
        # --- Dates ---
        dates_layout = QHBoxLayout()
        self.lbl_start = QLabel("Start Date:")
        self.lbl_start.setStyleSheet("color: #0099FF; font-family: 'Space Grotesk'; font-weight: bold;")
        self.date_start = QDateEdit(QDate.currentDate())
        self.date_start.setCalendarPopup(True)
        self._style_date_edit(self.date_start)
        
        self.lbl_end = QLabel("End Date:")
        self.lbl_end.setStyleSheet("color: #0099FF; font-family: 'Space Grotesk'; font-weight: bold;")
        self.date_end = QDateEdit(QDate.currentDate().addDays(7))
        self.date_end.setCalendarPopup(True)
        self._style_date_edit(self.date_end)
        
        dates_layout.addWidget(self.lbl_start)
        dates_layout.addWidget(self.date_start)
        dates_layout.addWidget(self.lbl_end)
        dates_layout.addWidget(self.date_end)
        dates_layout.addStretch()
        
        layout.addLayout(dates_layout)
        
        # --- Description ---
        self.lbl_desc = QLabel("Description:")
        self.lbl_desc.setStyleSheet("color: #0099FF; font-family: 'Space Grotesk'; font-weight: bold;")
        layout.addWidget(self.lbl_desc)
        
        self.desc_edit = QTextEdit()
        self.desc_edit.setMaximumHeight(80)
        self.desc_edit.setStyleSheet(get_minimal_scrollbar_style() + """
            QTextEdit {
                background-color: rgba(10, 17, 24, 0.95);
                color: #FFB84D;
                border: 1px solid #0099FF;
                padding: 5px;
                font-family: 'Space Grotesk';
                font-size: 13px;
            }
        """)
        layout.addWidget(self.desc_edit)
        
        # --- Tasks Tree ---
        self.lbl_tasks = QLabel("Tasks:")
        self.lbl_tasks.setStyleSheet("color: #0099FF; font-family: 'Space Grotesk'; font-weight: bold;")
        layout.addWidget(self.lbl_tasks)
        
        self.tree_tasks = QTreeWidget()
        self.tree_tasks.setHeaderHidden(True)
        self.tree_tasks.setStyleSheet(get_minimal_scrollbar_style() + """
            QTreeWidget {
                background-color: rgba(10, 17, 24, 0.95);
                color: #FFB84D;
                border: 1px solid #0099FF;
                font-family: 'Space Grotesk';
                font-size: 14px;
            }
            QTreeWidget::item { padding: 5px; }
            QTreeWidget::item:selected { background-color: rgba(0, 153, 255, 0.3); }
        """)
        layout.addWidget(self.tree_tasks)
        
        # --- Buttons ---
        btn_layout = QHBoxLayout()
        
        self.btn_add_task = QPushButton("+ ADD TASK")
        self._style_button(self.btn_add_task)
        self.btn_add_task.clicked.connect(self.add_task)
        
        self.btn_add_subtask = QPushButton("+ ADD SUBTASK")
        self._style_button(self.btn_add_subtask)
        self.btn_add_subtask.clicked.connect(self.add_subtask)
        
        self.btn_toggle_status = QPushButton("TOGGLE STATUS")
        self._style_button(self.btn_toggle_status)
        self.btn_toggle_status.clicked.connect(self.toggle_status)
        
        self.btn_save = QPushButton("SAVE")
        self._style_button(self.btn_save, primary=True)
        self.btn_save.clicked.connect(self.save_task)
        
        btn_layout.addWidget(self.btn_add_task)
        btn_layout.addWidget(self.btn_add_subtask)
        btn_layout.addWidget(self.btn_toggle_status)
        btn_layout.addStretch()
        btn_layout.addWidget(self.btn_save)
        
        layout.addLayout(btn_layout)
        
        self.set_body_widget(self.main_container)
        
        self.close_btn.setParent(self)
        self.close_btn.setStyleSheet("""
            QPushButton { background-color: rgba(22, 22, 22, 0.8); color: #FFB84D; font-weight: bold; border: 1px solid #0099FF; }
            QPushButton:hover { background-color: #0099FF; }
        """)
        self.close_btn.show()

    def _style_date_edit(self, widget):
        widget.setStyleSheet("""
            QDateEdit {
                background-color: #182533;
                color: #FFB84D;
                border: 1px solid #0099FF;
                padding: 4px;
                font-family: 'Space Grotesk';
            }
            QDateEdit::drop-down {
                border: none;
            }
        """)
        
    def _style_button(self, btn, primary=False):
        color = "#80BFFF" if primary else "#0099FF"
        bg_hover = "#0099FF" if primary else "rgba(0, 153, 255, 0.2)"
        text_hover = "#0A1118" if primary else "#FFB84D"
        
        btn.setStyleSheet(f"""
            QPushButton {{
                background-color: transparent;
                color: {color};
                border: 1px solid {color};
                padding: 6px 15px;
                font-family: 'Space Grotesk';
                font-weight: bold;
                font-size: 12px;
            }}
            QPushButton:hover {{
                background-color: {bg_hover};
                color: {text_hover};
            }}
        """)

    def load_task(self, path):
        self.current_path = path
        self.title_label.setText(f"TASK VIEWER: {path.replace('//', '/').split('/')[-1].upper()}")
        
        self.tree_tasks.clear()
        self.desc_edit.clear()
        self.date_start.setDate(QDate.currentDate())
        self.date_end.setDate(QDate.currentDate().addDays(7))
        
        try:
            with open(path, 'r', encoding='utf-8') as f:
                content = f.read()
            self._parse_markdown(content)
        except Exception as e:
            pass # if new file or error

    def _parse_markdown(self, content):
        lines = content.split('\n')
        
        in_desc = False
        desc_lines = []
        current_task = None
        
        for line in lines:
            line_s = line.strip()
            
            if line_s.startswith('Start Date:'):
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
            elif line_s == 'Tasks:':
                in_desc = False
            elif in_desc and line_s:
                desc_lines.append(line_s)
            elif not in_desc and '- [' in line:
                is_done = '- [x]' in line.lower()
                text = line.split(']', 1)[1].strip()
                
                # Check indent to see if it's subtask
                indent = len(line) - len(line.lstrip())
                
                item = QTreeWidgetItem([f"[{'X' if is_done else ' '}] {text}"])
                item.setData(0, Qt.UserRole, is_done)
                item.setData(0, Qt.UserRole + 1, text)
                
                if indent > 0 and current_task:
                    current_task.addChild(item)
                else:
                    self.tree_tasks.addTopLevelItem(item)
                    current_task = item
                    
        self.desc_edit.setPlainText('\n'.join(desc_lines))
        self.tree_tasks.expandAll()

    def _generate_markdown(self):
        lines = []
        lines.append(f"Start Date: {self.date_start.date().toString('yyyy-MM-dd')}")
        lines.append(f"End Date: {self.date_end.date().toString('yyyy-MM-dd')}")
        lines.append("")
        
        desc = self.desc_edit.toPlainText().strip()
        if desc:
            lines.append("Description:")
            lines.append(desc)
            lines.append("")
            
        lines.append("Tasks:")
        for i in range(self.tree_tasks.topLevelItemCount()):
            task_item = self.tree_tasks.topLevelItem(i)
            is_done = task_item.data(0, Qt.UserRole)
            text = task_item.data(0, Qt.UserRole + 1)
            mark = 'x' if is_done else ' '
            lines.append(f"- [{mark}] {text}")
            
            for j in range(task_item.childCount()):
                sub_item = task_item.child(j)
                sub_done = sub_item.data(0, Qt.UserRole)
                sub_text = sub_item.data(0, Qt.UserRole + 1)
                sub_mark = 'x' if sub_done else ' '
                lines.append(f"  - [{sub_mark}] {sub_text}")
                
        return '\n'.join(lines)

    def save_task(self):
        if not self.current_path: return
        try:
            with open(self.current_path, 'w', encoding='utf-8') as f:
                f.write(self._generate_markdown())
            
            # Show visual feedback
            self.btn_save.setText("SAVED!")
            self.btn_save.setStyleSheet("QPushButton { background-color: #00FF00; color: #000; border: none; padding: 6px 15px; font-weight: bold; }")
            from PySide6.QtCore import QTimer
            QTimer.singleShot(1000, lambda: (self.btn_save.setText("SAVE"), self._style_button(self.btn_save, True)))
        except Exception as e:
            pass

    def add_task(self):
        dialog = SciFiInputDialog(self, "ADD TASK", "Task name:")
        if dialog.exec() == dialog.Accepted:
            name = dialog.get_text()
            if name:
                item = QTreeWidgetItem([f"[ ] {name}"])
                item.setData(0, Qt.UserRole, False)
                item.setData(0, Qt.UserRole + 1, name)
                self.tree_tasks.addTopLevelItem(item)

    def add_subtask(self):
        selected = self.tree_tasks.currentItem()
        if not selected:
            return
            
        # If a subtask is selected, add to its parent
        if selected.parent():
            selected = selected.parent()
            
        dialog = SciFiInputDialog(self, "ADD SUBTASK", "Subtask name:")
        if dialog.exec() == dialog.Accepted:
            name = dialog.get_text()
            if name:
                item = QTreeWidgetItem([f"[ ] {name}"])
                item.setData(0, Qt.UserRole, False)
                item.setData(0, Qt.UserRole + 1, name)
                selected.addChild(item)
                selected.setExpanded(True)

    def toggle_status(self):
        selected = self.tree_tasks.currentItem()
        if not selected: return
        
        is_done = selected.data(0, Qt.UserRole)
        new_status = not is_done
        text = selected.data(0, Qt.UserRole + 1)
        
        selected.setData(0, Qt.UserRole, new_status)
        selected.setText(0, f"[{'X' if new_status else ' '}] {text}")

    def resizeEvent(self, event):
        super().resizeEvent(event)
        self.close_btn.move(self.width() - self.close_btn.width() - 5, 5)
        self.close_btn.raise_()
