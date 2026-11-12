from PySide6.QtWidgets import QApplication

from kyora.ui import icons

app = QApplication.instance() or QApplication([])


def test_unknown_program_gets_the_generic_icon_not_a_letter():
    pm = icons.app_icon("", 0, px=24)
    assert not pm.isNull() and pm.width() == 24
    assert pm.toImage().pixelColor(12, 12).alpha() >= 0  # dibujado, no vacío por error
    nonblank = any(pm.toImage().pixelColor(x, y).alpha() > 0 for x in range(24) for y in range(24))
    assert nonblank


def test_real_executable_gets_its_own_icon_and_is_cached():
    exe = r"C:\Windows\explorer.exe"
    a = icons.app_icon(exe, 0, px=32)
    b = icons.app_icon(exe, 0, px=32)
    assert a is b
    assert not a.isNull() and a.width() == 32


def test_icon_respects_the_screen_scale():
    pm = icons.app_icon(r"C:\Windows\explorer.exe", 0, px=32, dpr=1.25)
    assert pm.width() == 40 and pm.devicePixelRatio() == 1.25
