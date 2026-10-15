from PySide6.QtWidgets import QMainWindow, QWidget, QPushButton, QVBoxLayout, QHBoxLayout, QGridLayout, QSpacerItem, QSizePolicy, QLabel
from PySide6.QtCore import Qt
from PySide6.QtGui import QPainter, QColor, QPen

# Componentes
from core.matrix.motherboard.ecosystems.configuration import ConfigurationPanel
from core.matrix.motherboard.ecosystems.explorer.treeFiles import ExplorerPanel
from core.matrix.motherboard.ecosystems.youtube_music import YoutubeMusicPanel
from core.matrix.motherboard.ecosystems.explorer.filesType.image_viewer import ImageViewerPanel
from core.matrix.motherboard.ecosystems.explorer.filesType.audio_viewer import AudioPlayerWidget
from core.matrix.motherboard.ecosystems.explorer.filesType.text_viewer import TextViewerPanel
from core.matrix.motherboard.ecosystems.explorer.filesType.pdf_viewer import PdfViewerPanel
from core.matrix.motherboard.ecosystems.explorer.filesType.task_viewer import TaskViewerPanel
from core.matrix.motherboard.rootComponents.launcher import EcosystemLauncher

# Tareas
from core.matrix.motherboard.ecosystems.tasks.infrastructure.sqlite_task_repository import SqliteTaskRepository
from core.matrix.motherboard.ecosystems.tasks.use_cases.manage_tasks import TaskUseCases
from core.matrix.motherboard.ecosystems.tasks.presentation.tasks_viewmodel import TasksViewModel
from core.matrix.motherboard.ecosystems.tasks.presentation.tasks_view import TasksView

# Bitácora
from core.matrix.motherboard.ecosystems.logbook.infrastructure.sqlite_logbook_repository import SqliteLogbookRepository
from core.matrix.motherboard.ecosystems.logbook.use_cases.manage_logbook import LogbookUseCases
from core.matrix.motherboard.ecosystems.logbook.presentation.logbook_viewmodel import LogbookViewModel
from core.matrix.motherboard.ecosystems.logbook.presentation.logbook_view import LogbookView

# Calendario
from core.matrix.motherboard.ecosystems.calendar.infrastructure.sqlite_calendar_repository import SqliteCalendarRepository
from core.matrix.motherboard.ecosystems.calendar.infrastructure.tasks_adapter import TasksEcosystemAdapter
from core.matrix.motherboard.ecosystems.calendar.use_cases.manage_calendar import CalendarUseCases
from core.matrix.motherboard.ecosystems.calendar.presentation.calendar_viewmodel import CalendarViewModel
from core.matrix.motherboard.ecosystems.calendar.presentation.calendar_view import CalendarView
from core.matrix.motherboard.ecosystems.calendar.presentation.rootComponents.reminder_banner import ReminderBanner

class MainWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        
        self.setWindowTitle("Kiora")
        self.setWindowFlag(Qt.FramelessWindowHint)
        
        self.central_widget = QWidget()
        self.setCentralWidget(self.central_widget)
        
        self.setup_ui()
        
        # Instanciar paneles externos
        self.settings_panel = ConfigurationPanel(self.central_widget)
        self.settings_panel.hide()
        
        self.explorer_panel = ExplorerPanel(self.central_widget)
        self.explorer_panel.hide()
        self.explorer_panel.move(0, 0) # Fixed position left, touching top border
        self.explorer_panel.file_opened.connect(self.handle_file_opened)
        
        self.youtube_panel = YoutubeMusicPanel(self.central_widget)
        self.youtube_panel.hide()
        
        # Instanciar visores de archivos
        self.image_viewer = ImageViewerPanel(self.central_widget)
        self.image_viewer.hide()
        
        self.audio_player = AudioPlayerWidget(self.central_widget)
        self.audio_player.hide()
        self.audio_player.song_changed.connect(self.explorer_panel.highlight_file)
        
        self.text_viewer = TextViewerPanel(self.central_widget)
        self.text_viewer.hide()
        
        self.pdf_viewer = PdfViewerPanel(self.central_widget)
        self.pdf_viewer.hide()
        
        self.task_viewer = TaskViewerPanel(self.central_widget)
        self.task_viewer.hide()
        
        self.launcher_panel = EcosystemLauncher(self.central_widget)
        self.launcher_panel.hide()
        self.launcher_panel.ecosystem_selected.connect(self.handle_nav_selection)
        
        # Instanciar Ecosistema de Tareas (MVVM)
        import os
        config_path = os.path.join(os.path.dirname(os.path.dirname(__file__)), "global_config.json")
        self.task_repo = SqliteTaskRepository(config_path)
        self.task_use_cases = TaskUseCases(self.task_repo)
        self.tasks_viewmodel = TasksViewModel(self.task_use_cases)
        self.tasks_main_view = TasksView(self.tasks_viewmodel, self.central_widget)
        self.tasks_main_view.hide()
        self.tasks_viewmodel.load_tasks()
        self.tasks_main_view.open_task_requested.connect(self.handle_file_opened)
        self.task_viewer.task_saved.connect(self._handle_task_viewer_saved)

        # Instanciar Ecosistema de Bitácora (MVVM)
        self.logbook_repo = SqliteLogbookRepository()
        self.logbook_use_cases = LogbookUseCases(self.logbook_repo)
        self.logbook_viewmodel = LogbookViewModel(self.logbook_use_cases)
        self.logbook_view = LogbookView(self.logbook_viewmodel, self.central_widget)
        self.logbook_view.hide()

        # Instanciar Ecosistema de Calendario (MVVM). Lee las tareas en solo lectura.
        self.calendar_repo = SqliteCalendarRepository()
        self.calendar_use_cases = CalendarUseCases(
            self.calendar_repo, TasksEcosystemAdapter(self.task_repo))
        self.calendar_viewmodel = CalendarViewModel(self.calendar_use_cases)
        self.calendar_view = CalendarView(self.calendar_viewmodel, self.central_widget)
        self.calendar_view.hide()
        self.calendar_view.open_task_requested.connect(self._open_task_from_calendar)
        self.reminder_banner = ReminderBanner(self.central_widget)
        self.calendar_viewmodel.reminder_due.connect(self.reminder_banner.push)

        self.handle_nav_selection("HOME")
        self.showMaximized()

    def setup_ui(self):
        main_layout = QVBoxLayout(self.central_widget)
        main_layout.setContentsMargins(0, 0, 0, 0)
        
        # --- TOP LAYOUT ---
        top_container = QWidget()
        top_layout = QHBoxLayout(top_container)
        top_layout.setContentsMargins(0, 15, 15, 0) # Casi tocando el borde superior derecho
        top_layout.addStretch()

        main_layout.addWidget(top_container)
        main_layout.addStretch()

    def _open_task_from_calendar(self, task_id):
        """Abre en el ecosistema de Tareas el detalle de la tarea elegida en el calendario."""
        self.handle_nav_selection("TASKS")
        self.tasks_main_view.open_task_detail(task_id)

    def handle_nav_selection(self, option):
        self.settings_panel.hide()
        self.explorer_panel.hide()
        self.youtube_panel.hide()
        self.launcher_panel.hide()
        self.tasks_main_view.hide()
        self.logbook_view.hide()
        self.calendar_view.hide()
        
        if option == "EXPLORER":
            self.explorer_panel.show()
            self.explorer_panel.raise_()
        elif option == "MUSIC":
            self.youtube_panel.show()
            self.youtube_panel.raise_()
        elif option == "CONFIG":
            self.settings_panel.show()
            self.settings_panel.raise_()
        elif option == "TASKS":
            self.tasks_main_view.show()
            self.tasks_main_view.raise_()
            self.tasks_viewmodel.load_tasks()
        elif option == "CALENDAR":
            self.calendar_view.show()
            self.calendar_view.raise_()
            self.calendar_view.go_to_today()
        elif option == "LOGBOOK":
            self.logbook_view.show()
            self.logbook_view.raise_()
            self.logbook_view.open_today()
        elif option == "HOME":
            self.launcher_panel.show()
            self.launcher_panel.raise_()

    def resizeEvent(self, event):
        super().resizeEvent(event)
        
        if hasattr(self, 'launcher_panel') and self.launcher_panel:
            self.launcher_panel.resize(self.width(), self.height())
            self.launcher_panel.move(0, 0)
            
        if hasattr(self, 'tasks_main_view') and self.tasks_main_view:
            self.tasks_main_view.resize(self.width(), self.height())
            self.tasks_main_view.move(0, 0)

        if hasattr(self, 'logbook_view') and self.logbook_view:
            self.logbook_view.resize(self.width(), self.height())
            self.logbook_view.move(0, 0)

        if hasattr(self, 'calendar_view') and self.calendar_view:
            self.calendar_view.resize(self.width(), self.height())
            self.calendar_view.move(0, 0)

        if hasattr(self, 'reminder_banner') and self.reminder_banner:
            self.reminder_banner.move(max(0, (self.width() - self.reminder_banner.width()) // 2), 20)
            
        if hasattr(self, 'explorer_panel') and self.explorer_panel:
            self.explorer_panel.resize(int(self.width() * 0.6), self.height() - 50)
            
        if hasattr(self, 'youtube_panel') and self.youtube_panel:
            self.youtube_panel.resize(int(self.width() * 0.6), self.height() - 50)
            self.youtube_panel.move(0, 0)

        # Centrar paneles de manera individual si no los ha movido el usuario
        for panel in [getattr(self, 'settings_panel', None), 
                      getattr(self, 'image_viewer', None), getattr(self, 'text_viewer', None),
                      getattr(self, 'pdf_viewer', None), getattr(self, 'task_viewer', None)]:
            if panel and not getattr(panel, 'user_moved', False):
                x = (self.width() - panel.width()) // 2
                y = (self.height() - panel.height()) // 2
                panel.move(x, y)
                
        if hasattr(self, 'audio_player') and self.audio_player:
            self.audio_player.move(20, self.height() - self.audio_player.height() - 20)
                
    def handle_file_opened(self, path):
        ext = path.split('.')[-1].lower() if '.' in path else ''
        
        image_exts = ['png', 'jpg', 'jpeg', 'gif', 'bmp', 'webp']
        audio_exts = ['mp3', 'wav', 'ogg', 'flac']
        pdf_exts = ['pdf']
        
        if ext == 'task':
            self.task_viewer.load_task(path)
            self.task_viewer.show()
            self.task_viewer.raise_()
        elif ext in image_exts:
            self.image_viewer.load_image(path)
            self.image_viewer.show()
            self.image_viewer.raise_()
        elif ext in audio_exts:
            self.audio_player.load_audio(path)
            self.audio_player.show()
            self.audio_player.raise_()
            self.audio_player.move(self.width() - self.audio_player.width() - 20, self.height() - self.audio_player.height() - 20)
        elif ext in pdf_exts:
            self.pdf_viewer.load_pdf(path)
            self.pdf_viewer.show()
            self.pdf_viewer.raise_()
        else:
            # Fallback a texto para codigo y otros archivos (incluyendo docx)
            self.text_viewer.load_text(path)
            self.text_viewer.show()
            self.text_viewer.raise_()

    def _handle_task_viewer_saved(self):
        """Sincroniza la tarea editada en el visor con la base de datos SQLite y recarga el board."""
        path = getattr(self.task_viewer, 'current_path', '')
        if path and os.path.exists(path):
            try:
                task_id = os.path.basename(path).replace(".task", "")
                with open(path, 'r', encoding='utf-8') as f:
                    content = f.read()
                from core.matrix.motherboard.ecosystems.tasks.domain.entities import Task
                task = Task.from_markdown(content, task_id)
                self.task_repo.save_task(task)
                self.tasks_viewmodel.load_tasks()
            except Exception as e:
                print(f"Error sincronizando tarea desde visor a SQLite: {e}")

    def paintEvent(self, event):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)
        
        # 1. Base Background
        bg_color = QColor("#121212") 
        painter.fillRect(self.rect(), bg_color)
        
        painter.end()
