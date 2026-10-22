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
    assert keys["alt+m"][0] == "app.focus_follows_mouse"
    assert keys["alt+space"][0] == "search.toggle"
