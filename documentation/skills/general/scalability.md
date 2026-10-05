---
name: Scalability and Comprehension
description: Reglas para mantener el código escalable, mantenible y robusto.
version: 1.0
---

# Escalabilidad y Comprensión

El código debe ser escalable sin sacrificar la comprensión. Un sistema modular bien documentado es la mejor garantía.

## 1. Responsabilidad Única
Cada función debe realizar una tarea principal. Separar validación, persistencia y presentación es crucial.

### Ejemplo de Función con Múltiples Responsabilidades (Malo):
```php
public function registerUser(Request $request) {
    // Valida, guarda, envía correo y prepara la respuesta todo aquí
}
```

### Ejemplo Modular y Escalable (Correcto):
```javascript
function createUser(userData) {
    // 1. Validación
    validateUserData(userData);

    // 2. Normalización
    const normalizedUser = normalizeUserData(userData);

    // 3. Persistencia
    const savedUser = userRepository.save(normalizedUser);

    // 4. Respuesta
    return mapUserResponse(savedUser);
}
```

## 2. Organización de Archivos (MVC / Capas)
*   **Controladores / Routers:** Coordinan solicitudes. No reglas de negocio complejas.
*   **Servicios / Casos de Uso:** Lógica de negocio.
*   **Repositorios / Infraestructura:** Acceso a datos. 
*   **UI / Presentation:** Manejo estrictamente visual.

## 3. Pruebas y Robustez
*   Agrega pruebas para cada nueva regla de negocio.
*   Cubre casos normales, inválidos y límites.
*   No introduzcas patrones de diseño abstractos que no aporten beneficios claros, puesto que dificultan la comprensión futura.
