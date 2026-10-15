"""Ubicación aproximada del usuario a partir de su IP (ip-api.com)."""
import json
import threading
import urllib.request
from typing import Optional

from PySide6.QtCore import Signal

from core.matrix.motherboard.internalArtifacts.style import InfoRow
from core.resources.icons.information import location as location_icon

IP_API_URL = "http://ip-api.com/json/"
TIMEOUT_S = 5
UNKNOWN_TEXT = "Ubicación desconocida"


def fetch_location() -> Optional[dict]:
    """Consulta la ubicación por IP.

    Returns:
        Diccionario con ``city``, ``country``, ``lat`` y ``lon``, o None si la
        consulta falla o no trae coordenadas.
    """
    try:
        request = urllib.request.Request(IP_API_URL, headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(request, timeout=TIMEOUT_S) as response:
            data = json.loads(response.read())
    except Exception:
        return None

    city = data.get("city", "Desconocido")
    country = data.get("country", "Desconocido")
    lat, lon = data.get("lat"), data.get("lon")

    # Cloudflare WARP enruta el tráfico de la península hacia Cancún: si se detecta
    # ese proxy se fuerza la ubicación real del usuario.
    if "Cloudflare" in data.get("isp", "") and "Canc" in city:
        city, country, lat, lon = "Mérida", "Mexico", 20.9674, -89.6237

    if not lat or not lon:
        return None
    return {"city": city, "country": country, "lat": lat, "lon": lon}


class Location(InfoRow):
    """Fila con icono de globo que muestra "Ciudad, País" y emite las coordenadas cuando las obtiene.

    Signals:
        located(float, float): latitud y longitud de la ubicación encontrada.
    """

    located = Signal(float, float)
    _resolved = Signal(object)  # puente del hilo de red al hilo de la interfaz

    def __init__(self, parent=None):
        super().__init__(location_icon.draw, "Ubicando...", parent=parent)

        self._resolved.connect(self._on_resolved)
        self.refresh()

    def refresh(self) -> None:
        """Vuelve a consultar la ubicación sin bloquear la interfaz."""
        threading.Thread(target=lambda: self._resolved.emit(fetch_location()), daemon=True).start()

    def _on_resolved(self, result: Optional[dict]) -> None:
        if result is None:
            self.set_text(UNKNOWN_TEXT)
            return
        self.set_text(f"{result['city']}, {result['country']}")
        self.located.emit(result["lat"], result["lon"])
