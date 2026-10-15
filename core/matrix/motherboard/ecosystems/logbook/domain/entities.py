from dataclasses import dataclass


@dataclass
class LogEntry:
    """
    Representa la entrada de la bitácora correspondiente a un día.

    Attributes:
        entry_date: Fecha de la entrada en formato ISO-8601 (AAAA-MM-DD). Es única.
        content: Texto libre escrito por el usuario.
        id: Identificador único de la entrada (vacío si aún no se ha persistido).
        created_at: Marca temporal de creación en formato ISO-8601.
        updated_at: Marca temporal de la última modificación en formato ISO-8601.
    """
    entry_date: str
    content: str = ""
    id: str = ""
    created_at: str = ""
    updated_at: str = ""
