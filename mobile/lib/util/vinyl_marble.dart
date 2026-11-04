import 'dart:math' as math;
import 'dart:typed_data';

/// Lo que hace falta para jaspear un disco. Son solo números para poder calcularlo en otro hilo.
class MarbleSpec {
  const MarbleSpec({required this.colors, required this.size, required this.seed});

  /// Los colores de la portada, como `0xAARRGGBB`.
  final List<int> colors;

  /// El lado de la imagen, en píxeles.
  final int size;

  /// Con la misma semilla sale siempre el mismo dibujo: un álbum conserva su disco.
  final int seed;
}

/// Una semilla estable a partir de un texto (`String.hashCode` cambia entre ejecuciones).
int marbleSeed(String text) {
  var hash = 17;
  for (final unit in text.codeUnits) {
    hash = (hash * 31 + unit) & 0x7FFFFFFF;
  }
  return hash;
}

/// El vinilo jaspeado: los colores de la portada mezclados como tinta en el plástico, en remolino alrededor del centro y con vetas oscuras.
/// Devuelve los píxeles RGBA, opacos, de una imagen de `size` × `size`.
Uint8List marblePixels(MarbleSpec spec) {
  final size = spec.size;
  final out = Uint8List(size * size * 4);
  final colors = spec.colors.isEmpty ? const [0xFF2A2A2E, 0xFF141416] : spec.colors;
  final noise = _Noise(spec.seed);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final u = (x + 0.5) / size * 2 - 1;
      final v = (y + 0.5) / size * 2 - 1;
      final r = math.sqrt(u * u + v * v);
      // el remolino: cuanto más lejos del centro, más girado
      final a = math.atan2(v, u) + 1.5 * r;
      final px = math.cos(a) * r * 2.3;
      final py = math.sin(a) * r * 2.3;
      // el ruido deformado con otro ruido es lo que hace las volutas de tinta
      final qx = noise.fbm(px + 1.7, py + 9.2);
      final qy = noise.fbm(px + 8.3, py + 2.8);
      final n = noise.fbm(px + 3.4 * qx, py + 3.4 * qy);
      final t = ((n - 0.30) / 0.40).clamp(0.0, 1.0);

      // el color: un recorrido por los de la portada, algo apagado porque es plástico y no pintura
      final at = t * (colors.length - 1);
      final i = at.floor().clamp(0, colors.length - 1);
      final j = math.min(i + 1, colors.length - 1);
      final mix = at - i;
      var red = _channel(colors[i], 16) * (1 - mix) + _channel(colors[j], 16) * mix;
      var green = _channel(colors[i], 8) * (1 - mix) + _channel(colors[j], 8) * mix;
      var blue = _channel(colors[i], 0) * (1 - mix) + _channel(colors[j], 0) * mix;

      // las vetas oscuras, finas, por donde el ruido cruza la mitad
      final vein = noise.fbm(px * 1.5 + 5 * qy, py * 1.5 + 5 * qx);
      final dark = 1 - ((vein - 0.5).abs() / 0.05).clamp(0.0, 1.0);
      final shade = 0.64 * (1 - 0.82 * dark * dark);
      // y un humo más claro donde la tinta se acumula
      final smoke = 1 + 0.30 * math.pow(qx, 3).toDouble();
      red *= shade * smoke;
      green *= shade * smoke;
      blue *= shade * smoke;

      final p = (y * size + x) * 4;
      out[p] = red.round().clamp(0, 255);
      out[p + 1] = green.round().clamp(0, 255);
      out[p + 2] = blue.round().clamp(0, 255);
      out[p + 3] = 255;
    }
  }
  return out;
}

double _channel(int color, int shift) => ((color >> shift) & 0xFF).toDouble();

/// Ruido suave por valores: una rejilla de números al azar (fijos por semilla), interpolados.
class _Noise {
  _Noise(int seed) {
    final random = math.Random(seed);
    for (var i = 0; i < _side * _side; i++) {
      _grid[i] = random.nextDouble();
    }
  }

  static const _side = 64;
  final Float64List _grid = Float64List(_side * _side);

  double _at(int x, int y) => _grid[(y & (_side - 1)) * _side + (x & (_side - 1))];

  double _value(double x, double y) {
    final fx = x.floorToDouble(), fy = y.floorToDouble();
    final ix = fx.toInt(), iy = fy.toInt();
    final dx = x - fx, dy = y - fy;
    final sx = dx * dx * (3 - 2 * dx), sy = dy * dy * (3 - 2 * dy);
    final top = _at(ix, iy) * (1 - sx) + _at(ix + 1, iy) * sx;
    final bottom = _at(ix, iy + 1) * (1 - sx) + _at(ix + 1, iy + 1) * sx;
    return top * (1 - sy) + bottom * sy;
  }

  /// Varias capas del ruido, cada una el doble de fina y la mitad de fuerte. De 0 a 1, casi siempre alrededor de la mitad.
  double fbm(double x, double y) {
    var sum = 0.0, weight = 0.5, total = 0.0;
    var fx = x, fy = y;
    for (var i = 0; i < 4; i++) {
      sum += _value(fx, fy) * weight;
      total += weight;
      fx *= 2.03;
      fy *= 2.03;
      weight *= 0.5;
    }
    return sum / total;
  }
}
