from kyora.config import DEFAULTS
from kyora.core.commands import PANEL_ROWS, command_rows


def test_default_shortcuts_are_grouped_and_described():
    rows = {r["keys"]: r["text"] for r in command_rows(DEFAULTS["hotkeys"])}
    assert rows["Alt+←/→/↑/↓"] == "Mover la ventana con foco al hueco de ese lado"
    assert rows["Alt+1/2/3"] == "Ver 1, 2 o 3 ventanas"
    assert rows["Win+↑/↓"] == "Ir al escritorio de arriba o de abajo"
    assert rows["Alt+Espacio"] == "Buscador de apps y ventanas"
    assert "Win+Esc" in rows and "Ctrl+Alt+Shift+Q" in rows
    assert rows["Win+-/Num -"] == "Cerrar este escritorio (sus ventanas pasan al anterior)"
    assert rows["Win+X"] == "Apagar, reiniciar o suspender el equipo"
    assert rows["Win+I/E/T/B/K"] == ("Panel de arriba: Lobby (I), Archivos (E), Tareas (T), Segundo Cerebro (B) "
                                     "o Kyora (K)")
    assert rows["Ctrl+1/2/3/4/5"] == "Panel de arriba: Lobby, Archivos, Tareas, Segundo Cerebro o Kyora"
    assert rows["Ctrl+S / Ctrl+M"] == "Segundo Cerebro: guardar / ver el Markdown"
    assert len(rows) == 15 + len(PANEL_ROWS)


def test_unknown_actions_and_chords():
    rows = command_rows({"alt+f+left": ["wm.focus", {}], "alt+f+right": ["wm.focus", {}], "alt+k": ["mi.accion", {}]})
    assert rows[:2] == [
        {"keys": "Alt+F+←/→", "text": "Pasar el foco a la ventana de ese lado"},
        {"keys": "Alt+K", "text": "mi.accion"},
    ]
