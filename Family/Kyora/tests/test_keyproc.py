from kyora.system.keyproc import decode_bindings, encode_bindings


def test_bindings_survive_the_trip_to_the_hook_process():
    groups = {
        "chords": {(0x46, 0x25): "foco izquierda"},
        "taps": {0x46: "flotante"},
    }
    text, actions = encode_bindings(**groups)
    decoded = decode_bindings(text, lambda code: code)
    for kind, original in groups.items():
        assert {key: actions[code] for key, code in decoded[kind].items()} == original


def test_missing_groups_are_empty():
    text, actions = encode_bindings(chords={(0x46, 0x25): "foco izquierda"})
    decoded = decode_bindings(text, lambda code: code)
    assert decoded["taps"] == {}
    assert list(decoded["chords"]) == [(0x46, 0x25)] and actions == {"c0": "foco izquierda"}
