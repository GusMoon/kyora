from kyora.config import DEFAULTS
from kyora.core.commands import PANEL_ROWS, command_rows


def test_default_shortcuts_are_grouped_and_described():
    rows = {r["keys"]: r["text"] for r in command_rows(DEFAULTS["hotkeys"])}
    assert rows["Ctrl+Shift+←/→/↑/↓"].startswith("Mover la ventana con foco")
    assert rows["Ctrl+Shift+Alt+←/→/↑/↓"].startswith("Orientación de la ventana con foco")
    assert rows["Ctrl+Shift+1/2/3"] == "Ver 1, 2 o 3 ventanas"
    assert rows["Ctrl+Shift+RePág/AvPág"] == "Ir al escritorio anterior o siguiente (la pantalla se desliza)"
    assert rows["Ctrl+Shift+Espacio"] == "Buscador de apps, archivos y carpetas"
    assert rows["Ctrl+Shift+T/N/C"].startswith("Tus tareas (T, directo en el tablero Kanban)")
    assert rows["Ctrl+Shift+W"].startswith("Ver solo los fondos")
    assert rows["Ctrl+Shift+Q"] == "Cerrar la ventana con foco"
    assert rows["Ctrl+Shift+Alt+X"].startswith("Cerrar todas las ventanas")
    assert rows["Ctrl+Shift+Alt+E"] == "Cerrar este escritorio (sus ventanas pasan al anterior)"
    assert rows["Ctrl+Shift+X"] == "Apagar, reiniciar o suspender el equipo"
    assert "Ctrl+Shift+Alt+Q" in rows and "Ctrl+Shift+F" in rows and "Ctrl+Shift+M" in rows
    assert not any("Win" in key for key in rows)  # la tecla Windows está bloqueada
    assert len(rows) == 16 + len(PANEL_ROWS)


def test_unknown_actions_and_chords():
    rows = command_rows({"alt+f+left": ["wm.focus", {}], "alt+f+right": ["wm.focus", {}], "alt+k": ["mi.accion", {}]})
    assert [(r["keys"], r["text"], r["section"]) for r in rows[:2]] == [
        ("Alt+F+←/→", "Pasar el foco a la ventana de ese lado", "Navegación"),
        ("Alt+K", "mi.accion", "Sistema"),
    ]
    assert rows[0]["editable"] is False and rows[1]["editable"] is True      # los de dos teclas no se editan desde la página
    assert rows[1]["combos"] == ["alt+k"]


def test_shortcuts_are_grouped_by_section():
    from kyora.core.commands import SECTIONS, sections

    data = sections(DEFAULTS["hotkeys"])
    assert list(data) == list(SECTIONS)
    assert any(r["keys"] == "Ctrl+Shift+←/→/↑/↓" for r in data["Ventanas"])
    assert any(r["keys"] == "Ctrl+Shift+E" for r in data["Escritorios"])
    assert any(r["keys"] == "Ctrl+Shift+T/N/C" for r in data["Tareas"])


def test_config_page_data_groups_commands_by_section_and_by_key():
    from kyora.core.commands import KYORA_OPTIONS, config_data, key_group

    data = config_data(DEFAULTS["hotkeys"])
    by_section = {c["title"]: c for c in data["commands"]["section"]}
    assert list(by_section) == ["Navegación", "Ventanas", "Escritorios", "Sistema", "Tareas"]
    assert all(c["info"] for c in by_section.values())                  # cada tarjeta explica su sección
    by_key = {c["title"]: c for c in data["commands"]["key"]}
    assert next(iter(by_key)) == "Ctrl+Shift" and "Ctrl+Shift+Alt" in by_key and "Ctrl" in by_key and "Win" not in by_key
    assert any(r["keys"] == "Ctrl+Shift+←/→/↑/↓" for r in by_key["Ctrl+Shift"]["rows"])
    assert any(r["keys"] == "Ctrl+Shift+Alt+Q" for r in by_key["Ctrl+Shift+Alt"]["rows"])
    total = sum(len(c["rows"]) for c in by_key.values())
    assert total == sum(len(c["rows"]) for c in by_section.values())      # las dos formas de ordenar tienen lo mismo
    assert key_group("Ctrl+Shift+Espacio") == "Ctrl+Shift" and key_group("<texto · /texto") == "Otras"
    assert key_group("Ctrl+N · Ctrl+Enter") == "Ctrl" and key_group("Alt+F+←/→") == "Alt"
    runnable = [r for c in data["executables"] for r in c["rows"]]
    assert sorted(r["keys"] for r in runnable) == sorted(title for title, *_ in KYORA_OPTIONS)  # todos los ejecutables
    assert all(r["action"] for r in runnable)


def test_key_tokens_split_combinations_into_keycaps():
    from kyora.core.commands import key_tokens

    assert key_tokens("Ctrl+Shift+T") == [("cap", "Ctrl"), ("cap", "Shift"), ("cap", "T")]
    assert key_tokens("Ctrl+Shift+←/→/↑/↓")[-1] == ("cap", "←/→/↑/↓")
    assert key_tokens("Enter · Esc (en las tareas)") == [
        ("cap", "Enter"), ("sep", "·"), ("cap", "Esc"), ("note", "(en las tareas)")]


def test_filter_cards_keeps_matching_rows_or_whole_cards_by_title():
    from kyora.core.commands import config_data, filter_cards

    cards = config_data(DEFAULTS["hotkeys"])["commands"]["section"]
    assert filter_cards(cards, "") is cards
    found = filter_cards(cards, "escritorio")
    assert found and all(r for c in found for r in c["rows"])
    assert any("Escritorios" == c["title"] and len(c["rows"]) == len(next(x for x in cards if x["title"] == "Escritorios")["rows"])
               for c in found)                                         # coincide el título: se queda entera
    by_text = filter_cards(cards, "kanban")
    assert by_text and all("kanban" in (r["keys"] + r["text"]).lower() for c in by_text for r in c["rows"])
    assert filter_cards(cards, "zzzz") == []
