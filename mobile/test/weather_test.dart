import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kyora_chat/data/weather_service.dart';
import 'package:kyora_chat/data/weather_store.dart';
import 'package:kyora_chat/state/weather_controller.dart';

class FakeWeather implements WeatherBackend {
  Object? error;
  Weather result = const Weather(city: 'Lima', temperature: 19.4, code: 3);
  final List<String> asked = [];

  @override
  Future<Weather> fetch(String city) async {
    asked.add(city);
    if (error != null) throw error!;
    return result;
  }
}

void main() {
  group('OpenMeteoWeather', () {
    test('busca la ciudad y pide el tiempo de sus coordenadas', () async {
      final urls = <Uri>[];
      final client = MockClient((request) async {
        urls.add(request.url);
        if (request.url.host == 'geocoding-api.open-meteo.com') {
          return http.Response(
            jsonEncode({
              'results': [
                {'name': 'Bogotá', 'latitude': 4.6, 'longitude': -74.08},
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response(jsonEncode({'current': {'temperature_2m': 16.2, 'weather_code': 2}}), 200);
      });
      final weather = await OpenMeteoWeather(client: client).fetch('  Bogotá ');
      expect(weather.city, 'Bogotá');
      expect(weather.temperature, 16.2);
      expect(weather.code, 2);
      expect(weather.label, 'Parcialmente nublado');
      expect(urls.first.queryParameters['name'], 'Bogotá');
      expect(urls.first.queryParameters['language'], 'es');
      expect(urls.last.queryParameters['latitude'], '4.6');
      expect(urls.last.queryParameters['longitude'], '-74.08');
    });

    test('una ciudad que no existe lanza CityNotFound', () async {
      final client = MockClient((_) async => http.Response(jsonEncode({'generationtime_ms': 0.4}), 200));
      await expectLater(OpenMeteoWeather(client: client).fetch('Xyzzy'), throwsA(isA<CityNotFound>()));
    });

    test('un error del servicio lanza una excepción que no es «ciudad no encontrada»', () async {
      final client = MockClient((_) async => http.Response('boom', 500));
      await expectLater(OpenMeteoWeather(client: client).fetch('Lima'), throwsA(isA<http.ClientException>()));
    });
  });

  test('los códigos del cielo salen en español', () {
    expect(weatherLabel(0), 'Despejado');
    expect(weatherLabel(63), 'Lluvia');
    expect(weatherLabel(95), 'Tormenta');
  });

  group('WeatherController', () {
    late FakeWeather backend;
    late MemoryWeatherStore store;

    setUp(() {
      backend = FakeWeather();
      store = MemoryWeatherStore();
    });

    test('sin ciudad no pide nada', () async {
      final c = WeatherController(backend, store);
      expect(c.status, WeatherStatus.noCity);
      await c.refresh();
      expect(backend.asked, isEmpty);
    });

    test('elegir ciudad la guarda, pide el clima y guarda el dato', () async {
      final c = WeatherController(backend, store);
      await c.setCity(' Lima ');
      expect(backend.asked, ['Lima']);
      expect(c.status, WeatherStatus.ready);
      expect(c.weather!.temperature, 19.4);
      expect(store.city, 'Lima');
      expect(store.last!.city, 'Lima');
    });

    test('una ciudad desconocida se avisa y no deja un dato de otra', () async {
      final c = WeatherController(backend, store);
      await c.setCity('Lima');
      backend.error = const CityNotFound('Xyzzy');
      await c.setCity('Xyzzy');
      expect(c.status, WeatherStatus.unknownCity);
      expect(c.weather, isNull);
    });

    test('sin internet enseña lo último que se supo y lo marca', () async {
      final c = WeatherController(backend, store);
      await c.setCity('Lima');
      backend.error = Exception('sin red');
      await c.refresh(force: true);
      expect(c.status, WeatherStatus.offline);
      expect(c.stale, isTrue);
      expect(c.weather!.city, 'Lima');
    });

    test('al abrir la app recuerda la ciudad y el último dato', () {
      store.city = 'Lima';
      store.last = const Weather(city: 'Lima', temperature: 20, code: 0);
      final c = WeatherController(backend, store);
      expect(c.city, 'Lima');
      expect(c.status, WeatherStatus.ready);
      expect(c.weather!.temperature, 20);
    });

    test('no repite la petición si el dato es reciente, salvo que se fuerce', () async {
      final c = WeatherController(backend, store);
      await c.setCity('Lima');
      await c.refresh();
      expect(backend.asked, hasLength(1));
      await c.refresh(force: true);
      expect(backend.asked, hasLength(2));
    });

    test('vaciar la ciudad lo olvida todo', () async {
      final c = WeatherController(backend, store);
      await c.setCity('Lima');
      await c.setCity('  ');
      expect(c.status, WeatherStatus.noCity);
      expect(store.city, isNull);
      expect(store.last, isNull);
    });
  });
}
