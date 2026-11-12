"""Estado del wifi: de la API Native Wifi (kyora/system/wlan.py) y, si falla, de `netsh wlan show interfaces`."""
import ctypes
import re
import subprocess

CREATE_NO_WINDOW = 0x08000000
OFF = {"available": False, "connected": False, "ssid": "", "signal": 0}


def parse(output):
    ssid = re.search(r"^\s*SSID\s*:\s*(.+?)\s*$", output, re.MULTILINE)
    signal = re.search(r":\s*(\d+)\s*%", output)
    if not ssid:
        return {"available": "wlan" in output.lower() or "Wi-Fi" in output, "connected": False, "ssid": "", "signal": 0}
    return {
        "available": True,
        "connected": True,
        "ssid": ssid.group(1),
        "signal": int(signal.group(1)) if signal else 0,
    }


def status():
    try:
        from kyora.system import wlan

        return wlan.status()
    except OSError:
        pass  # sin wlanapi: se mira con netsh
    try:
        result = subprocess.run(
            ["netsh", "wlan", "show", "interfaces"],
            check=False, capture_output=True, timeout=5, creationflags=CREATE_NO_WINDOW,
        )
    except (OSError, subprocess.TimeoutExpired):
        return dict(OFF)
    # netsh escribe en la página de códigos OEM de la consola (850 en español)
    text = result.stdout.decode(f"cp{ctypes.windll.kernel32.GetOEMCP()}", errors="replace")
    return parse(text)
