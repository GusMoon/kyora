import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;

/// Cifrado de la bóveda de contraseñas, **idéntico byte a byte al de Merida** (`Family/Merida/src/vault/crypto.ts`): lo que se guarda aquí se
/// abre allí con la misma contraseña maestra, y al revés.
///
///  - La clave sale de la contraseña maestra (normalizada NFKC) con PBKDF2-SHA-256 (600 000 vueltas) y una sal aleatoria de 16 bytes propia del
///    usuario.
///  - Cada texto se cifra con AES-GCM de 256 bits y un IV aleatorio de 12 bytes. Se usa el id de la fila como «datos asociados» (AAD): una entrada
///    copiada a la fila de otra no se puede descifrar.
///  - Formato guardado: «v1.» + base64(IV ‖ texto cifrado ‖ etiqueta de 16 bytes).
class VaultCrypto {
  const VaultCrypto._();

  static const iterations = 600000;
  static const prefix = 'v1.';
  static const verifierText = 'kyora-vault-v1';
  static const _ivLength = 12;
  static const _macLength = 16;

  static final _random = math.Random.secure();

  static Uint8List randomBytes(int n) => Uint8List.fromList(List<int>.generate(n, (_) => _random.nextInt(256)));

  /// La clave AES-GCM derivada de la contraseña maestra. Lenta a propósito (frena a quien pruebe contraseñas).
  static Future<SecretKey> deriveKey(String password, List<int> salt, {int rounds = iterations}) {
    final pbkdf2 = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: rounds, bits: 256);
    return pbkdf2.deriveKey(secretKey: SecretKey(utf8.encode(unorm.nfkc(password))), nonce: salt);
  }

  static final _aes = AesGcm.with256bits();

  /// Cifra `plaintext`. `iv` solo se da en las pruebas (uno fijo); si no, uno nuevo al azar.
  static Future<String> encryptText(SecretKey key, String plaintext, {String aad = '', List<int>? iv}) async {
    final box = await _aes.encrypt(utf8.encode(plaintext), secretKey: key, nonce: iv ?? randomBytes(_ivLength), aad: utf8.encode(aad));
    return prefix + base64.encode(box.concatenation());
  }

  /// Descifra. Lanza [VaultFormatException] si el formato no es el de la bóveda y `SecretBoxAuthenticationError` si la clave no es la correcta, el
  /// texto se alteró o el `aad` no coincide.
  static Future<String> decryptText(SecretKey key, String token, {String aad = ''}) async {
    if (!token.startsWith(prefix)) throw const VaultFormatException('Formato de bóveda desconocido.');
    final Uint8List packed;
    try {
      packed = base64.decode(token.substring(prefix.length));
    } on FormatException {
      throw const VaultFormatException('Texto cifrado dañado.');
    }
    if (packed.length < _ivLength + 1) throw const VaultFormatException('Texto cifrado incompleto.');
    final box = SecretBox.fromConcatenation(packed, nonceLength: _ivLength, macLength: _macLength);
    return utf8.decode(await _aes.decrypt(box, secretKey: key, aad: utf8.encode(aad)));
  }

  /// La «prueba» que se guarda en `vault_meta`: un texto conocido cifrado. Si descifra bien, la contraseña maestra es la correcta.
  static Future<String> makeVerifier(SecretKey key, {List<int>? iv}) => encryptText(key, verifierText, aad: 'vault_meta', iv: iv);

  static Future<bool> checkVerifier(SecretKey key, String verifier) async {
    try {
      return await decryptText(key, verifier, aad: 'vault_meta') == verifierText;
    } catch (_) {
      return false;
    }
  }

  // ---------- generador y fuerza (los mismos que en Merida) ----------

  /// Sin `l` ni `o` (se confunden con 1 y 0), ni `I` ni `O`, ni `0` ni `1`.
  static const lowerSet = 'abcdefghijkmnpqrstuvwxyz';
  static const upperSet = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
  static const digitSet = '23456789';
  static const symbolSet = '!@#\$%^&*-_=+?';

  /// Un número al azar en [0, max) sin sesgo.
  static int _randomBelow(int max, math.Random random) {
    final limit = (0x100000000 ~/ max) * max;
    int v;
    do {
      v = random.nextInt(0x100000000);
    } while (v >= limit);
    return v % max;
  }

  /// Una contraseña al azar. Lleva al menos un carácter de cada tipo elegido; el largo va de la cantidad de tipos a 128.
  static String generatePassword({int length = 20, bool lower = true, bool upper = true, bool digits = true, bool symbols = true, math.Random? random}) {
    final r = random ?? _random;
    final groups = [if (lower) lowerSet, if (upper) upperSet, if (digits) digitSet, if (symbols) symbolSet];
    if (groups.isEmpty) return '';
    final size = math.min(128, math.max(groups.length, length));
    final all = groups.join();
    final chars = [for (final g in groups) g[_randomBelow(g.length, r)]];
    while (chars.length < size) {
      chars.add(all[_randomBelow(all.length, r)]);
    }
    for (var i = chars.length - 1; i > 0; i--) {
      final j = _randomBelow(i + 1, r);
      final t = chars[i];
      chars[i] = chars[j];
      chars[j] = t;
    }
    return chars.join();
  }

  /// Una estimación simple de la fuerza: 0 (muy débil) a 4 (fuerte).
  static int strength(String password) {
    if (password.isEmpty) return 0;
    var pool = 0;
    if (RegExp('[a-z]').hasMatch(password)) pool += 26;
    if (RegExp('[A-Z]').hasMatch(password)) pool += 26;
    if (RegExp(r'\d').hasMatch(password)) pool += 10;
    if (RegExp('[^A-Za-z0-9]').hasMatch(password)) pool += 20;
    final bits = password.length * (math.log(math.max(pool, 2)) / math.ln2);
    return bits < 28
        ? 0
        : bits < 45
        ? 1
        : bits < 60
        ? 2
        : bits < 80
        ? 3
        : 4;
  }
}

