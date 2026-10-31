"""Los colores de Kyora sacados 100 % del fondo de pantalla (al arrancar y cada vez que el carrusel cambia el fondo).

Se buscan los colores que más ocupan la imagen, grises incluidos (corte de la mediana sobre una miniatura):
- Acento: el color que más predomina (sin contar el negro casi puro, que es el telón), aclarado si hace falta para
  que se lea. Si ese color es gris, el acento es un gris claro: nunca un color que apenas aparece. Excepción: si el que
  más ocupa es casi blanco o gris pero entre los 4 primeros hay un color vivo, el acento es ese (si no, un fondo con
  mucho blanco y mucho color se vería siempre blanco).
- Segundo color: el siguiente que más ocupa; tiñe los filetes de luz. Tercero y cuarto: los que siguen.
- Los cuatro que más se repiten del fondo (`top_colors`) quedan en el tema (`wall_colors`) y se enseñan en Configuración >
  Fondos; con ellos Kyora empieza a tener una paleta y no solo un color plano. Los fondos oscuros no cambian nunca.
- Marco y placas: siempre oscuros, con el matiz del color que más ocupa.
- Texto e iconos del marco: claros, con un toque del acento.
"""
import logging

from PySide6.QtCore import QSize, Qt
from PySide6.QtGui import QColor, QImage, QImageReader

from kyora.system import wallpaper

log = logging.getLogger("kyora.ui")

SAMPLE = (96, 54)  # se analiza una miniatura: basta y es instantáneo
CUT_DEPTH = 4  # 2^4 = 16 cajas de color antes de juntar las parecidas
MERGE_DISTANCE = 48  # dos cajas más cerca que esto (en RGB) son el mismo color
REFINE = 2
NEAR_BLACK = 0.12  # brillo por debajo del cual un color es "negro": el telón, no el acento
MIN_ACCENT_WEIGHT = 0.08  # un color que ocupa menos que esto no puede ser el acento
GRAY = 0.12  # saturación por debajo de la cual un color es gris
SECOND_WEIGHT = 0.25  # el segundo color solo tiñe si ocupa al menos esto
NEUTRAL = 0.25  # si el que más ocupa tiene menos saturación que esto (blanco, crema, gris), pesa más un color vivo
VIVID = 0.35  # saturación mínima de un color "vivo" de los 4 primeros para ser el acento en su lugar
VIVID_WEIGHT = 0.08  # y lo que debe ocupar como mínimo
OTHER_WEIGHT = 0.06  # el tercero y el cuarto color solo cuentan si ocupan al menos esto

# valores (brillo HSV) de los fondos: siempre oscuros, con el matiz del fondo de pantalla
DARK = {
    "frame": 0.065, "frame_light": 0.085, "frame_dark": 0.04, "capsule": 0.115, "dots_pill": 0.025,
    "card": 0.09, "card_inner": 0.055, "glass_top": 0.125, "glass_bottom": 0.085, "capsule_pressed": 0.07,
    "raised_top": 0.17, "raised_bottom": 0.095, "plate_top": 0.15, "plate_bottom": 0.105, "plate_pick": 0.21,
}


TOP = 4  # los colores que más se repiten que se guardan del fondo


def top_colors(colors, count=TOP):
    """Los `count` colores que más se repiten ([(color, peso)] del que más al que menos): ["#rrggbb", ...]."""
    return [c for c, _ in colors[:count]]


def _small(image):
    return image.scaled(*SAMPLE, Qt.IgnoreAspectRatio, Qt.SmoothTransformation).convertToFormat(QImage.Format_RGB32)


def median_cut(pixels, depth=CUT_DEPTH):
    """[(color "#rrggbb", peso 0..1)] de los colores que más ocupan, del que más al que menos.

    `pixels`: [(r, g, b)]. Se parte la caja de colores por su lado más largo, por la mediana, `depth` veces; luego
    se juntan las cajas de colores parecidos."""
    if not pixels:
        return []
    boxes = [list(pixels)]
    for _ in range(depth):
        split = []
        for box in boxes:
            if len(box) < 2:
                split.append(box)
                continue
            ranges = [max(p[i] for p in box) - min(p[i] for p in box) for i in range(3)]
            axis = ranges.index(max(ranges))
            box.sort(key=lambda p, a=axis: p[a])
            half = len(box) // 2
            split += [box[:half], box[half:]]
        boxes = split
    clusters = []  # [[r, g, b, cuántos]]
    for box in boxes:
        if not box:
            continue
        n = len(box)
        r, g, b = (sum(p[i] for p in box) / n for i in range(3))
        for c in clusters:
            if ((c[0] - r) ** 2 + (c[1] - g) ** 2 + (c[2] - b) ** 2) ** 0.5 < MERGE_DISTANCE:
                total = c[3] + n
                c[0], c[1], c[2] = ((c[i] * c[3] + v * n) / total for i, v in enumerate((r, g, b)))
                c[3] = total
                break
        else:
            clusters.append([r, g, b, n])
    for _ in range(REFINE):  # un par de pasadas de k-medias: cada píxel al color más cercano (las cajas mezcladas
        sums = [[0.0, 0.0, 0.0, 0] for _ in clusters]  # de la mediana dejarían colores intermedios que no están)
        for p in pixels:
            best = min(range(len(clusters)), key=lambda i: sum((clusters[i][k] - p[k]) ** 2 for k in range(3)))
            acc = sums[best]
            acc[0] += p[0]
            acc[1] += p[1]
            acc[2] += p[2]
            acc[3] += 1
        clusters = [[a[0] / a[3], a[1] / a[3], a[2] / a[3], a[3]] for a in sums if a[3]]
    clusters.sort(key=lambda c: -c[3])
    total = len(pixels)
    return [(QColor(round(r), round(g), round(b)).name(), n / total) for r, g, b, n in clusters]


