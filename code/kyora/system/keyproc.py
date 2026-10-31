"""El gancho del teclado en su propio proceso (`python -m kyora.system.keyproc`).

Un gancho WH_KEYBOARD_LL hace esperar a cada tecla de todo el sistema hasta que responde. Dentro de Kyora, escrito
en Python, compartía el intérprete con la interfaz y los hilos del núcleo: cualquier trabajo largo (pintar, consultar
a Windows) dejaba las teclas esperando hasta 2 s. Aquí tiene un Python solo para él y responde al momento.

Protocolo, por líneas de texto:
- Kyora le manda por stdin una línea JSON con las combinaciones (ver `encode_bindings`); cada una lleva un código.
- El hijo contesta "ready" (o "failed"), luego el código de cada combinación que se dispara, y "log <texto>" para
  lo que Kyora debe anotar en su registro (las teclas lentas).
- Si stdin se cierra (Kyora se cerró o se cayó), el gancho se quita y el proceso termina: la tecla Windows vuelve a
  ser la de siempre.
"""
import json
import logging
import os
import sys
import threading

KINDS = ("chords", "taps")


def _key_out(kind, key):
    """Clave de un diccionario de combinaciones -> algo que cabe en JSON."""
    return list(key) if kind == "chords" else key  # taps: la tecla de la capa


def _key_in(kind, value):
    return tuple(value) if kind == "chords" else value


def encode_bindings(**groups):
    """{tipo: {clave: función}} -> (texto JSON para el hijo, {código: función} para Kyora)."""
    data, actions = {}, {}
    for kind in KINDS:
        rows = []
        for i, (key, fn) in enumerate((groups.get(kind) or {}).items()):
            code = f"{kind[0]}{i}"
            rows.append([_key_out(kind, key), code])
            actions[code] = fn
        data[kind] = rows
    return json.dumps(data), actions


def decode_bindings(text, make):
    """Lo contrario en el hijo: {tipo: {clave: make(código)}}."""
    data = json.loads(text)
    groups = {kind: {_key_in(kind, key): make(code) for key, code in data.get(kind, [])} for kind in KINDS}
    return groups


class _Lines(logging.Handler):
    """Lo que el gancho anota (teclas lentas, fallos) viaja a Kyora como "log …"."""

    def __init__(self, send):
        super().__init__(logging.INFO)
        self._send = send

    def emit(self, record):
        self._send("log " + record.getMessage().replace("\n", " "))


def _allow_parent_foreground():
    """Este proceso es el que lee las teclas, así que Windows le da el derecho de pasar ventanas al frente: se lo
    cede a Kyora (si no, el buscador se abriría sin foco y no dejaría escribir)."""
    try:
        import ctypes

        ctypes.windll.user32.AllowSetForegroundWindow(os.getppid())
    except (AttributeError, OSError):
        pass


def main():
    # se importa aquí: los tests usan este módulo sin tocar Windows
    from kyora.system.keys import KeyboardHook

    out_lock = threading.Lock()

    def send(line):
        _allow_parent_foreground()
        with out_lock:
            sys.stdout.write(line + "\n")
            sys.stdout.flush()

    keys_log = logging.getLogger("kyora.keys")
    keys_log.addHandler(_Lines(send))
    keys_log.setLevel(logging.INFO)
    first = sys.stdin.readline()
    if not first:
        return
    groups = decode_bindings(first, lambda code: (lambda: send(code)))
    hook = KeyboardHook(groups["chords"], groups["taps"])
    hook.start()
    hook.ready.wait(3)
    send("failed" if hook.failed or not hook.ready.is_set() else "ready")
    sys.stdin.read()  # espera a que Kyora cierre stdin (o se caiga)
    hook.stop()


if __name__ == "__main__":
    main()
