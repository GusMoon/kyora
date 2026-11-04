// Prueba en vivo de las CUENTAS contra TU Supabase, con el mismo `ChatRepository` que usa la app.
//   $env:KYORA_LIVE='1'; flutter test test/live_accounts_test.dart
// Parte 1 (siempre con KYORA_LIVE=1, solo lectura): tu cuenta es administradora y ve a quién se le puede mandar música.
// Parte 2 (además KYORA_LIVE_SIGNUP=1): CREA una cuenta de pasante de prueba (no se puede borrar desde aquí: bórrala en
// Authentication > Users) y comprueba que solo ve música: no puede leer el chat, ni crear mensajes, ni subir archivos.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/data/chat_backend.dart';
import 'package:kyora_chat/data/chat_repository.dart';
import 'package:kyora_chat/models/profile.dart';
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
  final signup = Platform.environment['KYORA_LIVE_SIGNUP'] == '1';

  test('tu cuenta es administradora y la lista de destinatarios te trae a ti primero', () async {
    final env = readEnv();
    final client = SupabaseClient(env['SUPABASE_URL']!, env['SUPABASE_ANON_KEY']!);
    addTearDown(() async => client.dispose());
    final repo = ChatRepository(client);
    await repo.signIn(env['CHAT_EMAIL']!, env['CHAT_PASSWORD']!);

    final me = await repo.myProfile();
    expect(me, isNotNull, reason: 'sin perfil: ¿ejecutaste supabase/schema.sql con tu usuario ya creado?');
    expect(me!.role, Role.admin);
    // ignore: avoid_print
    print('Perfil: ${me.username} (${me.role.name})');

    final recipients = await client.rpc('list_recipients') as List<dynamic>;
    expect(recipients, isNotEmpty);
    final first = Map<String, dynamic>.from(recipients.first as Map);
    expect(first['me'], isTrue);
    expect(first['id'], me.id);
    // ignore: avoid_print
    print('Destinatarios: ${recipients.map((r) => (r as Map)['username']).join(', ')}');

    expect(await client.rpc('username_available', params: {'p_username': me.username}), isFalse);
    expect(await client.rpc('username_available', params: {'p_username': 'libre-${DateTime.now().microsecondsSinceEpoch}'}), isTrue);
  }, skip: live ? false : 'define KYORA_LIVE=1');

  test('un pasante se registra, entra, solo ve música y no puede usar el chat', () async {
    final env = readEnv();
    final stamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final username = 'prueba-$stamp';
    final email = 'prueba.$stamp@example.com';
    final client = SupabaseClient(env['SUPABASE_URL']!, env['SUPABASE_ANON_KEY']!);
    addTearDown(() async => client.dispose());
    final repo = ChatRepository(client);

    expect(await repo.signUp(username: username, email: email, password: 'prueba-123456'), isTrue,
        reason: '¿está desactivado "Confirm email" en Authentication > Providers > Email?');
    final me = await repo.myProfile();
    expect(me!.role, Role.intern);
    expect(me.username, username);

    // Ya entró, y el nombre de usuario ya no está libre (comprobado con la sesión del pasante).
    expect(await client.rpc('username_available', params: {'p_username': username.toUpperCase()}), isFalse);

    // No ve el chat ni puede escribir en él ni subir archivos.
    await expectLater(repo.ensureConversation(), throwsA(isA<ChatException>()));
    await expectLater(repo.upload('${me.id}/music/x/x.mp3', Uint8List.fromList([1]), 'audio/mpeg'), throwsA(isA<ChatException>()));
    await expectLater(client.rpc('list_recipients'), throwsA(anything));
    await expectLater(
      client.rpc('add_music_track', params: {
        'p_id': '00000000-0000-4000-8000-000000000001',
        'p_title': 'x',
        'p_file_name': 'x.mp3',
        'p_storage_path': '${me.id}/music/x/x.mp3',
      }),
      throwsA(anything),
    );

    // Música: su lista existe y está vacía (nadie le ha mandado nada).
    expect(await repo.listTracks(), isEmpty);
    await repo.signOut();
  }, skip: live && signup ? false : 'define KYORA_LIVE=1 y KYORA_LIVE_SIGNUP=1 (crea una cuenta de prueba)');
}
