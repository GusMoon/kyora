# Kyora

Aplicación de escritorio todo en uno, enfocada en la multitarea y el enfoque personal. Organiza el trabajo en ecosistemas (tareas, bitácora, calendario, explorador de archivos y música) sobre una interfaz principal común.

## Stack

Python 3.14 · PySide6 (Qt Widgets) · SQLite con `sqlite3` estándar · yt-dlp + Deno · pytest · PyInstaller

## Requisitos

- Windows
- Python 3.14

## Instalación

```bash
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
```

## Ejecución

```bash
python main.py
```

## Estructura

El núcleo vive en `core/matrix/motherboard/`:

- `globalComponents/`: componentes y funciones globales que cualquier ecosistema puede usar.
- `rootComponents/`: interfaz raíz heredada (`rootView.py` y launcher), aún no conectada a `motherboardRoot.py`.
- `globalArtifacts/`: elementos visuales globales de la ventana raíz (el `Reactor`).
- `internalArtifacts/`: información de la ventana raíz (fecha y hora, ubicación y clima).
- `ecosystems/`: un subpaquete por ecosistema (`tasks`, `logbook`, `calendar`, `explorer`, `studio`).
- `motherboardRoot.py`: ventana raíz (punto de entrada de `main.py`).

Los íconos viven en `core/resources/icons/`.

## Documentación

- Reglas de trabajo con IA: `AGENTS.md`
- Metodología de documentación: `docs/FRAMEWORK.md`
