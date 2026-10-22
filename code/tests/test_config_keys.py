from kyora.config import DEFAULTS
from kyora.system.hotkeys import parse_chord, parse_combo, split_bindings


def test_default_shortcuts():
    keys = DEFAULTS["hotkeys"]
    expected = {
        "alt+f": ["wm.focus_next", {}],
        "alt+esc": ["wm.close", {}],
        "alt+d": ["desktop.create", {}],
        "alt+e": ["switcher.toggle", {}],
        "alt+o": ["wm.rotate", {}],
        "alt+space": ["search.toggle", {}],
        "alt+m": ["app.focus_follows_mouse", {}],
        "ctrl+alt+shift+q": ["app.release", {}],
        **{f"alt+{d}": ["wm.move", {"dir": d}] for d in ("left", "right", "up", "down")},
        **{f"alt+{n}": ["wm.show_count", {"n": n}] for n in (1, 2, 3)},
        "win+up": ["desktop.step", {"delta": -1}],
        "win+down": ["desktop.step", {"delta": 1}],
        "win+esc": ["wm.close_all", {}],
        "win+-": ["desktop.close_current", {}],
        "win+subtract": ["desktop.close_current", {}],
        "win+x": ["power.menu", {}],
        "win+i": ["hub.toggle", {"section": "lobby"}],
        "win+e": ["hub.toggle", {"section": "files"}],
        "win+t": ["hub.toggle", {"section": "tasks"}],
        "win+b": ["hub.toggle", {"section": "brain"}],
        "win+k": ["hub.toggle", {"section": "kyora"}],
    }
    assert keys == expected
    normal, chords, taps, wins, failed = split_bindings(keys)
    assert wins == {
        0x26: ["desktop.step", {"delta": -1}], 0x28: ["desktop.step", {"delta": 1}], 0x1B: ["wm.close_all", {}],
        0xBD: ["desktop.close_current", {}], 0x6D: ["desktop.close_current", {}], ord("X"): ["power.menu", {}],
        ord("I"): ["hub.toggle", {"section": "lobby"}], ord("E"): ["hub.toggle", {"section": "files"}],
        ord("T"): ["hub.toggle", {"section": "tasks"}], ord("B"): ["hub.toggle", {"section": "brain"}],
        ord("K"): ["hub.toggle", {"section": "kyora"}],
    }
    assert not chords and not taps and not failed
    for combo in normal:
        parse_combo(combo)  # los demás son de una tecla: van por RegisterHotKey


def test_two_key_chords_can_still_be_added_in_the_config():
    bindings = {"alt+f+left": ["wm.focus", {"dir": "left"}], "alt+f": ["wm.float_toggle", {}], "alt+e": ["switcher.toggle", {}]}
    normal, chords, taps, wins, failed = split_bindings(bindings)
    assert chords == {(ord("F"), 0x25): ["wm.focus", {"dir": "left"}]}
    assert taps == {ord("F"): ["wm.float_toggle", {}]}
    assert normal == {"alt+e": ["switcher.toggle", {}]} and not failed and not wins
    assert parse_chord("alt+m+down") == (ord("M"), 0x28)


def test_only_plain_windows_shortcuts_go_to_the_keyboard_hook():
    bindings = {"win+up": ["a", {}], "win+shift+up": ["b", {}], "win+ñ": ["c", {}]}
    normal, _, _, wins, failed = split_bindings(bindings)
    assert wins == {0x26: ["a", {}]}
    assert normal == {"win+shift+up": ["b", {}]}  # con más modificadores sigue yendo por RegisterHotKey
    assert failed == ["win+ñ"]
