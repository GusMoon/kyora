---
name: Work Structure Routine
description: Rutina y proceso de trabajo obligatorio para el agente de IA antes y durante el desarrollo en Kiora.
version: 2.0
---

# Rutina de Trabajo Estructurado

Este documento define las reglas de comportamiento que deben ser respetadas antes de escribir cualquier línea de código, guiadas al 100% por nuestras buenas prácticas.

## 1. Etapa 1: Analizar antes de programar
SIEMPRE lee la estructura general del proyecto y comprende su arquitectura antes de ejecutar.
**Ejemplo de análisis a realizar mentalmente o consultar:**
*   ¿Qué arquitectura usamos? (MVC, capas, Hexagonal)
*   ¿Qué archivos se relacionan?
*   ¿Existen dependencias?

## 2. Etapa 2: Proponer un plan
Antes de implementar, propone un plan en pasos pequeños y concretos. Espera mi aprobación.
**Ejemplo de lo que debes proporcionar:**
*   **Archivo:** `core/voice_engine/main.py`
*   **Responsabilidad:** Iniciar el pipeline de voz.
*   **Posibles efectos:** Uso excesivo de memoria por el thread.
*   **Pruebas:** Mockear el micrófono para testing.

## 3. Etapa 3: Implementar una parte
Implementa únicamente una parte del plan respetando la arquitectura.
**Ejemplo:** Si estás creando el controlador, no introduzcas reglas de negocio complejas ni queries a bases de datos allí. Usa los servicios correspondientes.

## 4. Etapa 4 y 5: Revisar y Refactorizar
Revisa el código generado (claridad, complejidad, duplicación) como un revisor senior. Luego, corrige solo problemas críticos e importantes.

## 5. Registro de Cambios
Si realizas descargas, instalaciones, o alteras la lógica y los archivos, DEBES documentarlo obligatoriamente en `c:\proyectos\kiora\documentation\changes`.

**Formato obligatorio del log de cambios:**
*   **Fecha y hora:** `YYYY-MM-DD HH:MM:SS`
*   **Archivos afectados:** `+ core/voice_engine/vad.py`
*   **Explicación breve:** "Se integró el detector de actividad de voz."
*   **Cambios lógicos:** "Se pasó de un threshold estático a dinámico."
*   **Instalaciones:** "Se instaló `webrtcvad`."
*   **Toggles:** "N/A"
