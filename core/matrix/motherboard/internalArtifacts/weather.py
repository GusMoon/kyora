"""Temperatura actual de unas coordenadas (Open-Meteo, sin API key)."""
import json
import threading
import urllib.request
from typing import Optional

from PySide6.QtCore import Signal

from core.matrix.motherboard.internalArtifacts.style import InfoRow
from core.resources.icons.information import weather

OPEN_METEO_URL = "https://api.open-meteo.com/v1/forecast?latitude={lat}&longitude={lon}&current_weather=true"
TIMEOUT_S = 5
UNKNOWN_TEXT = "--°C"


def fetch_temperature(lat: float, lon: float) -> Optional[float]:
    """Consulta la temperatura actual en grados Celsius.

    Args:
        lat: latitud.
        lon: longitud.

    Returns:
        La temperatura, o None si la consulta falla.
    """
    try:
        request = urllib.request.Request(
            OPEN_METEO_URL.format(lat=lat, lon=lon), headers={"User-Agent": "Mozilla/5.0"}
        )
        with urllib.request.urlopen(request, timeout=TIMEOUT_S) as response:
            data = json.loads(response.read())
        return float(data["current_weather"]["temperature"])
    except Exception:
        return None


class Weather(InfoRow):
    """Fila con icono de clima que muestra la temperatura del lugar indicado con ``set_coordinates``."""

    _resolved = Signal(object)  # puente del hilo de red al hilo de la interfaz

    def __init__(self, parent=None):
        super().__init__(weather.draw, UNKNOWN_TEXT, parent=parent)

        self._resolved.connect(self._on_resolved)

    def set_coordinates(self, lat: float, lon: float) -> None:
        """Consulta la temperatura de las coordenadas sin bloquear la interfaz."""
        threading.Thread(
            target=lambda: self._resolved.emit(fetch_temperature(lat, lon)), daemon=True
        ).start()

    def _on_resolved(self, temperature: Optional[float]) -> None:
        self.set_text(UNKNOWN_TEXT if temperature is None else f"{temperature}°C")
