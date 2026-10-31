"""El chat guardado en SQLite (chat.sqlite en la carpeta de datos de Kyora): lo que se ve sin conexión y la bandeja de salida.

Un mensaje nace aquí **en espera** (`pending`) y pasa a **enviado** (`sent`) cuando Supabase confirma que llegó. Lo que
llega de otros dispositivos se guarda ya como enviado. El `id` lo crea el dispositivo (uuid), así que reintentar un envío
nunca duplica el mensaje. Los adjuntos de un mensaje en espera apuntan al archivo del disco (`local_path`) hasta que se
suben; después se sustituyen por los del servidor (que conservan ese `local_path` para no volver a bajarlos).
"""
import sqlite3
import threading

SCHEMA = """
CREATE TABLE IF NOT EXISTS messages (
    id TEXT PRIMARY KEY,
    conversation_id TEXT,
    device TEXT NOT NULL DEFAULT '',
    kind TEXT NOT NULL DEFAULT 'text',
    body TEXT,
    status TEXT NOT NULL DEFAULT 'pending',
    sent_at TEXT NOT NULL,
    created_at TEXT,
    deleted INTEGER NOT NULL DEFAULT 0,
    error TEXT,
    attempts INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS messages_sent ON messages(sent_at, id);
CREATE TABLE IF NOT EXISTS attachments (
    id TEXT PRIMARY KEY,
    message_id TEXT NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
    file_name TEXT NOT NULL,
    mime_type TEXT NOT NULL DEFAULT 'application/octet-stream',
    size_bytes INTEGER NOT NULL DEFAULT 0,
    width INTEGER,
    height INTEGER,
    duration_ms INTEGER,
    storage_path TEXT,
    thumb_path TEXT,
    local_path TEXT,
    position INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS attachments_message ON attachments(message_id, position);
CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
"""
MESSAGE_COLS = ("id", "conversation_id", "device", "kind", "body", "status", "sent_at", "created_at", "deleted",
                "error", "attempts")
ATTACHMENT_COLS = ("id", "message_id", "file_name", "mime_type", "size_bytes", "width", "height", "duration_ms",
                   "storage_path", "thumb_path", "local_path", "position")


def kind_of(mime):
    """La clase de mensaje según el tipo del primer adjunto (la misma regla que `send_message` en el SQL)."""
    mime = (mime or "").lower()
    if not mime:
        return "other"
    return {"image": "image", "audio": "audio", "video": "video"}.get(mime.split("/", 1)[0], "file")


