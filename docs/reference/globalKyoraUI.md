# globalKyoraUI: lenguaje visual global

Reglas visuales comunes a la base (`motherboard`) y a los ecosistemas. Los valores
exactos (hexadecimales, radios) viven en código, en
[kyora_theme.py](../../core/matrix/motherboard/globalComponents/kyora_theme.py);
aquí solo se describe qué significan y cuándo usarlos.

## Tipografía
| Propiedad | Valor |
|---|---|
| Familia | `Prototype` (constante `FONT` de `kyora_theme.py`, `FONT_FAMILY` de [style.py](../../core/matrix/motherboard/internalArtifacts/style.py)) |
| Archivo | [Prototype.ttf](../../core/resources/font/prototype/Prototype.ttf), cargado en [main.py](../../main.py) |
| Fuente por defecto de la app | `QFont("Prototype", 10)` |
| Pesos | Solo existe el regular; la negrita es sintetizada por Qt |

Nunca se escribe el nombre de la familia a mano en un ecosistema nuevo: se importa
`FONT` de `kyora_theme.py`.

## Color
| Grupo | Uso | Constantes |
|---|---|---|
| Superficies | Fondos, de más oscuro a más claro | `BG_*` |
| Bordes | Contornos de paneles, campos y tarjetas | `BORDER*` |
| Texto | Jerarquía de énfasis, de `TEXT` (máximo) a `TEXT_DISABLED` | `TEXT*` |
| Acento | Elemento activo o destacado | `ACCENT*` |
| Acción principal | Botón primario | `PRIMARY*` |
| Estados | Pendiente, en progreso, completado, peligro | `STATUS_*`, `DANGER*` |

Los artefactos informativos de la ventana raíz usan la paleta del reactor
(`TEXT_PRIMARY` `#ebeef2`, `TEXT_SECONDARY` `#969ba2`), no la de los ecosistemas.

## Componentes
| Componente | Descripción | Código |
|---|---|---|
| Botón | Variantes `standard`, `primary`, `ghost`, `accent`, `danger` | `button_style()` |
| Chip conmutable | Reposo y `:checked` con acento | `chip_style()` |
| Esquinas | `RADIUS_CARD` en tarjetas y botones, `RADIUS_PANEL` en paneles | `rounded_path()` |
| Fila de información | Icono sin contorno y el atributo a su lado | `IconBox` e `InfoRow` en [style.py](../../core/matrix/motherboard/internalArtifacts/style.py) |

### Fila de información
Patrón de la esquina superior izquierda de la ventana raíz (detalle de sus filas en
[motherboardRootUI.md](motherboardRootUI.md)).

| Propiedad | Valor |
|---|---|
| Área | `ICON_BOX` = 32 px, sin contorno ni relleno |
| Icono | `ICON_SIZE` = 28 px, color `TEXT_PRIMARY`, función `draw` de [icons/information](../../core/resources/icons/information/) |
| Atributo | A la derecha del icono, 11 pt, `TEXT_PRIMARY`, separado `ROW_SPACING` = 12 px |

## Iconos
Cada icono es un módulo de [core/resources/icons](../../core/resources/icons/) con una
función `draw(painter, center, scale, color, base_size)`. Pueden ser vectoriales
(`QPainter`, trazo de 1.6 px con extremos redondeados) o de fuente `Segoe MDL2 Assets`
(vía `font_icon.py`).

Se clasifican en subcarpetas por categoría. `information/` agrupa los de datos
informativos: `calendar`, `clock`, `location` y `weather`.
