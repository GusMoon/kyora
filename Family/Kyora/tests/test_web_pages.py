"""Las páginas web del buscador, los navegadores y su sección en la configuración (Qt fuera de pantalla)."""
import os
import sys

import pytest
from PySide6.QtCore import QPointF
from PySide6.QtWidgets import QApplication

from kyora.config import DEFAULTS
from kyora.core.commands import config_data
from kyora.search import web
from kyora.system import browsers
from kyora.ui import configpage
from kyora.ui.theme import THEME

app = QApplication.instance() or QApplication([])


# ---------- search/web.py ----------

def test_normalize_url_adds_the_scheme_and_refuses_junk():
    assert web.normalize_url("youtube.com") == "https://youtube.com"
    assert web.normalize_url("  http://localhost:8000/x ") == "http://localhost:8000/x"
    assert web.normalize_url("") is None
    assert web.normalize_url("dos palabras.com") is None
    assert web.normalize_url("https://") is None


def test_clean_validates_names_and_urls():
    assert web.clean([{"name": " yt ", "url": "youtube.com"}]) == [{"name": "yt", "url": "https://youtube.com"}]
    with pytest.raises(ValueError, match="nombre"):
        web.clean([{"name": " ", "url": "a.com"}])
    with pytest.raises(ValueError, match="repetido"):
        web.clean([{"name": "YT", "url": "a.com"}, {"name": "yt", "url": "b.com"}])
    with pytest.raises(ValueError, match="dirección"):
        web.clean([{"name": "yt", "url": "no valida"}])


def test_search_matches_the_name_best_first():
    items = [{"name": "Mi youtube", "url": "a"}, {"name": "yt", "url": "b"}, {"name": "gmail", "url": "c"}]
    assert [w["name"] for w in web.search(items, "yt")] == ["yt"]
    assert [w["name"] for w in web.search(items, "you")] == ["Mi youtube"]
    assert web.search(items, "zzz") == [] and web.search(None, "yt") == []


# ---------- system/browsers.py ----------

def test_exe_of_reads_quoted_and_plain_commands():
    assert browsers.exe_of('"C:\\Program Files\\Mozilla Firefox\\firefox.exe" -osint -url "%1"') == \
        "C:\\Program Files\\Mozilla Firefox\\firefox.exe"
    assert browsers.exe_of("C:\\Chrome\\chrome.exe --flag") == "C:\\Chrome\\chrome.exe"
    assert browsers.exe_of("") == ""


@pytest.mark.skipif(sys.platform != "win32", reason="registro de Windows")
def test_installed_lists_existing_executables_without_repeats():
    found = browsers.installed()
    exes = [os.path.normcase(b["exe"]) for b in found]
    assert len(exes) == len(set(exes)) and all(os.path.isfile(b["exe"]) and b["name"] for b in found)


def test_open_url_uses_the_chosen_browser_or_falls_back(monkeypatch, tmp_path):
    exe = tmp_path / "fake.exe"
    exe.write_text("")
    launched, started = [], []
    monkeypatch.setattr(browsers.subprocess, "Popen", lambda cmd, **kw: launched.append(cmd))
    monkeypatch.setattr(browsers.os, "startfile", started.append, raising=False)
    browsers.open_url("https://a.com", str(exe))
    browsers.open_url("https://b.com", str(tmp_path / "gone.exe"))
    browsers.open_url("https://c.com")
    assert launched == [[str(exe), "https://a.com"]] and started == ["https://b.com", "https://c.com"]


# ---------- ui/configpage.py ----------

CHROME, EDGE = "C:\\x\\chrome.exe", "C:\\x\\msedge.exe"


def make(shortcuts=()):
    calls = []
    data = {**config_data(DEFAULTS["hotkeys"]), "wallpapers": [], "options": [], "web": {
        "shortcuts": [dict(s) for s in shortcuts], "browser": EDGE, "chosen": "", "default": EDGE,
        "browsers": [{"name": "Google Chrome", "exe": CHROME}, {"name": "Microsoft Edge", "exe": EDGE}]}}
    page = configpage.ConfigPage(THEME, lambda action, **payload: calls.append((action, payload)), lambda: data)
    page.setFixedSize(720, 580)
    page.activate()
    return page, calls


