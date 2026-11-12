import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/installed_apps.dart';
import '../data/nav_hint_store.dart';
import '../state/dock_controller.dart';
import '../theme.dart';
import 'widgets/apps_arch.dart';
import 'widgets/app_section.dart';
import 'widgets/cut_border.dart';
import 'widgets/focus_space.dart';
import 'widgets/radial_menu.dart';
import 'widgets/section_motion.dart';
import 'widgets/swirl_detector.dart';
import 'widgets/wave_sweep.dart';

/// Las secciones de la app, **una sola a la vez**, a pantalla completa y sin barra de pestañas. Se cambia de sección con el **menú circular**,
/// que se abre **dibujando un círculo con el dedo** en cualquier pantalla (sin mantener ni tocar): hacia la **izquierda** sale el aro de las
/// **aplicaciones** (las 8 elegidas) y hacia la **derecha** el de las **funciones** (las secciones de Kyra y la Configuración), con un efecto de
/// holograma. Con el aro abierto, tocar una opción la abre; girarlo cambia entre aplicaciones y funciones; y tocar el centro (en las aplicaciones)
/// o deslizar hacia arriba desde él abre **todas las apps** a pantalla completa, repartidas por los bordes del teléfono en forma de «n»
/// (esquinas redondeadas, sin punta) y con el abecedario en columna en el centro; entran con el efecto de holograma al paso de una **ola**
/// que barre la pantalla de arriba a la izquierda a abajo a la derecha. Tocar fuera del aro o «atrás» lo cierran.
///
/// Al cambiar, los bloques de la sección actual se van y los de la nueva aparecen (`SectionMotion`, `FlyIn`); cuando termina, la de antes
/// **se destruye** (no queda nada en segundo plano). Las páginas que se abren encima (un álbum, una tarea) también van **dentro de la
/// pantalla**, en su propio navegador; mientras hay una abierta el menú no sale y «atrás» la cierra primero.
class SectionHost extends StatefulWidget {
  const SectionHost({
    super.key,
    required this.sections,
    this.actions = const [],
    this.initial = 0,
    this.hint,
    this.canExit,
    this.dock,
  });

  final List<AppSection> sections;

  /// Opciones del menú circular que no son una sección (van detrás de las secciones): por ejemplo, abrir la Configuración.
  final List<NavAction> actions;

  /// La sección con la que se arranca (y a la que vuelve «atrás»).
  final int initial;

  /// Si ya se enseñó cómo abrir el menú: mientras no, Inicio muestra una pista. Sin esto no hay pista.
  final NavHintStore? hint;

  /// Si «atrás» en la sección de inicio puede cerrar la app. Siendo la pantalla de inicio del teléfono no debe (se volvería a abrir sola).
  /// Sin esto, sí cierra.
  final bool Function()? canExit;

  /// Las apps del teléfono para el modo «aplicaciones» del menú (las 8 elegidas) y el panel de todas. Sin esto el aro solo tiene funciones.
  final DockController? dock;

  /// Lo que hay que girar el aro (rad) para pasar de funciones a aplicaciones o al revés.
  static const turnToSwitch = 0.7;

  /// Lo que hay que deslizar hacia arriba desde el centro para abrir todas las apps.
  static const swipeUp = 40.0;

  /// La clave de la pantalla del aparato (para las pruebas: ahí se mantiene el dedo).
  static const screenKey = Key('device-screen');

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
  const _Menu({
    required this.geometry,
    required this.origin,
    this.selected,
    this.mode = LauncherMode.functions,
    this.turn = 0,
  });

  final RadialGeometry geometry;
  final Offset origin;
  final int? selected;
  final LauncherMode mode;
  final double turn;

  _Menu copy({
    int? selected,
    bool clearSelected = false,
    LauncherMode? mode,
    double? turn,
    RadialGeometry? geometry,
  }) => _Menu(
    geometry: geometry ?? this.geometry,
    origin: origin,
    selected: clearSelected ? null : (selected ?? this.selected),
    mode: mode ?? this.mode,
    turn: turn ?? this.turn,
  );
}

