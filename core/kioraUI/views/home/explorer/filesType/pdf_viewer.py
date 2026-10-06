from PySide6.QtWidgets import QVBoxLayout, QHBoxLayout, QWidget, QLabel, QPushButton
from PySide6.QtPdfWidgets import QPdfView
from PySide6.QtPdf import QPdfDocument
from PySide6.QtCore import Qt
from core.kioraUI.views.global_ui.viewer_base import SciFiViewerBase
from core.kioraUI.views.global_ui.styles import get_minimal_scrollbar_style

class PdfViewerPanel(SciFiViewerBase):
    def __init__(self, parent=None):
        super().__init__(parent, "PDF DOCUMENT VIEWER")
        self.resize(800, 700)
        
        self.header.hide()
        self.close_btn.setParent(self)
        self.close_btn.setStyleSheet("""
            QPushButton { background-color: rgba(22, 22, 22, 0.8); color: #FFFFFF; font-weight: bold; border: 1px solid #D96600;}
            QPushButton:hover { background-color: #D96600; }
        """)
        self.close_btn.show()

        self.pdf_document = QPdfDocument(self)
        self.pdf_view = QPdfView(self.body_frame)
        self.pdf_view.setDocument(self.pdf_document)
        self.pdf_view.setPageMode(QPdfView.PageMode.MultiPage)
        self.pdf_view.setZoomMode(QPdfView.ZoomMode.FitToWidth)
        
        self.pdf_view.setStyleSheet(get_minimal_scrollbar_style() + """
            QPdfView { background-color: transparent; border: none; }
        """)

        self.set_body_widget(self.pdf_view)
        
        # Habilitar zoom con Ctrl + Rueda del ratón
        self.pdf_view.viewport().installEventFilter(self)
        
        # Controles
        self.controls_widget = QWidget(self.body_frame)
        self.controls_widget.setStyleSheet("""
            QWidget { background-color: rgba(22, 22, 22, 0.85); border: 1px solid #182533; border-radius: 4px; }
            QPushButton { background-color: transparent; color: #FFFFFF; font-family: 'Consolas'; font-size: 16px; border: none; padding: 4px 10px; font-weight: bold; }
            QPushButton:hover { color: #D96600; }
            QLabel { color: #FFFFFF; font-family: 'Consolas'; font-size: 12px; background-color: transparent; border: none; padding: 0 10px; }
        """)
        c_layout = QHBoxLayout(self.controls_widget)
        c_layout.setContentsMargins(5, 5, 5, 5)
        
        self.btn_zoom_out = QPushButton("-")
        self.btn_zoom_in = QPushButton("+")
        self.lbl_page = QLabel("PÁGINA 1 / 1")
        
        c_layout.addWidget(self.btn_zoom_out)
        c_layout.addWidget(self.lbl_page)
        c_layout.addWidget(self.btn_zoom_in)
        
        self.btn_zoom_in.clicked.connect(self._zoom_in)
        self.btn_zoom_out.clicked.connect(self._zoom_out)
        
        self.pdf_view.pageNavigator().currentPageChanged.connect(self._update_page_label)
        self.pdf_document.statusChanged.connect(self._on_doc_status_changed)
        
        self.current_zoom = 1.0
        
    def load_pdf(self, path):
        self.pdf_document.load(path)
        self.pdf_view.setZoomMode(QPdfView.ZoomMode.FitToWidth)
        
    def _zoom_in(self):
        if self.pdf_view.zoomMode() != QPdfView.ZoomMode.Custom:
            self.pdf_view.setZoomMode(QPdfView.ZoomMode.Custom)
        self.current_zoom *= 1.2
        self.pdf_view.setZoomFactor(self.current_zoom)

    def _zoom_out(self):
        if self.pdf_view.zoomMode() != QPdfView.ZoomMode.Custom:
            self.pdf_view.setZoomMode(QPdfView.ZoomMode.Custom)
        self.current_zoom /= 1.2
        self.pdf_view.setZoomFactor(self.current_zoom)

    def _on_doc_status_changed(self, status):
        if status == QPdfDocument.Status.Ready:
            self._update_page_label()
            self.current_zoom = self.pdf_view.zoomFactor()

    def _update_page_label(self):
        current = self.pdf_view.pageNavigator().currentPage() + 1
        total = self.pdf_document.pageCount()
        self.lbl_page.setText(f"PÁGINA {current} / {total}")
        
    def resizeEvent(self, event):
        super().resizeEvent(event)
        self.close_btn.move(self.width() - self.close_btn.width() - 5, 5)
        self.close_btn.raise_()
        
        w = self.body_frame.width()
        h = self.body_frame.height()
        pad = 25
        self.controls_widget.adjustSize()
        self.controls_widget.move(w - self.controls_widget.width() - pad, h - self.controls_widget.height() - pad)
        self.controls_widget.raise_()

    def eventFilter(self, obj, event):
        if obj == self.pdf_view.viewport() and event.type() == event.Type.Wheel:
            if event.modifiers() == Qt.ControlModifier:
                if event.angleDelta().y() > 0:
                    self._zoom_in()
                else:
                    self._zoom_out()
                return True
        return super().eventFilter(obj, event)
