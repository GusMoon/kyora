"""El clima del Lobby: Open-Meteo (gratis y sin cuenta).

Dónde: la ciudad de config.json (`weather.city`) si hay una; si no, la ubicación aproximada de la IP pública
(ipwho.is, y si falla ipapi.co). La ciudad se convierte una vez en coordenadas y se guarda en weather.json; la
ubicación por IP se guarda en location.json y se renueva cada 12 horas (por si viajas).
"""
import json
import logging
import time
import urllib.parse
import urllib.request

log = logging.getLogger("kyora.weather")

GEOCODE_URL = "https://geocoding-api.open-meteo.com/v1/search?name={}&count=1&language=es&format=json"
FORECAST_URL = (
    "https://api.open-meteo.com/v1/forecast?latitude={}&longitude={}"
    "&current=temperature_2m,weather_code,is_day&timezone=auto"
    "&hourly=temperature_2m,weather_code,is_day&forecast_hours=8"
)
HOURS = 6  # horas siguientes en la franja del Lobby (más la de ahora)
TIMEOUT = 10
IP_SERVICES = ("https://ipwho.is/", "https://ipapi.co/json/")
IP_MAX_AGE = 12 * 3600

# códigos del tiempo de la OMM (los que usa Open-Meteo) -> (icono, texto)
_CODES = (
    ((0,), "clear", "Despejado"),
    ((1,), "clear", "Casi despejado"),
    ((2,), "partly", "Parcialmente nublado"),
    ((3,), "cloud", "Nublado"),
    ((45, 48), "fog", "Niebla"),
    ((51, 53, 55, 56, 57), "rain", "Llovizna"),
    ((61, 63, 65, 66, 67), "rain", "Lluvia"),
    ((80, 81, 82), "rain", "Chubascos"),
    ((71, 73, 75, 77), "snow", "Nieve"),
    ((85, 86), "snow", "Chubascos de nieve"),
    ((95, 96, 99), "storm", "Tormenta"),
)


def describe(code, is_day=True):
    """(icono, texto) de un código del tiempo. Los iconos son los de kyora/ui/glyphs.py (WEATHER)."""
    for codes, icon, text in _CODES:
        if code in codes:
            if icon == "clear":
                icon = "sun" if is_day else "night"
            elif icon == "partly":
                icon = "partly_day" if is_day else "partly_night"
            return icon, text
    return "cloud", "Sin datos del cielo"


def parse_hours(data, after=""):
    """[{hour: "23", temp, icon}] de las próximas horas (las posteriores a `after`, "2026-10-21T22:45")."""
    hourly = data.get("hourly") or {}
    rows = zip(hourly.get("time", ()), hourly.get("temperature_2m", ()), hourly.get("weather_code", ()),
               hourly.get("is_day", ()))
    hours = []
    for moment, temp, code, is_day in rows:
        if moment > after and temp is not None and code is not None:
            hours.append({"hour": moment[11:13], "temp": round(float(temp)),
                          "icon": describe(int(code), bool(is_day))[0]})
    return hours[:HOURS]


def parse_current(data, place=""):
    """Respuesta de Open-Meteo -> {temp, icon, text, place, hours}."""
    current = data["current"]
    icon, text = describe(int(current["weather_code"]), bool(current.get("is_day", 1)))
    return {"temp": round(float(current["temperature_2m"])), "icon": icon, "text": text, "place": place,
            "hours": parse_hours(data, current.get("time", ""))}


def _get(url):
    request = urllib.request.Request(url, headers={"User-Agent": "Kyora"})
    with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
        return json.loads(response.read().decode("utf-8"))


def locate(city, cache_path):
    """(latitud, longitud, nombre) de la ciudad; se guarda en `cache_path` mientras la ciudad no cambie."""
    try:
        cached = json.loads(cache_path.read_text(encoding="utf-8"))
        if cached.get("city") == city:
            return cached["lat"], cached["lon"], cached["name"]
    except (OSError, ValueError, KeyError):
        pass
    results = _get(GEOCODE_URL.format(urllib.parse.quote(city))).get("results") or []
    if not results:
        raise LookupError(f"No se encontró la ciudad «{city}»")
    hit = results[0]
    name = ", ".join(x for x in (hit.get("name"), hit.get("country")) if x)
    try:
        cache_path.write_text(json.dumps({"city": city, "lat": hit["latitude"], "lon": hit["longitude"], "name": name}),
                              encoding="utf-8")
    except OSError:
        log.warning("No se pudo guardar weather.json")
    return hit["latitude"], hit["longitude"], name


def parse_ip(data):
    """(latitud, longitud, "Ciudad, País") de la respuesta de ipwho.is o de ipapi.co."""
    if data.get("success") is False or data.get("error"):
        raise LookupError(data.get("message") or data.get("reason") or "Sin ubicación")
    lat, lon = data.get("latitude"), data.get("longitude")
    if lat is None or lon is None:
        raise LookupError("La respuesta no trae coordenadas")
    country = data.get("country") or data.get("country_name")
    name = ", ".join(x for x in (data.get("city"), country) if x)
    return float(lat), float(lon), name


def locate_ip(cache_path, now=time.time):
    """(latitud, longitud, nombre) de donde está el equipo según su IP pública; se guarda 12 horas."""
    try:
        cached = json.loads(cache_path.read_text(encoding="utf-8"))
        if now() - cached["at"] < IP_MAX_AGE:
            return cached["lat"], cached["lon"], cached["name"]
    except (OSError, ValueError, KeyError, TypeError):
        pass
    errors = []
    for url in IP_SERVICES:
        try:
            lat, lon, name = parse_ip(_get(url))
            break
        except (OSError, ValueError, LookupError) as err:
            errors.append(f"{url}: {err}")
    else:
        raise LookupError("No se pudo saber dónde estás (" + "; ".join(errors) + ")")
    try:
        cache_path.write_text(json.dumps({"lat": lat, "lon": lon, "name": name, "at": now()}, ensure_ascii=False),
                              encoding="utf-8")
    except OSError:
        log.warning("No se pudo guardar location.json")
    return lat, lon, name


def current(city, cache_path):
    """El tiempo de ahora: en la ciudad, o donde diga la IP si no hay ciudad. Lanza OSError/LookupError/ValueError si
    no se puede saber."""
    if city:
        lat, lon, name = locate(city, cache_path)
    else:
        lat, lon, name = locate_ip(cache_path.with_name("location.json"))
    return parse_current(_get(FORECAST_URL.format(lat, lon)), name)
