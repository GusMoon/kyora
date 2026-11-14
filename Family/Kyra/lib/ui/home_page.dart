import 'dart:async';

import 'package:flutter/material.dart';

import '../data/favorites_store.dart';
import '../state/dock_controller.dart';
import '../state/event_controller.dart';
import '../state/habit_controller.dart';
import '../state/player_controller.dart';
import '../state/reminder_controller.dart';
import '../state/system_controller.dart';
import '../state/task_controller.dart';
import '../state/weather_controller.dart';
import 'agenda_view.dart';
import 'section_host.dart';
import 'widgets/home_grid.dart';
import 'widgets/home_player.dart';

/// La pantalla de inicio de Kyra: sobre el **fondo de pantalla** (lo pinta `AppBackdrop` para toda la app), un **tablero de 2 × 2**: la hora,
/// el clima, el estado del sistema (batería, memoria, almacenamiento) y los accesos rápidos (Wi-Fi y Bluetooth). El menú circular se abre con
/// un giro del dedo, como en cualquier sección (`SectionHost`).
///
/// **Tocar la hora expande esa tesela** y ahí vive la agenda (antes era la sección «Calendario»): tareas, y deslizando, hábitos y recordatorios,
/// con el calendario del mes. Las otras tres teselas se reacomodan en una franja compacta debajo.
class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.onOpenSettings,
    this.weather,
    this.dock,
    this.system,
    this.player,
    this.favorites,
    this.now,
    this.tasks,
    this.reminders,
    this.habits,
    this.events,
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

  /// El reloj (en las pruebas, uno fijo).
  final DateTime Function()? now;

  /// Lo que muestra la agenda de la hora expandida. Sin nada de esto la hora no se puede expandir.
  final Future<TaskController>? tasks;
  final Future<ReminderController>? reminders;
  final Future<HabitController>? habits;
  final Future<EventController>? events;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  late DateTime _today = _clock();
  Timer? _tick;

  /// La hora está expandida (la agenda abierta).
  bool _agendaOpen = false;

  bool get _hasAgenda => widget.tasks != null || widget.reminders != null || widget.habits != null || widget.events != null;

  void _toggleAgenda() => setState(() => _agendaOpen = !_agendaOpen);

  void _closeAgenda() {
    if (_agendaOpen) setState(() => _agendaOpen = false);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        key: const Key('home-board'),
        fit: StackFit.expand,
        children: [
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              // en una pantalla baja, con el reproductor puesto, todo se puede desplazar
              child: LayoutBuilder(
                builder: (context, box) => SingleChildScrollView(
                  child: Column(
                    children: [
                      HomeGrid(
                        now: _today,
                        weather: widget.weather,
                        system: widget.system,
                        onNeedCity: widget.onOpenSettings,
                        // expandida, la hora ocupa la pantalla visible (menos el reproductor, que queda debajo)
                        expandedHeight: box.maxHeight,
                        expanded: _agendaOpen && _hasAgenda,
                        onToggle: _toggleAgenda,
                        agenda: _hasAgenda
                            ? AgendaView(embedded: true, tasks: widget.tasks, reminders: widget.reminders, habits: widget.habits, events: widget.events, now: widget.now, onClose: _closeAgenda)
                            : null,
                      ),
                      if (widget.player != null) ...[
                        const SizedBox(height: HomeGrid.gap),
                        HomePlayer(player: widget.player!, favorites: widget.favorites, onOpenMusic: () => SectionHost.goTo(context, 'music')),
                        const SizedBox(height: 14),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
