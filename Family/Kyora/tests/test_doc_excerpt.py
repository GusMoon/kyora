"""El extracto de los documentos del chat: texto, Markdown, Word y PDF."""
import zipfile

from PySide6.QtGui import QPageSize, QPainter, QPdfWriter
from PySide6.QtWidgets import QApplication

from kyora.ui import doc_excerpt

app = QApplication.instance() or QApplication([])


def test_only_documents_with_a_readable_text_have_an_excerpt():
    for name in ("a.pdf", "A.DOCX", "n.txt", "leeme.md", "codigo.py"):
        assert doc_excerpt.supported(name)
    for name in ("foto.png", "musica.mp3", "datos.xlsx", "programa.exe", "sin_extension"):
        assert not doc_excerpt.supported(name)


def test_text_and_markdown_are_cleaned_and_shortened(tmp_path):
    md = tmp_path / "leeme.md"
    md.write_text("# Título\n\n> Una cita\n\n- **uno**\n- `dos`\n\n" + "palabra " * 300, encoding="utf-8")
    text = doc_excerpt.excerpt(str(md))
    assert text.startswith("Título\nUna cita\nuno\ndos\npalabra") and len(text) <= doc_excerpt.LIMIT
    assert "#" not in text and "*" not in text and "`" not in text
    cp1252 = tmp_path / "nota.txt"
    cp1252.write_bytes("Cotización número 1".encode("cp1252"))
    assert doc_excerpt.excerpt(str(cp1252)) == "Cotización número 1"


def test_markdown_front_matter_is_skipped(tmp_path):
    md = tmp_path / "cotizacion.md"
    md.write_text("---\ntitle: 'Cotización'\ndate: '30 de octubre'\n---\n\n# Resumen de la propuesta\n\nTexto.",
                  encoding="utf-8")
    assert doc_excerpt.excerpt(str(md)) == "Resumen de la propuesta\nTexto."


def test_a_word_document_gives_its_paragraphs(tmp_path):
    docx = tmp_path / "carta.docx"
    body = ('<w:document xmlns:w="x"><w:body><w:p><w:r><w:t>Estimado cliente:</w:t></w:r></w:p>'
            '<w:p><w:r><w:t>Le enviamos la cotizaci&#243;n &amp; el contrato.</w:t></w:r></w:p></w:body></w:document>')
    with zipfile.ZipFile(docx, "w") as z:
        z.writestr("word/document.xml", body)
    assert doc_excerpt.excerpt(str(docx)) == "Estimado cliente:\nLe enviamos la cotización & el contrato."


def test_a_pdf_gives_the_text_of_its_first_page(tmp_path):
    pdf = tmp_path / "informe.pdf"
    writer = QPdfWriter(str(pdf))
    writer.setPageSize(QPageSize(QPageSize.A4))
    painter = QPainter(writer)
    painter.drawText(500, 1500, "Informe de requerimientos")
    painter.end()
    assert "Informe de requerimientos" in doc_excerpt.excerpt(str(pdf))


def test_broken_empty_or_unsupported_files_have_no_excerpt(tmp_path):
    broken = tmp_path / "roto.pdf"
    broken.write_bytes(b"esto no es un pdf")
    fake_docx = tmp_path / "falso.docx"
    fake_docx.write_bytes(b"tampoco")
    empty = tmp_path / "vacio.txt"
    empty.write_text("   \n\n", encoding="utf-8")
    binary = tmp_path / "datos.txt"
    binary.write_bytes(b"\x00\x01\x02")
    assert [doc_excerpt.excerpt(str(p)) for p in (broken, fake_docx, empty, binary, tmp_path / "no_existe.txt")] == [None] * 5
    assert doc_excerpt.excerpt(str(tmp_path / "foto.png")) is None
