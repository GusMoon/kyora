import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'weather_service.dart';

/// La ciudad elegida y el último tiempo que se supo de ella (para enseñarlo sin internet).
abstract class WeatherStore {
  String? get city;
  Weather? get last;
  Future<void> saveCity(String? city);
  Future<void> saveLast(Weather? weather);
}

class MemoryWeatherStore implements WeatherStore {
  @override
  String? city;

  @override
  Weather? last;

  @override
  Future<void> saveCity(String? value) async => city = value;

  @override
  Future<void> saveLast(Weather? value) async => last = value;
}

class PrefsWeatherStore implements WeatherStore {
  PrefsWeatherStore._(this._prefs);

  static const _cityKey = 'weather.city';
  static const _lastKey = 'weather.last';

  final SharedPreferences _prefs;

  static Future<PrefsWeatherStore> open() async => PrefsWeatherStore._(await SharedPreferences.getInstance());

  @override
  String? get city => _prefs.getString(_cityKey);

  @override
  Weather? get last {
    final text = _prefs.getString(_lastKey);
    if (text == null) return null;
    try {
      return Weather.fromJson(jsonDecode(text));
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> saveCity(String? city) async {
    if (city == null) {
      await _prefs.remove(_cityKey);
    } else {
      await _prefs.setString(_cityKey, city);
    }
  }

  @override
  Future<void> saveLast(Weather? weather) async {
    if (weather == null) {
      await _prefs.remove(_lastKey);
    } else {
      await _prefs.setString(_lastKey, jsonEncode(weather.toJson()));
    }
  }
}
