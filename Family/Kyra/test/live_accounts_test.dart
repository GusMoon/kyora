// Prueba en vivo de las CUENTAS contra TU Supabase, con el mismo `ChatRepository` que usa la app.
//   $env:KYORA_LIVE='1'; flutter test test/live_accounts_test.dart
// Parte 1 (siempre con KYORA_LIVE=1, solo lectura): tu cuenta es administradora y ve a quién se le puede mandar música.
// Parte 2 (además KYORA_LIVE_SIGNUP=1): el administrador CREA un visitante de prueba con la función admin-users (y al acabar lo BORRA), y
// comprueba el código de 6 dígitos, la presencia en línea y que sin verificar no entra al chat familiar.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/data/chat_backend.dart';
import 'package:kyora_chat/data/chat_repository.dart';
import 'package:kyora_chat/models/profile.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Map<String, String> readEnv() {
  final values = <String, String>{};
  for (final raw in File('../../Server/supabase/.env').readAsLinesSync()) {
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
    expect(me, isNotNull, reason: 'sin perfil: ¿ejecutaste Server/supabase/schema.sql con tu usuario ya creado?');
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

  test('el administrador crea un visitante, que verifica su código, entra, aparece en línea y solo ve el chat familiar', () async {
    final env = readEnv();
    final stamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final username = 'prueba-$stamp';
    const password = 'prueba-123456';
    final adminClient = SupabaseClient(env['SUPABASE_URL']!, env['SUPABASE_ANON_KEY']!);
    final guestClient = SupabaseClient(env['SUPABASE_URL']!, env['SUPABASE_ANON_KEY']!);
    addTearDown(() async {
      await adminClient.dispose();
      await guestClient.dispose();
    });
    final admin = ChatRepository(adminClient);
    final guest = ChatRepository(guestClient);
    await admin.signIn(env['CHAT_EMAIL']!, env['CHAT_PASSWORD']!);

    // El administrador crea la cuenta (nombre + contraseña, sin correo) y recibe el código de 6 dígitos.
    final issued = await admin.createAccount(username: username, password: password, role: Role.intern);
    expect(issued.code, matches(RegExp(r'^\d{6}$')));
    final created = (await admin.listPresence()).firstWhere((e) => e.username == username);
    addTearDown(() => admin.removeAccount(created.id));
    expect(created.verified, isFalse);
    expect(created.codePending, isTrue);

    // El visitante entra solo con su nombre y contraseña, pero sin verificar no puede abrir el chat privado.
    await guest.signIn(username, password);
    final me = await guest.myProfile();
    expect(me!.role, Role.intern);
    expect(me.verified, isFalse);
    await expectLater(guest.openThread(admin.userId!), throwsA(isA<ChatException>()));

    // Un código malo no sirve; el bueno, sí.
    await expectLater(guest.claimAccount(issued.code == '000000' ? '000001' : '000000'), throwsA(isA<ChatException>()));
    await guest.claimAccount(issued.code);
    expect((await guest.myProfile())!.verified, isTrue);
    expect((await guest.directory()).map((p) => p.id), contains(admin.userId));

    // No puede crear cuentas ni ver a los demás.
    await expectLater(guestClient.rpc('list_presence'), throwsA(anything));
    await expectLater(guest.createAccount(username: 'x$stamp', password: password, role: Role.intern), throwsA(isA<ChatException>()));

    // Está en línea para el administrador.
    await guest.touchPresence();
    expect((await admin.listPresence()).firstWhere((e) => e.username == username).online, isTrue);
    await guest.signOut();
  }, skip: live && signup ? false : 'define KYORA_LIVE=1 y KYORA_LIVE_SIGNUP=1 (crea y borra una cuenta de prueba; antes despliega admin-users y ejecuta schema.sql)');
}
