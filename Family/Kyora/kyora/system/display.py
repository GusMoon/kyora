"""Brillo de la pantalla del portátil por WMI (win32com, que viene con pywin32).

Los monitores externos no suelen admitirlo: entonces `get()` devuelve None y la barra no muestra el brillo.
Hay que llamarlo desde un hilo con COM iniciado (pythoncom.CoInitialize).
"""
import logging

log = logging.getLogger("kyora.display")


_service = None  # la conexión a WMI tarda más de un segundo la primera vez: se guarda (solo la usa un hilo)


def _wmi():
    global _service
    if _service is None:
        import win32com.client  # se importa aquí: arrancar COM solo cuando hace falta

        _service = win32com.client.GetObject(r"winmgmts:\\.\root\WMI")
    return _service


def get():
    """Brillo 0-100, o None si la pantalla no deja cambiarlo."""
    try:
        for monitor in _wmi().InstancesOf("WmiMonitorBrightness"):
            return int(monitor.CurrentBrightness)
    except Exception:
        log.debug("Brillo no disponible", exc_info=True)
    return None


def set_brightness(level):
    level = int(min(max(level, 0), 100))
    for methods in _wmi().InstancesOf("WmiMonitorBrightnessMethods"):
        methods.WmiSetBrightness(1, level)  # 1 s de transición: como el control de Windows
        return level
    raise OSError("Esta pantalla no deja cambiar el brillo")
