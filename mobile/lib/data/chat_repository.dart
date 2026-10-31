import 'dart:async';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../models/message.dart';
import '../models/track.dart';
import 'chat_backend.dart';
import 'music_backend.dart';

/// El chat sobre Supabase: el mismo contrato que usa la PC (supabase/endpoints.md). Sesión con correo y contraseña,
/// funciones RPC para enviar y leer, Storage para los archivos y Realtime para lo que llega al instante. También sirve la
/// música: las canciones que la PC sube con «Descargar» (`music_tracks` y sus MP3 en el mismo bucket).
class ChatRepository implements ChatBackend, MusicBackend {
  ChatRepository(this._client);

  final SupabaseClient _client;

  @override
  String? get userId => _client.auth.currentUser?.id;

  bool get signedIn => _client.auth.currentSession != null;

  Stream<AuthState> get authChanges => _client.auth.onAuthStateChange;

  // ---------- sesión ----------

  Future<void> signIn(String email, String password) =>
      _guard(() => _client.auth.signInWithPassword(email: email.trim(), password: password));

  Future<void> signOut() => _guard(() => _client.auth.signOut());

  // ---------- mensajes ----------

  @override
  Future<String> ensureConversation() async {
    final id = await _guard(() => _client.rpc('ensure_default_conversation'));
    return id.toString();
  }

  @override
  Future<List<Message>> listMessages(String conversationId, {DateTime? before, DateTime? after, int limit = 50}) async {
    final data = await _guard(() => _client.rpc('list_messages', params: {
          'p_conversation_id': conversationId,
          'p_before': before?.toUtc().toIso8601String(),
          'p_after': after?.toUtc().toIso8601String(),
          'p_limit': limit,
        }));
    return [
      for (final item in (data as List<dynamic>? ?? const [])) Message.fromJson(Map<String, dynamic>.from(item as Map)),
    ];
  }

  @override
  Future<Message> sendMessage({
    required String id,
    required String conversationId,
    required DateTime sentAt,
    required String device,
    String? body,
    List<Attachment> attachments = const [],
  }) async {
    final data = await _guard(() => _client.rpc('send_message', params: {
          'p_id': id,
          'p_conversation_id': conversationId,
          'p_body': body,
          'p_sent_at': sentAt.toUtc().toIso8601String(),
          'p_device': device,
          'p_attachments': [for (final a in attachments) a.toRpc()],
        }));
    return Message.fromJson(Map<String, dynamic>.from(data as Map));
  }

  @override
  Future<void> deleteMessage(String id) async {
    await _guard(() => _client.rpc('delete_message', params: {'p_id': id}));
  }

  // ---------- archivos ----------

  @override
  Future<void> upload(String storagePath, Uint8List bytes, String mime) async {
    await _guard(() => _client.storage
        .from(AppConfig.bucket)
        .uploadBinary(storagePath, bytes, fileOptions: FileOptions(contentType: mime, upsert: true)));
  }

  @override
  Future<String> signedUrl(String storagePath) =>
      _guard(() => _client.storage.from(AppConfig.bucket).createSignedUrl(storagePath, 3600));

  // ---------- música ----------

  @override
  Future<List<Track>> listTracks({int limit = 200}) async {
    final data = await _guard(() => _client.rpc('list_music_tracks', params: {'p_limit': limit}));
    return [
      for (final item in (data as List<dynamic>? ?? const [])) Track.fromJson(Map<String, dynamic>.from(item as Map)),
    ];
  }

  @override
  Future<Uint8List> downloadTrack(String storagePath) =>
      _guard(() => _client.storage.from(AppConfig.bucket).download(storagePath));

