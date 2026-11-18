import 'dart:convert';
import 'dart:math' as math;

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/data/chat_backend.dart';
import 'package:kyora_chat/data/password_vault.dart';
import 'package:kyora_chat/state/passwords_controller.dart';

/// La bóveda en memoria, como si fuera Supabase.
class FakePasswordBackend implements PasswordBackend {
  VaultMeta? meta;
  final Map<String, VaultEntryRow> rows = {};
  final Map<String, DateTime> deleted = {};
  ChatException? failWith;
  int metaCreates = 0;

  @override
  Future<VaultMeta?> loadMeta() async {
    if (failWith != null) throw failWith!;
    return meta;
  }

  @override
  Future<void> createMeta(VaultMeta value) async {
    metaCreates++;
    if (meta != null) throw const ChatException('duplicate key', code: '23505');
    meta = value;
  }

  @override
  Future<List<VaultEntryRow>> loadRows() async => [for (final r in rows.values) if (!deleted.containsKey(r.id)) r];

  @override
  Future<void> saveRow(VaultEntryRow row) async {
    if (failWith != null) throw failWith!;
    rows[row.id] = row;
  }

  @override
  Future<void> deleteRow(String id, DateTime at) async => deleted[id] = at;
}

/// Un vector generado con **el mismo código de Merida** (`vault/crypto.ts`, Web Crypto de Node) con 1 000 vueltas: lo que cifra la web se tiene
/// que abrir aquí y lo que cifra Kyra tiene que quedar byte a byte igual.
const _password = 'Contraseñá-ﬁnal Ⅻ'; // «ñ», una «a» + acento combinado, una ligadura y un numeral romano: NFKC los normaliza
const _saltBase64 = 'AQIDBAUGBwgJCgsMDQ4PEA==';
const _ivBase64 = 'ZGVmZ2hpamtsbW5v';
const _rounds = 1000;
const _verifier = 'v1.ZGVmZ2hpamtsbW5vrlT3ZF/1I4fTSzdQ7xG6YEEsHBYnQmNQESMXbTd+';
const _rowId = '11111111-2222-3333-4444-555555555555';
const _secret =
    '{"service":"Correo","email":"yo@ejemplo.com","username":"yo","password":"p@ss-ñandú-€","url":"https://correo.example","notes":"línea 1\\nlínea 2"}';
const _payload =
    'v1.ZGVmZ2hpamtsbW5vvg/rc0yuPIXDBXlf2k9txZzzMovl4DtExrqvUN24+gd+ddDzvjnCkvdYiSoqspXpJvzn16udkk8EwOVB1vureoJkR/Io1z6UQ7QKlgXMehfR9oEJf4/OBt4xOz72UBM9L52UmPAI40eilqkDrBwADd6QQx64SGdQIZ0BKEN/IV08yhLLWdBdTZmOie8iEWGDcM4iB1ZGcmzs/+NgQinTBrPCXG8fge4=';

