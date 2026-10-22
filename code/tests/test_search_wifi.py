import pytest

from kyora.search.apps import AppIndex, score
from kyora.system import wifi
from kyora.system.hotkeys import MOD_ALT, MOD_SHIFT, parse_combo


def test_score_orders_prefix_before_substring():
    assert score("chr", "Chrome") == 0
    assert score("stu", "Visual Studio Code") == 1
    assert score("udio", "Visual Studio Code") == 2
    assert score("vsc", "Visual Studio Code") == 3
    assert score("zzz", "Visual Studio Code") is None
    assert score("", "Visual Studio Code") is None


def test_search_ranks_and_limits():
    index = AppIndex.__new__(AppIndex)
    index.entries = [
        {"name": "Notepad", "kind": "lnk", "target": "a"},
        {"name": "Visual Studio Code", "kind": "lnk", "target": "b"},
        {"name": "Notas", "kind": "lnk", "target": "c"},
    ]
    assert [e["name"] for e in index.search("not")] == ["Notas", "Notepad"]
    assert len(index.search("o", limit=1)) == 1


CONNECTED = """
    Nombre                 : Wi-Fi
    Estado                 : conectado
    SSID                   : MiRed
    BSSID                  : aa:bb:cc:dd:ee:ff
    Señal                  : 87%
"""


def test_wifi_parse_connected():
    assert wifi.parse(CONNECTED) == {"available": True, "connected": True, "ssid": "MiRed", "signal": 87}


def test_wifi_parse_disconnected():
    result = wifi.parse("    Nombre : Wi-Fi\n    Estado : desconectado\n")
    assert result["connected"] is False and result["ssid"] == ""


def test_parse_combo():
    assert parse_combo("alt+shift+h") == (MOD_ALT | MOD_SHIFT, ord("H"))
    assert parse_combo("alt+space")[1] == 0x20
    with pytest.raises(ValueError):
        parse_combo("h")
    with pytest.raises(ValueError):
        parse_combo("alt+ñ")
