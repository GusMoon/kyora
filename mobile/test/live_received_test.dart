// Prueba en vivo del botón «Recibido» contra TU Supabase, con el mismo `ChatRepository` que usa la app.
//   $env:KYORA_LIVE='1'; flutter test test/live_received_test.dart
// Antes hay que haber ejecutado supabase/schema.sql (trae `received_at` y `confirm_track_received`).
// Con tu cuenta de administrador, que también puede recibir canciones («Yo»): sube un MP3 de prueba, se lo manda a sí misma,
// confirma que lo recibió y comprueba que `received_at` se escribe una sola vez. Al terminar borra la fila y el archivo de prueba.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/data/chat_backend.dart';
import 'package:kyora_chat/data/chat_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

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

  test('«Recibido»: received_at se escribe al confirmar, una sola vez, y solo sobre canciones propias', () async {
    final env = readEnv();
    final client = SupabaseClient(env['SUPABASE_URL']!, env['SUPABASE_ANON_KEY']!);
    addTearDown(() async => client.dispose());
    final repo = ChatRepository(client);
    await repo.signIn(env['CHAT_EMAIL']!, env['CHAT_PASSWORD']!);
    final me = repo.userId!;

    // Una canción de prueba, mandada a mí misma (como hace la PC con «Yo»).
    final id = const Uuid().v4();
    final path = '$me/music/$id/prueba-recibido.mp3';
    await repo.upload(path, Uint8List.fromList([0xFF, 0xFB, 0x90, 0x00]), 'audio/mpeg');
    addTearDown(() async {
      try {
        await client.from('music_tracks').delete().eq('id', id);
      } catch (_) {}
      try {
        await client.storage.from('chat-files').remove([path]);
      } catch (_) {}
    });
    await client.rpc('add_music_track', params: {
      'p_id': id,
      'p_title': 'Prueba recibido (test automático)',
      'p_file_name': 'prueba-recibido.mp3',
      'p_storage_path': path,
      'p_size_bytes': 4,
      'p_recipient_id': me,
    });

    // Recién mandada: sin confirmar.
    final before = (await repo.listTracks()).firstWhere((t) => t.id == id);
    expect(before.receivedAt, isNull);

    // Confirmar: queda la hora.
    await repo.confirmReceived(id);
    final after = (await repo.listTracks()).firstWhere((t) => t.id == id);
    expect(after.receivedAt, isNotNull);

    // Repetir no cambia la hora de la primera vez.
    await repo.confirmReceived(id);
    final again = (await repo.listTracks()).firstWhere((t) => t.id == id);
    expect(again.receivedAt, after.receivedAt);

    // Una canción que no existe (o que no es tuya) se rechaza con el motivo.
    await expectLater(
      repo.confirmReceived(const Uuid().v4()),
      throwsA(isA<ChatException>().having((e) => e.message, 'message', contains('ya no está'))),
    );

    await repo.signOut();
  }, skip: live ? false : 'define KYORA_LIVE=1', timeout: const Timeout(Duration(seconds: 90)));
}
