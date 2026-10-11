from PySide6.QtWidgets import (QListWidget, QVBoxLayout, QLineEdit, QPushButton, 
                               QHBoxLayout, QLabel, QStackedWidget, QWidget, QScrollArea, QGridLayout, QSizePolicy, QTabWidget)
from PySide6.QtCore import Qt, QThread, Signal
from PySide6.QtGui import QPainter, QColor, QPen
from core.matrix.ecosystems.motherBoard.globalComponents.base_container import KioraBaseContainer
from core.matrix.ecosystems.motherBoard.globalComponents.styles import get_minimal_scrollbar_style
from core.matrix.ecosystems.explorer.filesType.text_viewer import TextViewerPanel
from core.matrix.ecosystems.studio.mp3installer import MP3InstallerEcosystem, get_js_runtime_opts
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

    def __init__(self, url, browser_val, fetch_counts=True):
        super().__init__()
        self.url = url
        self.browser_val = browser_val
        self.fetch_counts = fetch_counts

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
                            items.append({'title': title, 'url': url, 'count': '?'})
                elif 'title' in info:
                    items.append({'title': info.get('title', 'Unknown'), 'url': info.get('webpage_url', self.url), 'count': '?'})
                
                # Segunda pasada para obtener la cantidad real de canciones de cada playlist en paralelo
                if self.fetch_counts:
                    from concurrent.futures import ThreadPoolExecutor
                    def get_count(item):
                        if not item['url']: return
                        try:
                            with yt_dlp.YoutubeDL(ydl_opts) as thread_ydl:
                                p_info = thread_ydl.extract_info(item['url'], download=False)
                                if 'entries' in p_info:
                                    item['count'] = str(len(list(p_info['entries'])))
                                elif 'playlist_count' in p_info:
                                    item['count'] = str(p_info['playlist_count'])
                        except Exception:
                            pass
                            
                    with ThreadPoolExecutor(max_workers=5) as executor:
                        executor.map(get_count, items)
                        
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
    def __init__(self, index, title, url, count="?"):
        super().__init__()
        self.url = url
        self.title = title
        
        idx_str = f"{index:03d}"
        
        self.setStyleSheet("""
            QPushButton {
                background-color: #1E1E1E;
                border: 1px solid #444444;
                text-align: left;
            }
            QPushButton:hover {
                background-color: #2A2A2A;
                border: 1px solid #666666;
            }
        """)
        self.setFixedHeight(35)
        self.setCursor(Qt.PointingHandCursor)
        
        layout = QHBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(0)
        
        # Bloque izquierdo (Número)
        num_container = QWidget()
        num_container.setFixedWidth(60)
        num_container.setStyleSheet("background-color: #FFFFFF; border: none;")
        num_layout = QVBoxLayout(num_container)
        num_layout.setContentsMargins(0, 0, 0, 0)
        num_layout.setAlignment(Qt.AlignCenter)
        
        num_label = QLabel(idx_str)
        num_label.setStyleSheet("color: #121212; font-size: 14px; font-weight: bold; font-family: 'Space Grotesk', sans-serif; background: transparent;")
        num_layout.addWidget(num_label)
        
        # Bloque derecho (Título)
        title_label = QLabel(title.upper())
        title_label.setContentsMargins(15, 0, 10, 0)
        title_label.setStyleSheet("color: #E0E0E0; font-size: 13px; font-family: 'Space Grotesk', sans-serif; font-weight: bold; border: none; background: transparent;")
        
        # Bloque derecho (Conteo)
        count_label = QLabel(f"{count} TRACKS")
        count_label.setContentsMargins(0, 0, 15, 0)
        count_label.setStyleSheet("color: #FFFFFF; font-size: 11px; font-family: 'Space Grotesk', sans-serif; font-weight: bold; border: none; background: transparent;")
        
        layout.addWidget(num_container)
        layout.addWidget(title_label)
        layout.addStretch()
        layout.addWidget(count_label)


