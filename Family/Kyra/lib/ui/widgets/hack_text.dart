import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../theme.dart';
import 'section_motion.dart';

/// Un texto que **se escribe solo**, como en las animaciones de hacking: de izquierda a derecha las letras se van descifrando; justo delante de
/// las que ya están salen unos pocos signos cambiantes (`░▒▓#@$%…`) y lo que falta aún no se ve. Se repite al aparecer (con el turno que le toque
/// dentro del cambio de sección, `order`) y cada vez que el texto cambia.
///
/// Al irse hace lo contrario: cuando la sección que lo lleva se va (o el panel que lo lleva se cierra, ver [HackExit]) las letras se **deshacen**
/// de derecha a izquierda, convertidas en signos cambiantes, hasta no quedar nada.
///
/// Lo que falta por escribir se pinta transparente **con el texto real**, así el tamaño y los saltos de línea no cambian mientras se escribe. Al
/// terminar es un `Text` normal. Con las animaciones del sistema quitadas (o con [enabled] en `false`) sale entero al instante.
class HackText extends StatefulWidget {
  const HackText(
    this.text, {
    super.key,
    this.textKey,
    this.style,
    this.maxLines,
    this.overflow,
    this.textAlign,
    this.softWrap,
    this.order = 0,
    this.animate = true,
    this.delay = Duration.zero,
    this.perChar = const Duration(milliseconds: 14),
  });

  final String text;

  /// La clave del `Text` de dentro (así una prueba o quien busque por clave encuentra un `Text`, no este widget).
  final Key? textKey;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;
  final bool? softWrap;

  /// Su turno dentro del cambio de sección (como el de `FlyIn`): empieza a escribirse cuando su bloque empieza a aparecer.
  final int order;

  /// Sin esto el texto sale entero, sin escribirse (lo que ya estaba cuando se abrió la pantalla). Cambiarlo con el texto escribiéndose no lo corta.
  final bool animate;

  /// Una espera más, al aparecer (para los bloques que se escalonan por su cuenta, como las fichas de Configuración).
  final Duration delay;

  /// Lo que tarda cada letra (la escritura entera dura entre [minTime] y [maxTime]).
  final Duration perChar;

  /// Apagado general (las pruebas lo apagan para ver siempre el texto entero).
  static bool enabled = true;

  /// Los signos que salen delante de lo escrito.
  static const glyphs = '░▒▓#@\$%&*+=<>/\\01ｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄ';

  /// Cuántas letras de «ruido» van delante de las ya escritas, y cada cuánto cambian (ms).
  static const window = 3;
  static const flicker = 30;

  static const minTime = Duration(milliseconds: 180);
  static const maxTime = Duration(milliseconds: 560);

  /// Lo que dura escribir un texto de `length` letras.
  static Duration timeFor(int length, Duration perChar) {
    final ms = (perChar.inMilliseconds * (length + window)).clamp(minTime.inMilliseconds, maxTime.inMilliseconds);
    return Duration(milliseconds: ms);
  }

  /// Cuántas letras de `length` se ven con el avance `progress` (de 0 a 1): las ya escritas y las del ruido de delante. Sube siempre.
  static int revealed(double progress, int length) => (progress.clamp(0.0, 1.0) * (length + window)).floor();

  /// El texto como se ve con el avance `progress` en el instante `tick`: (lo escrito, el ruido, lo que falta —el texto real, para guardar el sitio—).
  /// Los espacios y los saltos de línea no se cambian por ruido.
  static (String done, String noise, String rest) frame(String text, double progress, int tick) {
    final shown = revealed(progress, text.length).clamp(0, text.length + window);
    final done = (shown - window).clamp(0, text.length);
    final end = shown.clamp(0, text.length);
    final noise = StringBuffer();
    for (var i = done; i < end; i++) {
      final c = text[i];
      noise.write(c.trim().isEmpty ? c : glyphs[(i * 7 + tick * 13 + text.length) % glyphs.length]);
    }
    return (text.substring(0, done), noise.toString(), text.substring(end));
  }

  @override
  State<HackText> createState() => _HackTextState();
}

