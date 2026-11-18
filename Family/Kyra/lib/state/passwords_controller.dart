import 'dart:async';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import 'dart:convert';

import '../data/chat_backend.dart';
import '../data/password_vault.dart';

/// En qué punto está la bóveda: cargando, sin crear, bloqueada, abierta o con un error (sin conexión, falta la parte en Supabase…).
enum VaultState { loading, none, locked, unlocked, error }

/// Algo que la persona puede arreglar (la contraseña maestra es corta, no coincide…): el mensaje ya viene explicado.
class VaultException implements Exception {
  const VaultException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// La bóveda de contraseñas, **compatible con la de Merida** (mismas tablas y mismo cifrado): la contraseña maestra nunca sale del teléfono ni se
/// guarda; de ella sale la clave que vive solo en memoria mientras la bóveda está abierta. Se bloquea sola a los 5 minutos sin tocarla (y al salir
/// de la pantalla o de la app: ver `PasswordsPage`) y lo copiado se borra del portapapeles a los 30 segundos.
class PasswordsController extends ChangeNotifier {
  PasswordsController(
    this._backend, {
    this.rounds = VaultCrypto.iterations,
    this.idle = const Duration(minutes: 5),
    this.clipboardTime = const Duration(seconds: 30),
    DateTime Function()? now,
    String Function()? newId,
    Future<void> Function(String text)? writeClipboard,
    Future<String?> Function()? readClipboard,
  }) : _now = now ?? (() => DateTime.now().toUtc()),
       _newId = newId ?? (() => const Uuid().v4()),
       _write = writeClipboard ?? _systemWrite,
       _read = readClipboard ?? _systemRead;

  /// Lo mínimo que tiene que medir la contraseña maestra (el mismo que en Merida).
  static const minMaster = 12;

  final PasswordBackend _backend;

  /// Las vueltas de la derivación al crear la bóveda (en las pruebas, menos). Al abrir valen las que quedaron guardadas.
  final int rounds;
  final Duration idle;
  final Duration clipboardTime;
  final DateTime Function() _now;
  final String Function() _newId;
  final Future<void> Function(String) _write;
  final Future<String?> Function() _read;

  VaultState state = VaultState.loading;

  /// Lo que falló al leer (con `state == error`).
  String? error;

  /// Cuántas entradas no se pudieron descifrar (no se pierden ni se muestran).
  int broken = 0;

  VaultMeta? _meta;
  SecretKey? _key;
  List<VaultItem> _items = const [];
  Timer? _idleTimer;
  Timer? _clipboardTimer;
  bool _disposed = false;

  bool get unlocked => state == VaultState.unlocked;

  /// Todas las entradas (solo con la bóveda abierta), por servicio.
  List<VaultItem> get items => unlocked ? searchVaultItems(_items, '') : const [];

  static Future<void> _systemWrite(String text) => Clipboard.setData(ClipboardData(text: text));

  static Future<String?> _systemRead() async => (await Clipboard.getData(Clipboard.kTextPlain))?.text;

  void _tell() {
    if (!_disposed) notifyListeners();
  }

  // ---------- abrir, crear y cerrar ----------

  /// Mira en Supabase si esta cuenta ya tiene bóveda (sin abrirla).
  Future<void> refresh() async {
    if (unlocked) return;
    state = VaultState.loading;
    error = null;
    _tell();
    try {
      _meta = await _backend.loadMeta();
      state = _meta == null ? VaultState.none : VaultState.locked;
    } on ChatException catch (e) {
      state = VaultState.error;
      error = e.message;
    }
    _tell();
  }

  /// Crea la bóveda con esta contraseña maestra (sal nueva, clave y la prueba para validarla después) y la deja abierta.
  Future<void> create(String master) async {
    if (master.length < minMaster) throw const VaultException('La contraseña maestra debe tener al menos $minMaster caracteres.');
    final salt = VaultCrypto.randomBytes(16);
    final key = await VaultCrypto.deriveKey(master, salt, rounds: rounds);
    final meta = VaultMeta(salt: base64.encode(salt), kdfIter: rounds, verifier: await VaultCrypto.makeVerifier(key));
    try {
      await _backend.createMeta(meta);
    } on ChatException catch (e) {
      if (e.code == '23505') {
        // ya había una (creada desde otro dispositivo): se pasa a pedir su contraseña
        await refresh();
        throw const VaultException('Esta cuenta ya tiene una bóveda: usa su contraseña maestra.');
      }
      rethrow;
    }
    _meta = meta;
    _open(key, const [], 0);
  }

