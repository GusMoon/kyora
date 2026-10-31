"""Comprueba el chat desde la PC, sin abrir Kyora: `python -m kyora.chat.check [--send]` (o scripts\\probar_chat.bat).

Lee las credenciales del .env, inicia sesión en Supabase, saca (o crea) la conversación «General» y enseña los últimos
mensajes. Con `--send` manda además un mensaje de prueba «Prueba desde Kyora (PC → móvil)»: queda guardado en la base de
datos y se ve en el móvil. Si algo falla dice en español qué es y cómo arreglarlo. Nunca imprime credenciales.
"""
import sys
import uuid

from kyora import config as app_config
from kyora.chat import env as chat_env
from kyora.chat.client import ChatError, SupabaseClient
from kyora.chat.service import now_iso

TEST_TEXT = "Prueba desde Kyora (PC → móvil)"
SHOWN = 10  # cuántos mensajes se enseñan


def explain(err):
    """Qué pasó y qué hacer, en español, según el error de Supabase."""
    text = f"{err.code} {err.message}".lower()
    if "invalid_credentials" in text or "invalid login" in text:
        return "El correo o la contraseña de supabase/.env no son los del usuario que creaste en Authentication > Users."
    if "email_not_confirmed" in text or "not confirmed" in text:
        return "Ese usuario no está confirmado: en Authentication > Users, ábrelo y confírmalo (o créalo con «Auto Confirm User»)."
    if err.code in ("PGRST202", "42883") or "could not find the function" in text:
        return "Falta crear la base de datos: pega supabase/schema.sql en Supabase > SQL Editor y pulsa Run."
    if err.code == "42P01" or "does not exist" in text:
        return "Faltan tablas: ejecuta supabase/schema.sql completo en Supabase > SQL Editor."
    if err.code == "offline":
        return "No hay conexión con Supabase: revisa internet y que SUPABASE_URL sea la de tu proyecto."
    if "invalid api key" in text or "apikey" in text:
        return "La clave SUPABASE_ANON_KEY no es válida: copia la «anon public» de Settings > API."
    return "Revisa supabase/README.md; el detalle de arriba viene de Supabase."


def run(args, out=print, env=None, client_factory=SupabaseClient):
    """Devuelve 0 si todo salió bien, 1 si Supabase falló y 2 si faltan datos en el .env."""
    env = env if env is not None else chat_env.load(app_config.data_dir())
    if not env.ready:
        where = env.source or "supabase/.env"
        out(f"Faltan datos en {where}: {', '.join(env.missing())}. Rellénalos (ver supabase/README.md).")
        return 2
    client = client_factory(env)
    try:
        client.sign_in()
        out("[1/3] Sesión iniciada en Supabase.")
        conversation = str(client.rpc("ensure_default_conversation"))
        out("[2/3] Conversación «General» lista.")
        if "--send" in args:
            sent = client.rpc("send_message", {"p_id": str(uuid.uuid4()), "p_conversation_id": conversation,
                                               "p_body": TEST_TEXT, "p_sent_at": now_iso(), "p_device": env.device,
                                               "p_attachments": []})
            out(f"      Mensaje de prueba enviado (estado: {sent.get('status')}).")
        messages = client.rpc("list_messages", {"p_conversation_id": conversation, "p_limit": SHOWN}) or []
    except ChatError as err:
        out(f"Falló: {err.message}")
        out(explain(err))
        return 1
    out(f"[3/3] Últimos mensajes ({len(messages)}):")
    for message in messages:
        what = (message.get("body") or "").strip().replace("\n", " ")[:70]
        if message.get("attachments"):
            what = (what + " " if what else "") + f"[{len(message['attachments'])} adjunto(s)]"
        out(f"      {message['sent_at'][:19].replace('T', ' ')}  {message['sender_device']:<8}  {message['status']:<7}  {what}")
    if not messages:
        out("      (todavía no hay mensajes; usa --send para mandar uno de prueba)")
    out("Todo bien: la PC puede guardar y leer mensajes en tu base de datos.")
    return 0


def main():
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8", errors="replace")  # la consola de Windows no siempre trae UTF-8
    sys.exit(run(sys.argv[1:]))


if __name__ == "__main__":
    main()
