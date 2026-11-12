import 'dart:convert';

import 'package:http/http.dart' as http;

/// El tiempo de una ciudad en este momento.
class Weather {
  const Weather({required this.city, required this.temperature, required this.code});

  /// El nombre de la ciudad tal como la conoce el servicio (con el país si hace falta para distinguirla).
  final String city;

  /// Grados centígrados.
  final double temperature;

  /// El código WMO del estado del cielo (0 despejado, 61 lluvia…).
  final int code;

  Map<String, Object> toJson() => {'city': city, 'temperature': temperature, 'code': code};

  static Weather? fromJson(Object? json) {
    if (json is! Map) return null;
    final city = json['city'], temperature = json['temperature'], code = json['code'];
    if (city is! String || temperature is! num || code is! num) return null;
    return Weather(city: city, temperature: temperature.toDouble(), code: code.toInt());
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
/// pide el tiempo de ahora en sus coordenadas.
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
        'current': 'temperature_2m,weather_code',
        'timezone': 'auto',
      }),
    );
    final current = forecast['current'];
    if (current is! Map || current['temperature_2m'] is! num || current['weather_code'] is! num) {
      throw const FormatException('Respuesta del clima inesperada');
    }
    return Weather(
      city: (place['name'] as String?) ?? query,
      temperature: (current['temperature_2m'] as num).toDouble(),
      code: (current['weather_code'] as num).toInt(),
    );
  }

  Future<Map<String, dynamic>> _json(Uri uri) async {
    final response = await _client.get(uri).timeout(_timeout);
    if (response.statusCode != 200) throw http.ClientException('El servicio del clima respondió ${response.statusCode}', uri);
    return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
  }
}
