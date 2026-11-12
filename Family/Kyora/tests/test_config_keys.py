from kyora.config import DEFAULTS
from kyora.system.hotkeys import parse_chord, parse_combo, split_bindings


def test_default_shortcuts():
    keys = DEFAULTS["hotkeys"]
    arrows = ("left", "right", "up", "down")
    expected = {
        "ctrl+shift+space": ["search.toggle", {}],
        "ctrl+shift+t": ["search.open_mode", {"mode": "task"}],
        "ctrl+shift+n": ["search.open_mode", {"mode": "notes"}],
        "ctrl+shift+f": ["wm.focus_next", {}],
        "ctrl+shift+r": ["switcher.toggle", {}],
        "ctrl+shift+w": ["wallpaper.mode", {}],
        "ctrl+shift+e": ["desktop.create", {}],
        "ctrl+shift+x": ["power.menu", {}],
        "ctrl+shift+q": ["wm.close", {}],
        "ctrl+shift+alt+x": ["wm.close_all", {}],
        "ctrl+shift+m": ["music.panel", {}],
        "ctrl+shift+c": ["search.open_mode", {"mode": "chat"}],
        **{f"ctrl+shift+{d}": ["wm.move", {"dir": d}] for d in arrows},
        **{f"ctrl+shift+alt+{d}": ["wm.arrange", {"dir": d}] for d in arrows},
        **{f"ctrl+shift+{n}": ["wm.show_count", {"n": n}] for n in (1, 2, 3)},
        "ctrl+shift+pageup": ["desktop.step", {"delta": -1}],
        "ctrl+shift+pagedown": ["desktop.step", {"delta": 1}],
        "ctrl+shift+alt+e": ["desktop.close_current", {}],
        "ctrl+alt+shift+q": ["app.release", {}],
    }
    assert keys == expected
    assert not any("win" in combo.split("+") for combo in keys)  # la tecla Windows no se usa
    normal, chords, taps, failed = split_bindings(keys)
    assert normal == keys and not chords and not taps and not failed  # todos por RegisterHotKey
    for combo in normal:
        parse_combo(combo)


def test_two_key_chords_can_still_be_added_in_the_config():
    bindings = {"alt+f+left": ["wm.focus", {"dir": "left"}], "alt+f": ["wm.float_toggle", {}], "alt+e": ["switcher.toggle", {}]}
    normal, chords, taps, failed = split_bindings(bindings)
    assert chords == {(ord("F"), 0x25): ["wm.focus", {"dir": "left"}]}
    assert taps == {ord("F"): ["wm.float_toggle", {}]}
    assert normal == {"alt+e": ["switcher.toggle", {}]} and not failed
    assert parse_chord("alt+m+down") == (ord("M"), 0x28)


def test_shortcuts_with_the_windows_key_are_rejected_because_windows_is_blocked():
    bindings = {"win+up": ["a", {}], "win": ["b", {}], "win+esc+esc": ["c", {}], "ctrl+shift+u": ["d", {}]}
    normal, chords, taps, failed = split_bindings(bindings)
    assert normal == {"ctrl+shift+u": ["d", {}]} and not chords and not taps
    assert failed == ["win+up", "win", "win+esc+esc"]


def test_page_keys_are_known():
    assert parse_combo("ctrl+shift+pageup")[1] == 0x21
    assert parse_combo("ctrl+shift+pagedown")[1] == 0x22
