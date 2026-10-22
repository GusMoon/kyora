import xml.etree.ElementTree as ET

import pytest

from kyora.system.wlan import merge_networks, profile_xml

NS = "{http://www.microsoft.com/networking/WLAN/profile/v1}"


def _read(xml):
    root = ET.fromstring(xml)
    auth = root.find(f"{NS}MSM/{NS}security/{NS}authEncryption")
    key = root.find(f"{NS}MSM/{NS}security/{NS}sharedKey/{NS}keyMaterial")
    return (root.find(f"{NS}name").text, auth.find(f"{NS}authentication").text, auth.find(f"{NS}encryption").text,
            key.text if key is not None else None, root.find(f"{NS}SSIDConfig/{NS}SSID/{NS}hex").text)


def test_wpa2_profile_escapes_name_and_password():
    name, auth, enc, key, hexname = _read(profile_xml("Casa & <5G>", 7, 4, 'pa"ss<word>'))
    assert (name, auth, enc, key) == ("Casa & <5G>", "WPA2PSK", "AES", 'pa"ss<word>')
    assert bytes.fromhex(hexname).decode() == "Casa & <5G>"


def test_open_and_wpa3_profiles():
    assert _read(profile_xml("Libre", 1, 0))[1:4] == ("open", "none", None)
    assert _read(profile_xml("Nueva", 9, 4, "secreto123"))[1:3] == ("WPA3SAE", "AES")


def test_profile_needs_password_and_personal_network():
    with pytest.raises(ValueError):
        profile_xml("Casa", 7, 4)
    with pytest.raises(ValueError):
        profile_xml("Oficina", 6, 4, "x")  # WPA2 de empresa (802.1X)


def test_networks_are_merged_and_sorted():
    def net(ssid, signal, profile=False, connected=False):
        return {"ssid": ssid, "signal": signal, "has_profile": profile, "profile": ssid if profile else "",
                "connected": connected}

    merged = merge_networks([net("B", 40), net("A", 90), net("B", 70, profile=True), net("", 99), net("C", 10, connected=True)])
    assert [n["ssid"] for n in merged] == ["C", "A", "B"]
    b = merged[2]
    assert b["signal"] == 70 and b["has_profile"] and b["profile"] == "B"
