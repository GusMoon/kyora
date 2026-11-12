"""Iconos reales de las aplicaciones (los del programa o los de su ventana), con caché.

Nunca devuelve una letra ni un emoticono: si no encuentra el icono dibuja uno genérico (una cuadrícula de fichas).
"""
import ctypes
import logging
from ctypes import wintypes

from PySide6.QtCore import QFileInfo, QRectF, Qt
from PySide6.QtGui import QColor, QImage, QPainter, QPixmap
from PySide6.QtWidgets import QFileIconProvider

log = logging.getLogger("kyora.ui")

user32 = ctypes.WinDLL("user32")
gdi32 = ctypes.WinDLL("gdi32")
user32.SendMessageTimeoutW.restype = ctypes.c_ssize_t
user32.SendMessageTimeoutW.argtypes = [
    wintypes.HWND, wintypes.UINT, wintypes.WPARAM, wintypes.LPARAM, wintypes.UINT, wintypes.UINT, ctypes.POINTER(ctypes.c_size_t),
]
user32.GetClassLongPtrW.restype = ctypes.c_size_t
user32.GetClassLongPtrW.argtypes = [wintypes.HWND, ctypes.c_int]
user32.DrawIconEx.argtypes = [
    wintypes.HDC, ctypes.c_int, ctypes.c_int, ctypes.c_void_p, ctypes.c_int, ctypes.c_int, wintypes.UINT, ctypes.c_void_p, wintypes.UINT,
]
user32.GetDC.restype = wintypes.HDC
user32.GetDC.argtypes = [wintypes.HWND]
user32.ReleaseDC.argtypes = [wintypes.HWND, wintypes.HDC]
gdi32.CreateCompatibleDC.restype = wintypes.HDC
gdi32.CreateCompatibleDC.argtypes = [wintypes.HDC]
gdi32.CreateDIBSection.restype = wintypes.HBITMAP
gdi32.CreateDIBSection.argtypes = [wintypes.HDC, ctypes.c_void_p, wintypes.UINT, ctypes.POINTER(ctypes.c_void_p), wintypes.HANDLE, wintypes.DWORD]
gdi32.SelectObject.restype = wintypes.HGDIOBJ
gdi32.SelectObject.argtypes = [wintypes.HDC, wintypes.HGDIOBJ]
gdi32.DeleteObject.argtypes = [wintypes.HGDIOBJ]
gdi32.DeleteDC.argtypes = [wintypes.HDC]

shell32 = ctypes.WinDLL("shell32")
ole32 = ctypes.WinDLL("ole32")


class _SHFILEINFOW(ctypes.Structure):
    _fields_ = [
        ("hIcon", ctypes.c_void_p), ("iIcon", ctypes.c_int), ("dwAttributes", wintypes.DWORD),
        ("szDisplayName", wintypes.WCHAR * 260), ("szTypeName", wintypes.WCHAR * 80),
    ]


shell32.SHParseDisplayName.argtypes = [wintypes.LPCWSTR, ctypes.c_void_p, ctypes.POINTER(ctypes.c_void_p), wintypes.ULONG, ctypes.POINTER(wintypes.ULONG)]
shell32.SHGetFileInfoW.restype = ctypes.c_size_t
shell32.SHGetFileInfoW.argtypes = [ctypes.c_void_p, wintypes.DWORD, ctypes.POINTER(_SHFILEINFOW), wintypes.UINT, wintypes.UINT]
ole32.CoTaskMemFree.argtypes = [ctypes.c_void_p]
user32.DestroyIcon.argtypes = [ctypes.c_void_p]
SHGFI_ICON, SHGFI_LARGEICON, SHGFI_PIDL = 0x100, 0x0, 0x8
WM_GETICON = 0x007F
ICON_BIG, ICON_SMALL2 = 1, 2
GCLP_HICON = -14
DI_NORMAL = 3
SMTO_ABORTIFHUNG = 0x2
FRAME_HOST = "applicationframehost.exe"  # aloja las aplicaciones de la Tienda: su icono real es el de la ventana

_cache = {}


class _BITMAPINFOHEADER(ctypes.Structure):
    _fields_ = [
        ("biSize", wintypes.DWORD), ("biWidth", wintypes.LONG), ("biHeight", wintypes.LONG),
        ("biPlanes", wintypes.WORD), ("biBitCount", wintypes.WORD), ("biCompression", wintypes.DWORD),
        ("biSizeImage", wintypes.DWORD), ("biXPelsPerMeter", wintypes.LONG), ("biYPelsPerMeter", wintypes.LONG),
        ("biClrUsed", wintypes.DWORD), ("biClrImportant", wintypes.DWORD),
    ]


