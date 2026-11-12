"""Shell de Windows para el explorador: carpetas conocidas, la Papelera y el diálogo "Abrir con"."""
import ctypes
import os
import subprocess
from ctypes import wintypes

from kyora.system.audio import GUID

shell32 = ctypes.WinDLL("shell32")
ole32 = ctypes.WinDLL("ole32")
shell32.SHGetKnownFolderPath.argtypes = [ctypes.POINTER(GUID), wintypes.DWORD, wintypes.HANDLE, ctypes.POINTER(ctypes.c_wchar_p)]
ole32.CoTaskMemFree.argtypes = [ctypes.c_void_p]

FO_DELETE = 3
FOF_SILENT, FOF_NOCONFIRMATION, FOF_ALLOWUNDO, FOF_NOERRORUI = 0x4, 0x10, 0x40, 0x400

# carpetas de Windows (respetan las que se movieron, por ejemplo a OneDrive)
FOLDERS = {
    "desktop": "B4BFCC3A-DB2C-424C-B029-7FE99A87C641",
    "documents": "FDD39AD0-238F-46AF-ADB4-6C85480369C7",
    "downloads": "374DE290-123F-4565-9164-39C4925E467B",
    "pictures": "33E28130-4E1E-4676-835A-98395C3BC3BB",
    "music": "4BD8D571-6D19-48D3-BE97-422220080E43",
    "videos": "18989B1D-99B5-455B-841C-AB7C74E4DDFC",
}


class SHFILEOPSTRUCTW(ctypes.Structure):
    _fields_ = [
        ("hwnd", wintypes.HWND), ("func", wintypes.UINT), ("source", ctypes.c_void_p), ("target", ctypes.c_void_p),
        ("flags", wintypes.WORD), ("aborted", wintypes.BOOL), ("mappings", ctypes.c_void_p),
        ("title", wintypes.LPCWSTR),
    ]


def known_folder(key):
    """Ruta de una carpeta de Windows (`FOLDERS`), o None."""
    path = ctypes.c_wchar_p()
    if shell32.SHGetKnownFolderPath(ctypes.byref(GUID.of(FOLDERS[key])), 0, None, ctypes.byref(path)) != 0:
        return None
    try:
        return path.value
    finally:
        ole32.CoTaskMemFree(path)


def recycle(paths):
    """Manda archivos y carpetas a la Papelera de Windows (se pueden recuperar desde ella)."""
    paths = [os.path.abspath(p) for p in paths]
    if not paths:
        return
    text = "\0".join(paths) + "\0"  # lista terminada en dos nulos (el búfer añade el segundo)
    source = ctypes.create_unicode_buffer(text, len(text) + 1)
    op = SHFILEOPSTRUCTW(None, FO_DELETE, ctypes.cast(source, ctypes.c_void_p), None,
                         FOF_ALLOWUNDO | FOF_NOCONFIRMATION | FOF_SILENT | FOF_NOERRORUI, False, None, None)
    code = shell32.SHFileOperationW(ctypes.byref(op))
    if code != 0 or op.aborted:
        raise OSError(f"No se pudo mandar a la Papelera (código {code})")


def open_with(path):
    """El diálogo de Windows para elegir con qué programa abrir un archivo."""
    subprocess.Popen(["rundll32.exe", "shell32.dll,OpenAs_RunDLL", os.path.abspath(path)])