class SongItem(QWidget):
    def __init__(self, index, title, url, status="NOT_INSTALLED"):
        super().__init__()
        self.url = url
        self.title = title
        self.status = status
        
        self.layout = QHBoxLayout(self)
        self.layout.setContentsMargins(10, 0, 10, 0)
        self.setFixedHeight(30)
        
        # Color alterno para filas
        if index % 2 == 0:
            self.setStyleSheet("SongItem { background-color: #161616; }")
        
        self.idx_label = QLabel(f"{index:02d}")
        self.idx_label.setFixedWidth(40)
        self.idx_label.setStyleSheet("color: #A0A0A0; font-size: 11px; font-family: 'Space Grotesk', sans-serif;")
        
        self.title_label = QLabel(title.upper())
        self.title_label.setStyleSheet("color: #E0E0E0; font-size: 11px; font-family: 'Space Grotesk', sans-serif; font-weight: bold;")
        
        self.status_container = QWidget()
        self.status_container.setFixedWidth(80)
        status_layout = QVBoxLayout(self.status_container)
        status_layout.setContentsMargins(0, 0, 0, 0)
        status_layout.setAlignment(Qt.AlignCenter)
        
        self.status_label = QLabel()
        self.status_label.setAlignment(Qt.AlignCenter)
        self.status_label.setStyleSheet("font-family: 'Space Grotesk', sans-serif; font-size: 9px; font-weight: bold;")
        status_layout.addWidget(self.status_label)
        
        btn_container = QWidget()
        btn_container.setFixedWidth(60)
        btn_layout = QVBoxLayout(btn_container)
        btn_layout.setContentsMargins(0, 0, 0, 0)
        btn_layout.setAlignment(Qt.AlignCenter)
        
        self.dl_btn = QPushButton("↓")
        self.dl_btn.setFixedSize(50, 20)
        self.dl_btn.setCursor(Qt.PointingHandCursor)
        btn_layout.addWidget(self.dl_btn)
        
        self.layout.addWidget(self.idx_label)
        self.layout.addWidget(self.title_label)
        self.layout.addWidget(self.status_container)
        self.layout.addWidget(btn_container)
        
        self.update_style()
        
    def set_status(self, status):
        self.status = status
        self.update_style()
        
    def update_style(self):
        if self.status == "NOT_INSTALLED":
            txt_color = "#555555"
            bg_color = "transparent"
            txt = "--"
            self.dl_btn.setEnabled(True)
            self.dl_btn.setText("↓")
            btn_color = "#444444"
        elif self.status.startswith("DOWNLOADING"):
            txt_color = "#121212"
            bg_color = "#FFFFFF" # Amarillo
            txt = "DOWNLOADING"
            self.dl_btn.setEnabled(False)
            if " " in self.status:
                percent = self.status.split(" ", 1)[1]
                self.dl_btn.setText(percent)
            else:
                self.dl_btn.setText("...")
            btn_color = "#FFFFFF"
        elif self.status == "INSTALLED":
            txt_color = "#121212"
            bg_color = "#444444" # Azul sólido
            txt = "ONLINE"
            self.dl_btn.setEnabled(False)
            self.dl_btn.setText("✓")
            btn_color = "#444444"
        else: # ERROR
            txt_color = "#121212"
            bg_color = "#A31F34" # Rojo sólido
            txt = "OFFLINE"
            self.dl_btn.setEnabled(True)
            self.dl_btn.setText("↻")
            btn_color = "#A31F34"
            
        self.status_label.setStyleSheet(f"color: {txt_color}; background-color: {bg_color}; padding: 2px 5px; border-radius: 2px;")
        self.status_label.setText(txt)
        
        self.dl_btn.setStyleSheet(f"""
            QPushButton {{ background-color: transparent; border: 1px solid {btn_color}; color: {btn_color}; border-radius: 10px; font-weight: bold; font-size: 10px; }}
            QPushButton:hover {{ background-color: {btn_color}33; }}
        """)

# --- PANEL PRINCIPAL ---

