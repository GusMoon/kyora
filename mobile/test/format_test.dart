import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/models/message.dart';
import 'package:kyora_chat/util/format.dart';

void main() {
  test('safeName es la misma regla que la PC (kyora/chat/service.py::safe_name)', () {
    expect(safeName('Mi foto (1).jpg'), 'Mi_foto_1_.jpg');
    expect(safeName('???'), 'archivo');
    expect(safeName('..oculto.txt'), 'oculto.txt');
    expect(safeName('informe final.pdf'), 'informe_final.pdf');
    expect(safeName('a' * 200).length, 120);
    expect(safeName('Presupuesto octubre 2026 (final).pdf'), 'Presupuesto_octubre_2026_final_.pdf');
  });

  test('humanSize usa base 1024, un decimal y coma, como la PC', () {
    expect(humanSize(0), '0 B');
    expect(humanSize(512), '512 B');
    expect(humanSize(1536), '1,5 KB');
    expect(humanSize(2400000), '2,3 MB');
    expect(humanSize(50 * 1000 * 1000), '47,7 MB');
    expect(humanSize(3 * 1024 * 1024 * 1024), '3,0 GB');
  });

  test('shortDate escribe «Mes Día, año» con el mes en mayúscula', () {
    expect(shortDate(DateTime(2026, 11, 3)), 'Noviembre 3, 2026');
    expect(shortDate(DateTime(2027, 1, 1)), 'Enero 1, 2027');
    expect(shortDate(DateTime(2026, 12, 31, 23, 59)), 'Diciembre 31, 2026');
  });

  test('greetingFor: días hasta las 11:59, tardes hasta las 18:59 y noches el resto', () {
    expect(greetingFor(DateTime(2026, 11, 3, 5, 0)), 'Buenos días');
    expect(greetingFor(DateTime(2026, 11, 3, 11, 59)), 'Buenos días');
    expect(greetingFor(DateTime(2026, 11, 3, 12, 0)), 'Buenas tardes');
    expect(greetingFor(DateTime(2026, 11, 3, 18, 59)), 'Buenas tardes');
    expect(greetingFor(DateTime(2026, 11, 3, 19, 0)), 'Buenas noches');
    expect(greetingFor(DateTime(2026, 11, 3, 0, 0)), 'Buenas noches');
    expect(greetingFor(DateTime(2026, 11, 3, 4, 59)), 'Buenas noches');
  });

  test('weekdayLetters va de lunes a domingo: L M M J V S D', () {
    expect(weekdayLetters, ['L', 'M', 'M', 'J', 'V', 'S', 'D']);
    expect(weekdayLetters[DateTime(2026, 11, 3).weekday - 1], 'M'); // martes
    expect(weekdayLetters[DateTime(2026, 11, 8).weekday - 1], 'D'); // domingo
  });

  test('dayLabel dice Hoy, Ayer o la fecha (con año si no es el actual)', () {
    final now = DateTime(2026, 10, 30, 12);
    expect(dayLabel(DateTime(2026, 10, 30, 1), now: now), 'Hoy');
    expect(dayLabel(DateTime(2026, 10, 29, 23), now: now), 'Ayer');
    expect(dayLabel(DateTime(2026, 10, 3), now: now), '3 de octubre');
    expect(dayLabel(DateTime(2025, 12, 24), now: now), '24 de diciembre de 2025');
  });

  test('clockText enseña la hora local con dos dígitos', () {
    expect(clockText(DateTime(2026, 10, 30, 9, 5)), '09:05');
    expect(clockText(DateTime.utc(2026, 10, 30, 14, 30)), clockText(DateTime.utc(2026, 10, 30, 14, 30).toLocal()));
  });

  test('sameDay compara el día en la hora local', () {
    expect(sameDay(DateTime(2026, 10, 30, 1), DateTime(2026, 10, 30, 23)), isTrue);
    expect(sameDay(DateTime(2026, 10, 30), DateTime(2026, 10, 31)), isFalse);
  });

  test('kindOfMime sigue la regla de send_message en el SQL', () {
    expect([for (final m in ['image/png', 'audio/mpeg', 'video/mp4', 'application/pdf', '', null]) kindOfMime(m)],
        ['image', 'audio', 'video', 'file', 'other', 'other']);
  });

  group('modelos', () {
    final json = <String, dynamic>{
      'id': 'm1',
      'conversation_id': 'c1',
      'owner_id': 'u1',
      'sender_device': 'pc',
      'kind': 'image',
      'body': 'mira',
      'status': 'sent',
      'sent_at': '2026-10-30T14:00:00.123456+00:00',
      'created_at': '2026-10-30T14:00:01.5+00:00',
      'edited_at': null,
      'deleted_at': null,
      'metadata': <String, dynamic>{},
      'attachments': [
        {
          'id': 'a1',
          'message_id': 'm1',
          'storage_path': 'u1/c1/m1/foto.png',
          'file_name': 'foto.png',
          'mime_type': 'image/png',
          'size_bytes': 482113,
          'width': 900,
          'height': 600,
          'duration_ms': null,
          'thumb_path': null,
        },
      ],
    };

    test('Message.fromJson lee el formato de message_json', () {
      final message = Message.fromJson(json);
      expect(message.id, 'm1');
      expect(message.device, 'pc');
      expect(message.body, 'mira');
      expect(message.state, SendState.sent);
      expect(message.sentAt, DateTime.utc(2026, 10, 30, 14, 0, 0, 123, 456));
      expect(message.createdAt, DateTime.utc(2026, 10, 30, 14, 0, 1, 500));
      expect(message.attachments.single.isImage, isTrue);
      expect(message.attachments.single.storagePath, 'u1/c1/m1/foto.png');
      expect(message.attachments.single.uploaded, isTrue);
      expect(message.attachments.single.width, 900);
    });

    test('un mensaje solo con adjuntos no tiene texto y un status pending sigue en espera', () {
      final message = Message.fromJson({...json, 'body': null, 'status': 'pending'});
      expect(message.hasText, isFalse);
      expect(message.state, SendState.pending);
    });

    test('Message.draft nace en espera, con la clase según su primer adjunto', () {
      final draft = Message.draft(
        id: 'x',
        conversationId: 'c',
        device: 'movil',
        sentAt: DateTime(2026, 10, 30, 9),
        body: '  hola  ',
        attachments: const [Attachment(id: 'a', fileName: 'f.pdf', mimeType: 'application/pdf', sizeBytes: 3)],
      );
      expect(draft.state, SendState.pending);
      expect(draft.kind, 'file');
      expect(draft.body, 'hola');
      expect(draft.sentAt.isUtc, isTrue);
      expect(Message.draft(id: 'y', conversationId: '', device: 'movil', sentAt: DateTime.now(), body: '   ').body, isNull);
    });

    test('Attachment.toRpc manda los campos que espera send_message', () {
      const att = Attachment(
          id: 'a', fileName: 'foto.png', mimeType: 'image/png', sizeBytes: 9, storagePath: 'u/c/m/foto.png', width: 3, height: 4);
      expect(att.toRpc(), {
        'storage_path': 'u/c/m/foto.png',
        'file_name': 'foto.png',
        'mime_type': 'image/png',
        'size_bytes': 9,
        'width': 3,
        'height': 4,
        'duration_ms': null,
        'thumb_path': null,
      });
    });
  });
}