class _SectionHostState extends State<SectionHost>
    with TickerProviderStateMixin {
  late final AnimationController _anim;
  late final AnimationController _opening;

  /// Las vueltas del reactor mientras el menú está abierto.
  late final AnimationController _spin;

  /// Las opciones nuevas del aro al pasar de funciones a aplicaciones (o al revés), y el giro que se asienta solo al soltar el dedo.
  late final AnimationController _swap;
  late final AnimationController _settle;
  double _settleFrom = 0;

  /// El contenido a la vista (1) o quitado por todas las apps (0): aparece y se deshace con parpadeo, no de golpe.
  late final AnimationController _reveal;

  late int _index = widget.initial;

  /// La sección que se está yendo (se destruye al terminar).
  int? _leavingIndex;

  final _menu = ValueNotifier<_Menu?>(null);

  /// Todas las apps a pantalla completa (la «n» con el abecedario) está abierto, y se está cerrando (las apps se van antes de quitarlo).
  bool _archOpen = false;
  bool _archClosing = false;

  /// El menú se está cerrando (el reactor se deshace antes de quitarlo): ya no recibe toques.
  bool _menuClosing = false;

  late bool _showHint = widget.hint != null && !widget.hint!.seen;

  /// El navegador de dentro de la pantalla y si tiene alguna página abierta encima de las secciones.
  final _navigator = GlobalKey<NavigatorState>();
  late final _observer = _CoverObserver(_onCovered);
  bool _covered = false;

  /// La caja de la pantalla (ahí se abre el menú).
  final _screen = GlobalKey();

  List<RadialEntry> get _functions => [
    for (final s in widget.sections)
      RadialEntry(id: s.id, icon: s.icon, label: s.label, glyph: s.glyph),
    for (final a in widget.actions)
      RadialEntry(id: a.id, icon: a.icon, label: a.label, glyph: a.glyph),
  ];

  /// Las 8 apps elegidas (sin las ranuras vacías).
  List<InstalledApp> get _apps => [
    for (final app in widget.dock?.slots ?? const <InstalledApp?>[]) ?app,
  ];

  List<RadialEntry> _entriesFor(LauncherMode mode) =>
      mode == LauncherMode.functions
      ? _functions
      : [
          for (final app in _apps)
            RadialEntry(
              id: 'app-${app.package}',
              icon: Icons.apps_rounded,
              label: app.label,
              image: app.icon,
            ),
        ];

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: SectionMotion.total,
      value: 1,
    )..addStatusListener(_onStatus);
    _opening = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _spin = AnimationController(vsync: this, duration: ReactorSpin.period);
    _swap = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
      value: 1,
    );
    _settle = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    )..addListener(_onSettle);
    // al irse el contenido, la ola tarda lo mismo que la entrada de las apps (van a la par); al volver, lo que tarda la salida de las apps
    _reveal = AnimationController(
      vsync: this,
      duration: AppsArch.leaving,
      reverseDuration: AppsArch.entering,
      value: 1,
    );
    _menu.addListener(_menuChanged);
  }

  @override
  void dispose() {
    _anim.dispose();
    _opening.dispose();
    _menu.removeListener(_menuChanged);
    _spin.dispose();
    _swap.dispose();
    _settle.dispose();
    _reveal.dispose();
    _menu.dispose();
    super.dispose();
  }

  /// El giro del aro vuelve a su sitio con suavidad al soltar el dedo (no de golpe).
  void _onSettle() {
    final menu = _menu.value;
    if (menu == null) return;
    _menu.value = menu.copy(
      turn: _settleFrom * (1 - Curves.easeOutCubic.transform(_settle.value)),
    );
  }

  /// Cierra el menú **con animación**: el reactor se deshace (parpadea y se apaga) y el hueco se cierra, y solo entonces se quita.
  void _dismissMenu() {
    if (_menu.value == null || _menuClosing) return;
    _settle.stop();
    setState(() => _menuClosing = true);
    unawaited(
      _opening.reverse().whenComplete(() {
        _menuClosing = false;
        if (!mounted) return;
        _menu.value = null;
        setState(() {});
      }),
    );
  }

  /// Cierra todas las apps con animación: se van por donde entraron y después vuelve el contenido.
  void _closeArch() {
    if (!_archOpen || _archClosing) return;
    setState(() => _archClosing = true);
  }

  void _archClosed() {
    if (!mounted) return;
    setState(() {
      _archOpen = false;
      _archClosing = false;
    });
    unawaited(_reveal.forward());
  }

  /// El reactor gira mientras haya menú abierto y se para al cerrarlo.
  void _menuChanged() {
    if (_menu.value == null) {
      _spin.stop();
    } else if (ReactorSpin.enabled && !_spin.isAnimating) {
      unawaited(_spin.repeat());
    }
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && _leavingIndex != null && mounted) {
      setState(() => _leavingIndex = null);
    }
  }

  void _onCovered() {
    final covered = _navigator.currentState?.canPop() ?? false;
    if (covered != _covered && mounted) setState(() => _covered = covered);
  }

  void _goToId(String id) {
    final index = widget.sections.indexWhere((section) => section.id == id);
    if (index >= 0) _go(index);
  }

  void _go(int i) {
    if (i == _index || i < 0 || i >= widget.sections.length) return;
    FocusManager.instance.primaryFocus?.unfocus();
    // lo que hubiera abierto encima se cierra: la sección nueva se ve entera
    _navigator.currentState?.popUntil((route) => route.isFirst);
    setState(() {
      // si todavía se estaba cambiando, lo anterior se salta al final (la que se iba se destruye ya)
      _leavingIndex = _index;
      _index = i;
    });
    unawaited(_anim.forward(from: 0));
  }

  /// «Atrás»: primero lo de dentro de la pantalla (una página abierta, o lo que la sección quiera hacer antes, como volver de un modo);
  /// después, volver a la sección de inicio; y desde ella, salir de la app.
  Future<void> _back() async {
    if (_archOpen) {
      _closeArch();
      return;
    }
    if (_menu.value != null) {
      _dismissMenu();
      return;
    }
    final handled =
        await (_navigator.currentState?.maybePop() ?? Future.value(false));
    if (handled || !mounted) return;
    if (_index != widget.initial) {
      _go(widget.initial);
    } else if (widget.canExit?.call() ?? true) {
      await SystemNavigator.pop();
    }
  }

  // ---- el menú circular ----

  RenderBox? get _screenBox =>
      _screen.currentContext?.findRenderObject() as RenderBox?;

  _Menu? _newMenu(Offset global, {required LauncherMode mode}) {
    final box = _screenBox;
    if (box == null || _covered) return null;
    final local = box.globalToLocal(global);
    // el aro se queda fuera de la barra de estado y de la de gestos
    final padding = MediaQuery.paddingOf(context);
    final bounds = Rect.fromLTRB(
      padding.left,
      padding.top,
      box.size.width - padding.right,
      box.size.height - padding.bottom,
    );
    final geometry = RadialGeometry(
      count: _entriesFor(mode).length,
      bounds: bounds,
      touch: local,
    );
    FocusSpace.last = box.localToGlobal(geometry.center);
    return _Menu(geometry: geometry, origin: local, mode: mode);
  }

  void _shown(_Menu? menu) {
    if (menu == null) return;
    _settle.stop();
    _swap.value = 1;
    _menu.value = menu;
    unawaited(_opening.forward(from: 0));
    if (_showHint) {
      setState(() => _showHint = false);
      unawaited(widget.hint?.markSeen());
    }
  }

  /// Un giro del dedo: el aro se abre donde se dibujó el círculo. A la **izquierda**, las aplicaciones; a la **derecha**, las funciones.
  void _swirl(Swirl swirl) {
    if (_covered || _archOpen || _menu.value != null || _menuClosing) return;
    unawaited(HapticFeedback.mediumImpact().catchError((Object _) {}));
    _shown(
      _newMenu(
        swirl.center,
        mode: swirl.clockwise ? LauncherMode.functions : LauncherMode.apps,
      ),
    );
  }

  /// Hace lo de la opción `i` del aro en ese modo: ir a la sección, la acción o abrir la app.
  void _run(LauncherMode mode, int i) {
    if (mode == LauncherMode.apps) {
      final apps = _apps;
      if (i < apps.length) unawaited(widget.dock?.launch(apps[i].package));
      return;
    }
    final sections = widget.sections.length;
    if (i < sections) {
      _go(i);
    } else if (i - sections < widget.actions.length) {
      final context = _navigator.currentContext ?? this.context;
      widget.actions[i - sections].run(context);
    }
  }

  // con el aro abierto: se maneja tocando, girando y deslizando

  Offset? _panFrom;
  Offset? _panLast;
  bool _panInHub = false;

  void _tapUp(Offset local) {
    final menu = _menu.value;
    if (menu == null) return;
    final i = menu.geometry.hit(local);
    if (i != null) {
      // la opción tocada (con el aro girado, se busca por su posición)
      final hit = _hitTurned(menu, local) ?? i;
      _dismissMenu();
      _run(menu.mode, hit);
    } else if (menu.geometry.inHub(local)) {
      if (menu.mode == LauncherMode.apps) _openAllApps();
    } else if (!menu.geometry.contains(local)) {
      _dismissMenu(); // fuera del aro: se cierra
    }
  }

  /// La opción cuyo icono está más cerca del toque, con el giro que lleve el aro.
  int? _hitTurned(_Menu menu, Offset local) {
    final count = _entriesFor(menu.mode).length;
    int? best;
    var bestDistance = RadialGeometry.item;
    for (var i = 0; i < count; i++) {
      final d = (menu.geometry.positionOf(i, menu.turn) - local).distance;
      if (d < bestDistance) {
        bestDistance = d;
        best = i;
      }
    }
    return best;
  }

  void _panStart(Offset local) {
    final menu = _menu.value;
    if (menu == null) return;
    _settle.stop();
    _panFrom = local;
    _panLast = local;
    _panInHub = menu.geometry.inHub(local);
  }

  void _panUpdate(Offset local) {
    final menu = _menu.value;
    final last = _panLast;
    if (menu == null || last == null) return;
    _panLast = local;
    if (_panInHub) return; // desde el centro: es un deslizamiento, no un giro
    final turn = menu.turn + menu.geometry.turnBetween(last, local);
    final next = turn > SectionHost.turnToSwitch
        ? LauncherMode.functions
        : (turn < -SectionHost.turnToSwitch ? LauncherMode.apps : null);
    if (next != null && next != menu.mode) {
      // cambia lo que enseña el aro: el giro continúa donde iba (nada salta), el hueco y el reactor se quedan como están, y solo las
      // opciones nuevas se materializan (parpadeando) en su sitio; al soltar el dedo el aro se asienta solo
      unawaited(HapticFeedback.selectionClick().catchError((Object _) {}));
      final geometry = RadialGeometry(
        count: _entriesFor(next).length,
        bounds: menu.geometry.bounds,
        touch: menu.geometry.touch,
      );
      _menu.value = menu.copy(
        mode: next,
        turn: turn.clamp(
          -SectionHost.turnToSwitch * 1.4,
          SectionHost.turnToSwitch * 1.4,
        ),
        geometry: geometry,
        clearSelected: true,
      );
      unawaited(_swap.forward(from: 0));
    } else {
      _menu.value = menu.copy(
        turn: turn.clamp(
          -SectionHost.turnToSwitch * 1.4,
          SectionHost.turnToSwitch * 1.4,
        ),
      );
    }
  }

  void _panEnd() {
    final menu = _menu.value;
    final from = _panFrom, last = _panLast;
    _panFrom = null;
    _panLast = null;
    if (menu == null) return;
    if (_panInHub &&
        from != null &&
        last != null &&
        from.dy - last.dy > SectionHost.swipeUp) {
      _openAllApps();
      return;
    }
    if (menu.turn != 0) {
      _settleFrom = menu.turn;
      unawaited(_settle.forward(from: 0));
    }
  }

  /// Todas las apps a pantalla completa: por los bordes, en forma de «n», con el abecedario en columna en el centro.
  void _openAllApps() {
    if (widget.dock == null) return;
    _dismissMenu();
    setState(() {
      _archOpen = true;
      _archClosing = false;
    });
    unawaited(
      _reveal.reverse(),
    ); // el contenido se deshace mientras entran las apps
  }

  Widget _layer(int i, {required bool leaving}) {
    final moving = _leavingIndex != null;
    // siempre la misma estructura: la sección conserva su estado al pasar de «la que llega» a «la que se va»
    return KeyedSubtree(
      key: ValueKey(widget.sections[i].id),
      // la que se va no recibe toques; la que llega sí, desde el primer momento
      child: IgnorePointer(
        ignoring: moving && leaving,
        child: SectionMotion(
          animation: _anim,
          leaving: leaving,
          moving: moving,
          // cada sección con su `ScaffoldMessenger`, para que sus avisos salgan solo en su pantalla
          child: ScaffoldMessenger(
            child: Builder(builder: widget.sections[i].builder),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final sections = Stack(
      fit: StackFit.expand,
      children: [
        // la que se va (debajo) y la que llega (encima)
        if (_leavingIndex != null) _layer(_leavingIndex!, leaving: true),
        _layer(_index, leaving: false),
      ],
    );
    return PopScope(
      // «atrás» lo decide `_back`: la app solo se cierra desde la sección de inicio y sin nada abierto encima
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_back());
      },
      // el menú y la pista van fuera de los `Scaffold`: sin este `Material` su texto no heredaría la letra del tema
      child: Material(
        type: MaterialType.transparency,
        child: DefaultTextStyle.merge(
          style: TextStyle(fontFamily: screenFont, color: c.ink),
          child: KeyedSubtree(
            key: SectionHost.screenKey,
            child: SwirlDetector(
              enabled: !_covered && !_archOpen,
              onSwirl: _swirl,
              child: Stack(
                key: _screen,
                fit: StackFit.expand,
                children: [
                  // el contenido: con el menú abierto se le corta un hueco del tamaño del reactor y baja de opacidad; con todas las apps
                  // abiertas se quita (sigue vivo, solo no se ve)
                  ValueListenableBuilder<_Menu?>(
                    valueListenable: _menu,
                    child: Navigator(
                      key: _navigator,
                      observers: [_observer],
                      pages: [
                        MaterialPage<void>(
                          key: const ValueKey('sections'),
                          child: sections,
                        ),
                      ],
                      onDidRemovePage: (_) {},
                    ),
                    builder: (context, menu, child) => RadialCut(
                      center: menu?.geometry.center,
                      opening: _opening,
                      reveal: _reveal,
                      child: child!,
                    ),
                  ),
                  if (_showHint &&
                      _index == widget.initial &&
                      !_covered &&
                      !_archOpen)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: MediaQuery.paddingOf(context).bottom + 20,
                      child: IgnorePointer(
                        child: Center(child: NavHintPill(ink: c.ink)),
                      ),
                    ),
                  ValueListenableBuilder<_Menu?>(
                    valueListenable: _menu,
                    builder: (context, menu, _) => menu == null
                        ? const SizedBox.shrink()
                        : Stack(
                            fit: StackFit.expand,
                            children: [
                              RadialMenuView(
                                geometry: menu.geometry,
                                entries: _entriesFor(menu.mode),
                                selected: menu.selected,
                                currentId: widget.sections[_index].id,
                                opening: _opening,
                                spin: _spin,
                                swap: _swap,
                                mode: menu.mode,
                                turn: menu.turn,
                              ),
                              IgnorePointer(
                                ignoring: _menuClosing, // mientras se deshace, ya no recibe toques
                                child: GestureDetector(
                                  key: const Key('radial-touch'),
                                  behavior: HitTestBehavior.opaque,
                                  onTapUp: (d) => _tapUp(d.localPosition),
                                  onPanStart: (d) => _panStart(d.localPosition),
                                  onPanUpdate: (d) =>
                                      _panUpdate(d.localPosition),
                                  onPanEnd: (_) => _panEnd(),
                                  onPanCancel: _panEnd,
                                ),
                              ),
                            ],
                          ),
                  ),
                  // todas las apps, por los bordes en forma de «n»
                  if (_archOpen && widget.dock != null)
                    Positioned.fill(
                      child: AppsArch(
                        key: const Key('all-apps'),
                        apps: widget.dock!.alphabetical,
                        closing: _archClosing,
                        onClosed: _archClosed,
                        onClose: _closeArch,
                        onOpen: (app) {
                          _closeArch();
                          unawaited(widget.dock?.launch(app.package));
                        },
                      ),
                    ),
                  // la ola que cruza la pantalla mientras el contenido se va (y las apps llegan) o vuelve: del borde de arriba a la izquierda al de
                  // abajo a la derecha. Al cerrarse las apps la dibuja `AppsArch`
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedBuilder(
                        animation: _reveal,
                        builder: (context, _) {
                          final v = _reveal.value;
                          if (v <= 0 || v >= 1) return const SizedBox.shrink();
                          return CustomPaint(
                            key: const Key('wave-sweep'),
                            painter: WavePainter(
                              t: WaveSweep.timeFor(_reveal),
                              accent: c.accent,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// La pista de cómo se navega: una píldora oscura con el texto.
class NavHintPill extends StatelessWidget {
  const NavHintPill({super.key, required this.ink});

  static const text = 'dibuja un círculo con el dedo para abrir el menú';

  final Color ink;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('nav-hint'),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    decoration: ShapeDecoration(
      color: context.colors.plate,
      shape: CutBorder(side: BorderSide(color: context.colors.edge)),
    ),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: lcdStatus(color: ink),
    ),
  );
}

/// Avisa cuando se abre o se cierra una página encima de las secciones.
class _CoverObserver extends NavigatorObserver {
  _CoverObserver(this.onChange);

  final VoidCallback onChange;

  void _later() =>
      WidgetsBinding.instance.addPostFrameCallback((_) => onChange());

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _later();

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _later();

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _later();

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _later();
}