def click(page, hit_kind, index=None):
    """Pulsa el primer sitio de la página que da `hit_kind` (y, si se indica, esa página web)."""
    for y in range(0, page.height(), 4):
        for x in range(page._content_x(), page.width(), 12):
            hit = page._hit(QPointF(x, y))
            if hit and hit[0] == hit_kind and (index is None or hit[2].get("index") == index):
                return hit
    raise AssertionError(hit_kind)


def test_atajos_has_a_web_kind_with_an_add_row():
    page, _ = make()
    page._set_kind("web")
    rows = page._groups()[0]["rows"]
    assert [r.get("add") for r in rows] == [True] and not page.filter.isVisible()
    page._set_kind("keys")
    assert page._filtering()


def test_adding_a_web_page_validates_and_saves_it():
    page, calls = make()
    page._set_kind("web")
    page._web_start(0)                                   # la fila "añadir" es la primera cuando no hay ninguna
    assert page._web_edit is not None
    page.web_name.setText("yt")
    page.web_url.setText("no valida")
    page._web_save()
    assert page._web_edit["message"] and not calls       # avisa y no guarda
    page.web_url.setText("youtube.com")
    page._web_save()
    assert page._web_edit is None
    assert calls == [("config.set_web_shortcuts", {"items": [{"name": "yt", "url": "https://youtube.com"}]})]
    assert [r["keys"] for r in page._groups()[0]["rows"]] == ["yt", "Añadir página"]


def test_deleting_needs_a_second_press_and_editing_replaces_the_row():
    page, calls = make([{"name": "yt", "url": "https://youtube.com"}, {"name": "gm", "url": "https://gmail.com"}])
    page._set_kind("web")
    page._web_start(1)
    page.web_name.setText("correo")
    page._web_save()
    assert calls[-1][1]["items"][1] == {"name": "correo", "url": "https://gmail.com"}
    page._web_del = 0                                     # la primera pulsación arma el borrado
    assert page._web()["shortcuts"][0]["name"] == "yt"
    page._web_delete(0)                                   # la segunda lo hace
    assert [s["name"] for s in page._web()["shortcuts"]] == ["correo"]
    assert calls[-1] == ("config.set_web_shortcuts", {"items": [{"name": "correo", "url": "https://gmail.com"}]})


def test_the_edit_fields_sit_on_their_row_and_hide_when_cancelled():
    page, _ = make([{"name": "yt", "url": "https://youtube.com"}])
    page.show()
    page._set_kind("web")
    page._web_start(0)
    assert page.web_name.isVisible() and page.web_url.isVisible()
    assert page.web_name.text() == "yt" and page.web_url.text() == "https://youtube.com"
    assert page.web_name.geometry().top() >= page._list_top()
    page._web_cancel()
    assert not page.web_name.isVisible() and page._web_edit is None
    page.hide()


def test_switching_kind_or_area_drops_a_web_edit():
    page, _ = make()
    page._set_kind("web")
    page._web_start(0)
    page._set_area(configpage.RENDIMIENTO)
    assert page._web_edit is None


def test_predeterminados_lists_browsers_and_saves_the_pick():
    page, calls = make()
    page._set_area(configpage.PREDETERMINADOS)
    assert [r["keys"] for r in page._groups()[0]["rows"]] == ["Navegador"]       # cerrada: solo el elegido
    assert page._groups()[0]["rows"][0]["text"] == configpage.SYSTEM_BROWSER
    page._browser_open = True
    names = [r["keys"] for r in page._groups()[0]["rows"]]
    assert names == ["Navegador", configpage.SYSTEM_BROWSER, "Google Chrome", "Microsoft Edge"]
    page._pick_browser(CHROME)
    assert calls == [("config.set_default_browser", {"exe": CHROME})]
    assert not page._browser_open and page._groups()[0]["rows"][0]["text"] == "Google Chrome"
    assert page._web()["browser"] == CHROME


