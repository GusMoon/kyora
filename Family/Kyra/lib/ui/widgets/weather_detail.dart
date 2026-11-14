import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/weather_service.dart';
import '../../state/weather_controller.dart';
import '../../theme.dart';
import 'focus_space.dart';
import 'pixel_glyph.dart';

/// El clima con detalle: cómo está ahora, la máxima y la mínima, el amanecer y el atardecer, y el día hora a hora.
Future<void> showWeatherDetail(BuildContext context, WeatherController controller) =>
    showFocusPanel<void>(context, maxWidth: 460, builder: (context) => WeatherDetail(controller: controller));

class WeatherDetail extends StatefulWidget {
  const WeatherDetail({super.key, required this.controller});

  final WeatherController controller;

  @override
  State<WeatherDetail> createState() => _WeatherDetailState();
}

class _WeatherDetailState extends State<WeatherDetail> {
  @override
  void initState() {
    super.initState();
    // los datos guardados de antes pueden no traer las horas: se piden otra vez
    if (!(widget.controller.weather?.hasDetail ?? false)) {
      unawaited(Future.microtask(() => widget.controller.refresh(force: true)));
    }
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
  static String _hhmm(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final mono = TextStyle(fontFamily: monoFont, fontSize: 15, height: 1.25, color: c.dim);
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final weather = widget.controller.weather;
        if (weather == null) {
          return Padding(padding: const EdgeInsets.fromLTRB(20, 12, 20, 12), child: Text('Cargando el clima…', key: const Key('weather-detail-loading'), style: mono));
        }
        final hours = weather.upcoming();
        Widget stat(String label, String value, Key key) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: mono),
              Text(value, key: key, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: monoFont, fontSize: 15, color: c.ink)),
            ],
          ),
        );
        String deg(double? v) => v == null ? '--' : '${v.round()}°';
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 12, 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  PixelIcon(pixelWeatherGlyph(weather.code), size: 36, color: c.accent),
                  const SizedBox(width: 12),
                  Text('${weather.temperature.round()}°', key: const Key('weather-detail-temp'), style: display(size: 44, color: c.ink, weight: FontWeight.w500).copyWith(height: 1)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(weather.label, key: const Key('weather-detail-label'), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: monoFont, fontSize: 15, color: c.ink)),
                        Text(weather.city, maxLines: 1, overflow: TextOverflow.ellipsis, style: mono),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  stat('MÁX / MÍN', '${deg(weather.high)} / ${deg(weather.low)}', const Key('weather-detail-range')),
                  stat('HUMEDAD', weather.humidity == null ? '--' : '${weather.humidity}%', const Key('weather-detail-humidity')),
                  stat('VIENTO', weather.wind == null ? '--' : '${weather.wind!.round()} km/h', const Key('weather-detail-wind')),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  stat('AMANECER', weather.sunrise == null ? '--' : _hhmm(weather.sunrise!), const Key('weather-detail-sunrise')),
                  stat('ATARDECER', weather.sunset == null ? '--' : _hhmm(weather.sunset!), const Key('weather-detail-sunset')),
                  const Spacer(),
                ],
              ),
              const SizedBox(height: 12),
              Text('HORA A HORA · LLUVIA · VIENTO', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: monoFont, fontSize: 15, letterSpacing: 1.2, color: c.accent)),
              const SizedBox(height: 4),
              if (hours.isEmpty)
                Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('Actualizando las horas…', key: const Key('weather-detail-updating'), style: mono))
              else
                Flexible(
                  child: ListView.builder(
                    key: const Key('weather-hours'),
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(right: 8),
                    itemCount: hours.length,
                    itemExtent: 34,
                    itemBuilder: (context, i) => _HourRow(hour: hours[i], first: i == 0),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _HourRow extends StatelessWidget {
  const _HourRow({required this.hour, required this.first});

  final HourlyForecast hour;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final mono = TextStyle(fontFamily: monoFont, fontSize: 15, color: c.dim);
    final time = first ? 'Ahora' : '${hour.time.hour.toString().padLeft(2, '0')}:00';
    return Row(
      key: Key('weather-hour-${hour.time.day}-${hour.time.hour}'),
      children: [
        SizedBox(width: 62, child: Text(time, maxLines: 1, style: TextStyle(fontFamily: monoFont, fontSize: 15, color: first ? c.accent : c.ink))),
        PixelIcon(pixelWeatherGlyph(hour.code), size: 20, color: c.accent),
        const SizedBox(width: 10),
        SizedBox(width: 44, child: Text('${hour.temperature.round()}°', maxLines: 1, style: TextStyle(fontFamily: monoFont, fontSize: 15, fontWeight: FontWeight.w700, color: c.ink))),
        Expanded(child: Text(hour.rainChance == null ? '' : '${hour.rainChance}%', maxLines: 1, overflow: TextOverflow.clip, style: mono)),
        Text(hour.wind == null ? '' : '${hour.wind!.round()} km/h', maxLines: 1, style: mono),
      ],
    );
  }
}
