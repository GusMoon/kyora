from kyora.core.winkey import VK_LWIN, VK_RWIN, WinComboGuard, WinKeyGuard

L = 0x4C  # la tecla L
D = 0x44


def press(guard, *events):
    """events: (tecla, True=baja / False=sube). Devuelve las veces que pidió inyectar la tapadera."""
    return sum(guard.feed(vk, down) for vk, down in events)


def test_lone_press_is_masked():
    assert press(WinKeyGuard(), (VK_LWIN, True), (VK_LWIN, False)) == 1


def test_lone_press_with_key_repeat_is_still_masked_once():
    assert press(WinKeyGuard(), (VK_LWIN, True), (VK_LWIN, True), (VK_LWIN, True), (VK_LWIN, False)) == 1


def test_combinations_pass_through_untouched():
    assert press(WinKeyGuard(), (VK_LWIN, True), (L, True), (L, False), (VK_LWIN, False)) == 0
    assert press(WinKeyGuard(), (VK_RWIN, True), (D, True), (VK_RWIN, False), (D, False)) == 0


def test_next_lone_press_is_masked_again_after_a_combination():
    g = WinKeyGuard()
    assert press(g, (VK_LWIN, True), (L, True), (L, False), (VK_LWIN, False)) == 0
    assert press(g, (VK_LWIN, True), (VK_LWIN, False)) == 1


def test_other_keys_without_windows_are_ignored():
    g = WinKeyGuard()
    assert press(g, (L, True), (L, False)) == 0
    assert press(g, (VK_LWIN, True), (VK_LWIN, False)) == 1   # la L anterior no cuenta como combinación


def test_both_windows_keys_together_then_released():
    g = WinKeyGuard()
    # soltar la primera no abre nada; al soltar la última sigue siendo una pulsación sin combinar: se tapa una sola vez
    assert press(g, (VK_LWIN, True), (VK_RWIN, True), (VK_LWIN, False), (VK_RWIN, False)) == 1


def test_stray_release_without_press_does_nothing():
    assert press(WinKeyGuard(), (VK_LWIN, False)) == 0


UP, ESC, SHIFT = 0x26, 0x1B, 0xA0


def combos():
    return WinComboGuard({UP: "escritorio arriba", ESC: "cerrar todo"})


def test_windows_combo_is_swallowed_and_fires_once():
    g = combos()
    assert g.feed(VK_LWIN, True) == (False, None)  # la tecla Windows pasa: la tapa WinKeyGuard
    assert g.feed(UP, True) == (True, "escritorio arriba")
    assert g.feed(UP, True) == (True, None)  # autorrepetición
    assert g.feed(UP, False) == (True, None)  # su subida también se traga
    assert g.feed(ESC, True) == (True, "cerrar todo")
    assert g.feed(VK_LWIN, False) == (False, None)
    assert g.feed(ESC, False) == (True, None)  # aunque Windows ya se soltara


def test_keys_without_windows_or_with_more_modifiers_pass():
    g = combos()
    assert g.feed(UP, True) == (False, None)
    assert g.feed(UP, False) == (False, None)
    g.feed(VK_RWIN, True)
    g.feed(SHIFT, True)
    assert g.feed(UP, True) == (False, None)  # Win+Shift+↑ sigue siendo de Windows
    g.feed(SHIFT, False)
    assert g.feed(0x4C, True) == (False, None)  # Win+L no es de Kyora
