import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/nav_hint_store.dart';
import '../theme.dart';
import 'widgets/app_backdrop.dart';
import 'widgets/app_section.dart';
import 'widgets/radial_menu.dart';
import 'widgets/section_motion.dart';

/// Las secciones de la app, **una sola a la vez**. Se cambia de sección con el **menú circular**: se mantiene el dedo un
/// momento en cualquier punto de la pantalla, se despliegan las opciones alrededor, se desliza hacia una y se suelta.
///
/// Al cambiar, los bloques de la sección actual salen cada uno por su borde y, con una espera mínima, los de la nueva entran por el suyo
/// (`SectionMotion`, `FlyIn`); cuando termina, la de antes **se destruye** (no queda nada en segundo plano). Sobre los bloques nada se anima
/// con opacidad: el cristal de las tarjetas no podría difuminar lo que tiene detrás.
///
/// El fondo no se mueve, pero cambia a la vez que los bloques: la sección inicial lleva la foto nítida arriba y las demás, el efecto completo
/// (todo borroso y más oscuro). Esa capa va debajo de las secciones, así que su fundido no afecta al cristal.
class SectionHost extends StatefulWidget {
  const SectionHost({super.key, required this.sections, this.actions = const [], this.initial = 0, this.hint});

  final List<AppSection> sections;

  /// Opciones del menú circular que no son una sección (van detrás de las secciones): por ejemplo, abrir la Configuración.
  final List<NavAction> actions;

  /// La sección con la que se arranca (y a la que vuelve «atrás»).
  final int initial;

  /// Si ya se enseñó cómo abrir el menú: mientras no, Inicio muestra una pista. Sin esto no hay pista.
  final NavHintStore? hint;

  /// Cuánto hay que mantener el dedo para que se abra el menú: lo mismo que una pulsación larga del sistema, así que las pulsaciones largas
  /// de dentro de las pantallas (un mensaje del chat, una canción) ganan sobre el menú en su sitio.
  static const holdTime = kLongPressTimeout;

  /// Salta a la sección con ese `id` (desde cualquier pantalla de dentro del `SectionHost`). No hace nada si no existe.
  static void goTo(BuildContext context, String id) {
    final state = context.findAncestorStateOfType<_SectionHostState>();
    state?._goToId(id);
  }

  @override
  State<SectionHost> createState() => _SectionHostState();
}

/// Lo que se ve del menú circular mientras está abierto.
class _Menu {
  const _Menu({required this.geometry, required this.origin, this.selected});

  final RadialGeometry geometry;
  final Offset origin;
  final int? selected;

  _Menu withSelected(int? value) => _Menu(geometry: geometry, origin: origin, selected: value);
}

class _SectionHostState extends State<SectionHost> with TickerProviderStateMixin {
  late final AnimationController _anim;
  late final AnimationController _opening;

  /// Cuánto se ve el efecto completo del fondo: 0 en la sección inicial, 1 en las demás.
  late final AnimationController _depth;

  late int _index = widget.initial;

  /// La sección que se está yendo (se destruye al terminar).
  int? _leavingIndex;

  final _menu = ValueNotifier<_Menu?>(null);
  late bool _showHint = widget.hint != null && !widget.hint!.seen;

