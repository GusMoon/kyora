---
name: Architecture Clean MVVM
description: Reglas de arquitectura limpia combinada con MVVM para el desarrollo de KioraUI.
version: 1.0
---

# Arquitectura Clean + MVVM para KioraUI

Kiora utiliza una arquitectura separada por capas combinada con Model-View-ViewModel (MVVM) para desacoplar la interfaz gráfica de la lógica de negocio.

## 1. Regla de Oro
**Las dependencias deben apuntar hacia el núcleo.** La lógica de negocio jamás debe depender de PySide6, de una base de datos específica o de una API.

## 2. Flujo Estricto de Acción
Toda interacción del usuario debe seguir el siguiente flujo unidireccional:
1. **View (UI):** Recibe el clic/evento.
2. **View:** Notifica al `ViewModel`.
3. **ViewModel:** Obtiene los datos de la vista y coordina el estado.
4. **ViewModel:** Ejecuta el `Caso de Uso` (Use Case).
5. **Caso de Uso:** Valida y coordina la operación con el Dominio.
6. **Entidad (Domain):** Aplica las reglas estrictas de negocio.
7. **Repositorio (Infrastructure):** Persiste o consume los datos.
8. **Resultado:** Regresa al `ViewModel`.
9. **ViewModel:** Actualiza el estado y emite señales.
10. **View:** Reacciona a las señales para actualizar la interfaz.

## 3. Ensamblaje de Dependencias
*   Ninguna clase debe crear directamente sus propias dependencias complejas (como un Repositorio o un ViewModel).
*   El ensamblado y la inyección de dependencias deben realizarse en el punto de entrada (por ejemplo, `bootstrap.py` o `main.py`).

## 4. Estructura de Capas
*   **Presentation (`views`, `viewmodels`, `widgets`):** Muestra información.
*   **Application (`use_cases`):** Nombres de acciones reales (`CreateTask`, `UpdateTask`). No `Manager` o `Utils`.
*   **Domain (`entities`, `value_objects`):** Reglas puras que pueden probarse sin UI ni DB.
*   **Infrastructure (`database`, `repositories`):** Implementaciones técnicas (SQLite, APIs).
