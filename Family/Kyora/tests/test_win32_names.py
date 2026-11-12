"""Comprueba que todas las funciones y constantes de pywin32 que usa Kyora existen de verdad."""
import importlib
import re
from pathlib import Path

import pytest

MODULES = ("win32api", "win32con", "win32gui", "win32process", "win32event", "winerror")
SOURCES = list((Path(__file__).parent.parent / "kyora").rglob("*.py"))


def used_names():
    pattern = re.compile(r"\b(" + "|".join(MODULES) + r")\.([A-Za-z_][A-Za-z0-9_]*)")
    found = set()
    for path in SOURCES:
        found.update(pattern.findall(path.read_text(encoding="utf-8")))
    return sorted(found)


@pytest.mark.parametrize(("module", "name"), used_names())
def test_pywin32_name_exists(module, name):
    assert hasattr(importlib.import_module(module), name), f"{module}.{name} no existe"


def test_ui_is_pure_python():
    """La interfaz es solo Python (Qt): no deben volver archivos web ni pywebview."""
    root = Path(__file__).parent.parent / "kyora"
    assert not [p for p in root.rglob("*") if p.suffix in (".html", ".css", ".js")]
    assert not [p for p in SOURCES if "import webview" in p.read_text(encoding="utf-8")]
