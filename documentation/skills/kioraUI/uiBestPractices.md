---
name: UI Best Practices
description: Prácticas obligatorias y restricciones al desarrollar la interfaz gráfica.
version: 1.0
---

# Buenas Prácticas de Interfaz Gráfica

Al desarrollar componentes visuales en `kioraUI`, el agente debe acatar las siguientes prohibiciones y obligaciones para mantener el código mantenible y libre de congelamientos.

## 1. Lo que NUNCA debes hacer
*   **No mezclar UI y Base de Datos:** Nunca hacer consultas SQL directamente desde un archivo de vista o de ventana.
*   **No poner todo en `main.py`:** `main.py` solo inicia y ensambla. No debe crear widgets, validar o consultar BD.
*   **No bloquear el Hilo Principal (Main Thread):** NUNCA ejecutes procesos largos (procesar audio, descargar archivos, leer miles de registros) en la interfaz. La ventana se congelará.
*   **No usar `utils.py` como cajón de sastre:** Organiza las funciones según su responsabilidad (ej. formateadores de fecha en un archivo de strings/dates, validadores en otro).
*   **No depender de Variables Globales:** Utiliza objetos, inyección de dependencias explícitas y el ViewModel para mantener estados.

## 2. Mantén las Vistas Delgadas
Una ventana (`View`) SOLO debe:
*   Crear botones y campos.
*   Mostrar información y errores.
*   Emitir y reaccionar a señales.

Si una vista tiene cientos de líneas con cálculos matemáticos, formateos complejos o lógica condicional profunda, DEBE ser refactorizada moviendo esa lógica al `ViewModel` o a un `Caso de Uso`.

## 3. Validación de Dos Capas
*   La interfaz (UI) puede tener validación rápida (ej. comprobar que un campo no esté vacío) para mejorar la Experiencia de Usuario (UX).
*   Sin embargo, el **Dominio** siempre debe garantizar y re-validar que no se cree un estado inválido, independientemente de la UI.
