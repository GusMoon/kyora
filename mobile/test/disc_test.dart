import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/data/audio_levels.dart';
import 'package:kyora_chat/data/music_store.dart';
import 'package:kyora_chat/ui/widgets/deck_math.dart';
import 'package:kyora_chat/ui/widgets/disc_player.dart';
import 'package:kyora_chat/ui/widgets/song_arc_list.dart';
import 'package:kyora_chat/util/sound_shape.dart';

void main() {
  group('la ruleta de álbumes', () {
    test('el de enfrente está a 0° y se reparten la vuelta entera', () {
      expect(DeckMath.angleOf(0, 0, 6), 0);
      expect(DeckMath.angleOf(1, 0, 6), closeTo(math.pi / 3, 1e-9));
      expect(DeckMath.angleOf(5, 0, 6), closeTo(-math.pi / 3, 1e-9)); // la última queda a la izquierda de la primera
      expect(DeckMath.stepFor(6) * 6, closeTo(2 * math.pi, 1e-9));
    });

    test('da vueltas sin tope: la posición puede crecer o bajar sin límite', () {
      for (final pos in [0.0, 6.0, -6.0, 60.0]) {
        expect(DeckMath.frontOf(pos, 6), 0, reason: '$pos');
        expect(DeckMath.angleOf(2, pos, 6), closeTo(2 * math.pi / 3, 1e-9), reason: '$pos');
      }
      expect(DeckMath.frontOf(-1, 6), 5);
      expect(DeckMath.frontOf(7, 6), 1);
    });

    test('con muchos álbumes el paso no baja de 30°, y sigue sin tope', () {
      expect(DeckMath.stepFor(40), closeTo(math.pi / 6, 1e-9));
      expect(DeckMath.angleOf(39, 0, 40), closeTo(-math.pi / 6, 1e-9));
    });

    test('con uno solo no hay nada que girar', () {
      expect(DeckMath.stepFor(1), 0);
      expect(DeckMath.angleOf(0, 3, 1), 0);
    });

    test('al soltar se detiene en un álbum, más lejos cuanto más rápido iba el dedo', () {
      expect(DeckMath.settleAt(1.2, 0), 1);
      expect(DeckMath.settleAt(1.6, 0), 2);
      expect(DeckMath.settleAt(0, -2000), greaterThan(2)); // hacia la izquierda: los siguientes
      expect(DeckMath.settleAt(0, 2000), lessThan(-2));
    });

    test('por muy rápido que vaya el dedo, la inercia no pasa de 3 álbumes', () {
      expect(DeckMath.settleAt(0, -100000), DeckMath.maxFling);
      expect(DeckMath.settleAt(5, 100000), 5 - DeckMath.maxFling);
    });

    test('la sensibilidad cambia cuánto hay que mover el dedo: lo normal es el doble que antes, y lo más rápido, lo de antes', () {
      expect(DeckMath.pixelsFor(1), 220);
      expect(DeckMath.pixelsFor(MusicSettings.deckSpeedMax), 110);
      expect(DeckMath.pixelsFor(MusicSettings.deckSpeedMin), 440);
      // y con menos sensibilidad, el mismo lanzamiento avanza menos
      expect(DeckMath.settleAt(0, -2000, pixels: DeckMath.pixelsFor(0.5)), greaterThan(DeckMath.settleAt(0, -2000, pixels: DeckMath.pixelsFor(2)) - 4));
      expect(DeckMath.settleAt(0, -1000, pixels: 440), lessThan(DeckMath.settleAt(0, -1000, pixels: 110)));
    });

    test('con el anillo abierto las tarjetas vecinas no se pisan: queda aire entre ellas, sean cuantas sean', () {
      const side = 272.0;
      final card = side * DeckMath.openScale;
      for (final n in [3, 4, 5, 6, 8, 10, 12, 13, 20, 40]) {
        final chord = 2 * DeckMath.radiusFor(n, side) * math.sin(DeckMath.stepFor(n) / 2);
        expect(chord, greaterThanOrEqualTo(card * (1 + DeckMath.gap) - 1e-9), reason: '$n álbumes');
      }
    });

    test('con pocos álbumes el anillo no crece de más', () {
      expect(DeckMath.radiusFor(2, 100), 78);
      expect(DeckMath.radiusFor(4, 100), 78);
      expect(DeckMath.radiusFor(12, 100), greaterThan(DeckMath.radiusFor(6, 100)));
    });
  });

  group('girar el disco con el dedo', () {
    const start = Duration(minutes: 1);
    const length = Duration(minutes: 3);

    test('hacia delante adelanta y hacia atrás retrocede, a 30 s por vuelta', () {
      expect(DiscPlayer.perTurn, const Duration(seconds: 30));
      expect(DiscPlayer.seekTarget(start, 2 * math.pi, length), const Duration(seconds: 90));
      expect(DiscPlayer.seekTarget(start, math.pi / 2, length), const Duration(seconds: 67, milliseconds: 500));
      expect(DiscPlayer.seekTarget(start, -math.pi, length), const Duration(seconds: 45));
    });

    test('no se sale de la canción', () {
      expect(DiscPlayer.seekTarget(start, -100, length), Duration.zero);
      expect(DiscPlayer.seekTarget(start, 100, length), length);
    });

    test('la diferencia de ángulos va por el camino corto, también al cruzar el lado izquierdo', () {
      expect(DiscPlayer.wrapAngle(0.2), closeTo(0.2, 1e-9));
      expect(DiscPlayer.wrapAngle(-0.2), closeTo(-0.2, 1e-9));
      expect(DiscPlayer.wrapAngle(2 * math.pi - 0.1), closeTo(-0.1, 1e-9)); // `atan2` salta de π a -π
      expect(DiscPlayer.wrapAngle(-2 * math.pi + 0.1), closeTo(0.1, 1e-9));
    });

    test('mientras suena da 33⅓ vueltas por minuto', () {
      expect(DiscPlayer.speed * 60 / (2 * math.pi), closeTo(100 / 3, 1e-9));
    });
  });

  group('el círculo que reacciona al sonido', () {
    List<double> wave([double size = 0.5]) => [for (var i = 0; i < SoundShape.points; i++) i.isEven ? size : -size];

    void run(SoundShape shape, {bool active = true, double seconds = 0.2}) {
      for (var t = 0.0; t < seconds; t += 1 / 60) {
        shape.tick(1 / 60, active: active, seconds: t);
      }
    }

    double spread(SoundShape shape) {
      var low = double.infinity, high = 0.0;
      for (var a = 0.0; a < 2 * math.pi; a += 0.05) {
        final r = shape.radiusAt(a, 100);
        low = math.min(low, r);
        high = math.max(high, r);
      }
      return high - low;
    }

    test('en silencio queda liso', () {
      final shape = SoundShape();
      expect(shape.atRest, isTrue);
      expect(spread(shape), closeTo(0, 1e-9));
      expect(shape.radiusAt(1, 100), 100);
    });

    test('los bajos lo hinchan', () {
      final shape = SoundShape()..add(SoundFrame(level: 0.3, bass: 0.5, wave: wave()));
      run(shape);
      expect(shape.swell, greaterThan(0.5));
      expect(shape.radiusAt(0, 100), greaterThan(100));
    });

    test('sin bajos, no se hincha aunque haya sonido', () {
      final shape = SoundShape()..add(SoundFrame(level: 0.3, bass: 0.5, wave: wave()));
      run(shape);
      final loud = shape.swell;
      for (var i = 0; i < 30; i++) {
        shape.add(SoundFrame(level: 0.3, bass: 0.01, wave: wave()));
        run(shape, seconds: 0.05);
      }
      expect(shape.swell, lessThan(loud / 3));
    });

    test('un golpe altera la línea de repente, y se calma enseguida', () {
      final shape = SoundShape();
      for (var i = 0; i < 40; i++) {
        shape.add(SoundFrame(level: 0.1, bass: 0.1, wave: wave()));
        run(shape, seconds: 0.05);
      }
      final calm = spread(shape);
      shape.add(SoundFrame(level: 0.9, bass: 0.1, wave: wave()));
      expect(shape.jolt, greaterThan(0.3));
      run(shape, seconds: 0.05);
      expect(spread(shape), greaterThan(calm * 1.5));
      for (var i = 0; i < 20; i++) {
        shape.add(SoundFrame(level: 0.05, bass: 0.01, wave: wave()));
        run(shape, seconds: 0.05);
      }
      expect(shape.jolt, lessThan(0.05));
    });

    test('reacciona igual en una canción suave que en una fuerte', () {
      double swellWith(double scale) {
        final shape = SoundShape();
        for (var i = 0; i < 30; i++) {
          shape.add(SoundFrame(level: 0.5 * scale, bass: (i.isEven ? 0.6 : 0.2) * scale, wave: wave()));
          run(shape, seconds: 0.05);
        }
        return shape.swell;
      }

      expect(swellWith(0.1), closeTo(swellWith(1), 0.05));
    });

    test('la línea se cierra: empieza y acaba en el mismo radio', () {
      final shape = SoundShape()..add(SoundFrame(level: 0.5, bass: 0.5, wave: [for (var i = 0; i < SoundShape.points; i++) math.sin(i * 0.7)]));
      run(shape);
      expect(shape.radiusAt(0, 100), closeTo(shape.radiusAt(2 * math.pi, 100), 1e-6));
    });

    test('sin poder leer el sonido, late mientras suena', () {
      final shape = SoundShape()..add(const SoundFrame(level: 0));
      expect(shape.heard, isFalse);
      run(shape, seconds: 0.4);
      expect(shape.swell, greaterThan(0.1));
    });

    test('al pausar vuelve a quedar liso', () {
      final shape = SoundShape()..add(SoundFrame(level: 0.5, bass: 0.5, wave: wave()));
      run(shape);
      expect(shape.atRest, isFalse);
      run(shape, active: false, seconds: 3);
      expect(shape.atRest, isTrue);
      expect(spread(shape), closeTo(0, 1));
    });

    test('lo que manda Android se entiende, y un número suelto es solo la fuerza', () {
      final frame = SoundFrame.fromEvent(<double>[0.4, 0.2, 0.1, -0.1]);
      expect(frame.level, 0.4);
      expect(frame.bass, 0.2);
      expect(frame.wave, [0.1, -0.1]);
      expect(SoundFrame.fromEvent(0.3).level, 0.3);
      expect(SoundFrame.fromEvent(null).level, 0);
    });
  });

  group('la curva de la lista', () {
    test('la fila del centro no se aparta, y cuanto más lejos, más', () {
      expect(SongArcList.offsetOf(0, 600), 0);
      expect(SongArcList.offsetOf(1, 600), greaterThan(0));
      expect(SongArcList.offsetOf(2, 600), greaterThan(SongArcList.offsetOf(1, 600) * 3)); // es una curva, no una recta
    });

    test('por arriba y por abajo es igual', () {
      expect(SongArcList.offsetOf(-2, 600), SongArcList.offsetOf(2, 600));
    });

    test('muy lejos no se rompe', () {
      expect(SongArcList.offsetOf(100, 600), 600);
    });
  });
}
