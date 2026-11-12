from kyora.core.chords import ChordGuard

ALT, SHIFT, CTRL = 0xA4, 0xA0, 0xA2
F, M, LEFT, RIGHT = 0x46, 0x4D, 0x25, 0x27


def guard():
    return ChordGuard({(F, LEFT): "focus-left", (M, RIGHT): "move-right"}, {F: "float", M: "mouse"})


def run(g, *events):
    """events: (tecla, True=baja / False=sube). Devuelve la lista de (tragar, acción, tapar)."""
    return [g.feed(vk, down) for vk, down in events]


def test_alt_f_arrow_fires_and_swallows_the_keys():
    out = run(guard(), (ALT, True), (F, True), (LEFT, True), (LEFT, False), (F, False), (ALT, False))
    assert [o[1] for o in out] == [None, None, "focus-left", None, None, None]  # usada: soltar F no hace el toque
    assert [o[0] for o in out] == [False, True, True, True, True, False]
    assert out[-1][2]  # al soltar Alt se tapa: la app no abre su menú


def test_other_layer_has_its_own_chords():
    out = run(guard(), (ALT, True), (M, True), (RIGHT, True))
    assert out[-1] == (True, "move-right", False)


def test_key_repeat_does_not_fire_again():
    out = run(guard(), (ALT, True), (F, True), (F, True), (LEFT, True), (LEFT, True), (LEFT, True))
    assert [o[1] for o in out].count("focus-left") == 1


def test_lone_layer_fires_its_tap_on_release():
    out = run(guard(), (ALT, True), (F, True), (F, False), (ALT, False))
    assert out[2] == (True, "float", False)
    assert out[3][2]


def test_tap_also_works_when_alt_is_released_first():
    out = run(guard(), (ALT, True), (F, True), (ALT, False), (F, False))
    assert out[2][2] and out[3] == (True, "float", False)


def test_shift_or_ctrl_leave_the_keys_to_the_apps():
    for modifier in (SHIFT, CTRL):
        out = run(guard(), (ALT, True), (modifier, True), (F, True), (LEFT, True))
        assert all(o == (False, None, False) for o in out)


def test_keys_without_alt_or_layer_pass_untouched():
    assert run(guard(), (F, True), (F, False), (LEFT, True)) == [(False, None, False)] * 3
    assert run(guard(), (ALT, True), (LEFT, True), (ALT, False)) == [(False, None, False)] * 3  # Alt+← del navegador
