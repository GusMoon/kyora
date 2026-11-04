import 'dart:async';

import 'package:flutter/material.dart';

import '../models/task.dart';
import '../state/task_controller.dart';
import '../state/weather_controller.dart';
import '../theme.dart';
import '../util/format.dart';
import 'section_host.dart';
import 'widgets/glass_card.dart';
import 'widgets/notched_card.dart';
import 'widgets/section_motion.dart';

/// Cómo se llama a la persona en el saludo de Inicio.
const homeName = 'Señor Marrufo';

/// La pantalla de inicio de Kyra. Arriba: la fecha, el saludo con el nombre y los días de la semana con el de hoy remarcado. Abajo del
/// todo, una tarjeta de cristal con las tareas y, en la muesca de su esquina, el clima. El fondo (la foto nítida arriba y el efecto
/// ganando hacia abajo) es el de toda la app: lo pone `AppBackdrop`.
class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.onOpenSettings, this.tasks, this.weather, this.now});

  /// Abre la configuración.
  final VoidCallback onOpenSettings;

  /// Las tareas (se abren en segundo plano). Sin esto no sale la tarjeta de tareas.
  final Future<TaskController>? tasks;

  /// El clima. Sin esto no sale el clima.
  final WeatherController? weather;

  /// El reloj (en las pruebas, uno fijo).
  final DateTime Function()? now;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  late DateTime _today = _clock();

  DateTime _clock() => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(widget.weather?.refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // al volver a la app puede haber cambiado el día, la hora del saludo y el clima
    if (state == AppLifecycleState.resumed) {
      setState(() => _today = _clock());
      unawaited(widget.weather?.refresh());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // un grupo por pantalla: sus tarjetas de cristal comparten una sola captura del fondo (menos trabajo para la GPU)
      body: BackdropGroup(
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: () async => widget.weather?.refresh(force: true),
            child: CustomScrollView(
              // al cambiar de sección los bloques llegan hasta el borde de la pantalla, sin cortarse en el de la lista
              clipBehavior: SectionMotion.movingOf(context) ? Clip.none : Clip.hardEdge,
              physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
              slivers: [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Header(today: _today, onOpenSettings: widget.onOpenSettings),
                        const Spacer(),
                        if (widget.tasks != null)
                          FlyIn(edge: MotionEdge.bottom, order: 2, child: _TasksCard(future: widget.tasks!, weather: widget.weather, onNeedCity: widget.onOpenSettings))
                        else if (widget.weather != null)
                          FlyIn(
                            edge: MotionEdge.bottom,
                            order: 2,
                            child: SizedBox(height: 170, child: _WeatherTile(controller: widget.weather!, onNeedCity: widget.onOpenSettings, corners: BorderRadius.circular(NotchShape.radius))),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Arriba: la fecha, el saludo y los días de la semana, con el botón de configuración a la derecha.
class _Header extends StatelessWidget {
  const _Header({required this.today, required this.onOpenSettings});

  final DateTime today;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: FlyIn(
            edge: MotionEdge.top,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(shortDate(today), key: const Key('home-date'), style: TextStyle(color: c.dim, fontSize: 16, letterSpacing: 0.3)),
                const SizedBox(height: 6),
                Text('${greetingFor(today)},\n$homeName', key: const Key('home-greeting'), style: TextStyle(color: c.ink, fontSize: 32, fontWeight: FontWeight.w500, height: 1.12, letterSpacing: -0.4)),
                const SizedBox(height: 14),
                _WeekDays(today: today),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        FlyIn(
          edge: MotionEdge.right,
          order: 1,
          child: Semantics(
            button: true,
            label: 'Configuración',
            child: SizedBox(
              width: 52,
              height: 52,
              child: GlassCard(key: const Key('home-settings'), radius: 26, padding: EdgeInsets.zero, onTap: onOpenSettings, child: Center(child: Icon(Icons.settings_outlined, color: c.ink, size: 24))),
            ),
          ),
        ),
      ],
    );
  }
}

/// `L M M J V S D`, con el día de hoy remarcado (en negrita, con una marquita redonda detrás).
class _WeekDays extends StatelessWidget {
  const _WeekDays({required this.today});

  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var day = 1; day <= 7; day++)
          Container(
            key: Key('home-day-$day'),
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: day == today.weekday ? const BoxDecoration(shape: BoxShape.circle, color: Color(0x38FFFFFF)) : null,
            child: Text(
              weekdayLetters[day - 1],
              style: TextStyle(color: day == today.weekday ? c.ink : c.dim, fontSize: 16, fontWeight: day == today.weekday ? FontWeight.w800 : FontWeight.w500, letterSpacing: 1),
            ),
          ),
      ],
    );
  }
}

