import 'dart:async';

import 'package:flutter/material.dart';

import '../data/favorites_store.dart';
import '../state/dock_controller.dart';
import '../state/player_controller.dart';
import '../state/system_controller.dart';
import '../state/weather_controller.dart';
import 'section_host.dart';
import 'widgets/home_grid.dart';
import 'widgets/home_player.dart';

/// La pantalla de inicio de Kyra: sobre el **fondo de pantalla** (lo pinta `AppBackdrop` para toda la app), un **tablero de 2 × 2**: la hora,
/// el clima, el estado del sistema (batería, memoria, almacenamiento) y los accesos rápidos (Wi-Fi y Bluetooth). El menú circular se abre con
/// un giro del dedo, como en cualquier sección (`SectionHost`).
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

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  late DateTime _today = _clock();
  Timer? _tick;

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
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    HomeGrid(now: _today, weather: widget.weather, system: widget.system, onNeedCity: widget.onOpenSettings),
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
        ],
      ),
    );
  }
}