def _window_hicon(hwnd):
    for kind in (ICON_BIG, ICON_SMALL2):
        result = ctypes.c_size_t(0)
        user32.SendMessageTimeoutW(hwnd, WM_GETICON, kind, 0, SMTO_ABORTIFHUNG, 100, ctypes.byref(result))
        if result.value:
            return result.value
    return user32.GetClassLongPtrW(hwnd, GCLP_HICON)


def _hicon_image(hicon, size):
    """Dibuja un HICON sobre un DIB de 32 bits con alfa y lo devuelve como QImage."""
    screen = user32.GetDC(None)
    dc = gdi32.CreateCompatibleDC(screen)
    header = _BITMAPINFOHEADER(ctypes.sizeof(_BITMAPINFOHEADER), size, -size, 1, 32, 0, 0, 0, 0, 0, 0)
    bits = ctypes.c_void_p()
    bitmap = gdi32.CreateDIBSection(screen, ctypes.byref(header), 0, ctypes.byref(bits), None, 0)
    try:
        old = gdi32.SelectObject(dc, bitmap)
        user32.DrawIconEx(dc, 0, 0, hicon, size, size, 0, None, DI_NORMAL)
        gdi32.SelectObject(dc, old)
        raw = ctypes.string_at(bits, size * size * 4)
        return QImage(raw, size, size, size * 4, QImage.Format_ARGB32_Premultiplied).copy()
    finally:
        gdi32.DeleteObject(bitmap)
        gdi32.DeleteDC(dc)
        user32.ReleaseDC(None, screen)


def _shell_icon_image(parse_name, size):
    r"""Icono de un elemento del shell (por ejemplo una aplicación de la Tienda: 'shell:AppsFolder\<id>')."""
    pidl = ctypes.c_void_p()
    if shell32.SHParseDisplayName(parse_name, None, ctypes.byref(pidl), 0, None) != 0 or not pidl.value:
        return None
    try:
        info = _SHFILEINFOW()
        if not shell32.SHGetFileInfoW(pidl, 0, ctypes.byref(info), ctypes.sizeof(info), SHGFI_PIDL | SHGFI_ICON | SHGFI_LARGEICON):
            return None
        try:
            return _hicon_image(info.hIcon, size)
        finally:
            user32.DestroyIcon(info.hIcon)
    finally:
        ole32.CoTaskMemFree(pidl)


def generic_icon(px):
    """Icono de reserva: cuatro fichas redondeadas (una aplicación sin icono conocido)."""
    pm = QPixmap(px, px)
    pm.fill(Qt.transparent)
    p = QPainter(pm)
    p.setRenderHint(QPainter.Antialiasing)
    p.setPen(Qt.NoPen)
    p.setBrush(QColor(200, 200, 200, 190))
    gap, tile = px * 0.1, px * 0.36
    for row in range(2):
        for col in range(2):
            x, y = px * 0.14 + col * (tile + gap), px * 0.14 + row * (tile + gap)
            p.drawRoundedRect(QRectF(x, y, tile, tile), px * 0.08, px * 0.08)
    p.end()
    return pm


def app_icon(exe, hwnd=0, px=32, dpr=1.0):
    """Icono de la aplicación como QPixmap de `px` píxeles lógicos (nítido en pantallas con escala)."""
    size = round(px * dpr)
    framed = (exe or "").lower().endswith(FRAME_HOST)
    key = (hwnd if framed or not exe else exe, size)
    if key in _cache:
        return _cache[key]
    pixmap = None
    try:
        if framed and hwnd:
            hicon = _window_hicon(hwnd)
            if hicon:
                pixmap = QPixmap.fromImage(_hicon_image(hicon, size))
        elif exe.startswith("shell:"):
            image = _shell_icon_image(exe, size)
            pixmap = QPixmap.fromImage(image) if image is not None else None
        elif exe:
            icon = QFileIconProvider().icon(QFileInfo(exe))
            if not icon.isNull():
                pixmap = icon.pixmap(size, size)
        if pixmap is None and hwnd:
            hicon = _window_hicon(hwnd)
            if hicon:
                pixmap = QPixmap.fromImage(_hicon_image(hicon, size))
    except Exception:
        log.debug("No se pudo obtener el icono de %s", exe, exc_info=True)
    if pixmap is None or pixmap.isNull():
        pixmap = generic_icon(size)
    pixmap.setDevicePixelRatio(1.0)  # el icono del sistema puede venir ya con la escala de la pantalla: se normaliza
    if pixmap.width() != size or pixmap.height() != size:
        pixmap = pixmap.scaled(size, size, Qt.KeepAspectRatio, Qt.SmoothTransformation)
    pixmap.setDevicePixelRatio(dpr)
    _cache[key] = pixmap
    return pixmap
