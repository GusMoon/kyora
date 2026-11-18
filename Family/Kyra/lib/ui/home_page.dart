import 'dart:async';

import 'package:flutter/material.dart';

import '../data/calendar_view_store.dart';
import '../state/clock_controller.dart';
import 'widgets/home_clock_panel.dart';
import '../data/favorites_store.dart';
import '../models/track.dart';
import '../state/dock_controller.dart';
import '../state/event_controller.dart';
import '../state/habit_controller.dart';
import '../state/player_controller.dart';
import '../state/reminder_controller.dart';
import '../state/system_controller.dart';
import '../state/task_controller.dart';
import '../state/weather_controller.dart';
import '../theme.dart';
import '../util/agenda.dart' show CalendarMode;
import '../util/format.dart';
import 'agenda_view.dart';
import 'section_host.dart';
import 'widgets/home_grid.dart';
import 'widgets/home_player.dart';
import 'widgets/section_motion.dart';
import 'widgets/weather_detail.dart';

/// La pantalla de inicio de Kyra: sobre el **fondo de pantalla** (lo pinta `AppBackdrop` para toda la app), un **tablero de 2 × 2**: la hora,
/// el clima, el estado del sistema (batería, memoria, almacenamiento) y los accesos rápidos (Wi-Fi y Bluetooth). El menú circular se abre con
/// un giro del dedo, como en cualquier sección (`SectionHost`).
///
/// **Tocar la hora o el clima** disuelve el tablero (y el reproductor) con el efecto de holograma de las secciones y enseña esa información
/// **a pantalla completa, sin marco**, directamente sobre el fondo: la agenda (tareas, hábitos, recordatorios y el calendario del mes) o el
/// detalle del clima. Al cerrarla (el botón de arriba o «atrás») el tablero se materializa otra vez.
class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.onOpenSettings,
    this.weather,
    this.dock,
    this.system,
    this.player,
    this.favorites,
    this.albumRequest,
    this.albumOf,
    this.now,
    this.tasks,
    this.reminders,
    this.habits,
    this.events,
    this.calendarView,
    this.alarms,
    this.stopwatch,
  });

  /// Abre la configuración (para elegir la ciudad del clima).
  final VoidCallback onOpenSettings;

  /// El clima. Sin esto el panel del clima dice que no hay.
  final WeatherController? weather;

  /// Las apps del teléfono (se vuelven a leer al abrir Inicio y al volver a la app).
  final DockController? dock;

  /// El estado del teléfono. Sin esto los paneles del sistema y de accesos dicen que no hay.
  final SystemController? system;

  /// El reproductor: si hay una canción cargada, sale debajo del tablero un reproductor a todo lo ancho. Sin esto no sale.
  final PlayerController? player;

  /// Las favoritas (el corazón del reproductor).
  final FavoritesController? favorites;

  /// Con el botón del álbum del reproductor se apunta aquí el álbum de la canción que suena (lo calcula [albumOf]) y se va a Música, que lo
  /// abre. Sin esto el botón solo lleva a Música.
  final ValueNotifier<String?>? albumRequest;
  final String Function(Track track)? albumOf;

  /// El reloj (en las pruebas, uno fijo).
  final DateTime Function()? now;

  /// Lo que muestra la agenda a pantalla completa. Sin nada de esto la hora no se puede tocar.
  final Future<TaskController>? tasks;
  final Future<ReminderController>? reminders;
  final Future<HabitController>? habits;
  final Future<EventController>? events;

  /// La vista con la que se abre el calendario (la elegida en Configuración). Sin esto, la semana.
  final CalendarViewStore? calendarView;

  /// El reloj: si hay un cronómetro en marcha o una alarma próxima, sale un panel debajo del tablero (`HomeClockPanel`). Sin esto no sale.
  final AlarmController? alarms;
  final StopwatchController? stopwatch;

  @override
  State<HomePage> createState() => _HomePageState();
}

/// Lo que ocupa la pantalla: el tablero de siempre o una de las dos vistas a pantalla completa.
enum _Focus { none, agenda, weather }

class _HomePageState extends State<HomePage> with WidgetsBindingObserver, TickerProviderStateMixin {
  late DateTime _today = _clock();
  Timer? _tick;

  /// Lo que se ve ahora a pantalla completa (nada: el tablero).
  _Focus _focus = _Focus.none;

  /// Hay una transición en marcha (se ignoran toques y «atrás» hasta que acabe).
  bool _busy = false;

  /// Mientras dura una transición, quién manda sobre los bloques (`FlyIn`) de la pantalla y si se están yendo; en reposo, nadie (valen los de
  /// la sección).
  Animation<double>? _motion;
  bool _leaving = false;

  /// Lo que sale tarda lo que un bloque en romperse; lo que entra, el cambio de sección entero.
  late final AnimationController _out = AnimationController(vsync: this, duration: SectionMotion.exitTime);
  late final AnimationController _in = AnimationController(vsync: this, duration: SectionMotion.total);
  late final Animation<double> _outTime = _out.drive(Tween(begin: 0.0, end: SectionMotion.exitTime.inMilliseconds / SectionMotion.total.inMilliseconds));

  bool get _hasAgenda => widget.tasks != null || widget.reminders != null || widget.habits != null || widget.events != null;

  /// Pasa a [to]: lo que hay se rompe y desaparece y, a continuación, se materializa lo nuevo.
  Future<void> _go(_Focus to) async {
    if (_busy || to == _focus) return;
    _busy = true;
    setState(() {
      _leaving = true;
      _motion = _outTime;
    });
    await _out.forward(from: 0);
    if (!mounted) return;
    setState(() {
      _focus = to;
      _leaving = false;
      _motion = _in;
    });
    await _in.forward(from: 0);
    if (!mounted) return;
    setState(() {
      _motion = null;
      _busy = false;
    });
  }

