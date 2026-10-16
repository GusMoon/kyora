# Kyora

Aplicación de escritorio todo en uno, enfocada en la multitarea y el enfoque personal. Organiza el trabajo en ecosistemas (tareas, bitácora, calendario, directorio de archivos y música) sobre una interfaz principal común.

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

- `artifacts/`: artefactos visuales de la ventana raíz.
  - `globalArtifacts/`: elementos visuales globales (el `Reactor`).
- `modules/`: módulos globales (tema, estilos, diálogos, componentes y `directory`, con sus `components/`) que cualquier ecosistema puede usar; ver `definitions.txt`.
- `ecosystems/`: un subpaquete por ecosistema (`tasks`, `logbook`, `calendar`, `studio`).
- `motherboardRoot.py`: ventana raíz (punto de entrada de `main.py`).

Los íconos viven en `core/resources/icons/`.

## Documentación

- Reglas de trabajo con IA: `AGENTS.md`
- Metodología de documentación: `docs/FRAMEWORK.md`
