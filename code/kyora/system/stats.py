"""Uso del equipo para el Lobby: CPU, RAM, disco y batería (psutil; solo lectura y barato), y quién lo usa."""
import getpass
import os
from collections import deque

import psutil
import pywintypes
import win32api

DISK = "C:\\"
HISTORY = 60  # valores guardados de CPU y RAM (uno por lectura: 2 minutos con una lectura cada 2 s)


def usage(disk=True):
    """{cpu, ram, ram_used, ram_total} y, si `disk`, también {disk, disk_used, disk_total}. Porcentajes enteros."""
    memory = psutil.virtual_memory()
    data = {
        "cpu": round(psutil.cpu_percent(None)),  # desde la llamada anterior: no bloquea
        "ram": round(memory.percent), "ram_used": memory.used, "ram_total": memory.total,
    }
    battery = psutil.sensors_battery()
    if battery is not None:
        data.update(battery=round(battery.percent), plugged=bool(battery.power_plugged))
    if disk:
        try:
            d = psutil.disk_usage(DISK)
            data.update(disk=round(d.percent), disk_used=d.used, disk_total=d.total)
        except OSError:
            pass
    return data


class History:
    """Los últimos valores de CPU y RAM, para la gráfica de rendimiento."""

    def __init__(self, size=HISTORY):
        self.cpu, self.ram = deque(maxlen=size), deque(maxlen=size)

    def add(self, data):
        if "cpu" in data:
            self.cpu.append(data["cpu"])
            self.ram.append(data["ram"])

    def as_dict(self):
        return {"cpu": list(self.cpu), "ram": list(self.ram)}


def gigabytes(n):
    """Bytes -> texto en GB con coma decimal, como se escribe en español."""
    return f"{n / 1024 ** 3:.1f}".replace(".", ",")


def user_info():
    """(nombre para mostrar, nombre del equipo) de quien usa Windows."""
    try:
        name = win32api.GetUserNameEx(3)  # NameDisplay: el nombre completo (falla en algunas cuentas locales)
    except pywintypes.error:
        name = ""
    return name or getpass.getuser(), os.environ.get("COMPUTERNAME", "")