class ChatStore:
    def __init__(self, path):
        """`path`: archivo .sqlite (o ":memory:")."""
        self._lock = threading.RLock()  # la interfaz y los hilos del chat usan la misma conexión
        self.db = sqlite3.connect(str(path), check_same_thread=False)
        self.db.row_factory = sqlite3.Row
        self.db.execute("PRAGMA foreign_keys = ON")
        self.db.executescript(SCHEMA)

    def close(self):
        with self._lock:
            self.db.close()

    # ---------- ajustes sueltos ----------

    def meta(self, key, default=""):
        with self._lock:
            row = self.db.execute("SELECT value FROM meta WHERE key = ?", (key,)).fetchone()
        return row["value"] if row else default

    def set_meta(self, key, value):
        with self._lock, self.db:
            self.db.execute("INSERT INTO meta(key, value) VALUES(?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                            (key, str(value)))

    # ---------- escribir ----------

    def add_pending(self, message, attachments=()):
        """Guarda un mensaje nuevo en espera. `message`: {id, conversation_id, device, body, sent_at}; cada adjunto:
        {id, file_name, mime_type, size_bytes, local_path, storage_path}."""
        kind = kind_of(attachments[0]["mime_type"]) if attachments else "text"
        with self._lock, self.db:
            self.db.execute(
                "INSERT INTO messages(id, conversation_id, device, kind, body, status, sent_at) VALUES(?,?,?,?,?,?,?)",
                (message["id"], message.get("conversation_id") or None, message.get("device", ""), kind,
                 message.get("body") or None, "pending", message["sent_at"]))
            for n, att in enumerate(attachments):
                self.db.execute(
                    "INSERT INTO attachments(id, message_id, file_name, mime_type, size_bytes, width, height, duration_ms,"
                    " storage_path, thumb_path, local_path, position) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)",
                    (att["id"], message["id"], att["file_name"], att.get("mime_type") or "application/octet-stream",
                     int(att.get("size_bytes") or 0), att.get("width"), att.get("height"), att.get("duration_ms"),
                     att.get("storage_path"), att.get("thumb_path"), att.get("local_path"), n))
        return self.get(message["id"])

    def upsert_remote(self, remote, advance=True):
        """Guarda (o actualiza) un mensaje tal como lo devuelve el servidor (`message_json`): ya enviado. Los adjuntos que
        ya se habían bajado o subido conservan su `local_path`. Devuelve True si el mensaje era nuevo aquí. `advance`:
        si la hora de llegada mueve el punto desde el que se piden las novedades (no para los envíos propios: si no, se
        podrían saltar mensajes de otros dispositivos que llegaron justo antes)."""
        with self._lock, self.db:
            known = self.db.execute("SELECT 1 FROM messages WHERE id = ?", (remote["id"],)).fetchone()
            local = {row["storage_path"]: row["local_path"] for row in self.db.execute(
                "SELECT storage_path, local_path FROM attachments WHERE message_id = ? AND local_path IS NOT NULL",
                (remote["id"],))}
            values = (remote["id"], remote.get("conversation_id"), remote.get("sender_device") or "", remote.get("kind") or "text",
                      remote.get("body"), "sent", remote.get("sent_at") or remote.get("created_at") or "",
                      remote.get("created_at"), 1 if remote.get("deleted_at") else 0)
            self.db.execute(
                "INSERT INTO messages(id, conversation_id, device, kind, body, status, sent_at, created_at, deleted, error)"
                " VALUES(?,?,?,?,?,?,?,?,?,NULL) ON CONFLICT(id) DO UPDATE SET conversation_id = excluded.conversation_id,"
                " device = excluded.device, kind = excluded.kind, body = excluded.body, status = 'sent',"
                " sent_at = excluded.sent_at, created_at = excluded.created_at, deleted = excluded.deleted, error = NULL",
                values)
            attachments = remote.get("attachments")
            if attachments is not None:
                self.db.execute("DELETE FROM attachments WHERE message_id = ?", (remote["id"],))
                for n, att in enumerate(attachments):
                    self.db.execute(
                        "INSERT INTO attachments(id, message_id, file_name, mime_type, size_bytes, width, height,"
                        " duration_ms, storage_path, thumb_path, local_path, position) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)",
                        (att["id"], remote["id"], att.get("file_name") or "archivo",
                         att.get("mime_type") or "application/octet-stream", int(att.get("size_bytes") or 0),
                         att.get("width"), att.get("height"), att.get("duration_ms"), att.get("storage_path"),
                         att.get("thumb_path"), local.get(att.get("storage_path")), n))
            if advance and remote.get("created_at") and remote["created_at"] > self.meta("last_created_at"):
                self.db.execute("INSERT INTO meta(key, value) VALUES('last_created_at', ?)"
                                " ON CONFLICT(key) DO UPDATE SET value = excluded.value", (remote["created_at"],))
        return known is None

    def set_conversation(self, conversation_id):
        """Los mensajes en espera que aún no tenían conversación (se escribieron sin conexión) se quedan con esta."""
        with self._lock, self.db:
            self.db.execute("UPDATE messages SET conversation_id = ? WHERE conversation_id IS NULL", (conversation_id,))
        self.set_meta("conversation_id", conversation_id)

    def fail(self, message_id, error, retryable=True):
        """Un intento de envío falló: se cuenta; si ya no tiene remedio (`retryable` False), el error se queda anotado y
        el mensaje no se vuelve a intentar hasta `retry`."""
        with self._lock, self.db:
            self.db.execute("UPDATE messages SET attempts = attempts + 1, error = ? WHERE id = ?",
                            (None if retryable else error, message_id))

    def retry(self, message_id):
        with self._lock, self.db:
            self.db.execute("UPDATE messages SET error = NULL WHERE id = ? AND status = 'pending'", (message_id,))

    def set_attachment(self, attachment_id, **fields):
        allowed = {k: v for k, v in fields.items() if k in ("storage_path", "local_path", "thumb_path", "width", "height")}
        if not allowed:
            return
        sets = ", ".join(f"{k} = ?" for k in allowed)
        with self._lock, self.db:
            self.db.execute(f"UPDATE attachments SET {sets} WHERE id = ?", (*allowed.values(), attachment_id))

    def mark_deleted(self, message_id):
        with self._lock, self.db:
            self.db.execute("UPDATE messages SET deleted = 1 WHERE id = ?", (message_id,))

    def forget(self, message_id):
        """Quita un mensaje en espera (el usuario lo cancela): no llegó a salir."""
        with self._lock, self.db:
            self.db.execute("DELETE FROM messages WHERE id = ? AND status = 'pending'", (message_id,))

    # ---------- leer ----------

    def _message(self, row):
        data = {col: row[col] for col in MESSAGE_COLS}
        data["deleted"] = bool(data["deleted"])
        data["attachments"] = [dict(a) for a in self.db.execute(
            "SELECT * FROM attachments WHERE message_id = ? ORDER BY position", (row["id"],))]
        return data

    def get(self, message_id):
        with self._lock:
            row = self.db.execute("SELECT * FROM messages WHERE id = ?", (message_id,)).fetchone()
            return self._message(row) if row else None

    def history(self, limit=50, before=None):
        """Los últimos `limit` mensajes (o los anteriores a la hora `before`), del más antiguo al más nuevo."""
        with self._lock:
            if before:
                rows = self.db.execute("SELECT * FROM messages WHERE deleted = 0 AND sent_at < ? ORDER BY sent_at DESC, id DESC"
                                       " LIMIT ?", (before, limit)).fetchall()
            else:
                rows = self.db.execute("SELECT * FROM messages WHERE deleted = 0 ORDER BY sent_at DESC, id DESC LIMIT ?",
                                       (limit,)).fetchall()
            return [self._message(row) for row in reversed(rows)]

    def outbox(self):
        """Lo que falta por enviar (sin errores sin remedio), del más antiguo al más nuevo."""
        with self._lock:
            rows = self.db.execute("SELECT * FROM messages WHERE status = 'pending' AND deleted = 0 AND error IS NULL"
                                   " ORDER BY sent_at, id").fetchall()
            return [self._message(row) for row in rows]

    def attachment(self, attachment_id):
        with self._lock:
            row = self.db.execute("SELECT * FROM attachments WHERE id = ?", (attachment_id,)).fetchone()
            return dict(row) if row else None
