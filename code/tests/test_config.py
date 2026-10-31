import json

from kyora import config


def test_first_run_writes_defaults(tmp_path, monkeypatch):
    monkeypatch.setenv("APPDATA", str(tmp_path))
    cfg = config.load()
    assert cfg["focus_follows_mouse"] and cfg["config_version"] == config.CONFIG_VERSION
    assert (tmp_path / "Kyora" / "config.json").exists()


def test_old_config_is_backed_up_and_replaced(tmp_path, monkeypatch):
    monkeypatch.setenv("APPDATA", str(tmp_path))
    folder = tmp_path / "Kyora"
    folder.mkdir()
    (folder / "config.json").write_text(json.dumps({"config_version": 5, "gap": 8, "focus_follows_mouse": False}), encoding="utf-8")
    cfg = config.load()
    assert "gap" not in cfg and cfg["focus_follows_mouse"]  # la separación ahora la define el tema de la interfaz
    assert json.loads((folder / "config.old.json").read_text(encoding="utf-8"))["gap"] == 8
    assert json.loads((folder / "config.json").read_text(encoding="utf-8"))["config_version"] == config.CONFIG_VERSION


def test_current_config_keeps_user_values(tmp_path, monkeypatch):
    monkeypatch.setenv("APPDATA", str(tmp_path))
    folder = tmp_path / "Kyora"
    folder.mkdir()
    (folder / "config.json").write_text(
        json.dumps({"config_version": config.CONFIG_VERSION, "focus_follows_mouse": False}), encoding="utf-8"
    )
    cfg = config.load()
    assert cfg["focus_follows_mouse"] is False and cfg["hide_taskbar"]
    assert not (folder / "config.old.json").exists()


def test_corrupt_config_is_replaced(tmp_path, monkeypatch):
    monkeypatch.setenv("APPDATA", str(tmp_path))
    folder = tmp_path / "Kyora"
    folder.mkdir()
    (folder / "config.json").write_text("{no es json", encoding="utf-8")
    assert config.load()["config_version"] == config.CONFIG_VERSION
    assert (folder / "config.old.json").exists()


def test_default_hotkeys_cover_new_actions():
    keys = config.DEFAULTS["hotkeys"]
    assert keys["ctrl+shift+m"][0] == "music.panel"
    assert keys["ctrl+shift+space"][0] == "search.toggle"


def test_the_chat_hotkey_is_offered_once_to_an_existing_config(tmp_path, monkeypatch):
    monkeypatch.setenv("APPDATA", str(tmp_path))
    folder = tmp_path / "Kyora"
    folder.mkdir()
    mine = {"ctrl+shift+space": ["search.toggle", {}]}
    (folder / "config.json").write_text(json.dumps({"config_version": config.CONFIG_VERSION, "hotkeys": mine}),
                                        encoding="utf-8")
    cfg = config.load()
    assert cfg["hotkeys"]["ctrl+shift+c"] == ["search.open_mode", {"mode": "chat"}]
    assert cfg["hotkeys"]["ctrl+shift+space"] == ["search.toggle", {}] and len(cfg["hotkeys"]) == 2   # lo suyo, intacto
    saved = json.loads((folder / "config.json").read_text(encoding="utf-8"))
    assert saved["hotkeys_offered"] == ["chat"] and "ctrl+shift+c" in saved["hotkeys"]
    del saved["hotkeys"]["ctrl+shift+c"]                      # lo quitó a propósito: no se vuelve a poner
    (folder / "config.json").write_text(json.dumps(saved), encoding="utf-8")
    assert "ctrl+shift+c" not in config.load()["hotkeys"]


def test_the_chat_hotkey_is_not_offered_when_the_combination_is_taken(tmp_path, monkeypatch):
    monkeypatch.setenv("APPDATA", str(tmp_path))
    folder = tmp_path / "Kyora"
    folder.mkdir()
    mine = {"ctrl+shift+c": ["wm.close", {}]}
    (folder / "config.json").write_text(json.dumps({"config_version": config.CONFIG_VERSION, "hotkeys": mine}),
                                        encoding="utf-8")
    assert config.load()["hotkeys"] == mine