  /// Abre la bóveda. `false` si la contraseña maestra no es la correcta.
  Future<bool> unlock(String master) async {
    final meta = _meta;
    if (meta == null) return false;
    final key = await VaultCrypto.deriveKey(master, base64.decode(meta.salt), rounds: meta.kdfIter);
    if (!await VaultCrypto.checkVerifier(key, meta.verifier)) return false;
    final rows = await _backend.loadRows();
    final items = <VaultItem>[];
    var bad = 0;
    for (final row in rows) {
      try {
        final secret = jsonDecode(await VaultCrypto.decryptText(key, row.payload, aad: row.id)) as Map<String, dynamic>;
        items.add(VaultItem.fromSecret(row, Map<String, Object?>.from(secret)));
      } catch (_) {
        bad++;
      }
    }
    _open(key, items, bad);
    return true;
  }

  void _open(SecretKey key, List<VaultItem> items, int bad) {
    _key = key;
    _items = items;
    broken = bad;
    state = VaultState.unlocked;
    error = null;
    touch();
    _tell();
  }

  /// Cierra la bóveda: la clave y lo descifrado se sueltan de la memoria.
  void lock() {
    _idleTimer?.cancel();
    _key = null;
    _items = const [];
    broken = 0;
    if (state == VaultState.unlocked) state = _meta == null ? VaultState.none : VaultState.locked;
    _tell();
  }

  /// Hubo actividad: el reloj del bloqueo automático vuelve a empezar.
  void touch() {
    _idleTimer?.cancel();
    if (!unlocked) return;
    _idleTimer = Timer(idle, lock);
  }

  // ---------- las entradas ----------

  SecretKey get _openKey => _key ?? (throw const VaultException('La bóveda está bloqueada.'));

  /// Cifra y sube una entrada; solo si sale bien se pone en la lista.
  Future<void> _store(VaultItem item) async {
    final key = _openKey;
    final payload = await VaultCrypto.encryptText(key, jsonEncode(item.toSecret()), aad: item.id);
    await _backend.saveRow(VaultEntryRow(id: item.id, payload: payload, createdAt: item.createdAt, updatedAt: item.updatedAt));
    _items = [for (final i in _items) if (i.id != item.id) i, item];
    touch();
    _tell();
  }

  /// Una entrada nueva. Sin servicio no se crea; sin correo, usuario ni contraseña tampoco.
  Future<VaultItem?> add({required String service, String email = '', String username = '', String password = '', String url = '', String notes = ''}) async {
    if (service.trim().isEmpty) return null;
    if (email.trim().isEmpty && username.trim().isEmpty && password.isEmpty) return null;
    final t = _now();
    final item = VaultItem(
      id: _newId(),
      service: service.trim(),
      email: email.trim(),
      username: username.trim(),
      password: password,
      url: url.trim(),
      notes: notes,
      createdAt: t,
      updatedAt: t,
    );
    await _store(item);
    return item;
  }

  /// Una hora de cambio siempre mayor que la anterior: Supabase ignora un cambio que no sea más reciente.
  DateTime _stamp(DateTime previous) {
    final t = _now();
    return t.isAfter(previous) ? t : previous.add(const Duration(milliseconds: 1));
  }

  Future<void> update(VaultItem item, {String? service, String? email, String? username, String? password, String? url, String? notes}) =>
      _store(item.copyWith(service: service, email: email, username: username, password: password, url: url, notes: notes, updatedAt: _stamp(item.updatedAt)));

  /// Borrado suave: la fila queda en el servidor con `deleted_at` (su contenido sigue cifrado).
  Future<void> remove(VaultItem item) async {
    _openKey;
    await _backend.deleteRow(item.id, _stamp(item.updatedAt));
    _items = [for (final i in _items) if (i.id != item.id) i];
    touch();
    _tell();
  }

  List<VaultItem> search(String query) => unlocked ? searchVaultItems(_items, query) : const [];

  // ---------- el portapapeles ----------

  /// Copia un texto y a los 30 segundos lo borra del portapapeles (solo si todavía es lo que se copió).
  Future<void> copy(String text) async {
    await _write(text);
    touch();
    _clipboardTimer?.cancel();
    _clipboardTimer = Timer(clipboardTime, () async {
      try {
        if (await _read() == text) await _write('');
      } catch (_) {
        // sin poder leerlo, no se toca
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _idleTimer?.cancel();
    _clipboardTimer?.cancel();
    _key = null;
    _items = const [];
    super.dispose();
  }
}
