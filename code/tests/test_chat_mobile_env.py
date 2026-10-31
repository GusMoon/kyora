"""mobile/env.json: solo lo público (URL y clave anon), nunca el correo ni la contraseña."""
import json

from kyora.chat import env as chat_env
from kyora.chat import mobile_env

ENV = chat_env.ChatEnv(url="https://abc.supabase.co", anon_key="anon-publica", email="yo@correo.com", password="secreta",
                       device="pc", source="supabase/.env")


def test_env_json_has_only_the_public_values(tmp_path):
    lines = []
    target = tmp_path / "mobile" / "env.json"
    assert mobile_env.run(out=lines.append, env=ENV, target=target) == 0
    data = json.loads(target.read_text(encoding="utf-8"))
    assert data == {"SUPABASE_URL": "https://abc.supabase.co", "SUPABASE_ANON_KEY": "anon-publica"}
    text = target.read_text(encoding="utf-8")
    assert "secreta" not in text and "yo@correo.com" not in text
    assert "secreta" not in "\n".join(lines) and "anon-publica" not in "\n".join(lines)


def test_env_json_is_not_written_without_url_or_key(tmp_path):
    lines = []
    target = tmp_path / "env.json"
    empty = chat_env.ChatEnv(email="yo@correo.com", password="secreta", source="supabase/.env")
    assert mobile_env.run(out=lines.append, env=empty, target=target) == 2
    assert not target.exists()
    assert "SUPABASE_URL" in lines[0] and "SUPABASE_ANON_KEY" in lines[0]


def test_default_target_is_mobile_env_json_next_to_code():
    path = mobile_env.target_path()
    assert path.name == "env.json" and path.parent.name == "mobile" and (path.parents[1] / "code").is_dir()
