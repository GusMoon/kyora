# A) Manifiesto

Este documento es el marco operativo para crear, estructurar y mantener documentación en cualquier proyecto de software. Está escrito para ser interpretado por una IA: define **principios, criterios de decisión e invariantes**, no listas cerradas de archivos ni pasos fijos.

Se rige por dos fuentes:
- **Diátaxis:** cada documento sirve a una sola intención.
- **Just Enough Documentation:** documentar lo necesario, cuando es necesario.

**Cómo debes usar este marco:**
1. Los ejemplos (stacks, archivos, comandos) son **ilustrativos**. Nunca los trates como requisitos del proyecto.
2. Antes de documentar, **infiere el contexto real del proyecto** (stack, tamaño, madurez, audiencia) leyendo el repositorio y su `AGENTS.md`.
3. Si el proyecto contradice un ejemplo, gana el proyecto. Si contradice un principio o invariante, gana este marco y lo señalas.
4. Ante información insuficiente para decidir dónde o cómo documentar, pregunta antes de escribir.

---

# B) Raíz De La Metodología

Cuatro principios. Todo lo demás se deriva de ellos.

1. **Separación por intención.** Cada documento responde a una sola necesidad: *aprender, hacer, consultar o entender*. Si un texto sirve a dos, divídelo y enlaza.
2. **Documentación viva.** La documentación es código: cambia en el mismo commit/PR que lo que describe. Un cambio sin su documentación asociada está incompleto.
3. **Escalabilidad por capas.** Ningún proyecto necesita los cuatro sectores completos desde el día 1. Empieza por lo que reduce más riesgo (normalmente Referencia y Explicación mínima) y añade capas cuando el crecimiento lo justifique.
4. **Cero burocracia.** Elimina o actualiza todo documento duplicado, redundante u obsoleto (ej. un archivo que explica una tecnología que el sistema ya reemplazó). Un documento sin dueño ni vigencia es deuda.

**Protocolo de adaptación (cómo evolucionas con el proyecto):**
- **Detecta:** ¿qué componentes tiene el proyecto y cuáles cambian con frecuencia?
- **Decide:** por cada pieza de información, aplica la Matriz (sección D) para elegir sector; crea el archivo solo si hay información real que alojar.
- **Moldea:** adopta el stack, los nombres y las convenciones del proyecto en tus respuestas, código y documentos.
- **Poda:** cuando detectes documentación redundante u obsoleta, propón eliminarla o actualizarla.

---

# C) Sectores de Documentación (Diátaxis)

`docs/` se divide en cuatro sectores. Cada uno se define por **intención, prueba de pertenencia, forma e invariantes**. Los archivos concretos de cada sector nacen según las necesidades del proyecto.

## 1. Tutoriales (`docs/tutorials/`)
- **Intención:** que alguien nuevo **aprenda haciendo** y obtenga un resultado tangible.
- **Prueba de pertenencia:** *¿Es un recorrido guiado para un principiante en el sistema?*
- **Forma:** directiva y secuencial ("haz esto, luego aquello"). Sin teoría ni alternativas.
- **Invariantes:**
  - 100% reproducible: si se siguen los pasos, funciona a la primera.
  - Cero pasos omitidos; cada acción lleva su comando o instrucción exacta.
  - Cada tramo declara el **resultado esperado** (pantalla, salida, respuesta).
  - Prerrequisitos exactos al inicio. Se asume conocimiento del lenguaje, no del sistema.
- **Adaptación:** nace cuando hay onboarding o primer uso que enseñar. *(Ilustrativo: "getting started", primer flujo end-to-end.)*

## 2. Guías Prácticas (`docs/how-to/`)
- **Intención:** que alguien con el entorno listo **resuelva una tarea o problema concreto**.
- **Prueba de pertenencia:** *¿Es una receta para lograr X, sin necesidad de entender el porqué?*
- **Forma:** título como acción o pregunta; pasos numerados; flexible si hay alternativas.
- **Invariantes:**
  - Objetivo explícito de la tarea.
  - No explica teoría; enlaza a Explicación o Referencia.
  - Incluye "Solución de problemas" cuando la tarea es propensa a errores.
