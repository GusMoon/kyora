"""Registro de acciones: el catálogo de lo que Kyora sabe hacer.

La interfaz, los atajos de teclado y, más adelante, el móvil, la voz y la IA
invocan siempre estas mismas acciones por su nombre.
"""
import logging

log = logging.getLogger("kyora.actions")


class ActionError(Exception):
    def __init__(self, code, message):
        super().__init__(message)
        self.code = code
        self.message = message


class ActionRegistry:
    def __init__(self):
        self._actions = {}

    def register(self, name, fn, destructive=False):
        self._actions[name] = (fn, destructive)

    def names(self):
        return sorted(self._actions)

    def is_destructive(self, name):
        return name in self._actions and self._actions[name][1]

    def invoke(self, name, payload=None):
        """Ejecuta una acción y devuelve siempre {"ok": True, "data": ...} o {"ok": False, "error": ...}."""
        if name not in self._actions:
            return {"ok": False, "error": {"code": "unknown_action", "message": f"No existe la acción {name}"}}
        fn, _ = self._actions[name]
        try:
            return {"ok": True, "data": fn(**(payload or {}))}
        except ActionError as err:
            return {"ok": False, "error": {"code": err.code, "message": err.message}}
        except TypeError as err:
            log.warning("Payload inválido en %s: %s", name, err)
            return {"ok": False, "error": {"code": "bad_payload", "message": str(err)}}
        except Exception:
            log.exception("Fallo en la acción %s", name)
            return {"ok": False, "error": {"code": "internal", "message": "Error interno, mira kyora.log"}}