def dominant_colors(image):
    """Los colores que más ocupan la imagen, con su peso (ver median_cut)."""
    small = _small(image)
    pixels = []
    for y in range(small.height()):
        for x in range(small.width()):
            c = small.pixelColor(x, y)
            pixels.append((c.red(), c.green(), c.blue()))
    return median_cut(pixels)


def _readable(color):
    """El acento listo para verse sobre gris oscuro, sin cambiar su matiz: gris claro si es gris; aclarado si es
    oscuro."""
    if color.hsvSaturationF() < GRAY:
        return QColor.fromHsvF(0, 0, 0.82)
    hue = max(color.hsvHueF(), 0.0)
    return QColor.fromHsvF(hue, min(color.hsvSaturationF(), 0.85), max(color.valueF(), 0.78))


def derive_palette(colors):
    """Los colores del tema a partir de los dominantes del fondo ([(color, peso)], del que más al que menos).

    Fondos siempre oscuros con el matiz del que más ocupa; acento y segundo color de los que más predominan."""
    if not colors:
        return {}
    base = QColor(colors[0][0])
    hue = max(base.hsvHueF(), 0.0)
    tint = 0.0  # los fondos son siempre gris neutro: el color del fondo de pantalla queda para el énfasis (iconos, bordes)
    palette = {key: QColor.fromHsvF(hue, tint, value).name() for key, value in DARK.items()}
    visible = [(c, w) for c, w in colors if QColor(c).valueF() >= NEAR_BLACK and w >= MIN_ACCENT_WEIGHT]
    pool = visible or colors
    pick = 0  # el acento es el que más ocupa... salvo que sea casi blanco o gris y haya un color vivo entre los 4 primeros
    if QColor(pool[0][0]).hsvSaturationF() < NEUTRAL:
        for i, (c, w) in enumerate(pool[:TOP]):
            if QColor(c).hsvSaturationF() >= VIVID and w >= VIVID_WEIGHT:
                pick = i
                break
    accent = _readable(QColor(pool[pick][0]))
    others = [x for j, x in enumerate(pool) if j != pick]
    rest = [(c, w) for c, w in others if w >= SECOND_WEIGHT]
    second = _readable(QColor(rest[0][0])) if rest else accent
    more = [(c, w) for c, w in others if w >= OTHER_WEIGHT]
    third = _readable(QColor(more[1][0])) if len(more) > 1 else second
    fourth = _readable(QColor(more[2][0])) if len(more) > 2 else third
    ah = max(accent.hsvHueF(), 0.0)
    ink_sat = 0.0  # las letras, en gris claro
    palette.update(
        ink=QColor.fromHsvF(ah, ink_sat, 0.86).name(),
        dim=QColor.fromHsvF(ah, ink_sat, 0.62).name(),
        plate_hi=f"#38{second.name()[1:]}",
        accent=accent.name(),
        second=second.name(),
        third=third.name(),
        fourth=fourth.name(),
        wall_colors=tuple(top_colors(colors)),
    )
    return palette


def palette_from_path(path):
    """Colores del tema para la imagen `path` (se lee una miniatura: rápido aunque sea de 8K). {} si no se puede."""
    reader = QImageReader(path)
    reader.setAutoTransform(True)
    size = reader.size()
    if size.isValid():
        reader.setScaledSize(size.scaled(QSize(*SAMPLE) * 2, Qt.KeepAspectRatio))
    image = reader.read()
    if image.isNull():
        log.debug("No se pudo leer %s: %s", path, reader.errorString())
        return {}
    return derive_palette(dominant_colors(image))


def wallpaper_palette():
    """Los colores del fondo de pantalla actual ({} si no se puede leer: el tema se queda como está)."""
    try:
        return palette_from_path(wallpaper.current())
    except Exception:
        log.debug("No se pudo leer el fondo de pantalla", exc_info=True)
        return {}