/// Lo que se sabe de las tareas para la tarjeta (nulo mientras se abren).
class _TaskFigures {
  const _TaskFigures({required this.pending, required this.doing, required this.done, required this.next});

  final int pending;
  final int doing;
  final int done;
  final TaskItem? next;

  static _TaskFigures of(TaskController c) {
    final next = c.roots(active: true);
    return _TaskFigures(pending: c.count(null), doing: c.count(TaskStatus.doing), done: c.count(TaskStatus.done), next: next.isEmpty ? null : next.first);
  }
}

/// La tarjeta de tareas, con el clima en la muesca.
class _TasksCard extends StatelessWidget {
  const _TasksCard({required this.future, required this.weather, required this.onNeedCity});

  final Future<TaskController> future;
  final WeatherController? weather;
  final VoidCallback onNeedCity;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<TaskController>(
      future: future,
      builder: (context, snapshot) {
        final controller = snapshot.data;
        if (controller == null) return _body(context, null);
        return ListenableBuilder(listenable: controller, builder: (context, _) => _body(context, _TaskFigures.of(controller)));
      },
    );
  }

  Widget _body(BuildContext context, _TaskFigures? figures) {
    final c = context.colors;
    return NotchedCard(
      tile: weather == null ? const SizedBox.shrink() : _WeatherTile(controller: weather!, onNeedCity: onNeedCity, corners: NotchShape.tileCorners),
      content: (context, size) {
        final left = NotchShape.notchLeft(size.width);
        final next = figures?.next;
        return Stack(
          key: const Key('home-tasks'),
          children: [
            // a la izquierda de la muesca: la próxima tarea
            Positioned(
              left: 22,
              top: 22,
              width: left - 22 - 14,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _Pill(icon: Icons.schedule_rounded, text: 'Próxima'),
                  const SizedBox(height: 10),
                  if (figures != null && next == null)
                    Text('Todo al día', key: const Key('home-tasks-empty'), style: TextStyle(color: c.ink, fontSize: 16, fontWeight: FontWeight.w600))
                  else if (next != null) ...[
                    Text(next.name, key: const Key('home-next-name'), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.ink, fontSize: 16, height: 1.25)),
                    if (next.due != null) ...[
                      const SizedBox(height: 4),
                      Text(dayLabel(next.due!), style: TextStyle(color: next.due!.isBefore(DateTime.now().toUtc()) ? c.warn : c.dim, fontSize: 15)),
                    ],
                  ],
                ],
              ),
            ),
            // el título y el botón que abre las tareas
            Positioned(
              left: 22,
              right: 18,
              top: NotchShape.notchHeight + 16,
              child: Row(
                children: [
                  Expanded(child: Text('Tareas', style: TextStyle(color: c.ink, fontSize: 46, fontWeight: FontWeight.w400, letterSpacing: -1.4, height: 1.05))),
                  _RoundButton(key: const Key('home-open-tasks'), icon: Icons.arrow_outward_rounded, label: 'Abrir tareas', onTap: () => SectionHost.goTo(context, 'tasks')),
                ],
              ),
            ),
            // abajo: lo pendiente en grande y las otras dos cifras pequeñas
            Positioned(
              left: 22,
              right: 22,
              bottom: 22,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(figures == null ? '–' : '${figures.pending}', key: const Key('home-tasks-count'), style: TextStyle(color: c.ink, fontSize: 72, fontWeight: FontWeight.w300, letterSpacing: -2, height: 1)),
                      const SizedBox(height: 4),
                      Text('Pendientes', style: TextStyle(color: c.dim, fontSize: 15)),
                    ],
                  ),
                  const SizedBox(width: 12),
                  // si no caben (letra grande del sistema), las cifras se encogen en vez de salirse
                  if (figures != null)
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            _Figure(key: const Key('home-tasks-doing'), value: figures.doing, caption: 'En curso'),
                            const SizedBox(width: 22),
                            _Figure(key: const Key('home-tasks-done'), value: figures.done, caption: 'Hechas'),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Una cifra pequeña y atenuada con su nombre debajo.
class _Figure extends StatelessWidget {
  const _Figure({super.key, required this.value, required this.caption});

  final int value;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text('$value', style: TextStyle(color: c.dim, fontSize: 32, fontWeight: FontWeight.w300, height: 1.1)),
        Text(caption, style: TextStyle(color: c.dim, fontSize: 14)),
      ],
    );
  }
}

