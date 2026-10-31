import json

import pytest

from kyora.system import launch, stats, weather


def test_weather_codes_become_icons_and_spanish_text():
    assert weather.describe(0, True) == ("sun", "Despejado")
    assert weather.describe(0, False) == ("night", "Despejado")
    assert weather.describe(2, False) == ("partly_night", "Parcialmente nublado")
    assert weather.describe(63) == ("rain", "Lluvia")
    assert weather.describe(95) == ("storm", "Tormenta")
    assert weather.describe(1234)[0] == "cloud"


def test_open_meteo_answer_is_read():
    data = {"current": {"temperature_2m": 17.6, "weather_code": 3, "is_day": 1}}
    assert weather.parse_current(data, "Madrid, España") == {
        "temp": 18, "icon": "cloud", "text": "Nublado", "place": "Madrid, España", "hours": [],
    }


def test_open_meteo_hours_after_now():
    data = {
        "current": {"time": "2026-10-21T22:45", "temperature_2m": 17.6, "weather_code": 3, "is_day": 0},
        "hourly": {
            "time": [f"2026-10-21T{h:02d}:00" for h in (22, 23)] + [f"2026-10-22T{h:02d}:00" for h in range(6)],
            "temperature_2m": [17.2, 16.6, 16.1, 15.8, 15.2, 14.9, 14.4, 14.0],
            "weather_code": [3, 61, 61, 0, 0, 2, 2, 3],
            "is_day": [0, 0, 0, 0, 0, 0, 0, 1],
        },
    }
    hours = weather.parse_current(data)["hours"]
    assert len(hours) == weather.HOURS
    assert hours[0] == {"hour": "23", "temp": 17, "icon": "rain"}
    assert hours[2] == {"hour": "01", "temp": 16, "icon": "night"}


def test_city_coordinates_are_cached(tmp_path, monkeypatch):
    calls = []

    def fake_get(url):
        calls.append(url)
        return {"results": [{"name": "Madrid", "country": "España", "latitude": 40.4, "longitude": -3.7}]}

    monkeypatch.setattr(weather, "_get", fake_get)
    cache = tmp_path / "weather.json"
    assert weather.locate("Madrid", cache) == (40.4, -3.7, "Madrid, España")
    assert weather.locate("Madrid", cache) == (40.4, -3.7, "Madrid, España")
    assert len(calls) == 1 and json.loads(cache.read_text(encoding="utf-8"))["city"] == "Madrid"
    monkeypatch.setattr(weather, "_get", lambda url: {"results": []})
    with pytest.raises(LookupError):
        weather.locate("Ningunlugar", cache)


def test_usage_has_percentages():
    data = stats.usage()
    assert 0 <= data["ram"] <= 100 and 0 <= data["cpu"] <= 100 and "disk" in data
    assert stats.gigabytes(1.5 * 1024 ** 3) == "1,5"


def test_owl_menu_scripts_are_a_closed_list(tmp_path):
    assert launch.script_command("rescate", tmp_path)[-1].endswith("rescate_kyora.bat")
    assert launch.script_command("consola", tmp_path)[-1] == "--restart"
    assert launch.closes_kyora("rescate") and not launch.closes_kyora("actualizar")
    with pytest.raises(ValueError):
        launch.script_command("../../otra_cosa")
    for bat, _, _ in launch.SCRIPTS.values():
        assert (launch.ROOT / "scripts" / bat).exists()


def test_owl_menu_only_offers_known_scripts():
    from kyora.core.commands import KYORA_OPTIONS

    for _, _, action, payload in KYORA_OPTIONS:
        if action == "app.run_script":
            assert payload["name"] in launch.SCRIPTS


def test_location_by_ip_is_cached_and_falls_back(tmp_path, monkeypatch):
    calls = []

    def fake_get(url):
        calls.append(url)
        if "ipwho" in url:
            raise OSError("caído")
        return {"latitude": 20.97, "longitude": -89.62, "city": "Mérida", "country_name": "Mexico"}

    monkeypatch.setattr(weather, "_get", fake_get)
    cache = tmp_path / "location.json"
    clock = [1000.0]
    assert weather.locate_ip(cache, now=lambda: clock[0]) == (20.97, -89.62, "Mérida, Mexico")
    assert len(calls) == 2  # el primero falló: usó el de respaldo
    weather.locate_ip(cache, now=lambda: clock[0])
    assert len(calls) == 2  # de la caché
    clock[0] += weather.IP_MAX_AGE + 1
    weather.locate_ip(cache, now=lambda: clock[0])
    assert len(calls) == 4  # caducó: se vuelve a preguntar


def test_ipwhois_answer_and_errors():
    assert weather.parse_ip({"success": True, "latitude": 1, "longitude": 2, "city": "Mérida", "country": "México"}) \
        == (1.0, 2.0, "Mérida, México")
    try:
        weather.parse_ip({"success": False, "message": "límite"})
    except LookupError as err:
        assert "límite" in str(err)
    else:
        raise AssertionError("debía fallar")
