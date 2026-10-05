---
name: Coding Practices and Structure
description: Estándares de programación limpia, nombres y organización estructural.
version: 1.0
---

# Estructura y Buenas Prácticas de Programación

Un buen agente genera código fácil de leer para los humanos, enfocado en el mantenimiento sobre la brevedad extrema.

## 1. Legibilidad antes que brevedad
No combines demasiadas operaciones en una sola línea.

### Ejemplo Incorrecto:
```javascript
const r = u.filter(x => x.a && x.s === 1).map(x => x.n);
```

### Ejemplo Correcto:
```javascript
const activeUsers = users
    .filter(user => user.isActive)
    .map(user => user.name);
```

## 2. Retornos Tempranos y Complejidad
Usa retornos tempranos para manejar errores y no anides if's indiscriminadamente.

### Ejemplo Correcto:
```javascript
function processOrder(order) {
    if (!order) return null;
    if (order.items.length === 0) return null;
    if (!order.isPaid) return null;
    
    return sendOrder(order);
}
```

## 3. Convenciones de Nombres
Los nombres comunican la finalidad de las entidades.
*   **Variables:** `camelCase` o `snake_case` (según lenguaje). Ej: `userName` o `user_name`.
*   **Constantes:** Mayúsculas con guiones bajos. Ej: `MAX_LOGIN_ATTEMPTS`.
*   **Clases:** Sustantivos en PascalCase. Ej: `InvoiceService`.
*   **Funciones:** Verbos descriptivos. Ej: `calculateTotal()`.
*   **Booleanos:** Prefijos como `is`, `has`, `can`, `should`. Ej: `isVerified`, `hasPermission`.

Evitar: `data`, `value`, `temp`, `item`, `stringName`.

## 4. Organización Interna de la Clase
La organización ayuda a identificar responsabilidades:
1.  Constantes
2.  Propiedades / Atributos
3.  Constructor
4.  Métodos públicos
5.  Métodos privados
6.  Métodos auxiliares
