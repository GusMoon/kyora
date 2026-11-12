import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../theme.dart';
import 'cyber_panel.dart';
import 'hack_text.dart';
import 'section_motion.dart';

/// El **espacio focal**: el sitio de la pantalla donde se abre el menú circular y, después, cualquier panel (avisos, hojas de opciones,
/// editores rápidos). Lo de dentro se ve nítido; el resto del fondo se desenfoca un poco y se oscurece (`FocusVeil`).
abstract final class FocusSpace {
  /// Donde se abrió el menú la última vez (en la pantalla). Los paneles se abren ahí; sin nada, en el centro.
  static Offset? last;

  /// El aire con los bordes de la pantalla.
  static const margin = 16.0;

  /// Dónde va un panel de tamaño `size` en una pantalla `screen` (sin la zona de `insets`: barras y teclado): centrado en el punto focal y
  /// corrido lo justo para que quepa entero.
  static Rect place(Size size, Size screen, EdgeInsets insets, {Offset? around}) {
    final area = Rect.fromLTRB(insets.left + margin, insets.top + margin, screen.width - insets.right - margin, screen.height - insets.bottom - margin);
    final focus = around ?? last ?? area.center;
    double fit(double v, double low, double high) => low > high ? (low + high) / 2 : v.clamp(low, high);
    final left = fit(focus.dx - size.width / 2, area.left, area.right - size.width);
    final top = fit(focus.dy - size.height / 2, area.top, area.bottom - size.height);
    return Offset(left, top) & size;
  }
}

/// El velo del espacio focal: todo lo de fuera del hueco ([hole], en coordenadas de este widget) se desenfoca un poco y se oscurece; el hueco
/// queda limpio. [amount] va de 0 (sin velo) a 1 (entero), para abrirlo y cerrarlo con suavidad. Tocar fuera llama a [onTapOutside].
class FocusVeil extends StatelessWidget {
  const FocusVeil({super.key, required this.hole, this.amount = 1, this.onTapOutside, this.blur = 7, this.dim = 0.45});

  /// El hueco nítido.
  final Path Function(Size size) hole;
  final double amount;
  final VoidCallback? onTapOutside;

  /// El desenfoque (ligero) y el oscurecido de alrededor.
  final double blur;
  final double dim;

  /// Un hueco redondo de radio `radius` alrededor de `center`.
  static Path Function(Size) circle(Offset center, double radius) => (_) => Path()..addOval(Rect.fromCircle(center: center, radius: radius));

  /// Un hueco con la forma de un panel (rectángulo de esquinas rectas).
  static Path Function(Size) panel(Rect rect, {double cut = 0}) => (_) => Path()..addRect(rect);

  @override
  Widget build(BuildContext context) {
    if (amount <= 0) return const SizedBox.shrink();
    return GestureDetector(
      key: const Key('focus-veil'),
      behavior: HitTestBehavior.opaque,
      onTap: onTapOutside,
      child: ClipPath(
        clipper: _OutsideClipper(hole),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: blur * amount, sigmaY: blur * amount),
          child: ColoredBox(color: Colors.black.withValues(alpha: dim * amount), child: const SizedBox.expand()),
        ),
      ),
    );
  }
}

class _OutsideClipper extends CustomClipper<Path> {
  _OutsideClipper(this.hole);

  final Path Function(Size size) hole;

  @override
  Path getClip(Size size) => Path.combine(PathOperation.difference, Path()..addRect(Offset.zero & size), hole(size));

  @override
  bool shouldReclip(_OutsideClipper old) => true;
}

/// Abre un panel en el **espacio focal**: el contenido de [builder] en un panel ciberpunk centrado donde se abrió el menú (o en el centro),
/// con el resto del fondo desenfocado y oscurecido. Sustituye a los diálogos y a las hojas que salían desde abajo. Tocar fuera o «atrás» lo
/// cierran (devuelve `null`).
Future<T?> showFocusPanel<T>(BuildContext context, {required WidgetBuilder builder, double maxWidth = 420, String? title}) =>
    Navigator.of(context, rootNavigator: true).push<T>(FocusPanelRoute<T>(builder: builder, maxWidth: maxWidth, title: title));

