from PySide6.QtWidgets import QLabel, QPushButton, QVBoxLayout, QHBoxLayout, QWidget, QSlider
from PySide6.QtCore import Qt, QUrl, Signal, QTimer, QPointF
from PySide6.QtGui import QPainter, QPen, QColor, QPainterPath
from PySide6.QtMultimedia import QMediaPlayer, QAudioOutput
import math
import random

class SciFiAudioWaveTimeline(QWidget):
    sliderMoved = Signal(int)

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setMinimumHeight(100)
        self.duration = 100
        self.position = 0
        self.is_playing = False
        
        self.phase = 0.0
        
        self.waves = [
            {"base_amp": 16, "freq": 0.04, "speed": 1.0, "color": QColor(217, 102, 0, 180), "nodes": True, "target_amp": 1.0, "current_amp": 1.0},
            {"base_amp": 10, "freq": 0.06, "speed": 0.8, "color": QColor(217, 102, 0, 100), "nodes": False, "target_amp": 1.0, "current_amp": 1.0},
            {"base_amp": 6, "freq": 0.09, "speed": 1.2, "color": QColor(255, 170, 0, 80), "nodes": False, "target_amp": 1.0, "current_amp": 1.0},
        ]
        
        self.timer = QTimer(self)
        self.timer.timeout.connect(self.update_animation)
        self.timer.start(30)
        self.mouse_down = False
        
    def update_animation(self):
        if self.is_playing:
            self.phase += 0.2
            for wave in self.waves:
                if random.random() < 0.15:
                    wave["target_amp"] = random.uniform(0.3, 2.8)
                wave["current_amp"] += (wave["target_amp"] - wave["current_amp"]) * 0.15
            self.update()
            
    def setRange(self, minimum, maximum):
        self.duration = max(1, maximum)
        self.update()
        
    def setValue(self, value):
        if not self.mouse_down:
            self.position = max(0, min(value, self.duration))
            self.update()
            
    def mousePressEvent(self, event):
        if event.button() == Qt.LeftButton:
            self.mouse_down = True
            self._set_pos_from_mouse(event.pos().x())
            
    def mouseMoveEvent(self, event):
        if self.mouse_down:
            self._set_pos_from_mouse(event.pos().x())
            
    def mouseReleaseEvent(self, event):
        if event.button() == Qt.LeftButton:
            self.mouse_down = False
            
    def _set_pos_from_mouse(self, mx):
        margin = 15
        width = self.width() - margin * 2
        ratio = max(0.0, min(1.0, (mx - margin) / float(width)))
        self.position = int(ratio * self.duration)
        self.sliderMoved.emit(self.position)
        self.update()

    def paintEvent(self, event):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)
        
        w = self.width()
        h = self.height()
        cy = h / 2
        margin = 15
        track_w = w - margin * 2
        
        # 1. Waves
        painter.setBrush(Qt.NoBrush)
        
        for wave in self.waves:
            path = QPainterPath()
            points = []
            for x in range(margin, w - margin + 1, 4):
                eff_phase = self.phase * wave["speed"]
                dynamic_amp = wave["base_amp"] * wave["current_amp"] if self.is_playing else wave["base_amp"] * 0.3
                y = cy + math.sin((x - margin) * wave["freq"] + eff_phase) * dynamic_amp
                
                edge_dist = min(x - margin, w - margin - x)
                if edge_dist < 35:
                    y = cy + (y - cy) * (edge_dist / 35.0)
                    
                pt = QPointF(x, y)
                points.append(pt)
                if x == margin:
                    path.moveTo(pt)
                else:
                    path.lineTo(pt)
                    
            painter.setPen(QPen(wave["color"], 1.5))
            painter.drawPath(path)
            
            if wave["nodes"]:
                painter.setPen(QPen(wave["color"], 1.5))
                painter.setBrush(QColor(10, 10, 10))
                for i in range(1, len(points) - 1):
                    p0 = points[i-1].y()
                    p1 = points[i].y()
                    p2 = points[i+1].y()
                    if ((p1 < p0 and p1 <= p2) or (p1 > p0 and p1 >= p2)) and abs(p1 - cy) > 2:
                        painter.drawEllipse(points[i], 3, 3)

        # 2. Dashed Timeline
        pen = QPen(QColor(150, 150, 150, 100), 1.5, Qt.DashLine)
        painter.setPen(pen)
        painter.drawLine(margin, cy, w - margin, cy)
        
        # 3. End Nodes
        painter.setPen(QPen(QColor(200, 200, 200, 180), 1.5))
        painter.setBrush(QColor(10, 10, 10))
        painter.drawEllipse(QPointF(margin, cy), 4, 4)
        painter.drawEllipse(QPointF(w - margin, cy), 4, 4)
        
        # 4. Playhead
        ratio = self.position / float(self.duration) if self.duration > 0 else 0
        hx = margin + ratio * track_w
        
        painter.setPen(Qt.NoPen)
        painter.setBrush(QColor(217, 102, 0, 100))
        painter.drawEllipse(QPointF(hx, cy), 10, 10)
        
        painter.setPen(QPen(QColor(255, 255, 255), 2))
        painter.setBrush(QColor(217, 102, 0))
        painter.drawEllipse(QPointF(hx, cy), 4.5, 4.5)

