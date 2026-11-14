import 'dart:convert';

import 'package:http/http.dart' as http;

/// Una hora del pronóstico (la hora es la de la ciudad, sin zona).
class HourlyForecast {
  const HourlyForecast({required this.time, required this.temperature, required this.code, this.rainChance, this.wind, this.humidity, this.isDay = true});

  final DateTime time;
  final double temperature;
  final int code;

  /// Probabilidad de lluvia, de 0 a 100.
  final int? rainChance;

  /// Viento en km/h.
  final double? wind;

  /// Humedad relativa, de 0 a 100.
  final int? humidity;
  final bool isDay;

  Map<String, Object> toJson() => {
    'time': time.toIso8601String(),
    'temperature': temperature,
    'code': code,
    'rain': ?rainChance,
    'wind': ?wind,
    'humidity': ?humidity,
    'day': isDay,
  };

  static HourlyForecast? fromJson(Object? json) {
    if (json is! Map) return null;
    final time = json['time'], temperature = json['temperature'], code = json['code'];
    if (time is! String || temperature is! num || code is! num) return null;
    final at = DateTime.tryParse(time);
    if (at == null) return null;
    final rain = json['rain'], wind = json['wind'], humidity = json['humidity'];
    return HourlyForecast(
      time: at,
      temperature: temperature.toDouble(),
      code: code.toInt(),
      rainChance: rain is num ? rain.toInt() : null,
      wind: wind is num ? wind.toDouble() : null,
      humidity: humidity is num ? humidity.toInt() : null,
      isDay: json['day'] != false,
    );
  }
}

/// El tiempo de una ciudad en este momento y, si el servicio lo dio, el del día hora a hora.
class Weather {
  const Weather({
    required this.city,
    required this.temperature,
    required this.code,
    this.time,
    this.humidity,
    this.wind,
    this.high,
    this.low,
    this.sunrise,
    this.sunset,
    this.hourly = const [],
  });

  /// El nombre de la ciudad tal como la conoce el servicio (con el país si hace falta para distinguirla).
  final String city;

  /// Grados centígrados.
  final double temperature;

  /// El código WMO del estado del cielo (0 despejado, 61 lluvia…).
  final int code;

  /// La hora de la ciudad cuando se midió (sin zona).
  final DateTime? time;
  final int? humidity;

  /// Viento en km/h.
  final double? wind;

  /// La máxima y la mínima de hoy.
  final double? high;
  final double? low;

  /// El amanecer y el atardecer de hoy (hora de la ciudad).
  final DateTime? sunrise;
  final DateTime? sunset;

  /// Hora a hora, de hoy y del principio de mañana. Vacío si no se pidió (datos guardados de antes).
  final List<HourlyForecast> hourly;

  /// Si se tiene el pronóstico por horas.
  bool get hasDetail => hourly.isNotEmpty;

  /// Las horas desde la actual en adelante (hasta [limit]).
  List<HourlyForecast> upcoming({int limit = 24}) {
    final from = time ?? DateTime.now();
    final start = DateTime(from.year, from.month, from.day, from.hour);
    return hourly.where((h) => !h.time.isBefore(start)).take(limit).toList();
  }

  Map<String, Object> toJson() => {
    'city': city,
    'temperature': temperature,
    'code': code,
    'time': ?time?.toIso8601String(),
    'humidity': ?humidity,
    'wind': ?wind,
    'high': ?high,
    'low': ?low,
    'sunrise': ?sunrise?.toIso8601String(),
    'sunset': ?sunset?.toIso8601String(),
    if (hourly.isNotEmpty) 'hourly': [for (final h in hourly) h.toJson()],
  };

  static DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v) : null;

  static Weather? fromJson(Object? json) {
    if (json is! Map) return null;
    final city = json['city'], temperature = json['temperature'], code = json['code'];
    if (city is! String || temperature is! num || code is! num) return null;
    final hourly = json['hourly'];
    final humidity = json['humidity'], wind = json['wind'], high = json['high'], low = json['low'];
    return Weather(
      city: city,
      temperature: temperature.toDouble(),
      code: code.toInt(),
      time: _date(json['time']),
      humidity: humidity is num ? humidity.toInt() : null,
      wind: wind is num ? wind.toDouble() : null,
      high: high is num ? high.toDouble() : null,
      low: low is num ? low.toDouble() : null,
      sunrise: _date(json['sunrise']),
      sunset: _date(json['sunset']),
      hourly: hourly is List ? [for (final h in hourly) ?HourlyForecast.fromJson(h)] : const [],
    );
  }

  /// Cómo está el cielo, en español.
  String get label => weatherLabel(code);
}