class _HackTextState extends State<HackText> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_onTick);
  bool _started = false;
  bool _done = false;
  double _delayMs = 0;
  double _progress = 0;
  int _tick = 0;

  Duration get _duration => HackText.timeFor(widget.text.length, widget.perChar);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      final motion = SectionMotion.maybeOf(context);
      // dentro de un cambio de sección, espera a que su bloque empiece a aparecer; la sección que se va no escribe nada
      if (motion != null && motion.leaving) {
        _finish();
      } else {
        _begin((motion == null ? 0.0 : SectionMotion.waitFor(motion.animation.value, widget.order)) + widget.delay.inMilliseconds);
      }
    }
  }

  @override
  void didUpdateWidget(HackText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) _begin(0);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  /// ¿Hay que escribirlo? No si está apagado, si no se pidió o si el sistema pidió quitar las animaciones.
  bool get _active => widget.animate && HackText.enabled && !(MediaQuery.maybeDisableAnimationsOf(context) ?? false) && widget.text.isNotEmpty;

  void _begin(double delayMs) {
    _delayMs = delayMs;
    _progress = 0;
    _tick = 0;
    _done = false;
    if (!_active) {
      _finish();
      return;
    }
    if (_ticker.isActive) _ticker.stop();
    unawaited(_ticker.start());
  }

  void _finish() {
    _done = true;
    _progress = 1;
    if (_ticker.isActive) _ticker.stop();
  }

  void _onTick(Duration elapsed) {
    final ms = elapsed.inMilliseconds - _delayMs;
    final progress = (ms / _duration.inMilliseconds).clamp(0.0, 1.0);
    final tick = (elapsed.inMilliseconds / HackText.flicker).floor();
    if (progress >= 1) {
      setState(_finish);
    } else if (progress != _progress || tick != _tick) {
      setState(() {
        _progress = progress;
        _tick = tick;
      });
    }
  }

  /// ¿Se está deshaciendo el texto? Con la animación de salida de su panel (`HackExit`) o la de su sección (que se va).
  Animation<double>? _exitAnimation(BuildContext context) {
    if (!HackText.enabled || widget.text.isEmpty || (MediaQuery.maybeDisableAnimationsOf(context) ?? false)) return null;
    final exit = HackExit.maybeOf(context);
    if (exit != null) return exit.animation;
    final motion = SectionMotion.maybeOf(context);
    return motion != null && motion.leaving && motion.moving ? motion.animation : null;
  }

  @override
  Widget build(BuildContext context) {
    final exit = _exitAnimation(context);
    if (exit == null) return _typed(context);
    final motion = HackExit.maybeOf(context) == null ? SectionMotion.maybeOf(context) : null;
    return AnimatedBuilder(
      animation: exit,
      builder: (context, _) {
        // cuánto queda del texto: 1 entero → 0 nada
        final double left;
        if (motion != null) {
          left = 1 - SectionMotion.exitProgress(exit.value, widget.order);
        } else {
          left = exit.status == AnimationStatus.reverse ? exit.value : 1;
        }
        if (left >= 1) return _typed(context);
        final tick = (exit.value * 1000 / HackText.flicker).floor();
        return _frame(context, left, tick);
      },
    );
  }

  Widget _typed(BuildContext context) {
    if (_done) {
      return Text(widget.text, key: widget.textKey, style: widget.style, maxLines: widget.maxLines, overflow: widget.overflow, textAlign: widget.textAlign, softWrap: widget.softWrap);
    }
    return _frame(context, _progress, _tick);
  }

  Widget _frame(BuildContext context, double progress, int tick) {
    final (done, noise, rest) = HackText.frame(widget.text, progress, tick);
    final c = context.colors;
    return Semantics(
      label: widget.text,
      excludeSemantics: true,
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: done),
            TextSpan(text: noise, style: TextStyle(fontFamily: monoFont, color: c.accent)),
            TextSpan(text: rest, style: const TextStyle(color: Colors.transparent)),
          ],
        ),
        key: widget.textKey,
        style: widget.style,
        maxLines: widget.maxLines,
        overflow: widget.overflow,
        textAlign: widget.textAlign,
        softWrap: widget.softWrap,
      ),
    );
  }
}

/// Le dice a los [HackText] de dentro que **se están yendo**: mientras `animation` va de 1 a 0 (la salida de un panel que se cierra), sus textos se
/// deshacen de derecha a izquierda. Mientras sube (la entrada) no hacen nada: se escriben como siempre.
class HackExit extends InheritedWidget {
  const HackExit({super.key, required this.animation, required super.child});

  final Animation<double> animation;

  static HackExit? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<HackExit>();

  @override
  bool updateShouldNotify(HackExit old) => old.animation != animation;
}
