from kyora.core.winkey import VK_ESCAPE, VK_LWIN, VK_RWIN, WinBlock

CTRL, SHIFT, LETTER = 0xA2, 0xA0, 0x45


def test_both_windows_keys_are_swallowed_alone_and_in_any_combination():
    block = WinBlock()
    for vk in (VK_LWIN, VK_RWIN):
        assert block.feed(vk, True) and block.feed(vk, False)
    block.feed(VK_LWIN, True)
    assert block.feed(LETTER, True) is False          # Win+E: la E pasa, pero Windows no vio Win: no abre el Explorador
    assert block.feed(VK_LWIN, False)


def test_ctrl_esc_which_opens_the_start_menu_is_swallowed_but_plain_keys_pass():
    block = WinBlock()
    assert block.feed(VK_ESCAPE, True) is False and block.feed(VK_ESCAPE, False) is False
    block.feed(CTRL, True)
    assert block.feed(VK_ESCAPE, True) is True
    block.feed(CTRL, False)
    assert block.feed(VK_ESCAPE, False) is True        # la subida de la Esc tragada también se traga
    assert block.feed(VK_ESCAPE, True) is False


def test_ctrl_shift_esc_the_task_manager_is_left_alone():
    block = WinBlock()
    block.feed(CTRL, True)
    block.feed(SHIFT, True)
    assert block.feed(VK_ESCAPE, True) is False and block.feed(VK_ESCAPE, False) is False
