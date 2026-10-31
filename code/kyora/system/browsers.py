"""Navegadores instalados (registro de Windows) y apertura de una dirección con el que se elija."""
import ctypes
import logging
import os
import subprocess
import winreg

log = logging.getLogger("kyora.browsers")

CREATE_NO_WINDOW = 0x08000000
CLIENTS = r"SOFTWARE\Clients\StartMenuInternet"
HIVES = (
    (winreg.HKEY_LOCAL_MACHINE, winreg.KEY_READ | winreg.KEY_WOW64_64KEY),
    (winreg.HKEY_LOCAL_MACHINE, winreg.KEY_READ | winreg.KEY_WOW64_32KEY),
    (winreg.HKEY_CURRENT_USER, winreg.KEY_READ),
)


def exe_of(command):
    """La ruta del .exe dentro de la orden de `shell\\open\\command` (con o sin comillas, con o sin argumentos)."""
    command = os.path.expandvars((command or "").strip())
    if command.startswith('"'):
        end = command.find('"', 1)
        return command[1:end] if end > 0 else command[1:]
    lower = command.lower()
    cut = lower.find(".exe")
    return command[: cut + 4] if cut >= 0 else command


def _value(root, access, subkey):
    try:
        with winreg.OpenKey(root, subkey, 0, access) as key:
            return winreg.QueryValueEx(key, "")[0]
    except OSError:
        return None


def installed():
    """[{"name", "exe"}] de los navegadores registrados en Windows, sin repetidos y solo si el .exe existe."""
    found = {}
    for root, access in HIVES:
        try:
            clients = winreg.OpenKey(root, CLIENTS, 0, access)
        except OSError:
            continue
        with clients:
            for n in range(winreg.QueryInfoKey(clients)[0]):
                try:
                    sub = winreg.EnumKey(clients, n)
                except OSError:
                    break
                path = f"{CLIENTS}\\{sub}"
                exe = exe_of(_value(root, access, path + r"\shell\open\command"))
                if not exe or not os.path.isfile(exe) or os.path.basename(exe).lower() == "iexplore.exe":
                    continue  # Internet Explorer solo reenvía a Edge
                name = _value(root, access, path) or sub
                found.setdefault(os.path.normcase(exe), {"name": str(name), "exe": exe})
    return sorted(found.values(), key=lambda b: b["name"].lower())


def default_exe():
    """El .exe del navegador predeterminado de Windows ("" si no se puede saber)."""
    ASSOCSTR_EXECUTABLE = 2
    size = ctypes.c_ulong(1024)
    out = ctypes.create_unicode_buffer(size.value)
    try:
        ok = ctypes.windll.shlwapi.AssocQueryStringW(0, ASSOCSTR_EXECUTABLE, ".html", "open", out, ctypes.byref(size)) == 0
    except (AttributeError, OSError):
        return ""
    return out.value if ok and os.path.isfile(out.value) else ""


def open_url(url, exe=""):
    """Abre `url` con el navegador `exe`; sin él (o si ya no existe), con el predeterminado de Windows."""
    if exe and os.path.isfile(exe):
        subprocess.Popen([exe, url], creationflags=CREATE_NO_WINDOW)
    else:
        os.startfile(url)
