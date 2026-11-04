// Prueba en vivo del REPRODUCTOR contra TU Supabase, con el mismo `ChatRepository` que usa la app. Solo lee:
//   $env:KYORA_LIVE='1'; flutter test test/live_player_test.dart
// Pide las direcciones firmadas de tus canciones y comprueba que el servidor entrega el audio (lo que haría el reproductor).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/data/chat_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Map<String, String> readEnv() {
  final values = <String, String>{};
  for (final raw in File('../supabase/.env').readAsLinesSync()) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#') || !line.contains('=')) continue;
    final at = line.indexOf('=');
    var value = line.substring(at + 1).trim();
    if (value.length >= 2 && (value.startsWith('"') || value.startsWith("'")) && value.endsWith(value[0])) {
      value = value.substring(1, value.length - 1);
    }
    values[line.substring(0, at).trim()] = value;
  }
  return values;
}

void main() {
  final live = Platform.environment['KYORA_LIVE'] == '1';

  test('las direcciones firmadas de mis canciones entregan el audio', () async {
    final env = readEnv();
    final client = SupabaseClient(env['SUPABASE_URL']!, env['SUPABASE_ANON_KEY']!);
    addTearDown(() async => client.dispose());
    final repo = ChatRepository(client);
    await repo.signIn(env['CHAT_EMAIL']!, env['CHAT_PASSWORD']!);

    final tracks = await repo.listTracks();
    // ignore: avoid_print
    print('Canciones que recibo: ${tracks.length}');
    if (tracks.isEmpty) {
      markTestSkipped('No hay canciones en tu cuenta todavía: manda una desde la PC y repite.');
      return;
    }
    final urls = await repo.signedUrls([for (final t in tracks) t.storagePath], 86400);
    expect(urls, isNotEmpty);
    final first = tracks.firstWhere((t) => urls.containsKey(t.storagePath));
    final http = HttpClient();
    addTearDown(http.close);
    final request = await http.getUrl(Uri.parse(urls[first.storagePath]!));
    request.headers.set('Range', 'bytes=0-1023'); // como el reproductor: pide por trozos
    final response = await request.close();
    final bytes = await response.fold<int>(0, (sum, chunk) => sum + chunk.length);
    // ignore: avoid_print
    print('«${first.title}»: HTTP ${response.statusCode}, ${response.headers.contentType}, $bytes bytes');
    expect(response.statusCode, anyOf(200, 206));
    expect(bytes, greaterThan(0));
    expect(first.coverUrl, anyOf(isNull, startsWith('http')));
  }, skip: live ? false : 'define KYORA_LIVE=1');
}