  List<RadialEntry> get _entries => [
        for (final s in widget.sections) RadialEntry(id: s.id, icon: s.icon, label: s.label),
        for (final a in widget.actions) RadialEntry(id: a.id, icon: a.icon, label: a.label),
      ];

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: SectionMotion.total, value: 1)..addStatusListener(_onStatus);
    _opening = AnimationController(vsync: this, duration: const Duration(milliseconds: 260));
    _depth = AnimationController(vsync: this, duration: SectionMotion.total);
  }

  @override
  void dispose() {
    _anim.dispose();
    _opening.dispose();
    _depth.dispose();
    _menu.dispose();
    super.dispose();
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && _leavingIndex != null && mounted) setState(() => _leavingIndex = null);
  }

  void _goToId(String id) {
    final index = widget.sections.indexWhere((section) => section.id == id);
    if (index >= 0) _go(index);
  }

  void _go(int i) {
    if (i == _index || i < 0 || i >= widget.sections.length) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      // si todavía se estaba cambiando, lo anterior se salta al final (la que se iba se destruye ya)
      _leavingIndex = _index;
      _index = i;
    });
    unawaited(_anim.forward(from: 0));
    unawaited(_depth.animateTo(i == widget.initial ? 0 : 1, curve: Curves.easeInOut));
  }

  // ---- el menú circular ----

  void _open(Offset global) {
    final box = context.findRenderObject() as RenderBox;
    final local = box.globalToLocal(global);
    final padding = MediaQuery.paddingOf(context);
    final bounds = Rect.fromLTRB(padding.left, padding.top, box.size.width - padding.right, box.size.height - padding.bottom);
    _menu.value = _Menu(geometry: RadialGeometry(count: _entries.length, bounds: bounds, touch: local), origin: local);
    _buzz(HapticFeedback.mediumImpact);
    unawaited(_opening.forward(from: 0));
    if (_showHint) {
      setState(() => _showHint = false);
      unawaited(widget.hint?.markSeen());
    }
  }

  void _move(Offset global) {
    final menu = _menu.value;
    if (menu == null) return;
    final local = (context.findRenderObject() as RenderBox).globalToLocal(global);
    // hasta que el dedo no se ha movido un poco, no se elige nada
    final picked = (local - menu.origin).distance < 14 ? null : menu.geometry.pick(local);
    if (picked != menu.selected) {
      if (picked != null) _buzz(HapticFeedback.selectionClick);
      _menu.value = menu.withSelected(picked);
    }
  }

  void _end() {
    final menu = _menu.value;
    if (menu == null) return;
    _menu.value = null;
    final picked = menu.selected;
    if (picked == null) return; // soltar en el centro cancela
    final sections = widget.sections.length;
    if (picked < sections) {
      _go(picked);
    } else {
      widget.actions[picked - sections].run(context);
    }
  }

  void _cancel() => _menu.value = null;

  static void _buzz(Future<void> Function() haptic) {
    // sin vibrador (o en las pruebas) no pasa nada
    unawaited(haptic().catchError((Object _) {}));
  }

  Widget _layer(int i, {required bool leaving}) {
    final moving = _leavingIndex != null;
    // siempre la misma estructura: la sección conserva su estado al pasar de «la que llega» a «la que se va»
    return KeyedSubtree(
      key: ValueKey(widget.sections[i].id),
      // mientras sus bloques se mueven no recibe toques
      child: IgnorePointer(
        ignoring: moving,
        child: SectionMotion(
          animation: _anim,
          leaving: leaving,
          moving: moving,
          // cada sección con su `ScaffoldMessenger`, para que sus avisos salgan solo en su pantalla
          child: ScaffoldMessenger(child: Builder(builder: widget.sections[i].builder)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final gestures = <Type, GestureRecognizerFactory>{
      LongPressGestureRecognizer: GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
        () => LongPressGestureRecognizer(duration: SectionHost.holdTime),
        (recognizer) => recognizer
          ..onLongPressStart = ((details) => _open(details.globalPosition))
          ..onLongPressMoveUpdate = ((details) => _move(details.globalPosition))
          ..onLongPressEnd = ((_) => _end())
          ..onLongPressCancel = _cancel,
      ),
    };
    return PopScope(
      // «atrás» vuelve a la sección de inicio antes de salir de la app
      canPop: _index == widget.initial,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _go(widget.initial);
      },
      child: RawGestureDetector(
        behavior: HitTestBehavior.translucent,
        gestures: gestures,
        child: Stack(
          fit: StackFit.expand,
          children: [
            FadeTransition(
              key: const Key('backdrop-depth'),
              opacity: _depth,
              child: BackdropLayers(wallpaper: BackdropScope.maybeOf(context)?.wallpaper, full: true),
            ),
            // la que se va (debajo) y la que llega (encima)
            if (_leavingIndex != null) _layer(_leavingIndex!, leaving: true),
            _layer(_index, leaving: false),
            if (_showHint && _index == widget.initial)
              Positioned(
                left: 0,
                right: 0,
                bottom: MediaQuery.paddingOf(context).bottom + 5,
                child: IgnorePointer(
                  child: Text('Mantén el dedo para navegar', key: const Key('nav-hint'), textAlign: TextAlign.center, style: TextStyle(color: c.dim, fontSize: 13, letterSpacing: 0.2)),
                ),
              ),
            ValueListenableBuilder<_Menu?>(
              valueListenable: _menu,
              builder: (context, menu, _) => menu == null
                  ? const SizedBox.shrink()
                  : RadialMenuView(geometry: menu.geometry, entries: _entries, selected: menu.selected, currentId: widget.sections[_index].id, opening: _opening),
            ),
          ],
        ),
      ),
    );
  }
}