class YoutubeMusicPanel(QWidget):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.resize(800, 600)
        
        self.config_path = Path(__file__).parent / "global_config.json"
        
        self.main_layout = QVBoxLayout(self)
        self.main_layout.setContentsMargins(15, 15, 15, 15)
        
        # Cargar configuración primero
        self.load_global_config()
        
        # --- Top Section: Cookies ---
        top_bar = QHBoxLayout()
        top_bar.setAlignment(Qt.AlignLeft)
        
        # Cookie status box
        self.cookie_status_box = QWidget()
        self.cookie_status_box.setFixedSize(160, 60)
        cookie_layout = QVBoxLayout(self.cookie_status_box)
        cookie_layout.setContentsMargins(15, 10, 15, 10)
        
        self.cookie_status_title = QLabel("YOUTUBE COOKIES")
        self.cookie_status_title.setStyleSheet("color: #B7B7B7; font-size: 10px; font-weight: bold; font-family: 'Space Grotesk', sans-serif; letter-spacing: 1px;")
        
        self.cookie_status_label = QLabel()
        self.cookie_status_label.setStyleSheet("color: #FFFFFF; font-size: 14px; font-family: 'Space Grotesk', sans-serif; font-weight: bold;")
        
        cookie_layout.addWidget(self.cookie_status_title)
        cookie_layout.addWidget(self.cookie_status_label)
        
        top_bar.addWidget(self.cookie_status_box)
        
        self.main_layout.addLayout(top_bar)
        self.main_layout.addSpacing(30)
        
        # --- Título "Active playlists" ---
        playlists_title = QLabel("Active playlists")
        playlists_title.setStyleSheet("color: #FFFFFF; font-family: 'Space Grotesk', sans-serif; font-size: 22px; font-weight: bold;")
        self.main_layout.addWidget(playlists_title)
        self.main_layout.addSpacing(10)
        
        # --- Stacked Widget (Grid / Songs) ---
        self.stacked_widget = QStackedWidget()
        self.main_layout.addWidget(self.stacked_widget)
        
        self.setup_grid_view()
        self.setup_songs_view()
        
        self.thread = None
        self.dl_thread = None
        self.text_viewer = None
        
        self.check_cookie_status()
        
        if self.cfg.get("base_url"):
            self.load_base_playlists()

    def check_cookie_status(self):
        cookie_path = self.cfg.get("browser_for_cookies", "")
        is_valid = False
        if cookie_path.endswith('.txt') and os.path.exists(cookie_path):
            if os.path.getsize(cookie_path) > 50:
                is_valid = True
                
        if is_valid:
            self.cookie_status_box.setStyleSheet("background-color: #2A2A2A; border-left: 4px solid #444444;")
            self.cookie_status_label.setText("UPDATED")
        else:
            self.cookie_status_box.setStyleSheet("background-color: #3D1F1F; border-left: 4px solid #A31F34;")
            self.cookie_status_label.setText("EXPIRED")

    def load_global_config(self):
        if self.config_path.exists():
            try:
                with open(self.config_path, 'r', encoding='utf-8') as f:
                    self.cfg = json.load(f)
            except Exception:
                self.cfg = {}
        else:
            self.cfg = {}


    def setup_grid_view(self):
        view = QWidget()
        layout = QVBoxLayout(view)
        
        top_layout = QHBoxLayout()
        self.grid_status_label = QLabel("ANALYZING PLAYLISTS...")
        self.grid_status_label.setStyleSheet("color: #FFFFFF; font-family: 'Space Grotesk', sans-serif; font-size: 12px; font-weight: bold;")
        self.grid_status_label.hide()
        top_layout.addWidget(self.grid_status_label)
        top_layout.addStretch()
        
        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setStyleSheet(get_minimal_scrollbar_style() + "QScrollArea { border: none; background: transparent; } QWidget { background: transparent; }")
        
        self.grid_widget = QWidget()
        self.grid_layout = QVBoxLayout(self.grid_widget)
        self.grid_layout.setAlignment(Qt.AlignTop)
        self.grid_layout.setSpacing(5)
        scroll.setWidget(self.grid_widget)
        
        layout.addLayout(top_layout)
        layout.addWidget(scroll)
        
        self.stacked_widget.addWidget(view)

    def setup_songs_view(self):
        view = QWidget()
        layout = QVBoxLayout(view)
        
        top_layout = QHBoxLayout()
        top_layout.setContentsMargins(0, 0, 0, 10)
        top_layout.setSpacing(0)
        
        back_btn = QPushButton("PLAYLISTS ◄")
        back_btn.setStyleSheet("""
            QPushButton {
                background-color: #2A2A2A;
                color: #A0A0A0;
                font-family: 'Space Grotesk', sans-serif;
                font-weight: bold;
                font-size: 13px;
                padding: 6px 15px;
                border: 1px solid #444444;
                border-right: none;
            }
            QPushButton:hover { background-color: #333333; color: #E0E0E0; }
        """)
        back_btn.clicked.connect(lambda: self.stacked_widget.setCurrentIndex(0))
        
        self.songs_title = QLabel("TITLE")
        self.songs_title.setStyleSheet("""
            background-color: #FFFFFF;
            color: #121212;
            font-family: 'Space Grotesk', sans-serif;
            font-weight: bold;
            font-size: 13px;
            padding: 6px 15px;
            border: 1px solid #FFFFFF;
        """)
        
        top_layout.addWidget(back_btn)
        top_layout.addWidget(self.songs_title)
        top_layout.addStretch()
        
        self.install_all_btn = QPushButton("Instalar Todo")
        self.install_all_btn.setStyleSheet("""
            QPushButton { background-color: #333333; color: #FFFFFF; font-weight: bold; padding: 5px 15px; border-radius: 3px; }
            QPushButton:hover { background-color: #444444; }
            QPushButton:disabled { background-color: #555; color: #888; }
        """)
        self.install_all_btn.clicked.connect(self.start_download_all)
        
        self.stop_btn = QPushButton("Detener")
        self.stop_btn.setStyleSheet("""
            QPushButton { background-color: #A31F34; color: #FFFFFF; font-weight: bold; padding: 5px 15px; border-radius: 3px; }
            QPushButton:hover { background-color: #C82B46; }
            QPushButton:disabled { background-color: #555; color: #888; }
        """)
        self.stop_btn.clicked.connect(self.stop_downloads)
        self.stop_btn.hide()
        
        top_layout.addWidget(self.install_all_btn)
        top_layout.addWidget(self.stop_btn)
        
        # HEADER
        header_layout = QHBoxLayout()
        header_layout.setContentsMargins(10, 5, 10, 5)
        
        lbl_no = QLabel("NO")
        lbl_no.setFixedWidth(40)
        lbl_no.setStyleSheet("color: #A0A0A0; font-size: 10px; font-weight: bold; font-family: 'Space Grotesk', sans-serif;")
        
        lbl_station = QLabel("STATION")
        lbl_station.setStyleSheet("color: #A0A0A0; font-size: 10px; font-weight: bold; font-family: 'Space Grotesk', sans-serif;")
        
        lbl_status = QLabel("STATUS")
        lbl_status.setFixedWidth(80)
        lbl_status.setAlignment(Qt.AlignCenter)
        lbl_status.setStyleSheet("color: #A0A0A0; font-size: 10px; font-weight: bold; font-family: 'Space Grotesk', sans-serif;")
        
        lbl_action = QLabel("ACTION")
        lbl_action.setFixedWidth(60)
        lbl_action.setAlignment(Qt.AlignCenter)
        lbl_action.setStyleSheet("color: #A0A0A0; font-size: 10px; font-weight: bold; font-family: 'Space Grotesk', sans-serif;")
        
        header_layout.addWidget(lbl_no)
        header_layout.addWidget(lbl_station)
        header_layout.addWidget(lbl_status)
        header_layout.addWidget(lbl_action)
        
        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setStyleSheet(get_minimal_scrollbar_style() + "QScrollArea { border: none; background: transparent; } QWidget { background: transparent; }")
        
        self.songs_container = QWidget()
        self.songs_container.setStyleSheet("background-color: #121212;")
        self.songs_layout = QVBoxLayout(self.songs_container)
        self.songs_layout.setAlignment(Qt.AlignTop)
        self.songs_layout.setSpacing(0)
        
        # Loading indicator for songs
        self.songs_loading_label = QLabel("FETCHING TRACKS...")
        self.songs_loading_label.setStyleSheet("color: #FFFFFF; font-family: 'Space Grotesk', sans-serif; font-size: 12px; font-weight: bold; padding: 20px;")
        self.songs_loading_label.setAlignment(Qt.AlignCenter)
        self.songs_loading_label.hide()
        
        self.songs_layout.addWidget(self.songs_loading_label)
        scroll.setWidget(self.songs_container)
        
        layout.addLayout(top_layout)
        layout.addLayout(header_layout)
        layout.addWidget(scroll)
        
        self.stacked_widget.addWidget(view)
        self.current_song_widgets = []

    # --- LOGIC ---

    def load_base_playlists(self):
        # Clear grid
        for i in reversed(range(self.grid_layout.count())):
            self.grid_layout.itemAt(i).widget().setParent(None)
            
        self.grid_status_label.show()
        
        url = self.cfg.get("base_url")
        browser = self.cfg.get("browser_for_cookies", "chrome")
        if not url:
            return
            
        self.thread = FetchPlaylistThread(url, browser, fetch_counts=True)
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
        self.grid_status_label.hide()
        for i, item in enumerate(items):
            count = item.get('count', '?')
            card = SciFiCard(i+1, item['title'], item['url'], count)
            card.clicked.connect(lambda checked, url=item['url'], title=item['title']: self.open_playlist(url, title))
            self.grid_layout.addWidget(card)

    def open_playlist(self, url, title):
        if url.startswith('/'):
            url = 'https://www.youtube.com' + url
            
        self.songs_title.setText(title.upper())
        self.stacked_widget.setCurrentIndex(1)
        
        # Clear list
        for i in reversed(range(self.songs_layout.count())):
            widget = self.songs_layout.itemAt(i).widget()
            if widget and widget != self.songs_loading_label:
                widget.setParent(None)
                
        self.current_song_widgets.clear()
        self.songs_loading_label.show()
        self.install_all_btn.setEnabled(False)
        self.install_all_btn.setText("Cargando...")
        
        browser = self.cfg.get("browser_for_cookies", "chrome")
        self.thread = FetchPlaylistThread(url, browser, fetch_counts=False)
        self.thread.finished.connect(self.on_songs_fetched)
        self.thread.error.connect(lambda e: self.songs_title.setText(f"ERROR: {e}"))
        self._start_thread(self.thread)

    def on_songs_fetched(self, items):
        self.songs_loading_label.hide()
        self.install_all_btn.setEnabled(True)
        self.install_all_btn.setText("Instalar Todo")
        
        # Sort alphabetically
        items = sorted(items, key=lambda x: x['title'])
        
        # Comprobar instalados (simulación simple validando si existe algún archivo)
        dl_path = Path(self.cfg.get("download_path", str(Path.home() / "Music" / "KioraDownloads")))
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