- **Adaptación:** nace cuando una tarea se repite o es delicada (mantenimiento, despliegue, migraciones, extensión de componentes). *(Ilustrativo: "Cómo empaquetar la app", "Cómo revertir un cambio de datos".)*

## 3. Referencia (`docs/reference/`)
- **Intención:** que alguien **consulte un dato exacto**.
- **Prueba de pertenencia:** *¿Es un hecho verificable que alguien buscaría, no leería de corrido?*
- **Forma:** seca, técnica, estructurada; su organización **refleja la del sistema**, no las tareas del usuario. Se genera desde el código cuando es posible; si no, se mantiene con rigor en cada commit.
- **Invariantes:**
  - **Exactitud absoluta:** si la referencia miente, el sistema se rompe.
  - Solo hechos: sin opiniones, sin tutoriales.
  - Nombres exactos (case-sensitive), tipos, restricciones, valores por defecto y rangos.
- **Adaptación:** un archivo por cada superficie del sistema que tenga datos consultables (datos, interfaces, configuración, componentes, contratos). Si el proyecto no tiene esa superficie, no existe el archivo. *(Ilustrativo: esquema de BD, API, variables de entorno, catálogo de UI.)*

## 4. Explicación (`docs/explanation/` y `docs/adr/`)
- **Intención:** que alguien **entienda el porqué** del sistema.
- **Prueba de pertenencia:** *¿Responde por qué es así, qué alternativas se descartaron y qué costo tiene?*
- **Forma:** discursiva y contextual; sin instrucciones paso a paso.
- **Invariantes:**
  - Responde al **por qué**, no solo al qué.
  - Menciona alternativas descartadas y sus razones.
  - Registra consecuencias positivas y negativas, y reglas de negocio inmutables.
  - Las decisiones técnicas relevantes se registran como **ADR** (formato MADR). Un ADR no se edita para cambiar la decisión: se crea otro que lo reemplaza.
- **Adaptación:** `explanation/` para arquitectura, dominio y estrategias transversales; `adr/` solo para decisiones no triviales. *(Ilustrativo: arquitectura general, elección de tecnología, manejo de seguridad.)*

## 5. Elementos Transversales (fuera de `docs/`)
- **`README.md`:** puerta de entrada. Qué es el proyecto, stack, cómo instalarlo y ejecutarlo. Mínimo y enlazado, sin duplicar `docs/`.
- **`AGENTS.md`:** contrato operativo para la IA. Es un **índice y un conjunto de reglas**, nunca contenido técnico.
  - Contiene: identidad, stack y convenciones del proyecto, reglas if/then, Definition of Done, punteros de contexto.
  - Se mantiene corto (~500-800 palabras). Si crece, se modulariza por dominio (`docs/ai/context_*.md`) y se carga bajo demanda.

---

# D) Matriz de Diferenciación

Ante cualquier información por documentar, formula la pregunta del lector y enruta:

| Pregunta del lector | Sector | Señal |
| :-- | :-- | :-- |
| "¿Cómo empiezo desde cero?" | **Tutorial** | Recorrido guiado con resultado esperado |
| "¿Cómo logro X?" | **How-to** | Receta accionable para una tarea |
| "¿Cuál es el dato exacto de Y?" | **Referencia** | Hecho verificable, estructurado |
| "¿Por qué Z es así?" | **Explicación / ADR** | Contexto, alternativas y consecuencias |

**Regla de desempate:** si una información responde a dos preguntas, sepárala por intención y enlaza. Nunca la dupliques.

---

# E) Anti-Patrones

Evítalos siempre. Si detectas uno, corrígelo o señálalo.

1. **Mezclar sectores:** una instrucción de instalación dentro de una referencia, o teoría dentro de un how-to.
2. **Duplicar información:** cada hecho vive en un solo lugar; lo demás lo enlaza.
3. **Documentar lo obvio:** si el nombre, el tipado o el código ya lo explican, no lo repitas.
4. **Dejar documentos huérfanos u obsoletos:** si ya no aplica, se elimina o se actualiza.
5. **Tratar ejemplos como requisitos:** imponer archivos, stacks o estructuras que el proyecto no necesita.
6. **Inflar el contexto:** cargar documentación completa cuando basta el índice y los archivos relevantes a la tarea.
