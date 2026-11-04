import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/weather_service.dart';
import '../data/weather_store.dart';

/// En qué punto está el clima.
enum WeatherStatus {
  /// Todavía no se ha elegido ciudad.
  noCity,

  /// Pidiéndolo (si ya había un dato anterior, se sigue enseñando).
  loading,

  /// Se tiene el dato.
  ready,

  /// La ciudad escrita no se encontró.
  unknownCity,

  /// No se pudo pedir (sin internet…): se enseña el último dato, si lo hay.
  offline,
}

/// El clima de la ciudad que elegiste. Recuerda la ciudad y el último dato, así sin internet se ve lo de la última vez.
class WeatherController extends ChangeNotifier {
  WeatherController(this._backend, this._store) {
    _city = _store.city;
    _weather = _store.last;
    _status = _city == null ? WeatherStatus.noCity : (_weather != null ? WeatherStatus.ready : WeatherStatus.loading);
  }

  final WeatherBackend _backend;
  final WeatherStore _store;

  String? _city;
  Weather? _weather;
  late WeatherStatus _status;
  DateTime? _fetchedAt;
  int _request = 0;

  /// Lo que pasó tan poco que no vale la pena volver a pedirlo.
  static const freshFor = Duration(minutes: 20);

  String? get city => _city;
  Weather? get weather => _weather;
  WeatherStatus get status => _status;

  /// El dato que se enseña viene de la última vez, no de ahora.
  bool get stale => _status == WeatherStatus.offline && _weather != null;

  /// Cambia la ciudad (vacía = quitarla) y pide su clima.
  Future<void> setCity(String? value) async {
    final city = value?.trim();
    if (city == null || city.isEmpty) {
      _request++;
      _city = null;
      _weather = null;
      _fetchedAt = null;
      _status = WeatherStatus.noCity;
      await _store.saveCity(null);
      await _store.saveLast(null);
      notifyListeners();
      return;
    }
    _city = city;
    await _store.saveCity(city);
    _weather = null; // el dato de otra ciudad no vale
    await _store.saveLast(null);
    await refresh(force: true);
  }

  /// Pide el clima de ahora. Si ya se pidió hace poco, no lo repite (salvo con [force]).
  Future<void> refresh({bool force = false}) async {
    final city = _city;
    if (city == null) return;
    final at = _fetchedAt;
    if (!force && at != null && _status == WeatherStatus.ready && DateTime.now().difference(at) < freshFor) return;
    final request = ++_request;
    _status = WeatherStatus.loading;
    notifyListeners();
    try {
      final fresh = await _backend.fetch(city);
      if (request != _request) return;
      _weather = fresh;
      _fetchedAt = DateTime.now();
      _status = WeatherStatus.ready;
      await _store.saveLast(fresh);
    } on CityNotFound {
      if (request != _request) return;
      _weather = null;
      _status = WeatherStatus.unknownCity;
    } on Object {
      if (request != _request) return;
      _status = WeatherStatus.offline;
    }
    notifyListeners();
  }
}