/// El estado del cielo en español a partir del código WMO que da Open-Meteo.
String weatherLabel(int code) {
  if (code == 0) return 'Despejado';
  if (code == 1) return 'Casi despejado';
  if (code == 2) return 'Parcialmente nublado';
  if (code == 3) return 'Nublado';
  if (code == 45 || code == 48) return 'Niebla';
  if (code >= 51 && code <= 57) return 'Llovizna';
  if (code >= 61 && code <= 67) return 'Lluvia';
  if (code >= 71 && code <= 77) return 'Nieve';
  if (code >= 80 && code <= 82) return 'Chubascos';
  if (code == 85 || code == 86) return 'Chubascos de nieve';
  if (code >= 95) return 'Tormenta';
  return 'Variable';
}

/// La ciudad que se escribió no existe (o el servicio no la conoce).
class CityNotFound implements Exception {
  const CityNotFound(this.query);

  final String query;

  @override
  String toString() => 'No se encontró «$query»';
}

/// De dónde sale el tiempo (en las pruebas, uno falso).
abstract class WeatherBackend {
  Future<Weather> fetch(String city);
}

/// El tiempo de Open-Meteo: gratis, sin clave y sin pedir la ubicación del teléfono. Primero busca la ciudad por su nombre y luego
/// pide el tiempo de ahora y del día, hora a hora, en sus coordenadas.
class OpenMeteoWeather implements WeatherBackend {
  OpenMeteoWeather({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _timeout = Duration(seconds: 12);

  @override
  Future<Weather> fetch(String city) async {
    final query = city.trim();
    final found = await _json(Uri.https('geocoding-api.open-meteo.com', '/v1/search', {'name': query, 'count': '1', 'language': 'es', 'format': 'json'}));
    final results = found['results'];
    if (results is! List || results.isEmpty) throw CityNotFound(query);
    final place = results.first as Map<String, dynamic>;
    final forecast = await _json(
      Uri.https('api.open-meteo.com', '/v1/forecast', {
        'latitude': '${place['latitude']}',
        'longitude': '${place['longitude']}',
        'current': 'temperature_2m,weather_code,relative_humidity_2m,wind_speed_10m',
        'hourly': 'temperature_2m,weather_code,precipitation_probability,wind_speed_10m,relative_humidity_2m,is_day',
        'daily': 'temperature_2m_max,temperature_2m_min,sunrise,sunset',
        'forecast_days': '2',
        'timezone': 'auto',
      }),
    );
    final current = forecast['current'];
    if (current is! Map || current['temperature_2m'] is! num || current['weather_code'] is! num) {
      throw const FormatException('Respuesta del clima inesperada');
    }
    final daily = forecast['daily'];
    num? first(Object? list) => list is List && list.isNotEmpty && list.first is num ? list.first as num : null;
    DateTime? firstDate(Object? list) => list is List && list.isNotEmpty && list.first is String ? DateTime.tryParse(list.first as String) : null;
    final today = daily is Map ? daily : const <String, Object?>{};
    return Weather(
      city: (place['name'] as String?) ?? query,
      temperature: (current['temperature_2m'] as num).toDouble(),
      code: (current['weather_code'] as num).toInt(),
      time: current['time'] is String ? DateTime.tryParse(current['time'] as String) : null,
      humidity: current['relative_humidity_2m'] is num ? (current['relative_humidity_2m'] as num).toInt() : null,
      wind: current['wind_speed_10m'] is num ? (current['wind_speed_10m'] as num).toDouble() : null,
      high: first(today['temperature_2m_max'])?.toDouble(),
      low: first(today['temperature_2m_min'])?.toDouble(),
      sunrise: firstDate(today['sunrise']),
      sunset: firstDate(today['sunset']),
      hourly: _hours(forecast['hourly']),
    );
  }

  static List<HourlyForecast> _hours(Object? raw) {
    if (raw is! Map || raw['time'] is! List) return const [];
    final times = raw['time'] as List;
    Object? at(String key, int i) {
      final list = raw[key];
      return list is List && i < list.length ? list[i] : null;
    }

    final out = <HourlyForecast>[];
    for (var i = 0; i < times.length; i++) {
      final time = times[i] is String ? DateTime.tryParse(times[i] as String) : null;
      final temperature = at('temperature_2m', i), code = at('weather_code', i);
      if (time == null || temperature is! num || code is! num) continue;
      final rain = at('precipitation_probability', i), wind = at('wind_speed_10m', i), humidity = at('relative_humidity_2m', i), day = at('is_day', i);
      out.add(
        HourlyForecast(
          time: time,
          temperature: temperature.toDouble(),
          code: code.toInt(),
          rainChance: rain is num ? rain.toInt() : null,
          wind: wind is num ? wind.toDouble() : null,
          humidity: humidity is num ? humidity.toInt() : null,
          isDay: day is num ? day != 0 : true,
        ),
      );
    }
    return out;
  }

  Future<Map<String, dynamic>> _json(Uri uri) async {
    final response = await _client.get(uri).timeout(_timeout);
    if (response.statusCode != 200) throw http.ClientException('El servicio del clima respondió ${response.statusCode}', uri);
    return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
  }
}