void main() {
  group('el cifrado es el de Merida', () {
    late SecretKey key;

    setUp(() async {
      key = await VaultCrypto.deriveKey(_password, base64.decode(_saltBase64), rounds: _rounds);
    });

    test('abre la prueba y una entrada cifradas por Merida', () async {
      expect(await VaultCrypto.checkVerifier(key, _verifier), isTrue);
      expect(await VaultCrypto.decryptText(key, _payload, aad: _rowId), _secret);
    });

    test('lo que cifra Kyra con el mismo IV queda byte a byte igual al de Merida', () async {
      final iv = base64.decode(_ivBase64);
      expect(await VaultCrypto.makeVerifier(key, iv: iv), _verifier);
      expect(await VaultCrypto.encryptText(key, _secret, aad: _rowId, iv: iv), _payload);
    });

    test('la contraseña maestra se normaliza (NFKC): escrita de otra forma abre igual', () async {
      final composed = await VaultCrypto.deriveKey('Contraseñá-final XII', base64.decode(_saltBase64), rounds: _rounds);
      expect(await VaultCrypto.checkVerifier(composed, _verifier), isTrue);
    });

    test('una clave equivocada, otro id (AAD) o un byte cambiado no descifran', () async {
      final wrong = await VaultCrypto.deriveKey('otra-contraseña-maestra', base64.decode(_saltBase64), rounds: _rounds);
      expect(await VaultCrypto.checkVerifier(wrong, _verifier), isFalse);
      await expectLater(VaultCrypto.decryptText(key, _payload, aad: 'otro-id'), throwsA(anything));
      final bytes = base64.decode(_payload.substring(3));
      bytes[20] ^= 1;
      await expectLater(VaultCrypto.decryptText(key, 'v1.${base64.encode(bytes)}', aad: _rowId), throwsA(anything));
    });

    test('un formato desconocido o incompleto se rechaza con un aviso claro', () async {
      await expectLater(VaultCrypto.decryptText(key, 'v2.abc'), throwsA(isA<VaultFormatException>()));
      await expectLater(VaultCrypto.decryptText(key, 'v1.AAAA'), throwsA(isA<VaultFormatException>()));
      await expectLater(VaultCrypto.decryptText(key, 'v1.###'), throwsA(isA<VaultFormatException>()));
    });
  });

  group('el generador y la fuerza', () {
    test('lleva al menos un carácter de cada tipo, sin los que se confunden, y mide lo pedido', () {
      final random = math.Random(7);
      for (var i = 0; i < 40; i++) {
        final pw = VaultCrypto.generatePassword(length: 12, random: random);
        expect(pw, hasLength(12));
        expect(pw.split('').any(VaultCrypto.lowerSet.contains), isTrue);
        expect(pw.split('').any(VaultCrypto.upperSet.contains), isTrue);
        expect(pw.split('').any(VaultCrypto.digitSet.contains), isTrue);
        expect(pw.split('').any(VaultCrypto.symbolSet.contains), isTrue);
        expect(RegExp('[loIO01]').hasMatch(pw), isFalse);
      }
      expect(VaultCrypto.generatePassword(), hasLength(20));
      expect(VaultCrypto.generatePassword(length: 500), hasLength(128));
      expect(VaultCrypto.generatePassword(length: 1), hasLength(4)); // al menos uno de cada tipo
    });

    test('sin símbolos ni dígitos solo hay letras, y sin ningún tipo no hay contraseña', () {
      final pw = VaultCrypto.generatePassword(length: 30, digits: false, symbols: false, random: math.Random(1));
      expect(RegExp(r'^[A-Za-z]+$').hasMatch(pw), isTrue);
      expect(VaultCrypto.generatePassword(lower: false, upper: false, digits: false, symbols: false), isEmpty);
    });

    test('la fuerza va de 0 a 4 con los mismos umbrales que Merida', () {
      expect(VaultCrypto.strength(''), 0);
      expect(VaultCrypto.strength('abc'), 0);
      expect(VaultCrypto.strength('abcdefgh'), 1); // 8 × 4.7 = 37 bits
      expect(VaultCrypto.strength('Abcdefgh1'), 2); // 9 × 5,95 = 53,6 bits
      expect(VaultCrypto.strength(VaultCrypto.generatePassword(length: 24)), 4);
    });
  });

  group('la sesión de la bóveda', () {
    late FakePasswordBackend backend;
    late PasswordsController vault;
    late DateTime clock;
    var n = 0;
    String? clipboard;

    PasswordsController build({Duration idle = const Duration(minutes: 5), Duration clipboardTime = const Duration(seconds: 30)}) => PasswordsController(
      backend,
      rounds: 1000,
      idle: idle,
      clipboardTime: clipboardTime,
      now: () => clock,
      newId: () => 'id${++n}',
      writeClipboard: (text) async => clipboard = text,
      readClipboard: () async => clipboard,
    );

    setUp(() {
      backend = FakePasswordBackend();
      clock = DateTime.utc(2026, 11, 14, 12);
      clipboard = null;
      n = 0;
      vault = build();
    });

    tearDown(() => vault.dispose());

    test('sin bóveda: pide crearla; la contraseña maestra corta no vale', () async {
      await vault.refresh();
      expect(vault.state, VaultState.none);
      await expectLater(vault.create('corta'), throwsA(isA<VaultException>()));
      expect(backend.meta, isNull);
    });

    test('crear la bóveda guarda la sal y la prueba (nunca la contraseña) y la deja abierta', () async {
      await vault.refresh();
      await vault.create('una-contraseña-larga!');
      expect(vault.state, VaultState.unlocked);
      expect(backend.meta!.kdfIter, 1000);
      expect(backend.meta!.verifier, startsWith('v1.'));
      expect(base64.decode(backend.meta!.salt), hasLength(16));
      expect(jsonEncode(backend.meta!.toJson()), isNot(contains('una-contraseña-larga')));
    });

    test('añadir una entrada la guarda cifrada (con su id como AAD) y solo la contraseña maestra la abre', () async {
      await vault.refresh();
      await vault.create('una-contraseña-larga!');
      final item = await vault.add(service: ' Banco ', email: 'yo@ejemplo.com', password: 'secreto-123', notes: 'ojo');
      expect(item!.service, 'Banco');
      final row = backend.rows[item.id]!;
      expect(row.payload, startsWith('v1.'));
      expect(row.payload, isNot(contains('secreto')));
      expect(row.payload, isNot(contains('Banco')));
      // otra sesión (otro dispositivo, o Merida): se abre con la misma maestra
      final other = build();
      addTearDown(other.dispose);
      await other.refresh();
      expect(other.state, VaultState.locked);
      expect(await other.unlock('otra-contraseña-larga'), isFalse);
      expect(other.state, VaultState.locked);
      expect(await other.unlock('una-contraseña-larga!'), isTrue);
      expect(other.items.single.service, 'Banco');
      expect(other.items.single.password, 'secreto-123');
      expect(other.items.single.notes, 'ojo');
    });

    test('sin servicio, o sin correo, usuario ni contraseña, no se crea nada', () async {
      await vault.refresh();
      await vault.create('una-contraseña-larga!');
      expect(await vault.add(service: ' ', password: 'x'), isNull);
      expect(await vault.add(service: 'Algo'), isNull);
      expect(backend.rows, isEmpty);
    });

    test('editar sube una hora de cambio siempre mayor y borrar es suave', () async {
      await vault.refresh();
      await vault.create('una-contraseña-larga!');
      final item = (await vault.add(service: 'Correo', email: 'a@b.c'))!;
      await vault.update(item, service: 'Correo 2', password: 'nueva');
      expect(vault.items.single.service, 'Correo 2');
      expect(backend.rows[item.id]!.updatedAt.isAfter(item.updatedAt), isTrue); // la hora no cambió y aun así sube
      await vault.remove(vault.items.single);
      expect(vault.items, isEmpty);
      expect(backend.deleted.containsKey(item.id), isTrue);
      expect(backend.rows.containsKey(item.id), isTrue); // la fila sigue en el servidor, solo marcada
    });

    test('si no se puede subir, la entrada no se pone en la lista', () async {
      await vault.refresh();
      await vault.create('una-contraseña-larga!');
      backend.failWith = const ChatException('Sin conexión con Supabase', retryable: true, code: 'offline');
      await expectLater(vault.add(service: 'Correo', email: 'a@b.c'), throwsA(isA<ChatException>()));
      expect(vault.items, isEmpty);
    });

    test('la búsqueda mira servicio, correo, usuario y URL, nunca la contraseña ni las notas', () async {
      await vault.refresh();
      await vault.create('una-contraseña-larga!');
      await vault.add(service: 'Zeta', email: 'zeta@x.com', password: 'clave-unica');
      await vault.add(service: 'Alfa', username: 'beto', url: 'https://alfa.example', notes: 'nota-secreta');
      expect(vault.search('').map((i) => i.service), ['Alfa', 'Zeta']); // por servicio
      expect(vault.search('ZETA@').map((i) => i.service), ['Zeta']);
      expect(vault.search('beto').map((i) => i.service), ['Alfa']);
      expect(vault.search('alfa.example').map((i) => i.service), ['Alfa']);
      expect(vault.search('clave-unica'), isEmpty);
      expect(vault.search('nota-secreta'), isEmpty);
    });

    test('bloquear suelta la clave y lo descifrado; abrirla otra vez pide la maestra', () async {
      await vault.refresh();
      await vault.create('una-contraseña-larga!');
      await vault.add(service: 'Correo', email: 'a@b.c');
      vault.lock();
      expect(vault.state, VaultState.locked);
      expect(vault.items, isEmpty);
      await expectLater(vault.add(service: 'Otro', email: 'x@y.z'), throwsA(isA<VaultException>()));
      expect(await vault.unlock('una-contraseña-larga!'), isTrue);
      expect(vault.items.single.service, 'Correo');
    });

    test('se bloquea sola tras el tiempo sin tocarla, y tocarla reinicia el reloj', () async {
      final quick = build(idle: const Duration(milliseconds: 120));
      addTearDown(quick.dispose);
      await quick.refresh();
      await quick.create('una-contraseña-larga!');
      await Future<void>.delayed(const Duration(milliseconds: 80));
      quick.touch();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(quick.state, VaultState.unlocked); // el toque reinició el reloj
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(quick.state, VaultState.locked);
      expect(quick.items, isEmpty);
    });

    test('las entradas que no se pueden descifrar se cuentan aparte, sin perderlas ni enseñarlas', () async {
      await vault.refresh();
      await vault.create('una-contraseña-larga!');
      await vault.add(service: 'Bien', email: 'a@b.c');
      backend.rows['roto'] = VaultEntryRow(id: 'roto', payload: 'v1.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA', createdAt: clock, updatedAt: clock);
      final other = build();
      addTearDown(other.dispose);
      await other.refresh();
      expect(await other.unlock('una-contraseña-larga!'), isTrue);
      expect(other.items.map((i) => i.service), ['Bien']);
      expect(other.broken, 1);
      expect(backend.rows.containsKey('roto'), isTrue);
    });

    test('si otra sesión ya creó la bóveda, se avisa y se pasa a pedir su maestra', () async {
      final other = build();
      addTearDown(other.dispose);
      await other.refresh();
      await vault.refresh(); // las dos ven «sin bóveda»
      await vault.create('una-contraseña-larga!');
      await expectLater(other.create('otra-contraseña-larga'), throwsA(isA<VaultException>()));
      expect(other.state, VaultState.locked);
    });

    test('un fallo al leer se explica y se puede reintentar', () async {
      backend.failWith = const ChatException('Sin conexión con Supabase', retryable: true, code: 'offline');
      await vault.refresh();
      expect(vault.state, VaultState.error);
      expect(vault.error, 'Sin conexión con Supabase');
      backend.failWith = null;
      await vault.refresh();
      expect(vault.state, VaultState.none);
    });

    test('lo copiado se borra del portapapeles a los 30 s, pero solo si sigue siendo eso', () async {
      final quick = build(clipboardTime: const Duration(milliseconds: 60));
      addTearDown(quick.dispose);
      await quick.copy('secreto');
      expect(clipboard, 'secreto');
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(clipboard, ''); // se borró
      await quick.copy('uno');
      clipboard = 'otra cosa que copió la persona';
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(clipboard, 'otra cosa que copió la persona'); // no se pisa lo que no era
    });
  });
}
