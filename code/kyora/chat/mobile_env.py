"""Prepara `mobile/env.json` para compilar la app del móvil: `python -m kyora.chat.mobile_env` (lo llama scripts\\preparar_movil.bat).

La app solo necesita la URL de tu proyecto de Supabase y su clave pública (anon); el correo y la contraseña se escriben en la
pantalla de acceso del móvil y nunca van dentro de la app. Los datos salen del mismo .env que usa la PC, con su mismo lector.
"""
import json
import sys
from pathlib import Path

from kyora import config as app_config
from kyora.chat import env as chat_env

KEYS = {"SUPABASE_URL": "url", "SUPABASE_ANON_KEY": "anon_key"}


def target_path():
    """mobile/env.json del repositorio (esta carpeta es code/kyora/chat)."""
    return Path(__file__).resolve().parents[3] / "mobile" / "env.json"


def build(env):
    """El contenido de env.json: solo lo público."""
    return {name: getattr(env, attr) for name, attr in KEYS.items()}


def run(out=print, env=None, target=None):
    """Devuelve 0 si escribió el archivo y 2 si faltan datos en el .env."""
    env = env if env is not None else chat_env.load(app_config.data_dir())
    missing = [name for name, attr in KEYS.items() if not getattr(env, attr)]
    if missing:
        out(f"Faltan datos en {env.source or 'supabase/.env'}: {', '.join(missing)}. Rellénalos (ver supabase/README.md).")
        return 2
    path = Path(target) if target else target_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(build(env), indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    out(f"Escrito {path.name} con la URL y la clave pública de tu proyecto (sin correo ni contraseña).")
    return 0


def main():
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8", errors="replace")
    sys.exit(run())


if __name__ == "__main__":
    main()
