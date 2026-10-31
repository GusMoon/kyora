// Prueba en vivo contra TU Supabase, con el mismo `ChatRepository` que usa la app del móvil. No corre sola: hace falta
//   set KYORA_LIVE=1 && flutter test test/live_test.dart       (en PowerShell: $env:KYORA_LIVE='1')
// Lee la URL, la clave pública, el correo y la contraseña de ../supabase/.env en el momento (no los guarda en ningún sitio).
// Escribe un mensaje propio con un archivo de prueba y lo borra al final (borrado suave).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/data/chat_backend.dart';
import 'package:kyora_chat/data/chat_repository.dart';
import 'package:kyora_chat/models/message.dart';
import 'package:kyora_chat/util/format.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

Map<String, String> readEnv() {
  final file = File('../supabase/.env');
  final values = <String, String>{};
  for (final raw in file.readAsLinesSync()) {
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
  // KYORA_LIVE_KEEP=1: deja el mensaje de prueba sin borrar (para comprobar desde la PC que lo ve).
  final keep = Platform.environment['KYORA_LIVE_KEEP'] == '1';

  test('PC → Supabase → código del móvil → Supabase', () async {
    final env = readEnv();
    final client = SupabaseClient(env['SUPABASE_URL']!, env['SUPABASE_ANON_KEY']!);
    final repo = ChatRepository(client);
    addTearDown(() async {
      await client.dispose();
    });

    // 1. Entrar con la cuenta de la PC.
    await repo.signIn(env['CHAT_EMAIL']!, env['CHAT_PASSWORD']!);
    expect(repo.signedIn, isTrue);
    expect(repo.userId, isNotNull);

    // 2. La conversación y lo que mandó la PC.
    final conversation = await repo.ensureConversation();
    expect(conversation, hasLength(36));
    final history = await repo.listMessages(conversation, limit: 50);
    final fromPc = history.where((m) => m.device == (env['CHAT_DEVICE'] ?? 'pc') && m.hasText).toList();
    expect(fromPc, isNotEmpty, reason: 'la PC no ha mandado ningún mensaje: ejecuta scripts\\probar_chat.bat --send');
    // ignore: avoid_print
    print('Mensaje de la PC leído por el móvil: «${fromPc.last.body}» (${fromPc.last.sentAt.toIso8601String()})');
    expect(fromPc.last.state, SendState.sent);

    // 3. Realtime: escuchar y mandar un mensaje propio.
    final signals = <BackendSignal>[];
    final subscription = repo.signals(conversation).listen(signals.add);
    addTearDown(subscription.cancel);
    await _until(() => signals.any((s) => s.kind == SignalKind.connected), 'Realtime no se conectó');

    // 4. Enviar desde el móvil: subir un archivo y llamar a send_message (como hace la app).
    final id = const Uuid().v4();
    final payload = utf8.encode('Archivo de prueba del móvil ${DateTime.now().toIso8601String()}');
    final path = '${repo.userId}/$conversation/$id/${safeName('prueba móvil.txt')}';
    await repo.upload(path, Uint8List.fromList(payload), 'text/plain');
    final sent = await repo.sendMessage(
      id: id,
      conversationId: conversation,
      sentAt: DateTime.now(),
      device: 'movil',
      body: 'Prueba desde el móvil (test automático)',
      attachments: [
        Attachment(id: 'x', fileName: 'prueba móvil.txt', mimeType: 'text/plain', sizeBytes: payload.length, storagePath: path, uploaded: true),
      ],
    );
    addTearDown(() async {
      if (keep) return;
      try {
        await repo.deleteMessage(id);
      } catch (_) {}
    });
    expect(sent.id, id);
    expect(sent.state, SendState.sent);
    expect(sent.device, 'movil');
    expect(sent.kind, 'file');
    expect(sent.attachments.single.storagePath, path);

    // reintentar el mismo envío no duplica (idempotente)
    final again = await repo.sendMessage(id: id, conversationId: conversation, sentAt: DateTime.now(), device: 'movil', body: 'otro texto');
    expect(again.body, 'Prueba desde el móvil (test automático)');

    // 5. Realtime avisó del mensaje nuevo, y la puesta al día lo trae.
    await _until(() => signals.any((s) => s.kind == SignalKind.changed), 'Realtime no avisó del mensaje nuevo');
    final caught = await repo.listMessages(conversation, after: sent.createdAt!.subtract(const Duration(milliseconds: 1)), limit: 50);
    expect(caught.map((m) => m.id), contains(id));

    // 6. Bajar el archivo con una dirección temporal.
    final url = await repo.signedUrl(path);
    final http = HttpClient();
    final response = await (await http.getUrl(Uri.parse(url))).close();
    final bytes = await response.expand((chunk) => chunk).toList();
    http.close();
    expect(response.statusCode, 200);
    expect(bytes, payload);

    // 7. Borrar (la PC deja de verlo) y salir.
    if (!keep) {
      await repo.deleteMessage(id);
      final after = await repo.listMessages(conversation, limit: 50);
      expect(after.map((m) => m.id), isNot(contains(id)));
      await _until(() => signals.any((s) => s.kind == SignalKind.deleted && s.messageId == id), 'Realtime no avisó del borrado');
    }
    await repo.signOut();
    expect(repo.signedIn, isFalse);
  }, skip: live ? false : 'Pon KYORA_LIVE=1 para probar contra tu Supabase real.', timeout: const Timeout(Duration(seconds: 90)));
}

Future<void> _until(bool Function() condition, String message, {Duration timeout = const Duration(seconds: 20)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  fail(message);
}