/// Una pastilla blanca con un icono y un texto oscuro (como «Verified» de la referencia).
class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    const dark = Color(0xFF141414);
    return DecoratedBox(
      decoration: BoxDecoration(color: context.colors.ink, borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 5, 12, 5),
        child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 16, color: dark), const SizedBox(width: 5), Text(text, style: const TextStyle(color: dark, fontSize: 14, fontWeight: FontWeight.w700))]),
      ),
    );
  }
}

/// Un botón redondo blanco con un icono oscuro (como el (i) de la referencia).
class _RoundButton extends StatelessWidget {
  const _RoundButton({super.key, required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(width: 46, height: 46, decoration: BoxDecoration(shape: BoxShape.circle, color: context.colors.ink), child: Icon(icon, color: const Color(0xFF141414), size: 24)),
      ),
    );
  }
}

/// El icono del estado del cielo.
IconData weatherIcon(int code) {
  if (code == 0 || code == 1) return Icons.wb_sunny_outlined;
  if (code == 2) return Icons.wb_cloudy_outlined;
  if (code == 3) return Icons.cloud_outlined;
  if (code == 45 || code == 48) return Icons.foggy;
  if (code >= 51 && code <= 67 || code >= 80 && code <= 82) return Icons.water_drop_outlined;
  if (code >= 71 && code <= 77 || code == 85 || code == 86) return Icons.ac_unit;
  if (code >= 95) return Icons.thunderstorm_outlined;
  return Icons.cloud_queue;
}

/// El clima de la ciudad elegida (o la invitación a elegirla), en una tarjeta de cristal: va en la muesca de la tarjeta de tareas.
class _WeatherTile extends StatelessWidget {
  const _WeatherTile({required this.controller, required this.onNeedCity, required this.corners});

  final WeatherController controller;
  final VoidCallback onNeedCity;
  final BorderRadius corners;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = context.colors;
        final weather = controller.weather;
        final needsCity = controller.status == WeatherStatus.noCity || controller.status == WeatherStatus.unknownCity;
        Widget body;
        if (controller.status == WeatherStatus.noCity) {
          body = Text('Elige tu ciudad en Configuración', key: const Key('home-weather-nocity'), style: TextStyle(color: c.dim, fontSize: 15, height: 1.3));
        } else if (controller.status == WeatherStatus.unknownCity) {
          body = Text('No encontré «${controller.city}»', key: const Key('home-weather-unknown'), style: TextStyle(color: c.warn, fontSize: 15, height: 1.3));
        } else if (weather == null) {
          body = Text(controller.status == WeatherStatus.offline ? 'Sin conexión' : 'Cargando…', key: const Key('home-weather-wait'), style: TextStyle(color: c.dim, fontSize: 15));
        } else {
          body = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${weather.temperature.round()}°C', key: const Key('home-weather-temp'), style: TextStyle(color: c.ink, fontSize: 38, fontWeight: FontWeight.w500, letterSpacing: -1, height: 1)),
              const SizedBox(height: 6),
              Text(weather.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.ink, fontSize: 15)),
              Text(controller.stale ? '${weather.city} · sin conexión' : weather.city, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.dim, fontSize: 15)),
            ],
          );
        }
        return GlassCard(
          key: const Key('home-weather'),
          corners: corners,
          padding: const EdgeInsets.all(16),
          onTap: needsCity ? onNeedCity : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(weather == null ? Icons.cloud_queue : weatherIcon(weather.code), color: c.ink, size: 28),
              // el texto se encoge si no cabe (letra grande del sistema) en vez de salirse de la tarjeta
              Expanded(
                child: LayoutBuilder(
                  builder: (context, box) => Align(
                    alignment: Alignment.bottomLeft,
                    child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.bottomLeft, child: SizedBox(width: box.maxWidth, child: body)),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
