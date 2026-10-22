"""Lanzar los .bat de scripts/ y volver a abrir Kyora, desde el menú de la lechuza.

Solo se pueden lanzar los scripts de esta lista cerrada (nunca una ruta que llegue de fuera).
"""
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]  # la carpeta de Kyora (la que tiene scripts/ y code/)
CODE = ROOT / "code"
CREATE_NO_WINDOW = 0x08000000
DETACHED_PROCESS = 0x00000008
CREATE_NEW_PROCESS_GROUP = 0x00000200

# nombre -> (archivo .bat, argumentos, cerrar Kyora antes de lanzarlo)
SCRIPTS = {
    "actualizar": ("actualizar_kyora.bat", [], False),  # el .bat ya cierra Kyora él solo
    "consola": ("iniciar_kyora.bat", ["--restart"], True),
    "rescate": ("rescate_kyora.bat", [], True),
    "instalar_inicio": ("instalar_inicio.bat", [], False),
    "quitar_inicio": ("quitar_inicio.bat", [], False),
}


def script_command(name, root=ROOT):
    """Orden para abrir el script `name` en una consola nueva. ValueError si no está en la lista."""
    if name not in SCRIPTS:
        raise ValueError(f"No existe el script {name}")
    bat, args, _ = SCRIPTS[name]
    return ["cmd", "/c", "start", "", str(Path(root) / "scripts" / bat), *args]


def closes_kyora(name):
    return SCRIPTS[name][2]


def run_script(name):
    subprocess.Popen(script_command(name), cwd=str(ROOT), creationflags=CREATE_NO_WINDOW)


def relaunch():
    """Abre otra Kyora que espera a que esta se cierre (--restart) y arranca sin consola."""
    exe = Path(sys.executable)
    windowless = exe.with_name("pythonw.exe")
    subprocess.Popen(
        [str(windowless if windowless.exists() else exe), "-m", "kyora", "--restart"],
        cwd=str(CODE), creationflags=DETACHED_PROCESS | CREATE_NEW_PROCESS_GROUP, close_fds=True,
    )
