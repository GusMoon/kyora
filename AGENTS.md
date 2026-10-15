# AGENTS.md - Contrato Operativo (Versión Ligera)

## 1. Identidad
Eres un experto en Python 3.14 y PySide6 (Qt Widgets). Trabajas en Kyora, una aplicación de escritorio local, todo en uno, para multitarea y enfoque personal. Tu prioridad es la documentación viva, la estabilidad y la separación entre la base común (`motherboard`) y los ecosistemas.
Metodología de documentación: `docs/FRAMEWORK.md`. Consúltalo ante dudas de dónde o cómo documentar.

## 2. Regla de Oro de Contexto (CRÍTICO)
NO asumas ni inventes esquemas, rutas o estados.
ANTES de escribir código, DEBES leer con la herramienta de lectura de archivos solo lo relevante a la tarea:

* Si tocas la ventana principal o el fondo -> Lee `core/matrix/motherboard/motherboardRoot.py` y `docs/reference/motherboardRootUI.md`
* Si tocas el reactor u otro artefacto visual global -> Lee `core/matrix/motherboard/globalArtifacts/`
* Si tocas un ícono -> Lee `core/resources/icons/` y créalo ahí, en la subcarpeta de su categoría (p. ej. `information/`); nunca dentro del componente que lo usa
* Si tocas la navegación heredada (`rootView.py`) -> Lee `core/matrix/motherboard/rootComponents/rootView.py`
* Si tocas el launcher de ecosistemas -> Lee `core/matrix/motherboard/rootComponents/launcher.py`
* Si tocas colores, tipografía o componentes compartidos -> Lee `core/matrix/motherboard/globalComponents/kyora_theme.py`
* Si tocas un ecosistema -> Lee su carpeta en `core/matrix/motherboard/ecosystems/<nombre>/`
* Si dudas de una decisión pasada -> Busca por palabra clave en `docs/adr/`; no leas todos
* Si necesitas un procedimiento -> Revisa `docs/how-to/`

Flujo: clasifica la tarea -> identifica componentes -> lee solo lo necesario -> ejecuta -> actualiza documentación -> verifica el DoD -> entrega código y documentación juntos.

## 3. Definition of Done (DoD)
Una tarea no está completa hasta que:

1. El código cumple la sección 4.
2. Si cambiaste datos, interfaces o configuración, se actualizó su archivo en `docs/reference/`.
3. Si hubo una decisión de diseño no trivial, se creó un ADR en `docs/adr/` (MADR). No edites ADRs previos: crea uno que los reemplace.
4. Si eliminaste o reemplazaste algo, se eliminó o actualizó todo documento que lo describía.
5. `python -m pytest` pasa.

## 4. Estilo y Convenciones

* Python: PEP 8, docstrings Google Style en español.
* Datos: SQLite con `sqlite3` estándar y repositorios propios; esquema con `CREATE TABLE IF NOT EXISTS` (sin ORM ni migraciones).
* Imports absolutos desde `core.matrix.motherboard...`.
* Comentarios en código: solo para el *por qué* de algo no obvio.

## 5. Límites

* No mezcles intenciones: no escribas tutoriales dentro de archivos de referencia.
* No documentes lo que el código ya explica claramente con buenos nombres.
* Cada hecho vive en un solo lugar: enlaza, no copies.
* No crees ADRs ni documentos para cambios triviales.
* Si encuentras documentación obsoleta o redundante, propón eliminarla o actualizarla.
* Si no tienes suficiente contexto tras leer los archivos relevantes, PREGUNTA antes de codificar.

## 6. Crecimiento de este archivo
Este archivo es un índice con reglas, no documentación. Propón al usuario cada cambio antes de editarlo y hazlo en el mismo cambio que lo motiva:

* Aparece un componente con documentación propia -> añade su línea en la sección 2.
* Se elimina o renombra un archivo enlazado -> corrige o quita su línea.
* Un tipo de cambio se repite y siempre exige actualizar un documento -> añade una condición al DoD.
* Cambia el stack o una convención -> actualiza las secciones 1 y 4.
* Nunca añadas contenido técnico (esquemas, endpoints, listas de campos): enlázalo.
* Mantén el archivo bajo ~500 palabras. Si lo excede, mueve el detalle a `docs/ai/context_<dominio>.md` y deja solo el puntero en la sección 2.
