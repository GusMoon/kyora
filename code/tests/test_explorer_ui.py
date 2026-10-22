import os

from kyora.ui.explorer.navigation import HOME, crumbs
from kyora.ui.explorer.panel import human_size
from kyora.ui.explorer.preview import kind_of, read_text


def test_preview_kind_by_extension(tmp_path):
    assert kind_of(str(tmp_path)) == "folder"
    expected = {"a.md": "markdown", "b.py": "text", ".gitignore": "text", "c.JPG": "image", "d.pdf": "pdf",
                "e.mp3": "audio", "f.mp4": "video", "g.docx": None}
    for name, kind in expected.items():
        assert kind_of(str(tmp_path / name)) == kind, name


def test_read_text_detects_binary_and_encodings(tmp_path):
    (tmp_path / "utf8.txt").write_bytes("canción".encode())
    (tmp_path / "ansi.txt").write_bytes("canción".encode("cp1252"))
    (tmp_path / "bin.dat").write_bytes(b"ab\0cd")
    assert read_text(str(tmp_path / "utf8.txt")) == "canción"
    assert read_text(str(tmp_path / "ansi.txt")) == "canción"
    assert read_text(str(tmp_path / "bin.dat")) is None


def test_crumbs_start_at_home_or_drive():
    inside = crumbs(os.path.join(HOME, "Documents", "Kyora"))
    assert inside[0] == ("Carpeta personal", HOME)
    assert inside[-1] == ("Kyora", os.path.join(HOME, "Documents", "Kyora"))
    outside = crumbs(r"D:\Datos\Fotos")
    assert outside == [("D:", "D:" + os.sep), ("Datos", r"D:\Datos"), ("Fotos", r"D:\Datos\Fotos")]


def test_human_size():
    assert human_size(512) == "512 bytes"
    assert human_size(1536) == "1,5 KB"
    assert human_size(3 * 1024 ** 3) == "3,0 GB"


def test_kyora_icons_are_drawn_for_folders_and_files(tmp_path):
    from PySide6.QtCore import QFileInfo
    from PySide6.QtWidgets import QApplication

    from kyora.ui.explorer.file_icons import KyoraIcons

    QApplication.instance() or QApplication([])
    (tmp_path / "nota.txt").write_text("hola", encoding="utf-8")
    icons = KyoraIcons()
    folder = icons.icon(QFileInfo(str(tmp_path)))
    file = icons.icon(QFileInfo(str(tmp_path / "nota.txt")))
    assert not folder.isNull() and not file.isNull()
    assert folder.cacheKey() != file.cacheKey()
    assert icons.icon(QFileInfo(str(tmp_path))).cacheKey() == folder.cacheKey()  # dibujado una sola vez
    assert icons.type(QFileInfo(str(tmp_path / "nota.txt"))) == "Archivo TXT"
    assert icons.type(QFileInfo(str(tmp_path))) == "Carpeta"
