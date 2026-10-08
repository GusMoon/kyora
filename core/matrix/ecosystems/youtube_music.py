from PySide6.QtWidgets import (QListWidget, QVBoxLayout, QLineEdit, QPushButton, 
                               QHBoxLayout, QLabel, QStackedWidget, QWidget, QScrollArea, QGridLayout, QSizePolicy, QTabWidget)
from PySide6.QtCore import Qt, QThread, Signal
from PySide6.QtGui import QPainter, QColor, QPen
from core.matrix.ecosystems.motherBoard.base_container import KioraBaseContainer
from core.matrix.ecosystems.motherBoard.styles import get_minimal_scrollbar_style
from core.matrix.ecosystems.explorer.filesType.text_viewer import TextViewerPanel
from core.ecosystems.music.mp3installer import MP3InstallerEcosystem, get_js_runtime_opts
import yt_dlp
import json
import os
import time
import re
from pathlib import Path

# --- THREADS ---

class FetchPlaylistThread(QThread):
    finished = Signal(list)
    error = Signal(str)

    def __init__(self, url, browser_val):
        super().__init__()
        self.url = url
        self.browser_val = browser_val

    def run(self):
        try:
            ydl_opts = {
                'extract_flat': True,
                'quiet': True,
                **get_js_runtime_opts(),
            }
            if self.browser_val.endswith('.txt'):
                ydl_opts['cookiefile'] = self.browser_val
            else:
                ydl_opts['cookiesfrombrowser'] = (self.browser_val, )

            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                info = ydl.extract_info(self.url, download=False)
                items = []
                if 'entries' in info:
                    for entry in info['entries']:
                        if entry:
                            title = entry.get('title', 'Unknown')
                            url = entry.get('url', '')
                            items.append({'title': title, 'url': url})
                elif 'title' in info:
                    items.append({'title': info.get('title', 'Unknown'), 'url': info.get('webpage_url', self.url)})
                self.finished.emit(items)
        except Exception as e:
            self.error.emit(str(e))


class DownloadSequentialThread(QThread):
    progress = Signal(int, str) # index, status (DOWNLOADING, INSTALLED, ERROR)
    finished = Signal()
    
    def __init__(self, songs):
        super().__init__()
        self.songs = songs  # lista de (indice_widget, url)
        self.installer = MP3InstallerEcosystem()
        self.is_running = True

    def run(self):
        for n, (i, url) in enumerate(self.songs):
            if not self.is_running:
                break
            
            self.current_index = i
            self.progress.emit(i, "DOWNLOADING")
            success = self.installer.download_song(url, progress_hook=self._progress_hook)
            
            if success:
                self.progress.emit(i, "INSTALLED")
            else:
                self.progress.emit(i, "ERROR")
            
            if n < len(self.songs) - 1 and self.is_running:
                time.sleep(2) # Pausa manual para no saturar
                
        self.finished.emit()
        
    def _progress_hook(self, d):
        if not self.is_running:
            raise Exception("Download cancelled by user")
        if d['status'] == 'downloading':
            percent_str = d.get('_percent_str', '').strip()
            percent_str = re.sub(r'\x1b\[[0-9;]*m', '', percent_str)
            self.progress.emit(self.current_index, f"DOWNLOADING {percent_str}")
        
    def stop(self):
        self.is_running = False

# --- WIDGETS PERSONALIZADOS SCI-FI ---

class SciFiCard(QPushButton):
    def __init__(self, index, title, url):
        super().__init__()
        self.url = url
        self.title = title
        
        idx_str = f"{index:03d}"
        
        self.setStyleSheet("""
            QPushButton {
                background-color: rgba(10, 17, 24, 0.8);
                border: 1px solid #0099FF;
                border-top: 3px solid #0099FF;
                border-bottom: 1px solid #0099FF;
                color: #80BFFF;
                text-align: left;
                font-family: 'Space Grotesk', sans-serif;
            }
            QPushButton:hover {
                background-color: rgba(0, 153, 255, 0.2);
                border: 1px solid #80BFFF;
                border-top: 3px solid #80BFFF;
            }
        """)
        self.setFixedSize(140, 140)
        
        layout = QVBoxLayout(self)
        layout.setContentsMargins(10, 10, 10, 10)
        
        mode_label = QLabel("MODE A")
        mode_label.setStyleSheet("color: #0099FF; font-size: 10px; font-weight: bold; border: none; background: transparent;")
        
        num_label = QLabel(idx_str)
        num_label.setStyleSheet("color: #e0fbfc; font-size: 32px; font-weight: 300; border: none; background: transparent;")
        
        title_label = QLabel(title)
        title_label.setWordWrap(True)
        title_label.setStyleSheet("color: #a4a4a4; font-size: 11px; border: none; background: transparent;")
        
        layout.addWidget(mode_label)
        layout.addWidget(num_label)
        layout.addStretch()
        layout.addWidget(title_label)