class VaultFormatException implements Exception {
  const VaultFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Una entrada de la bóveda, ya descifrada. En el servidor solo existe cifrada (`vault_entries.payload`).
class VaultItem {
  const VaultItem({
    required this.id,
    required this.service,
    required this.createdAt,
    required this.updatedAt,
    this.email = '',
    this.username = '',
    this.password = '',
    this.url = '',
    this.notes = '',
  });

  final String id;

  /// El nombre del servicio o de la aplicación.
  final String service;

  /// El correo con el que se entra.
  final String email;
  final String username;
  final String password;
  final String url;
  final String notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  VaultItem copyWith({String? service, String? email, String? username, String? password, String? url, String? notes, DateTime? updatedAt}) => VaultItem(
    id: id,
    service: (service ?? this.service).trim().isEmpty ? this.service : (service ?? this.service).trim(),
    email: email?.trim() ?? this.email,
    username: username?.trim() ?? this.username,
    password: password ?? this.password,
    url: url?.trim() ?? this.url,
    notes: notes ?? this.notes,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  /// Lo que va dentro del texto cifrado (el id y las fechas viven fuera, en claro, porque el servidor los necesita). Mismas claves que en Merida.
  Map<String, Object?> toSecret() => {'service': service, 'email': email, 'username': username, 'password': password, 'url': url, 'notes': notes};

  factory VaultItem.fromSecret(VaultEntryRow row, Map<String, Object?> secret) => VaultItem(
    id: row.id,
    service: (secret['service'] as String?) ?? '',
    email: (secret['email'] as String?) ?? '',
    username: (secret['username'] as String?) ?? '',
    password: (secret['password'] as String?) ?? '',
    url: (secret['url'] as String?) ?? '',
    notes: (secret['notes'] as String?) ?? '',
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );
}

/// Lo que hay en `vault_meta`: la sal, las vueltas de la derivación y la prueba de la contraseña maestra.
class VaultMeta {
  const VaultMeta({required this.salt, required this.kdfIter, required this.verifier, this.version = 1});

  /// En base64.
  final String salt;
  final int kdfIter;
  final String verifier;
  final int version;

  factory VaultMeta.fromJson(Map<String, Object?> json) => VaultMeta(
    salt: json['salt']! as String,
    kdfIter: (json['kdf_iter']! as num).toInt(),
    verifier: json['verifier']! as String,
    version: (json['version'] as num?)?.toInt() ?? 1,
  );

  Map<String, Object?> toJson() => {'salt': salt, 'kdf_iter': kdfIter, 'verifier': verifier, 'version': version};
}

/// Una fila de `vault_entries`: el texto cifrado y sus fechas en claro.
class VaultEntryRow {
  const VaultEntryRow({required this.id, required this.payload, required this.createdAt, required this.updatedAt, this.version = 1});

  final String id;
  final String payload;
  final int version;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory VaultEntryRow.fromJson(Map<String, Object?> json) => VaultEntryRow(
    id: json['id']! as String,
    payload: json['payload']! as String,
    version: (json['version'] as num?)?.toInt() ?? 1,
    createdAt: DateTime.parse(json['created_at']! as String).toUtc(),
    updatedAt: DateTime.parse(json['updated_at']! as String).toUtc(),
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'payload': payload,
    'version': version,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'deleted_at': null,
  };
}

/// Dónde vive la bóveda: `vault_meta` y `vault_entries` en Supabase. Lanza `ChatException`.
abstract class PasswordBackend {
  /// La prueba de la bóveda de esta cuenta, o `null` si todavía no la creó.
  Future<VaultMeta?> loadMeta();

  /// Crea la bóveda. Lanza `ChatException` con código `23505` si esta cuenta ya tenía una.
  Future<void> createMeta(VaultMeta meta);

  /// Las entradas vivas (cifradas).
  Future<List<VaultEntryRow>> loadRows();

  /// Sube una entrada (nueva o editada).
  Future<void> saveRow(VaultEntryRow row);

  /// Borrado suave: la fila queda en el servidor con `deleted_at`.
  Future<void> deleteRow(String id, DateTime at);
}

/// Busca por servicio, correo, usuario y URL (nunca por la contraseña ni las notas), por orden alfabético del servicio.
List<VaultItem> searchVaultItems(Iterable<VaultItem> items, String query) {
  final q = query.trim().toLowerCase();
  final sorted = items.toList()..sort((a, b) => a.service.toLowerCase().compareTo(b.service.toLowerCase()));
  if (q.isEmpty) return sorted;
  return [
    for (final i in sorted)
      if ([i.service, i.email, i.username, i.url].any((f) => f.toLowerCase().contains(q))) i,
  ];
}
