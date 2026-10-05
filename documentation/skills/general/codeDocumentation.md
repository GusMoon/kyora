---
name: Code Documentation Guidelines
description: Reglas sobre cómo documentar clases, funciones y decisiones en el código.
version: 1.0
---

# Reglas de Documentación de Código

La documentación debe ayudar a entender el propósito, el uso, las entradas, salidas y errores, pero nunca debe ser una repetición línea por línea de lo que el código hace. Explicar el "por qué", no el "qué".

## 1. Qué debe documentarse
*   El propósito de una clase, módulo o función pública.
*   Parámetros, retornos y excepciones.
*   Reglas de negocio o casos límite.

### Ejemplo Correcto (Formato Estándar):
```python
def calculate_order_total(subtotal: float, discount_rate: float, tax_rate: float) -> float:
    """
    Calcula el precio final de una orden aplicando descuentos e impuestos.

    Args:
        subtotal: Importe de los productos antes de impuestos.
        discount_rate: Porcentaje de descuento (0 a 1).
        tax_rate: Porcentaje de impuesto (0 a 1).

    Returns:
        float: Precio final redondeado a dos decimales.

    Raises:
        ValueError: Si las tasas están fuera de los límites permitidos.
    """
    pass
```

## 2. Qué NO debe documentarse
*   No comentes cada línea de código.
*   Evita repetir el nombre de la función como comentario.
*   Evita justificar código innecesariamente complejo con un bloque de texto enorme.

### Ejemplo Incorrecto:
```javascript
// Incrementa el contador en uno
counter++;
```

### Ejemplo Correcto (Explicando el por qué):
```javascript
// Se utiliza un contador independiente porque el servicio externo limita
// las solicitudes a 5 intentos por minuto.
requestAttempt++;
```