class SongItem(QWidget):
    def __init__(self, index, title, url, status="NOT_INSTALLED"):
        super().__init__()
        self.url = url
        self.title = title
        self.status = status
        
        self.layout = QHBoxLayout(self)
        self.layout.setContentsMargins(10, 8, 10, 8)
        
        self.idx_label = QLabel(f"{index:03d}")
        self.idx_label.setFixedWidth(30)
        self.idx_label.setStyleSheet("font-family: 'Space Grotesk', sans-serif;")
        
        self.dl_btn = QPushButton("↓")
        self.dl_btn.setFixedSize(50, 20)
        self.dl_btn.setCursor(Qt.PointingHandCursor)
        
        self.title_label = QLabel(title)
        self.title_label.setStyleSheet("font-family: 'Space Grotesk', sans-serif; font-size: 12px;")
        
        self.status_label = QLabel()
        self.status_label.setFixedWidth(100)
        self.status_label.setAlignment(Qt.AlignRight | Qt.AlignVCenter)
        self.status_label.setStyleSheet("font-family: 'Space Grotesk', sans-serif; font-size: 10px; font-weight: bold;")
        
        self.layout.addWidget(self.idx_label)
        self.layout.addWidget(self.dl_btn)
        self.layout.addSpacing(10)
        self.layout.addWidget(self.title_label)
        self.layout.addStretch()
        self.layout.addWidget(self.status_label)
        
        self.update_style()
        
    def set_status(self, status):
        self.status = status
        self.update_style()
        
    def update_style(self):
        if self.status == "NOT_INSTALLED":
            color = "#555555" # Gris
            txt = ""
            self.dl_btn.setEnabled(True)
            self.dl_btn.setText("↓")
        elif self.status.startswith("DOWNLOADING"):
            color = "#f2c94c" # Amarillo
            txt = "DOWNLOADING..."
            self.dl_btn.setEnabled(False)
            if " " in self.status:
                percent = self.status.split(" ", 1)[1]
                self.dl_btn.setText(percent)
            else:
                self.dl_btn.setText("...")
        elif self.status == "INSTALLED":
            color = "#0099FF" # Azul
            txt = "INSTALLED"
            self.dl_btn.setEnabled(False)
            self.dl_btn.setText("✓")
        else: # ERROR
            color = "#eb5757" # Rojo
            txt = "FAILED"
            self.dl_btn.setEnabled(True)
            self.dl_btn.setText("↻")
            
        self.idx_label.setStyleSheet(f"color: {color}; font-weight: bold;")
        self.title_label.setStyleSheet(f"color: {color};")
        self.status_label.setStyleSheet(f"color: {color};")
        self.status_label.setText(txt)
        
        self.setStyleSheet("") # Quitar el borde punteado
        self.dl_btn.setStyleSheet(f"""
            QPushButton {{ background-color: transparent; border: 1px solid {color}; color: {color}; border-radius: 10px; font-weight: bold; font-size: 10px; }}
            QPushButton:hover {{ background-color: {color}33; }}
        """)

# --- PANEL PRINCIPAL ---

