import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/data/chat_backend.dart';
import 'package:kyora_chat/models/message.dart';
import 'package:kyora_chat/state/chat_controller.dart';

import 'fake_backend.dart';

Future<void> waitFor(bool Function() condition, {Duration timeout = const Duration(seconds: 3)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('no llegó a tiempo');
}

ChatController make(FakeBackend backend, {int pageSize = 50, int? maxFileBytes}) => ChatController(
      backend,
      retryDelay: const Duration(milliseconds: 20),
      catchUpDelay: const Duration(milliseconds: 10),
      pageSize: pageSize,
      maxFileBytes: maxFileBytes ?? 50 * 1000 * 1000,
    );

Message byId(ChatController c, String id) => c.messages.firstWhere((m) => m.id == id);

void main() {
  late Directory temp;
  final controllers = <ChatController>[];

  ChatController started(FakeBackend backend, {int pageSize = 50, int? maxFileBytes}) {
    final controller = make(backend, pageSize: pageSize, maxFileBytes: maxFileBytes);
    controllers.add(controller);
    return controller;
  }

  setUp(() => temp = Directory.systemTemp.createTempSync('kyora_chat_test_'));
  tearDown(() {
    for (final c in controllers) {
      c.dispose();
    }
    controllers.clear();
    temp.deleteSync(recursive: true);
  });

  test('al empezar carga el historial ordenado, se conecta y escucha', () async {
    final backend = FakeBackend()
      ..add('b', body: 'segundo', sentAt: DateTime.utc(2026, 10, 30, 10, 0, 2))
      ..add('a', body: 'primero', sentAt: DateTime.utc(2026, 10, 30, 10, 0, 1));
    final controller = started(backend);
    expect(controller.connection, Connection.connecting);
    await controller.start();
    expect([for (final m in controller.messages) m.body], ['primero', 'segundo']);
    expect(controller.connection, Connection.online);
    expect(controller.hasOlder, isFalse);
    expect(backend.calls, containsAllInOrder(['ensure', 'list', 'signals']));
  });

  test('un mensaje escrito sale «en espera» al instante y pasa a enviado con el mismo id', () async {
    final backend = FakeBackend();
    final controller = started(backend);
    await controller.start();
    final draft = controller.send(text: '  hola  ');
    expect(draft.state, SendState.pending);
    expect(draft.body, 'hola');
    expect(draft.device, 'movil');
    expect(controller.messages.single.state, SendState.pending);
    await waitFor(() => byId(controller, draft.id).state == SendState.sent);
    expect(backend.remote.keys, [draft.id]);
    expect(backend.remote[draft.id]!.device, 'movil');
    expect(controller.hasPending, isFalse);
  });

  test('sin conexión se queda en espera, avisa y sale solo al volver, sin duplicarse', () async {
    final backend = FakeBackend();
    final controller = started(backend);
    await controller.start();
    backend.offline = true;
    final draft = controller.send(text: 'sin red');
    await waitFor(() => controller.connection == Connection.offline);
    expect(byId(controller, draft.id).state, SendState.pending);
    expect(backend.remote, isEmpty);
    backend.offline = false;
    await waitFor(() => byId(controller, draft.id).state == SendState.sent);
    expect(backend.remote.length, 1);
    expect(controller.connection, Connection.online);
  });

  test('si el servidor lo guardó pero se perdió la respuesta, el reintento no lo duplica', () async {
    final backend = FakeBackend();
    final controller = started(backend);
    await controller.start();
    backend.loseReplyOnce = true;
    final draft = controller.send(text: 'una sola vez');
    await waitFor(() => byId(controller, draft.id).state == SendState.sent);
    expect(backend.remote.length, 1);
    expect(controller.messages.length, 1);
  });

  test('los mensajes salen en orden aunque se escriban varios seguidos', () async {
    final backend = FakeBackend();
    final controller = started(backend);
    await controller.start();
    final first = controller.send(text: 'uno');
    final second = controller.send(text: 'dos');
    await waitFor(() => !controller.hasPending);
    final sentCalls = backend.calls.where((c) => c.startsWith('send:')).toList();
    expect(sentCalls, ['send:${first.id}', 'send:${second.id}']);
  });

  test('un archivo se sube a Storage antes de enviar el mensaje, con la ruta de la PC', () async {
    final backend = FakeBackend();
    final controller = started(backend);
    await controller.start();
    final photo = File('${temp.path}${Platform.pathSeparator}Mi foto (1).jpg')..writeAsBytesSync([1, 2, 3, 4]);
    final draft = controller.send(text: 'mira', files: [OutgoingFile(path: photo.path, name: 'Mi foto (1).jpg', size: 4)]);
    expect(draft.kind, 'image');
    expect(draft.attachments.single.mimeType, 'image/jpeg');
    await waitFor(() => byId(controller, draft.id).state == SendState.sent);
    final path = 'user-1/conv-1/${draft.id}/Mi_foto_1_.jpg';
    expect(backend.uploads[path], [1, 2, 3, 4]);
    expect(backend.calls.indexOf('upload:$path'), lessThan(backend.calls.indexOf('send:${draft.id}')));
    final sent = byId(controller, draft.id);
    expect(sent.attachments.single.storagePath, path);
    expect(sent.attachments.single.localPath, photo.path); // se conserva: no hace falta volver a bajarla
  });

  test('un archivo demasiado grande se rechaza al momento y no crea nada', () async {
    final controller = started(FakeBackend(), maxFileBytes: 10);
    await controller.start();
    expect(
      () => controller.send(files: [OutgoingFile(path: 'x', name: 'grande.bin', size: 11)]),
      throwsA(isA<ChatException>().having((e) => e.code, 'code', 'too_big')),
    );
    expect(() => controller.send(text: '   '), throwsA(isA<ChatException>()));
    expect(controller.messages, isEmpty);
  });

  test('si el archivo no está, el mensaje queda con su error y se puede reintentar', () async {
    final backend = FakeBackend();
    final controller = started(backend);
    await controller.start();
    final doc = File('${temp.path}${Platform.pathSeparator}doc.txt'); // aún no existe (se borró o se movió)
    final draft = controller.send(files: [OutgoingFile(path: doc.path, name: 'doc.txt', size: 4)]);
    await waitFor(() => byId(controller, draft.id).state != SendState.pending);
    final failed = byId(controller, draft.id);
    expect(failed.state, SendState.failed);
    expect(failed.error, contains('doc.txt'));
    expect(backend.remote, isEmpty);
    doc.writeAsStringSync('hola otra vez');
    controller.retry(draft.id);
    await waitFor(() => byId(controller, draft.id).state == SendState.sent);
    expect(backend.uploads.values.single, 'hola otra vez'.codeUnits);
  });

  test('un error sin remedio marca el mensaje y sigue con el siguiente', () async {
    final backend = FakeBackend()..sendError = const ChatException('El mensaje está vacío.', code: 'empty_message');
    final controller = started(backend);
    await controller.start();
    final bad = controller.send(text: 'primero');
    final good = controller.send(text: 'segundo');
    await waitFor(() => byId(controller, good.id).state == SendState.sent);
    expect(byId(controller, bad.id).state, SendState.failed);
    expect(byId(controller, bad.id).error, 'El mensaje está vacío.');
    expect(backend.remote.keys, [good.id]);
  });

  test('lo que manda la PC llega por Realtime y se ve como ajeno', () async {
    final backend = FakeBackend();
    final controller = started(backend);
    await controller.start();
    backend.add('pc-1', body: 'hola desde la PC');
    backend.emit(const BackendSignal(SignalKind.changed));
    await waitFor(() => controller.messages.isNotEmpty);
    final incoming = controller.messages.single;
    expect(incoming.body, 'hola desde la PC');
    expect(incoming.device, 'pc');
    expect(incoming.device == controller.device, isFalse);
    // la puesta al día pide solo lo posterior a la última llegada
    backend.add('pc-2', body: 'otro');
    backend.emit(const BackendSignal(SignalKind.changed));
    await waitFor(() => controller.messages.length == 2);
    expect(backend.listCalls.last['after'], isNotNull);
  });

  test('al reconectar recupera lo que llegó mientras no había conexión', () async {
    final backend = FakeBackend();
    final controller = started(backend);
    await controller.start();
    backend.emit(const BackendSignal(SignalKind.disconnected));
    await waitFor(() => controller.connection == Connection.offline);
    backend.add('perdido', body: 'llegó sin que lo vieras');
    backend.emit(const BackendSignal(SignalKind.connected));
    await waitFor(() => controller.messages.length == 1);
    expect(controller.connection, Connection.online);
  });

  test('si arrancar falla por la red, se reintenta solo', () async {
    final backend = FakeBackend()..offline = true;
    backend.add('x', body: 'ya estaba');
    final controller = started(backend);
    await controller.start();
    expect(controller.connection, Connection.offline);
    expect(controller.messages, isEmpty);
    backend.offline = false;
    await waitFor(() => controller.connection == Connection.online);
    expect(controller.messages.single.body, 'ya estaba');
  });

  test('un error sin remedio al arrancar avisa y no reintenta', () async {
    final backend = _Broken();
    final controller = started(backend);
    final notices = <String>[];
    controller.notices.listen(notices.add);
    await controller.start();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(controller.connection, Connection.offline);
    expect(notices, ['Falta crear la base de datos: ejecuta supabase/schema.sql en Supabase.']);
    expect(backend.calls.where((c) => c == 'ensure').length, 1);
  });

  test('un mensaje borrado en la PC desaparece, y el borrado propio pide a Supabase borrarlo', () async {
    final backend = FakeBackend()
      ..add('a', body: 'uno')
      ..add('b', body: 'dos');
    final controller = started(backend);
    await controller.start();
    backend.deleted.add('a');
    backend.emit(const BackendSignal(SignalKind.deleted, 'a'));
    await waitFor(() => controller.messages.length == 1);
    await controller.delete('b');
    expect(controller.messages, isEmpty);
    expect(backend.deleted, containsAll(['a', 'b']));
  });

  test('si Supabase no deja borrar, el mensaje vuelve a aparecer y se avisa', () async {
    final backend = FakeBackend()..add('a', body: 'uno');
    final controller = started(backend);
    final notices = <String>[];
    controller.notices.listen(notices.add);
    await controller.start();
    backend.deleteError = const ChatException('No hay permiso', code: '42501');
    await controller.delete('a');
    expect(controller.messages.single.id, 'a');
    await waitFor(() => notices.isNotEmpty);
    expect(notices.single, contains('No hay permiso'));
  });

  test('borrar un mensaje que aún no salió lo quita sin tocar Supabase', () async {
    final backend = FakeBackend();
    final controller = started(backend);
    await controller.start();
    backend.offline = true;
    final draft = controller.send(text: 'cancelado');
    await controller.delete(draft.id);
    backend.offline = false;
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(controller.messages, isEmpty);
    expect(backend.remote, isEmpty);
    expect(backend.calls.where((c) => c.startsWith('delete:')), isEmpty);
  });

  test('al subir carga los mensajes anteriores y sabe cuándo ya no hay más', () async {
    final backend = FakeBackend();
    for (var i = 0; i < 5; i++) {
      backend.add('m$i', body: 'mensaje $i', sentAt: DateTime.utc(2026, 10, 30, 10, 0, i));
    }
    final controller = started(backend, pageSize: 3);
    await controller.start();
    expect([for (final m in controller.messages) m.body], ['mensaje 2', 'mensaje 3', 'mensaje 4']);
    expect(controller.hasOlder, isTrue);
    await controller.loadOlder();
    expect(controller.messages.length, 5);
    expect(controller.messages.first.body, 'mensaje 0');
    expect(controller.hasOlder, isFalse);
    final calls = backend.calls.length;
    await controller.loadOlder(); // ya no hay más: no pide nada
    expect(backend.calls.length, calls);
  });

  test('la dirección temporal de un archivo se pide una sola vez', () async {
    final backend = FakeBackend();
    final controller = started(backend);
    const att = Attachment(id: 'a', fileName: 'f.pdf', mimeType: 'application/pdf', sizeBytes: 1, storagePath: 'u/c/m/f.pdf');
    expect(await controller.urlFor(att), 'https://files.test/u/c/m/f.pdf');
    await controller.urlFor(att);
    expect(backend.calls.where((c) => c.startsWith('url:')).length, 1);
    await expectLater(
      controller.urlFor(const Attachment(id: 'b', fileName: 'x', mimeType: 'x/y', sizeBytes: 1)),
      throwsA(isA<ChatException>()),
    );
  });
}

/// Un servidor al que le falta el script SQL (la función no existe): un error sin remedio.
class _Broken extends FakeBackend {
  @override
  Future<String> ensureConversation() async {
    calls.add('ensure');
    throw const ChatException('Falta crear la base de datos: ejecuta supabase/schema.sql en Supabase.', code: 'PGRST202');
  }
}
