"""El fondo de pantalla de Windows: cuál es y cambiarlo (para el carrusel `wallpapers` del buscador)."""
import ctypes
import os

SPI_SETDESKWALLPAPER = 0x0014
SPI_GETDESKWALLPAPER = 0x0073
SPIF_UPDATEINIFILE = 0x01  # que se quede al reiniciar
SPIF_SENDCHANGE = 0x02  # y que se enteren las demás aplicaciones


def current():
    """Ruta de la imagen del fondo de pantalla actual, o ''."""
    buf = ctypes.create_unicode_buffer(520)
    ctypes.windll.user32.SystemParametersInfoW(SPI_GETDESKWALLPAPER, len(buf), buf, 0)
    return buf.value


def set_wallpaper(path):
    """Pone `path` de fondo de pantalla. Lanza OSError si Windows no lo acepta."""
    path = os.path.abspath(path)
    if not os.path.isfile(path):
        raise OSError(f"No existe {path}")
    ok = ctypes.windll.user32.SystemParametersInfoW(SPI_SETDESKWALLPAPER, 0, path,
                                                    SPIF_UPDATEINIFILE | SPIF_SENDCHANGE)
    if not ok:
        raise ctypes.WinError()