def test_clicking_the_sidebar_and_the_browser_row_works():
    page, _ = make()
    page._hit(QPointF(40, 270))                           # no debe fallar con 5 áreas
    page._set_area(configpage.PREDETERMINADOS)
    assert click(page, "browser_main")[0] == "browser_main"
    page._browser_open = True
    assert click(page, "browser_pick")[0] == "browser_pick"


def test_storing_hotkeys_keeps_the_other_data():
    page, _ = make([{"name": "yt", "url": "https://youtube.com"}])
    page._store(dict(DEFAULTS["hotkeys"]), "config.reset_hotkeys")
    assert page._web()["shortcuts"] == [{"name": "yt", "url": "https://youtube.com"}]


def test_page_paints_every_area_without_errors():
    page, _ = make([{"name": "yt", "url": "https://youtube.com"}])
    page.show()
    for area in range(len(configpage.AREAS)):
        page._set_area(area)
        if area == configpage.ATAJOS:
            page._set_kind("web")
            page._web_start(0)
        if area == configpage.PREDETERMINADOS:
            page._browser_open = True
        page.grab()
    page.hide()


# ---------- app.py: el buscador y las acciones ----------

class _Stub:
    ready = type("Ready", (), {"is_set": staticmethod(lambda: True)})()
    entries = ()

    @staticmethod
    def search(*_args, **_kwargs):
        return []


def make_kyora(monkeypatch, tmp_path, shortcuts=(), chosen=""):
    from kyora import app as kyora_app
    from kyora import config as config_module

    monkeypatch.setattr(config_module, "data_dir", lambda: tmp_path)
    monkeypatch.setattr(browsers, "default_exe", lambda: EDGE)
    monkeypatch.setattr(browsers, "installed", lambda: [{"name": "Chrome", "exe": CHROME}])
    k = kyora_app.Kyora.__new__(kyora_app.Kyora)
    k.cfg = {"web_shortcuts": list(shortcuts), "defaults": {"browser": chosen}}
    k.index = k.files = _Stub()
    k._window_list = list
    k._request_push = lambda: None
    return k


def test_search_shows_web_pages_with_the_browser_icon(monkeypatch, tmp_path):
    k = make_kyora(monkeypatch, tmp_path, [{"name": "yt", "url": "https://youtube.com"}])
    rows = k.search_query("yt")["results"]
    assert rows == [{"kind": "web", "id": "https://youtube.com", "name": "yt", "detail": "https://youtube.com",
                     "exe": EDGE, "hwnd": 0}]
    assert k.search_query("zzz")["results"] == []


def test_launching_a_web_row_opens_it_with_the_chosen_browser(monkeypatch, tmp_path):
    opened = []
    monkeypatch.setattr(browsers, "open_url", lambda url, exe="": opened.append((url, exe)))
    exe = tmp_path / "chrome.exe"
    exe.write_text("")
    k = make_kyora(monkeypatch, tmp_path, [{"name": "yt", "url": "https://youtube.com"}], chosen=str(exe))
    k.manager = type("M", (), {"expect_launch": staticmethod(lambda: None)})()
    k.close_search = lambda refocus=True: None
    k.search_launch("web", "https://youtube.com")
    assert opened == [("https://youtube.com", str(exe))]


def test_config_actions_save_pages_and_browser(monkeypatch, tmp_path):
    from kyora.core.actions import ActionError

    k = make_kyora(monkeypatch, tmp_path)
    k.set_web_shortcuts([{"name": "yt", "url": "youtube.com"}])
    assert k.cfg["web_shortcuts"] == [{"name": "yt", "url": "https://youtube.com"}]
    with pytest.raises(ActionError):
        k.set_web_shortcuts([{"name": "", "url": "a.com"}])
    k.set_default_browser(CHROME)
    assert k.cfg["defaults"]["browser"] == CHROME
    with pytest.raises(ActionError):
        k.set_default_browser("C:\nada\no.exe")
    k.set_default_browser("")                              # vuelve al predeterminado de Windows
    assert k.cfg["defaults"]["browser"] == ""
    saved = (tmp_path / "config.json").read_text(encoding="utf-8")
    assert "https://youtube.com" in saved
