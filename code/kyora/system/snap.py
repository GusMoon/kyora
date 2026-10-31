"""Apagar mientras Kyora está abierta los "acomodos" automáticos de Windows al arrastrar ventanas: acoplarlas a los
bordes, maximizarlas al llevarlas arriba, encogerlas al soltarlas de la barra de título de una maximizada. Kyora
coloca las ventanas sola y esos cambios de tamaño pelean con ella.

Los ajustes se cambian solo para la sesión (no se escriben en el registro): al cerrar Kyora se devuelven, y si Kyora
se cayera, Windows los recupera al cerrar sesión.
"""
import ctypes
import logging

log = logging.getLogger("kyora.system")

SPI_GETWINARRANGING, SPI_SETWINARRANGING = 0x0082, 0x0083
SPI_GETDOCKMOVING, SPI_SETDOCKMOVING = 0x0090, 0x0091
SETTINGS = ((SPI_GETWINARRANGING, SPI_SETWINARRANGING), (SPI_GETDOCKMOVING, SPI_SETDOCKMOVING))

_saved = {}


def _get(getter):
    value = ctypes.c_int(0)
    ok = ctypes.windll.user32.SystemParametersInfoW(getter, 0, ctypes.byref(value), 0)
    return bool(value.value) if ok else None


def _set(setter, on):
    return bool(ctypes.windll.user32.SystemParametersInfoW(setter, 0, ctypes.c_void_p(1 if on else 0), 0))


def disable():
    """Apaga el acoplado y el acomodo de ventanas de Windows (se recuerda cómo estaban)."""
    for getter, setter in SETTINGS:
        before = _get(getter)
        if before is None:
            continue
        _saved.setdefault(setter, before)
        if before and not _set(setter, False):
            log.warning("No se pudo apagar el acomodo de ventanas de Windows (%#x)", setter)


def restore():
    """Devuelve esos ajustes a como estaban antes de `disable`."""
    for setter, before in list(_saved.items()):
        _set(setter, before)
    _saved.clear()