  @override
  Stream<void> trackChanges() {
    late final StreamController<void> controller;
    RealtimeChannel? channel;
    controller = StreamController<void>(
      onListen: () {
        final created = _client.channel('kyora-musica-${DateTime.now().microsecondsSinceEpoch}');
        created.onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'music_tracks',
          callback: (_) => controller.add(null),
        );
        created.subscribe((status, error) {
          // al (re)conectarse también se pide la lista: así no se pierde lo que llegó con la conexión cortada
          if (!controller.isClosed && status == RealtimeSubscribeStatus.subscribed) controller.add(null);
        });
        channel = created;
      },
      onCancel: () async {
        final current = channel;
        channel = null;
        if (current != null) await _client.removeChannel(current);
      },
    );
    return controller.stream;
  }

  // ---------- tiempo real ----------

  @override
  Stream<BackendSignal> signals(String conversationId) {
    late final StreamController<BackendSignal> controller;
    RealtimeChannel? channel;

    void onChange(PostgresChangePayload payload) {
      final isMessage = payload.table == 'messages';
      if (isMessage && payload.eventType == PostgresChangeEvent.delete) {
        controller.add(BackendSignal(SignalKind.deleted, payload.oldRecord['id'] as String?));
      } else if (isMessage && payload.eventType == PostgresChangeEvent.update && payload.newRecord['deleted_at'] != null) {
        controller.add(BackendSignal(SignalKind.deleted, payload.newRecord['id'] as String?));
      } else {
        controller.add(const BackendSignal(SignalKind.changed));
      }
    }

    controller = StreamController<BackendSignal>(
      onListen: () {
        final created = _client.channel('kyora-movil-${DateTime.now().microsecondsSinceEpoch}');
        for (final table in const ['messages', 'attachments']) {
          created.onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: table, callback: onChange);
        }
        created.subscribe((status, error) {
          if (controller.isClosed) return;
          controller.add(BackendSignal(status == RealtimeSubscribeStatus.subscribed ? SignalKind.connected : SignalKind.disconnected));
        });
        channel = created;
      },
      onCancel: () async {
        final current = channel;
        channel = null;
        if (current != null) await _client.removeChannel(current);
      },
    );
    return controller.stream;
  }

  // ---------- errores ----------

  /// Ejecuta algo de Supabase y convierte cualquier fallo en un `ChatException` en español.
  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on ChatException {
      rethrow;
    } on AuthException catch (e) {
      throw explainAuth(e);
    } on PostgrestException catch (e) {
      throw explainPostgrest(e);
    } on StorageException catch (e) {
      throw explainStorage(e);
    } catch (_) {
      // Sin red, tiempo agotado o conexión cortada: se reintenta solo.
      throw const ChatException('Sin conexión con Supabase', retryable: true, code: 'offline');
    }
  }
}

ChatException explainAuth(AuthException e) {
  final code = e.code ?? '';
  final text = e.message.toLowerCase();
  if (code == 'invalid_credentials' || text.contains('invalid login')) {
    return ChatException('Correo o contraseña incorrectos.', code: 'invalid_credentials');
  }
  if (code == 'email_not_confirmed' || text.contains('not confirmed')) {
    return ChatException('Ese usuario aún no está confirmado en Supabase.', code: 'email_not_confirmed');
  }
  if (code == 'over_request_rate_limit' || e.statusCode == '429') {
    return ChatException('Demasiados intentos: espera un momento.', retryable: true, code: code);
  }
  final status = int.tryParse(e.statusCode ?? '');
  return ChatException(e.message, retryable: status == null || status >= 500, code: code);
}

ChatException explainPostgrest(PostgrestException e) {
  final code = e.code ?? '';
  final text = e.message.toLowerCase();
  if (code == 'PGRST202' || code == '42883' || text.contains('could not find the function')) {
    return ChatException('Falta crear la base de datos: ejecuta supabase/schema.sql en Supabase.', code: code);
  }
  if (code == 'PGRST205' || code == '42P01' || text.contains('music_tracks')) {
    return ChatException('Falta la parte de música: vuelve a ejecutar supabase/schema.sql en Supabase.', code: code);
  }
  if (code == 'PGRST301' || code == 'PGRST303' || code == '401' || text.contains('jwt')) {
    return ChatException('La sesión caducó: vuelve a entrar.', retryable: true, code: code);
  }
  if (text.contains('empty_message')) return ChatException('El mensaje está vacío.', code: code);
  if (text.contains('message_id_taken')) return ChatException('Ese mensaje ya existe en otra cuenta.', code: code);
  final status = int.tryParse(code);
  return ChatException(e.message, retryable: status != null && (status >= 500 || status == 408 || status == 429), code: code);
}

ChatException explainStorage(StorageException e) {
  final status = int.tryParse(e.statusCode ?? '');
  if (status == 413) return ChatException('El archivo es demasiado grande para Supabase.', code: '413');
  if (status == 400 || status == 403 || status == 404) {
    return ChatException('Supabase rechazó el archivo: ${e.message}', code: e.statusCode);
  }
  return ChatException(e.message, retryable: status == null || status >= 500 || status == 408 || status == 429, code: e.statusCode);
}
