import 'dart:async';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../models/message.dart';
import '../models/profile.dart';
import '../models/task.dart';
import '../models/track.dart';
import 'account_backend.dart';
import 'chat_backend.dart';
import 'music_backend.dart';
import 'task_backend.dart';

/// El chat sobre Supabase: el mismo contrato que usa la PC (supabase/endpoints.md). Sesión con correo y contraseña,
/// funciones RPC para enviar y leer, Storage para los archivos y Realtime para lo que llega al instante. También sirve la
/// música (las canciones que la PC manda con «Descargar»: `music_tracks` y sus MP3 en el mismo bucket) y las cuentas:
/// el administrador (tú) y los pasantes, que se registran solos. Y las tareas (`tasks`, `tags`, `task_tags`).
class ChatRepository implements ChatBackend, MusicBackend, AccountBackend, TaskBackend {
  ChatRepository(this._client);

  final SupabaseClient _client;

  @override
  String? get userId => _client.auth.currentUser?.id;

  @override
  bool get signedIn => _client.auth.currentSession != null;

  @override
  Stream<void> get authChanges => _client.auth.onAuthStateChange.map<void>((_) {});

  // ---------- sesión ----------

  @override
  Future<void> signIn(String email, String password) =>
      _guard(() => _client.auth.signInWithPassword(email: email.trim(), password: password));

  @override
  Future<bool> signUp({required String username, required String email, required String password}) async {
    final free = await _guard(() => _client.rpc('username_available', params: {'p_username': username.trim()}));
    if (free == false) throw const ChatException('Ese nombre de usuario ya está en uso.', code: 'username_taken');
    final response = await _guard(
        () => _client.auth.signUp(email: email.trim(), password: password, data: {'username': username.trim()}));
    return response.session != null;
  }

  @override
  Future<void> signOut() => _guard(() => _client.auth.signOut());

  @override
  Future<Profile?> myProfile() async {
    final data = await _guard(() => _client.rpc('my_profile'));
    if (data == null) return null;
    return Profile.fromJson(Map<String, dynamic>.from(data as Map));
  }

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
  Future<void> confirmReceived(String trackId) async {
    await _guard(() => _client.rpc('confirm_track_received', params: {'p_id': trackId}));
  }

  @override
  Future<Uint8List> downloadTrack(String storagePath) =>
      _guard(() => _client.storage.from(AppConfig.bucket).download(storagePath));

  @override
  Future<Map<String, String>> signedUrls(List<String> storagePaths, int expiresIn) async {
    if (storagePaths.isEmpty) return {};
    final results = await _guard(() => _client.storage.from(AppConfig.bucket).createSignedUrlsResult(storagePaths, expiresIn));
    return {
      for (final result in results)
        if (result is SignedUrlSuccess) result.path: _absolute(result.signedUrl),
    };
  }

  /// Supabase puede devolver la dirección firmada sin el servidor delante; con él delante, se deja tal cual.
  String _absolute(String url) => url.startsWith('http') ? url : '${AppConfig.supabaseUrl}/storage/v1$url';

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

  // ---------- tareas ----------

  static const _pushChunk = 200;
  static const _pullPage = 500;

  @override
  Future<void> push(TaskData changes) async {
    Future<void> up(String table, List<Map<String, Object?>> rows, String onConflict) async {
      for (var i = 0; i < rows.length; i += _pushChunk) {
        final chunk = rows.sublist(i, i + _pushChunk > rows.length ? rows.length : i + _pushChunk);
        await _guard(() => _client.from(table).upsert(chunk, onConflict: onConflict));
      }
    }

    // las subtareas después de sus tareas (la clave ajena las pide ya guardadas)
    final tasks = [...changes.tasks]..sort((a, b) => (a.parentId == null ? 0 : 1).compareTo(b.parentId == null ? 0 : 1));
    await up('tags', [for (final t in changes.tags) t.toJson()], 'id');
    await up('tasks', [for (final t in tasks) t.toJson()], 'id');
    await up('task_tags', [for (final l in changes.links) l.toJson()], 'task_id,tag_id');
  }

  @override
  Future<TaskData> pull({String? tasksSince, String? tagsSince, String? linksSince}) async {
    Future<List<Map<String, Object?>>> read(String table, String? since) async {
      final all = <Map<String, Object?>>[];
      var cursor = since;
      while (true) {
        final base = _client.from(table).select();
        final rows = await _guard(() => (cursor == null ? base : base.gt('synced_at', cursor)).order('synced_at', ascending: true).limit(_pullPage));
        all.addAll([for (final r in rows) Map<String, Object?>.from(r)]);
        if (rows.length < _pullPage) return all;
        cursor = DateTime.parse(rows.last['synced_at'] as String).toUtc().toIso8601String();
      }
    }

    return TaskData(
      tags: [for (final r in await read('tags', tagsSince)) Tag.fromJson(r)],
      tasks: [for (final r in await read('tasks', tasksSince)) TaskItem.fromJson(r)],
      links: [for (final r in await read('task_tags', linksSince)) TaskTag.fromJson(r)],
    );
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
  if (code == 'user_already_exists' || text.contains('already registered')) {
    return ChatException('Ese correo ya tiene una cuenta: entra con él.', code: 'user_already_exists');
  }
  if (code == 'weak_password' || text.contains('password should be')) {
    return ChatException('La contraseña es muy débil: usa al menos 6 caracteres.', code: 'weak_password');
  }
  if (code == 'signup_disabled' || text.contains('signups not allowed')) {
    return ChatException('El registro está desactivado en Supabase.', code: 'signup_disabled');
  }
  if (code == 'email_address_invalid' || text.contains('invalid format') || text.contains('is invalid')) {
    return ChatException('Supabase no aceptó ese correo: prueba con otro.', code: 'email_address_invalid');
  }
  if (code == 'over_request_rate_limit' || code == 'over_email_send_rate_limit' || e.statusCode == '429') {
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
  if ((code == 'PGRST205' || code == '42P01') && RegExp(r'\b(tasks|tags|task_tags)\b').hasMatch(text)) {
    return ChatException('Falta la parte de tareas: vuelve a ejecutar supabase/schema.sql en Supabase.', code: code);
  }
  if (code == 'PGRST205' || code == '42P01' || text.contains('music_tracks')) {
    return ChatException('Falta la parte de música: vuelve a ejecutar supabase/schema.sql en Supabase.', code: code);
  }
  if (code == 'PGRST301' || code == 'PGRST303' || code == '401' || text.contains('jwt')) {
    return ChatException('La sesión caducó: vuelve a entrar.', retryable: true, code: code);
  }
  if (text.contains('empty_message')) return ChatException('El mensaje está vacío.', code: code);
  if (text.contains('message_id_taken')) return ChatException('Ese mensaje ya existe en otra cuenta.', code: code);
  if (text.contains('unknown_track')) return ChatException('Esa canción ya no está en Supabase.', code: code);
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
