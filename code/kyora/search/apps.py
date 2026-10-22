"""Búsqueda de aplicaciones instaladas (Menú Inicio) y apertura."""
import json
import logging
import os
import subprocess
import threading
from pathlib import Path

log = logging.getLogger("kyora.search")

CREATE_NO_WINDOW = 0x08000000


def score(query, name):
    """Menor es mejor; None si no coincide. Prefiere el inicio del nombre o de una palabra."""
    q, n = query.lower().strip(), name.lower()
    if not q:
        return None
    if n.startswith(q):
        return 0
    if any(word.startswith(q) for word in n.replace("-", " ").replace("_", " ").split()):
        return 1
    if q in n:
        return 2
    initials = "".join(word[0] for word in n.replace("-", " ").replace("_", " ").split())
    if len(q) >= 2 and initials.startswith(q):
        return 3
    return None


def _start_menu_shortcuts():
    roots = [
        Path(os.environ.get("ProgramData", "C:/ProgramData")) / "Microsoft/Windows/Start Menu/Programs",
        Path(os.environ.get("APPDATA", "")) / "Microsoft/Windows/Start Menu/Programs",
    ]
    for root in roots:
        if root.exists():
            for lnk in root.rglob("*.lnk"):
                yield {"name": lnk.stem, "kind": "lnk", "target": str(lnk)}


def _start_apps():
    """Aplicaciones del Menú Inicio, incluidas las de la Tienda (Get-StartApps)."""
    try:
        result = subprocess.run(
            ["powershell", "-NoProfile", "-NonInteractive", "-Command",
             # sin forzar UTF-8, PowerShell escribe en la página de códigos de la consola y se pierden los acentos
             ("[Console]::OutputEncoding = [Text.Encoding]::UTF8; "
              "Get-StartApps | Select-Object Name,AppID | ConvertTo-Json -Compress")],
            check=False, capture_output=True, timeout=30, creationflags=CREATE_NO_WINDOW,
        )
        data = json.loads(result.stdout.decode("utf-8", errors="replace") or "[]")
    except (OSError, subprocess.TimeoutExpired, ValueError):
        return []
    if isinstance(data, dict):
        data = [data]
    return [{"name": d["Name"], "kind": "appid", "target": d["AppID"]} for d in data if d.get("Name") and d.get("AppID")]


class AppIndex:
    def __init__(self):
        self.entries = []
        self.ready = threading.Event()
        threading.Thread(target=self._load, daemon=True, name="kyora-appindex").start()

    def _load(self):
        try:
            entries = {}
            for entry in _start_menu_shortcuts():
                entries.setdefault(entry["name"].lower(), entry)
            for entry in _start_apps():  # tienen prioridad: abren igual que el Menú Inicio
                entries[entry["name"].lower()] = entry
            self.entries = sorted(entries.values(), key=lambda e: e["name"].lower())
        except Exception:
            log.exception("No se pudo indexar el Menú Inicio")
        finally:
            self.ready.set()

    def search(self, query, limit=8):
        scored = []
        for entry in self.entries:
            s = score(query, entry["name"])
            if s is not None:
                scored.append((s, len(entry["name"]), entry))
        scored.sort(key=lambda t: (t[0], t[1], t[2]["name"].lower()))
        return [e for _, _, e in scored[:limit]]

    @staticmethod
    def launch(entry):
        if entry["kind"] == "lnk":
            os.startfile(entry["target"])
        else:
            subprocess.Popen(["explorer.exe", f"shell:AppsFolder\\{entry['target']}"], creationflags=CREATE_NO_WINDOW)
