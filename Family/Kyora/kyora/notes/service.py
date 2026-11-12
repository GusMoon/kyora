"""Las notas como acciones con nombre (notes.*)."""
import os

from kyora.notes.store import NotesStore

FOLDER_NAME = "Notas Kyora"


class NotesService:
    def __init__(self, documents, recycle):
        """`documents`: la carpeta Documentos (las notas van en Documentos\\Notas Kyora)."""
        folder = os.path.join(documents or os.path.join(os.path.expanduser("~"), "Documents"), FOLDER_NAME)
        self.store = NotesStore(folder, recycle)

    def register(self, registry):
        r, s = registry, self.store
        r.register("notes.list", s.list)
        r.register("notes.create", s.create)
        r.register("notes.save", s.save)
        r.register("notes.delete", s.delete, destructive=True)
