from kyora.config import DEFAULTS
from kyora.core.commands import command_rows, label_of
from kyora.core.hotkey_edit import NAMED_KEYS, apply_edit, normalize, validate
from kyora.system.hotkeys import NAMED_KEYS as SYSTEM_KEYS

HOTKEYS = DEFAULTS["hotkeys"]


def label(combo):
    return label_of(HOTKEYS, combo)


def test_normalize_orders_the_modifiers():
    assert normalize("Shift+Ctrl+T") == "ctrl+shift+t" and normalize("ALT + ctrl + Left") == "ctrl+alt+left"


def test_every_named_key_is_known_to_the_system_layer():
    assert set(NAMED_KEYS) <= set(SYSTEM_KEYS)


def test_valid_free_combination_is_accepted():
    assert validate("ctrl+alt+j", HOTKEYS, own=["ctrl+shift+t"], label=label) == (True, "")


def test_combinations_that_make_no_sense_are_rejected():
    assert not validate("win+t", HOTKEYS)[0]                       # Windows está bloqueada
    assert not validate("t", HOTKEYS)[0]                           # sin modificadores
    assert not validate("shift+t", HOTKEYS)[0]                     # sin Ctrl ni Alt
    assert not validate("ctrl+shift", HOTKEYS)[0]                  # sin tecla
    assert not validate("ctrl+shift+a+b", HOTKEYS)[0]              # dos teclas
    assert not validate("ctrl+ñ", HOTKEYS)[0]                      # tecla que no se puede registrar
    for reserved in ("ctrl+c", "ctrl+v", "alt+f4", "alt+tab", "ctrl+esc", "ctrl+shift+esc", "ctrl+alt+delete"):
        assert not validate(reserved, HOTKEYS)[0], reserved


def test_a_combination_already_used_by_another_shortcut_is_rejected_naming_it():
    ok, message = validate("ctrl+shift+q", HOTKEYS, own=["ctrl+shift+t"], label=label)
    assert not ok and "Cerrar la ventana" in message
    assert validate("ctrl+shift+t", HOTKEYS, own=["ctrl+shift+t"], label=label)[0]      # la suya propia sí vale


def test_a_combination_taken_by_another_program_is_rejected():
    assert validate("ctrl+alt+j", HOTKEYS, is_free=lambda combo: True)[0]
    ok, message = validate("ctrl+alt+j", HOTKEYS, is_free=lambda combo: False)
    assert not ok and "Otro programa" in message


def test_editing_a_single_shortcut_replaces_it_keeping_its_action_and_position():
    new, message = apply_edit(HOTKEYS, ["ctrl+shift+q"], "ctrl+alt+k", label=label)
    assert message == "" and new["ctrl+alt+k"] == ["wm.close", {}] and "ctrl+shift+q" not in new
    assert list(new).index("ctrl+alt+k") == list(HOTKEYS).index("ctrl+shift+q")
    assert len(new) == len(HOTKEYS)


def test_editing_a_group_changes_only_the_modifiers_of_all_its_shortcuts():
    arrows = [f"ctrl+shift+{d}" for d in ("left", "right", "up", "down")]
    new, message = apply_edit(HOTKEYS, arrows, "ctrl+alt+x", label=label)       # la tecla pulsada no cuenta, solo ctrl+alt
    assert message == "" and all(new[f"ctrl+alt+{d}"] == ["wm.move", {"dir": d}] for d in ("left", "right", "up", "down"))
    assert not any(c in new for c in arrows)


def test_editing_a_group_onto_a_used_combination_is_rejected_without_changes():
    arrows = [f"ctrl+shift+{d}" for d in ("left", "right", "up", "down")]
    new, message = apply_edit(HOTKEYS, arrows, "ctrl+shift+alt+x", label=label)  # ctrl+shift+alt+left ya es "arrange"
    assert new is None and "Ya lo usa" in message


def test_every_editable_default_row_can_be_edited_with_a_free_combination():
    editable = [r for r in command_rows(HOTKEYS) if r["editable"]]
    assert editable and all(r["combos"] for r in editable)
    for row in editable:
        _new, message = apply_edit(HOTKEYS, row["combos"], "ctrl+alt+j", label=label)
        assert message == "" or "repetiría" in message                              # los grupos de teclas distintas valen
