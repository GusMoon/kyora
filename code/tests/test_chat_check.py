"""El comprobador del chat (python -m kyora.chat.check) con un Supabase falso."""
from kyora.chat import check
from kyora.chat import env as chat_env
from kyora.chat.client import ChatError

ENV = chat_env.ChatEnv(url="https://abc.supabase.co", anon_key="anon", email="yo@correo.com", password="secreta", device="pc")


class Fake:
    def __init__(self, env, fail=None, messages=()):
        self.fail, self.calls, self.stored = fail, [], list(messages)

    def sign_in(self):
        if self.fail == "login":
            raise ChatError("invalid_credentials", "Invalid login credentials")

    def rpc(self, name, payload=None):
        self.calls.append((name, payload))
        if self.fail == name:
            raise ChatError("PGRST202", f"Could not find the function public.{name}")
        if name == "ensure_default_conversation":
            return "conv-1"
        if name == "send_message":
            message = {"id": payload["p_id"], "sender_device": payload["p_device"], "status": "sent",
                       "body": payload["p_body"], "sent_at": payload["p_sent_at"], "attachments": []}
            self.stored.append(message)
            return message
        return self.stored


def run(args=(), env=ENV, **kw):
    lines, holder = [], {}

    def factory(e):
        holder["client"] = Fake(e, **kw)
        return holder["client"]

    code = check.run(list(args), out=lines.append, env=env, client_factory=factory)
    return code, "\n".join(lines), holder.get("client")


def test_check_without_credentials_names_what_is_missing_and_never_connects():
    code, text, client = run(env=chat_env.ChatEnv())
    assert code == 2 and "SUPABASE_URL" in text and "CHAT_PASSWORD" in text and client is None


def test_check_signs_in_and_lists_without_writing():
    old = {"id": "a", "sender_device": "movil", "status": "sent", "body": "hola desde el móvil", "sent_at": "2026-10-30T09:00:00Z",
           "attachments": [{"id": "x"}]}
    code, text, client = run(messages=[old])
    assert code == 0 and "hola desde el móvil" in text and "[1 adjunto(s)]" in text and "movil" in text
    assert [n for n, _ in client.calls] == ["ensure_default_conversation", "list_messages"]      # no se escribió nada


def test_check_with_send_stores_the_test_message_with_this_device():
    code, text, client = run(["--send"])
    assert code == 0 and "Mensaje de prueba enviado" in text and check.TEST_TEXT in text
    sent = next(p for n, p in client.calls if n == "send_message")
    assert sent["p_body"] == check.TEST_TEXT and sent["p_device"] == "pc" and sent["p_attachments"] == []
    assert sent["p_sent_at"].endswith("Z") and len(sent["p_id"]) == 36


def test_check_explains_the_common_failures_in_spanish_without_leaking_secrets():
    code, text, _ = run(fail="login")
    assert code == 1 and "correo o la contraseña" in text and "secreta" not in text
    code, text, _ = run(fail="ensure_default_conversation")
    assert code == 1 and "supabase/schema.sql" in text
    code, text, _ = run(["--send"], fail="send_message")
    assert code == 1 and "schema.sql" in text


def test_explain_covers_offline_and_unknown_errors():
    assert "internet" in check.explain(ChatError("offline", "Sin conexión con Supabase", retryable=True))
    assert "README" in check.explain(ChatError("500", "algo raro"))
    assert "confirmado" in check.explain(ChatError("email_not_confirmed", "Email not confirmed"))