/// La ruta del panel focal (ver [showFocusPanel]).
class FocusPanelRoute<T> extends PopupRoute<T> {
  FocusPanelRoute({required this.builder, this.maxWidth = 420, this.title});

  final WidgetBuilder builder;
  final double maxWidth;
  final String? title;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => false; // lo cierra el propio velo (que es el que se ve)

  @override
  String? get barrierLabel => 'Cerrar';

  @override
  Duration get transitionDuration => const Duration(milliseconds: 220);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 240);

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) => _FocusPanel<T>(route: this);
}

class _FocusPanel<T> extends StatefulWidget {
  const _FocusPanel({required this.route});

  final FocusPanelRoute<T> route;

  @override
  State<_FocusPanel<T>> createState() => _FocusPanelState<T>();
}

class _FocusPanelState<T> extends State<_FocusPanel<T>> {
  /// Dónde quedó el panel (para el hueco del velo).
  final ValueNotifier<Rect> _rect = ValueNotifier(Rect.zero);

  @override
  void dispose() {
    _rect.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final route = widget.route;
    final media = MediaQuery.of(context);
    final insets = EdgeInsets.fromLTRB(media.padding.left, media.padding.top, media.padding.right, math.max(media.padding.bottom, media.viewInsets.bottom));
    final c = context.colors;
    return AnimatedBuilder(
      animation: route.animation!,
      builder: (context, child) {
        final t = Curves.easeOutCubic.transform(route.animation!.value);
        return Stack(
          fit: StackFit.expand,
          children: [
            ValueListenableBuilder<Rect>(
              valueListenable: _rect,
              builder: (context, rect, _) => FocusVeil(
                hole: FocusVeil.panel(rect.inflate(2)),
                amount: t,
                onTapOutside: () => Navigator.of(context).maybePop(),
              ),
            ),
            CustomSingleChildLayout(
              delegate: _PanelLayout(insets: insets, maxWidth: route.maxWidth, report: _rect),
              // el panel se materializa al abrirse y se deshace al cerrarse con el mismo parpadeo de holograma
              child: Opacity(
                opacity: SectionMotion.glitchOpacity(t, 5),
                child: Transform.translate(
                  offset: SectionMotion.glitchShift(t, 5, MotionEdge.bottom),
                  child: Transform.scale(scale: 0.94 + 0.06 * t, child: child),
                ),
              ),
            ),
          ],
        );
      },
      child: HackExit(
        animation: route.animation!,
        child: Material(
          key: const Key('focus-panel'),
          type: MaterialType.transparency,
          child: CyberPanel(
          active: 1,
          child: MediaQuery.removeViewInsets(
            context: context,
            removeBottom: true,
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              removeBottom: true,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (route.title != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                      child: HackText(route.title!, style: display(size: 18, color: c.ink)),
                    ),
                  Flexible(child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Builder(builder: route.builder))),
                ],
              ),
            ),
          ),
        ),
        ),
      ),
    );
  }
}

class _PanelLayout extends SingleChildLayoutDelegate {
  _PanelLayout({required this.insets, required this.maxWidth, required this.report});

  final EdgeInsets insets;
  final double maxWidth;
  final ValueNotifier<Rect> report;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final width = math.min(maxWidth, constraints.maxWidth - insets.horizontal - FocusSpace.margin * 2);
    final height = constraints.maxHeight - insets.vertical - FocusSpace.margin * 2;
    return BoxConstraints(minWidth: width, maxWidth: width, maxHeight: math.max(0, height));
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final rect = FocusSpace.place(childSize, size, insets);
    if (report.value != rect) {
      WidgetsBinding.instance.addPostFrameCallback((_) => report.value = rect);
    }
    return rect.topLeft;
  }

  @override
  bool shouldRelayout(_PanelLayout old) => old.insets != insets || old.maxWidth != maxWidth;
}

/// Un aviso para el panel focal: el texto y los botones (lo que antes era un `AlertDialog`).
class FocusDialog extends StatelessWidget {
  const FocusDialog({super.key, this.content, required this.actions});

  final Widget? content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 4, 12, 4),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (content != null) Padding(padding: const EdgeInsets.only(right: 8, bottom: 12), child: content),
        Wrap(alignment: WrapAlignment.end, spacing: 4, children: actions),
      ],
    ),
  );
}
