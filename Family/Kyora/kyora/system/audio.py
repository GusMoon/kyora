"""Volumen del altavoz por defecto con Core Audio (IAudioEndpointVolume), por ctypes y sin dependencias.

Hay que llamarlo desde un hilo con COM iniciado (pythoncom.CoInitialize). Cada llamada pide el dispositivo por
defecto, así que si cambias de altavoz o auriculares sigue funcionando.
"""
import ctypes
import uuid
from ctypes import wintypes

ole32 = ctypes.WinDLL("ole32")
CLSCTX_ALL = 23
E_RENDER, E_MULTIMEDIA = 0, 1


class GUID(ctypes.Structure):
    _fields_ = [("bytes", ctypes.c_ubyte * 16)]

    @classmethod
    def of(cls, text):
        g = cls()
        ctypes.memmove(g.bytes, uuid.UUID(text).bytes_le, 16)
        return g


CLSID_ENUMERATOR = GUID.of("BCDE0395-E52F-467C-8E3D-C4579291692E")
IID_ENUMERATOR = GUID.of("A95664D2-9614-4F35-A746-DE8DB63617E6")
IID_ENDPOINT_VOLUME = GUID.of("5CDF2C82-841E-4546-9722-0CF74078229A")
HRESULT = ctypes.c_long


def _call(obj, index, *args, argtypes=()):
    """Llama al método `index` de la tabla de una interfaz COM."""
    table = ctypes.cast(obj, ctypes.POINTER(ctypes.POINTER(ctypes.c_void_p)))[0]
    fn = ctypes.WINFUNCTYPE(HRESULT, ctypes.c_void_p, *argtypes)(table[index])
    result = fn(obj, *args)
    if result < 0:
        raise OSError(f"Core Audio respondió {result & 0xFFFFFFFF:#010x}")
    return result


def _release(obj):
    if obj:
        _call(obj, 2)


class _Endpoint:
    """`with _Endpoint() as volume:` da el IAudioEndpointVolume del altavoz por defecto y lo suelta al salir."""

    def __enter__(self):
        self._objects = []
        enumerator = ctypes.c_void_p()
        hr = ole32.CoCreateInstance(ctypes.byref(CLSID_ENUMERATOR), None, CLSCTX_ALL,
                                    ctypes.byref(IID_ENUMERATOR), ctypes.byref(enumerator))
        if hr < 0:
            raise OSError(f"No hay Core Audio ({hr & 0xFFFFFFFF:#010x})")
        self._objects.append(enumerator)
        device = ctypes.c_void_p()
        _call(enumerator, 4, E_RENDER, E_MULTIMEDIA, ctypes.byref(device),
              argtypes=(ctypes.c_int, ctypes.c_int, ctypes.POINTER(ctypes.c_void_p)))
        self._objects.append(device)
        volume = ctypes.c_void_p()
        _call(device, 3, ctypes.byref(IID_ENDPOINT_VOLUME), CLSCTX_ALL, None, ctypes.byref(volume),
              argtypes=(ctypes.POINTER(GUID), wintypes.DWORD, ctypes.c_void_p, ctypes.POINTER(ctypes.c_void_p)))
        self._objects.append(volume)
        return volume

    def __exit__(self, *_):
        for obj in reversed(self._objects):
            _release(obj)


def get():
    """{level: 0-100, muted: bool} del altavoz por defecto."""
    with _Endpoint() as volume:
        level, muted = ctypes.c_float(), wintypes.BOOL()
        _call(volume, 9, ctypes.byref(level), argtypes=(ctypes.POINTER(ctypes.c_float),))
        _call(volume, 15, ctypes.byref(muted), argtypes=(ctypes.POINTER(wintypes.BOOL),))
        return {"level": round(level.value * 100), "muted": bool(muted.value)}


def set_volume(level=None, muted=None):
    """Cambia el nivel (0-100) y/o el silencio; devuelve el estado nuevo."""
    with _Endpoint() as volume:
        if level is not None:
            value = min(max(float(level), 0.0), 100.0) / 100
            _call(volume, 7, ctypes.c_float(value), None, argtypes=(ctypes.c_float, ctypes.c_void_p))
        if muted is not None:
            _call(volume, 14, wintypes.BOOL(bool(muted)), None, argtypes=(wintypes.BOOL, ctypes.c_void_p))
    return get()