class AudioPlayerWidget(QWidget):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.resize(500, 140)
        self.setStyleSheet("""
            QWidget { background-color: rgba(10, 10, 10, 0.85); border: 1px solid #182533; border-radius: 8px;}
            QLabel, QPushButton { border: none; background: transparent; }
        """)
        
        c_layout = QVBoxLayout(self)
        c_layout.setContentsMargins(20, 15, 25, 15)
        c_layout.setSpacing(8)
        
        self.song_name_lbl = QLabel("NO TRACK")
        self.song_name_lbl.setStyleSheet("color: #FFFFFF; font-family: 'Segoe UI'; font-size: 16px; font-weight: bold; letter-spacing: 2px;")
        
        self.progress_slider = SciFiAudioWaveTimeline()
        
        btns_layout = QHBoxLayout()
        btns_layout.setContentsMargins(0, 8, 0, 0)
        
        btn_style = """
            QPushButton { color: #FFFFFF; font-family: 'Segoe UI Symbol'; font-size: 24px; }
            QPushButton:hover { color: #D96600; }
        """
        
        self.btn_prev = QPushButton("⏮")
        self.btn_play = QPushButton("⏵")
        self.btn_next = QPushButton("⏭")
        
        self.btn_prev.setStyleSheet(btn_style)
        self.btn_play.setStyleSheet(btn_style)
        self.btn_next.setStyleSheet(btn_style)
        
        self.btn_play.clicked.connect(self._toggle_play)
        
        btns_layout.addWidget(self.btn_prev)
        btns_layout.addWidget(self.btn_play)
        btns_layout.addWidget(self.btn_next)
        btns_layout.addStretch()
        
        c_layout.addWidget(self.song_name_lbl)
        c_layout.addWidget(self.progress_slider)
        c_layout.addLayout(btns_layout)

        # PySide6 Audio setup
        self.player = QMediaPlayer()
        self.audio_output = QAudioOutput()
        self.player.setAudioOutput(self.audio_output)
        self.audio_output.setVolume(1.0)
        
        self.player.positionChanged.connect(self._update_position)
        self.player.durationChanged.connect(self._update_duration)
        self.progress_slider.sliderMoved.connect(self._set_position)
        self.player.playbackStateChanged.connect(self._on_state_changed)
        
    def _toggle_play(self):
        if self.player.playbackState() == QMediaPlayer.PlayingState:
            self.player.pause()
        else:
            self.player.play()
            
    def _on_state_changed(self, state):
        if state == QMediaPlayer.PlayingState:
            self.btn_play.setText("⏸")
            self.progress_slider.is_playing = True
        else:
            self.btn_play.setText("⏵")
            self.progress_slider.is_playing = False
            
    def _update_position(self, pos):
        self.progress_slider.setValue(pos)
        
    def _update_duration(self, duration):
        self.progress_slider.setRange(0, duration)
        
    def _set_position(self, pos):
        self.player.setPosition(pos)
        
    def load_audio(self, path):
        filename = path.replace("\\", "/").split('/')[-1]
        self.song_name_lbl.setText(filename.upper())
        self.player.setSource(QUrl.fromLocalFile(path))
        self.player.play()