class YoutubeMusicPanel(KioraBaseContainer):
    def __init__(self, parent=None):
        super().__init__(title_text="YOUTUBE DB SCANNER", parent=parent)
        self.resize(500, 600)
        
        self.config_path = Path(__file__).parent.parent.parent.parent / "ecosystems" / "music" / "mp3installer_config.json"
        
        # Pestañas principales
        self.tabs = QTabWidget()
        self.tabs.setStyleSheet("""
            QTabWidget::pane { border: 1px solid #0099FF; background: transparent; }
            QTabBar::tab { background: #0A1118; color: #a4a4a4; padding: 8px 20px; border: 1px solid #0099FF; font-family: 'Space Grotesk', sans-serif; }
            QTabBar::tab:selected { background: #0099FF; color: #FFB84D; font-weight: bold; }
        """)
        self.body_layout.addWidget(self.tabs)
        
        # Tab 1: Explorador (Usa StackedWidget internamente para Grid y Songs)
        self.explorer_tab = QWidget()
        self.explorer_layout = QVBoxLayout(self.explorer_tab)
        self.stacked_widget = QStackedWidget()
        self.explorer_layout.addWidget(self.stacked_widget)
        self.explorer_layout.setContentsMargins(0, 0, 0, 0)
        self.tabs.addTab(self.explorer_tab, "Explorador de Playlists")
        
        # Tab 2: Configuración
        self.config_tab = QWidget()
        self.setup_config_view(self.config_tab)
        self.tabs.addTab(self.config_tab, "Configuración")
        
        self.setup_grid_view()
        self.setup_songs_view()
        
        self.thread = None
        self.dl_thread = None
        self.text_viewer = None
        
        self.load_global_config()

    def load_global_config(self):
        if self.config_path.exists():
            try:
                with open(self.config_path, 'r', encoding='utf-8') as f:
                    self.cfg = json.load(f)
                    self.base_url_input.setText(self.cfg.get("base_url", ""))
                    self.cookies_input.setText(self.cfg.get("browser_for_cookies", "chrome"))
                    
                    if self.cfg.get("base_url"):
                        self.tabs.setCurrentIndex(0)
                        self.stacked_widget.setCurrentIndex(0)
                        self.load_base_playlists()
            except Exception:
                self.cfg = {}
        else:
            self.cfg = {}

    def save_config(self):
        self.cfg["base_url"] = self.base_url_input.text().strip()
        self.cfg["browser_for_cookies"] = self.cookies_input.text().strip()
        
        self.config_path.parent.mkdir(parents=True, exist_ok=True)
        with open(self.config_path, 'w', encoding='utf-8') as f:
            json.dump(self.cfg, f, indent=4)
            
        self.tabs.setCurrentIndex(0)
        self.stacked_widget.setCurrentIndex(0)
        self.load_base_playlists()

    # --- VIEWS SETUP ---

    def setup_config_view(self, view):
        layout = QVBoxLayout(view)
        
        label1 = QLabel("BASE URL (Tu canal o Feed de Playlists)")
        label1.setStyleSheet("color: #0099FF; font-family: 'Space Grotesk', sans-serif;")
        self.base_url_input = QLineEdit()
        self.base_url_input.setStyleSheet("background: #0A1118; color: #FFB84D; border: 1px solid #0099FF; padding: 5px;")
        
        label2 = QLabel("COOKIES (Navegador o archivo .txt)")
        label2.setStyleSheet("color: #0099FF; font-family: 'Space Grotesk', sans-serif;")
        self.cookies_input = QLineEdit()
        self.cookies_input.setStyleSheet("background: #0A1118; color: #FFB84D; border: 1px solid #0099FF; padding: 5px;")
        
        open_cookie_btn = QPushButton("Abrir archivo .txt")
        open_cookie_btn.setStyleSheet("""
            QPushButton { background-color: #0099FF; color: #0A1118; font-weight: bold; padding: 5px 15px; border-radius: 3px; }
            QPushButton:hover { background-color: #80BFFF; }
        """)
        open_cookie_btn.clicked.connect(self.open_cookie_file)
        
        cookie_layout = QHBoxLayout()
        cookie_layout.addWidget(self.cookies_input)
        cookie_layout.addWidget(open_cookie_btn)
        
        save_btn = QPushButton("Guardar y Conectar")
        save_btn.setStyleSheet("""
            QPushButton { background-color: #0099FF; color: #0A1118; font-weight: bold; padding: 10px; border-radius: 3px; }
            QPushButton:hover { background-color: #80BFFF; }
        """)
        save_btn.clicked.connect(self.save_config)
        
        layout.addStretch()
        layout.addWidget(label1)
        layout.addWidget(self.base_url_input)
        layout.addSpacing(20)
        layout.addWidget(label2)
        layout.addLayout(cookie_layout)
        layout.addSpacing(30)
        layout.addWidget(save_btn)
        layout.addStretch()

    def open_cookie_file(self):
        path = self.cookies_input.text().strip()
        if not path or not path.endswith('.txt'):
            return
            
        if not self.text_viewer:
            main_win = self.window()
            parent_widget = main_win.centralWidget() if hasattr(main_win, 'centralWidget') else main_win
            self.text_viewer = TextViewerPanel(parent_widget)
            
        # Si el archivo no existe lo creamos vacío
        if not Path(path).exists():
            Path(path).parent.mkdir(parents=True, exist_ok=True)
            with open(path, 'w', encoding='utf-8') as f:
                f.write("# Pega aqui tus cookies de youtube\\n")
                
        self.text_viewer.load_text(path)
        
        # Centrar relativo al widget padre
        parent_widget = self.text_viewer.parentWidget()
        x = (parent_widget.width() - self.text_viewer.width()) // 2
        y = (parent_widget.height() - self.text_viewer.height()) // 2
        if x < 0: x = 0
        if y < 0: y = 0
        self.text_viewer.move(x, y)
        
        self.text_viewer.show()
        self.text_viewer.raise_()

    def setup_grid_view(self):
        view = QWidget()
        layout = QVBoxLayout(view)
        
        top_layout = QHBoxLayout()
        self.grid_status_label = QLabel("Initializing connection...")
        self.grid_status_label.setStyleSheet("color: #0099FF; font-family: 'Space Grotesk', sans-serif;")
        
        top_layout.addWidget(self.grid_status_label)
        top_layout.addStretch()
        
        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setStyleSheet(get_minimal_scrollbar_style() + "QScrollArea { border: none; background: transparent; } QWidget { background: transparent; }")
        
        self.grid_widget = QWidget()
        self.grid_layout = QGridLayout(self.grid_widget)
        scroll.setWidget(self.grid_widget)
        
        layout.addLayout(top_layout)
        layout.addWidget(scroll)
        
        self.stacked_widget.addWidget(view)

    def setup_songs_view(self):
        view = QWidget()
        layout = QVBoxLayout(view)
        
        top_layout = QHBoxLayout()
        back_btn = QPushButton("◄ Volver a Playlists")
        back_btn.setStyleSheet("color: #0099FF; background: transparent; border: 1px solid #0099FF; padding: 5px;")
        back_btn.clicked.connect(lambda: self.stacked_widget.setCurrentIndex(0))
        
        self.songs_title = QLabel("PLAYLIST TITLE")
        self.songs_title.setStyleSheet("color: #FFB84D; font-weight: bold; font-family: 'Space Grotesk', sans-serif;")
        
        top_layout.addWidget(back_btn)
        top_layout.addSpacing(10)
        top_layout.addWidget(self.songs_title)
        top_layout.addStretch()
        
        self.install_all_btn = QPushButton("Instalar Todo")
        self.install_all_btn.setStyleSheet("""
            QPushButton { background-color: #27ae60; color: #FFB84D; font-weight: bold; padding: 5px 15px; border-radius: 3px; }
            QPushButton:hover { background-color: #2ecc71; }
            QPushButton:disabled { background-color: #555; color: #888; }
        """)
        self.install_all_btn.clicked.connect(self.start_download_all)
        
        self.stop_btn = QPushButton("Detener")
        self.stop_btn.setStyleSheet("""
            QPushButton { background-color: #eb5757; color: #FFB84D; font-weight: bold; padding: 5px 15px; border-radius: 3px; }
            QPushButton:hover { background-color: #ff7675; }
            QPushButton:disabled { background-color: #555; color: #888; }
        """)
        self.stop_btn.clicked.connect(self.stop_downloads)
        self.stop_btn.hide()
        
        top_layout.addWidget(self.install_all_btn)
        top_layout.addWidget(self.stop_btn)
        
        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setStyleSheet(get_minimal_scrollbar_style() + "QScrollArea { border: none; background: transparent; } QWidget { background: transparent; }")
        
        self.songs_container = QWidget()
        self.songs_layout = QVBoxLayout(self.songs_container)
        self.songs_layout.setAlignment(Qt.AlignTop)
        scroll.setWidget(self.songs_container)
        
        layout.addLayout(top_layout)
        layout.addWidget(scroll)
        
        self.stacked_widget.addWidget(view)
        self.current_song_widgets = []

    # --- LOGIC ---

    def load_base_playlists(self):
        self.grid_status_label.setText("Fetching database...")
        # Clear grid
        for i in reversed(range(self.grid_layout.count())):
            self.grid_layout.itemAt(i).widget().setParent(None)
            
        url = self.base_url_input.text()
        browser = self.cookies_input.text()
        if not url:
            return
            
        self.thread = FetchPlaylistThread(url, browser)
        self.thread.finished.connect(self.on_base_fetched)
        self.thread.error.connect(lambda e: self.grid_status_label.setText(f"ERROR: {e}"))
        self._start_thread(self.thread)

    def _start_thread(self, thread):
        """Guarda referencia al hilo hasta que termine para evitar
        'QThread: Destroyed while thread is still running'."""
        if not hasattr(self, '_active_threads'):
            self._active_threads = []
        self._active_threads.append(thread)
        thread.finished.connect(lambda *_, t=thread: self._release_thread(t))
        if hasattr(thread, 'error'):
            thread.error.connect(lambda *_, t=thread: self._release_thread(t))
        thread.start()

    def _release_thread(self, thread):
        if thread in getattr(self, '_active_threads', []):
            thread.wait()  # run() ya está terminando; espera breve
            self._active_threads.remove(thread)

    def on_base_fetched(self, items):
        self.grid_status_label.setText(f"DATABASE READY. {len(items)} MODULES FOUND.")
        row, col = 0, 0
        for i, item in enumerate(items):
            card = SciFiCard(i+1, item['title'], item['url'])
            card.clicked.connect(lambda checked, url=item['url'], title=item['title']: self.open_playlist(url, title))
            self.grid_layout.addWidget(card, row, col)
            col += 1
            if col > 2: # 3 columnas
                col = 0
                row += 1

    def open_playlist(self, url, title):
        if url.startswith('/'):
            url = 'https://www.youtube.com' + url
            
        self.songs_title.setText(title.upper())
        self.stacked_widget.setCurrentIndex(1)
        
        # Clear list
        for i in reversed(range(self.songs_layout.count())):
            widget = self.songs_layout.itemAt(i).widget()
            if widget:
                widget.setParent(None)
        self.current_song_widgets.clear()
        self.install_all_btn.setEnabled(False)
        self.install_all_btn.setText("Cargando...")
        
        browser = self.cookies_input.text()
        self.thread = FetchPlaylistThread(url, browser)
        self.thread.finished.connect(self.on_songs_fetched)
        self.thread.error.connect(lambda e: self.songs_title.setText(f"ERROR: {e}"))
        self._start_thread(self.thread)

    def on_songs_fetched(self, items):
        self.install_all_btn.setEnabled(True)
        self.install_all_btn.setText("Instalar Todo")
        
        # Sort alphabetically
        items = sorted(items, key=lambda x: x['title'])
        
        # Comprobar instalados (simulación simple validando si existe algún archivo)
        dl_path = Path.home() / "Music" / "KioraDownloads"
        existing_files = [f.stem for f in dl_path.glob("*.mp3")] if dl_path.exists() else []
        
        for i, item in enumerate(items):
            # Limpiar nombre para comprobación simple
            title_clean = item['title'].replace('/', '_').replace('\\', '_')
            status = "INSTALLED" if title_clean in existing_files else "NOT_INSTALLED"
            
            song_widget = SongItem(i+1, item['title'], item['url'], status)
            song_widget.dl_btn.clicked.connect(lambda _, w=song_widget: self.start_single_download(w))
            self.songs_layout.addWidget(song_widget)
            self.current_song_widgets.append(song_widget)
            
    def start_single_download(self, widget):
        if getattr(self, 'dl_thread', None) and self.dl_thread.isRunning():
            return
            
        index = self.current_song_widgets.index(widget)
        pending = [(index, widget.url)]
        self._start_download_thread(pending)
        
    def start_download_all(self):
        pending = [(i, w.url) for i, w in enumerate(self.current_song_widgets)
                   if w.status != "INSTALLED"]
                
        if not pending:
            return
        if getattr(self, 'dl_thread', None) and self.dl_thread.isRunning():
            return
            
        self._start_download_thread(pending)
        
    def _start_download_thread(self, pending):
        self.install_all_btn.setEnabled(False)
        self.install_all_btn.setText("Descargando...")
        self.stop_btn.show()
        self.stop_btn.setEnabled(True)
        self.stop_btn.setText("Detener")
        
        self.dl_thread = DownloadSequentialThread(pending)
        self.dl_thread.progress.connect(self.update_download_progress)
        self.dl_thread.finished.connect(self.on_download_finished)
        self._start_thread(self.dl_thread)
        
    def stop_downloads(self):
        if getattr(self, 'dl_thread', None) and self.dl_thread.isRunning():
            self.dl_thread.stop()
            self.stop_btn.setEnabled(False)
            self.stop_btn.setText("Deteniendo...")
        
    def update_download_progress(self, index, status):
        if 0 <= index < len(self.current_song_widgets):
            self.current_song_widgets[index].set_status(status)
            
    def on_download_finished(self):
        self.install_all_btn.setEnabled(True)
        self.install_all_btn.setText("Instalar Todo")
        self.stop_btn.hide()