  void _close() => unawaited(_go(_Focus.none));

  /// El botón del álbum del reproductor: a Música, directo al álbum al que pertenece la canción que suena.
  void _openAlbumOfCurrent() {
    final track = widget.player?.current;
    final request = widget.albumRequest;
    final albumOf = widget.albumOf;
    if (track != null && request != null && albumOf != null) request.value = albumOf(track);
    SectionHost.goTo(context, 'music');
  }

  DateTime _clock() => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(widget.weather?.refresh());
    unawaited(widget.dock?.refresh());
    _scheduleTick();
  }

  @override
  void dispose() {
    _tick?.cancel();
    _out.dispose();
    _in.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// La hora se actualiza justo al cambiar el minuto: un solo aviso por minuto, sin nada corriendo entre medias.
  void _scheduleTick() {
    _tick?.cancel();
    _tick = Timer(Duration(seconds: 60 - _clock().second), () {
      if (!mounted) return;
      setState(() => _today = _clock());
      _scheduleTick();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // al volver a la app pudo cambiar la hora, el clima, las apps instaladas o el Wi-Fi y el Bluetooth
    if (state == AppLifecycleState.resumed) {
      setState(() => _today = _clock());
      _scheduleTick();
      unawaited(widget.weather?.refresh());
      unawaited(widget.dock?.refresh());
      unawaited(widget.system?.refresh());
      // lo que cambió en otros dispositivos (el calendario) mientras la app estaba en segundo plano
      unawaited(widget.tasks?.then((c) => c.sync()));
      unawaited(widget.habits?.then((c) => c.sync()));
      unawaited(widget.reminders?.then((c) => c.sync()));
      unawaited(widget.events?.then((c) => c.sync()));
    }
  }

  /// El tablero: la cuadrícula de 2 × 2 y, debajo, el reproductor.
  Widget _board() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
        // en una pantalla baja, con el reproductor puesto, todo se puede desplazar
        child: SingleChildScrollView(
          child: Column(
            children: [
              HomeGrid(
                now: _today,
                weather: widget.weather,
                system: widget.system,
                onNeedCity: widget.onOpenSettings,
                onOpenTime: _hasAgenda ? () => unawaited(_go(_Focus.agenda)) : null,
                onOpenWeather: widget.weather == null ? null : () => unawaited(_go(_Focus.weather)),
              ),
              if (widget.alarms != null && widget.stopwatch != null)
                HomeClockPanel(alarms: widget.alarms!, stopwatch: widget.stopwatch!, now: widget.now, onOpen: () => SectionHost.goTo(context, 'clock')),
              if (widget.player != null) ...[
                const SizedBox(height: HomeGrid.gap),
                HomePlayer(player: widget.player!, favorites: widget.favorites, onOpenMusic: _openAlbumOfCurrent),
                const SizedBox(height: 14),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Una vista a pantalla completa, sin marco: una barra fina con el código, algo a la derecha y (si [closable]) el botón de cerrar, y debajo [child].
  Widget _full({required String code, Widget? trailing, bool closable = true, bool flush = false, required Widget child}) {
    final c = context.colors;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(flush ? 0 : 12, 6, flush ? 0 : 12, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FlyIn(
              edge: MotionEdge.top,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: flush ? 12 : 0),
                child: SizedBox(
                height: 40,
                child: Row(
                  children: [
                    const SizedBox(width: 4),
                    Expanded(child: Text(code, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: monoFont, fontSize: 15, letterSpacing: 1.2, color: c.accent))),
                    if (trailing != null) ...[const SizedBox(width: 8), trailing],
                    if (closable)
                      IconButton(
                        key: const Key('home-time-close'),
                        tooltip: 'Cerrar',
                        visualDensity: VisualDensity.compact,
                        onPressed: _close,
                        icon: Icon(Icons.expand_less_rounded, color: c.ink),
                      )
                    else
                      const SizedBox(width: 4),
                  ],
                ),
              ),
              ),
            ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }

  Widget _agenda() {
    final c = context.colors;
    return _full(
      code: 'SYS::TIME',
      closable: false, // se cierra con «atrás»
      flush: true, // la agenda va de borde a borde
      trailing: Text(clockText(_today), key: const Key('home-time-small'), style: TextStyle(fontFamily: monoFont, fontSize: 15, color: c.ink)),
      // «atrás» lo atiende la agenda (que llama a `_close`)
      child: AgendaView(embedded: true, tasks: widget.tasks, reminders: widget.reminders, habits: widget.habits, events: widget.events, now: widget.now, onClose: _close, initialMode: widget.calendarView?.mode ?? CalendarMode.week),
    );
  }

  Widget _weather(WeatherController weather) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: _full(
        code: 'ENV::WEATHER',
        child: FlyIn(
          edge: MotionEdge.bottom,
          order: 1,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520), child: WeatherDetail(controller: weather)),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final outer = SectionMotion.maybeOf(context);
    final motion = _motion;
    // siempre un `SectionMotion` (aunque en reposo repita el de la sección), para que al empezar o acabar una transición nada pierda su estado
    return SectionMotion(
      animation: motion ?? outer?.animation ?? kAlwaysCompleteAnimation,
      leaving: motion != null ? _leaving : (outer?.leaving ?? false),
      moving: motion != null || (outer?.moving ?? false),
      child: IgnorePointer(
        ignoring: _busy,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            key: const Key('home-board'),
            fit: StackFit.expand,
            children: [
              switch (_focus) {
                _Focus.none => _board(),
                _Focus.agenda => _agenda(),
                _Focus.weather => widget.weather == null ? _board() : _weather(widget.weather!),
              },
            ],
          ),
        ),
      ),
    );
  }
}
