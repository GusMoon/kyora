"""Las credenciales del chat: un .env (VARIABLE=valor) sin dependencias.

Primero se lee `%APPDATA%\\Kyora\\chat.env` si existe (para no dejar la contraseña dentro del repositorio) y, si no,
`supabase/.env` junto a `code/`. Las variables y qué son están en `supabase/README.md`. Sin ellas el chat no se conecta
(los mensajes se quedan en espera), pero Kyora funciona igual.
"""
from dataclasses import dataclass
from pathlib import Path

REQUIRED = ("SUPABASE_URL", "SUPABASE_ANON_KEY", "CHAT_EMAIL", "CHAT_PASSWORD")


def repo_env_path():
    """supabase/.env del repositorio (esta carpeta es code/kyora/chat)."""
    return Path(__file__).resolve().parents[3] / "supabase" / ".env"


def parse(text):
    """{VARIABLE: valor} de un texto .env: sin líneas vacías ni comentarios (#), con o sin comillas y con `export`."""
    values = {}
    for raw in (text or "").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip().removeprefix("export ").strip()
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
            value = value[1:-1]
        elif " #" in value:  # un comentario al final de la línea
            value = value.split(" #", 1)[0].rstrip()
        if key:
            values[key] = value
    return values


@dataclass(frozen=True)
class ChatEnv:
    url: str = ""
    anon_key: str = ""
    email: str = ""
    password: str = ""
    device: str = "pc"
    source: str = ""  # de qué archivo salió ("" si no hay)

    def missing(self):
        """Los nombres de las variables que faltan."""
        have = {"SUPABASE_URL": self.url, "SUPABASE_ANON_KEY": self.anon_key, "CHAT_EMAIL": self.email,
                "CHAT_PASSWORD": self.password}
        return [name for name in REQUIRED if not have[name]]

    @property
    def ready(self):
        return not self.missing()


def load(data_dir, repo_path=None):
    """Lee las credenciales (siempre devuelve un `ChatEnv`; mira `.ready` y `.missing()`)."""
    candidates = [Path(data_dir) / "chat.env", Path(repo_path) if repo_path else repo_env_path()]
    for path in candidates:
        try:
            values = parse(path.read_text(encoding="utf-8-sig"))
        except OSError:
            continue
        env = ChatEnv(url=values.get("SUPABASE_URL", "").rstrip("/"), anon_key=values.get("SUPABASE_ANON_KEY", ""),
                      email=values.get("CHAT_EMAIL", ""), password=values.get("CHAT_PASSWORD", ""),
                      device=values.get("CHAT_DEVICE") or "pc", source=str(path))
        if env.ready or path is candidates[-1] or any(values.get(name) for name in REQUIRED):
            return env
    return ChatEnv()
