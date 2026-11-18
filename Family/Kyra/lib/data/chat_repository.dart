import 'dart:async';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../models/event.dart';
import '../models/finance.dart';
import '../models/habit.dart';
import '../models/improvement.dart';
import '../models/message.dart';
import '../models/presence.dart';
import '../models/profile.dart';
import '../models/reminder.dart';
import '../models/task.dart';
import '../models/track.dart';
import 'account_backend.dart';
import 'admin_backend.dart';
import 'chat_backend.dart';
import 'direct_backend.dart';
import 'cloud_files.dart';
import 'server_stats.dart';
import 'habit_backend.dart';
import 'improvement_backend.dart';
import 'music_backend.dart';
import 'password_vault.dart';
import 'sync_rows.dart';
import 'task_backend.dart';

/// El chat sobre Supabase: el mismo contrato que usa la PC (Server/supabase/endpoints.md). Sesión con correo y contraseña,
/// funciones RPC para enviar y leer, Storage para los archivos y Realtime para lo que llega al instante. También sirve la
/// música (las canciones que la PC manda con «Descargar»: `music_tracks` y sus MP3 en el mismo bucket) y las cuentas:
/// el administrador (tú) y los pasantes, que se registran solos. Y las tareas (`tasks`, `tags`, `task_tags`).
class ChatRepository implements ChatBackend, MusicBackend, AccountBackend, AdminBackend, DirectBackend, TaskBackend, HabitBackend, LiveBackend, ServerBackend, CloudBackend {
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
  Future<void> signIn(String identifier, String password) =>
      _guard(() => _client.auth.signInWithPassword(email: loginEmail(identifier), password: password));

  @override
  Future<void> claimAccount(String code) async {
    await _guard(() => _client.rpc('claim_account', params: {'p_code': code.trim()}));
  }

  @override
  Future<void> signOut() => _guard(() => _client.auth.signOut());

  @override
  Future<Profile?> myProfile() async {
    final data = await _guard(() => _client.rpc('my_profile'));
    if (data == null) return null;
    return Profile.fromJson(Map<String, dynamic>.from(data as Map));
  }

  // ---------- presencia y cuentas (administrador) ----------

  @override
  Future<void> touchPresence() async {
    await _guard(() => _client.rpc('touch_presence'));
  }

  @override
  Future<List<PresenceEntry>> listPresence() async {
    final data = await _guard(() => _client.rpc('list_presence'));
    return [
      for (final item in (data as List<dynamic>? ?? const [])) PresenceEntry.fromJson(Map<String, dynamic>.from(item as Map)),
    ];
  }

  /// Llama a la función `admin-users` (con la sesión de quien administra) y devuelve su respuesta.
  Future<Map<String, dynamic>> _adminCall(Map<String, Object?> body) async {
    try {
      final response = await _client.functions.invoke('admin-users', body: body);
      final data = response.data;
      return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
    } on FunctionException catch (e) {
      final details = e.details;
      final code = details is Map ? details['error'] as String? : null;
      throw explainAdminError(code, e.status);
    } on ChatException {
      rethrow;
    } catch (_) {
      throw const ChatException('Sin conexión con Supabase', retryable: true, code: 'offline');
    }
  }

  @override
  Future<IssuedCode> createAccount({required String username, required String password, required Role role}) async {
    final data = await _adminCall({'action': 'create', 'username': username.trim(), 'password': password, 'role': role == Role.admin ? 'admin' : 'intern'});
    return IssuedCode(username: (data['username'] as String?) ?? username.trim().toLowerCase(), code: data['code'] as String);
  }

  @override
  Future<void> setRole(String userId, Role role) async {
    await _adminCall({'action': 'set_role', 'user_id': userId, 'role': role == Role.admin ? 'admin' : 'intern'});
  }

  @override
  Future<IssuedCode> regenerateCode(String userId, String username) async {
    final data = await _adminCall({'action': 'regenerate_code', 'user_id': userId});
    return IssuedCode(username: username, code: data['code'] as String);
  }

  @override
  Future<void> removeAccount(String userId) async {
    await _adminCall({'action': 'remove', 'user_id': userId});
  }

  // ---------- chat privado 1 a 1 (§19) ----------

  List<Map<String, dynamic>> _rows(Object? data) => [for (final item in (data as List<dynamic>? ?? const [])) Map<String, dynamic>.from(item as Map)];

  @override
  Future<List<ChatUser>> directory() async => [for (final r in _rows(await _guard(() => _client.rpc('dm_directory')))) ChatUser.fromJson(r)];

  @override
  Future<DirectThread> openThread(String userId) async {
    final data = await _guard(() => _client.rpc('dm_open_thread', params: {'p_user': userId}));
    return DirectThread.fromJson(Map<String, dynamic>.from(data as Map));
  }

  @override
  Future<List<DirectThread>> listThreads() async => [for (final r in _rows(await _guard(() => _client.rpc('dm_list_threads')))) DirectThread.fromJson(r)];

  @override
  Future<List<DirectMessage>> listDirectMessages(String threadId, {DateTime? before, DateTime? after, int limit = 100}) async {
    final data = await _guard(() => _client.rpc('dm_list_messages', params: {
          'p_thread': threadId,
          'p_before': before?.toUtc().toIso8601String(),
          'p_after': after?.toUtc().toIso8601String(),
          'p_limit': limit,
        }));
    return [for (final r in _rows(data)) DirectMessage.fromJson(r)];
  }

  @override
  Future<DirectMessage> sendDirect({required String id, required String threadId, required String body, required DateTime sentAt, required String device}) async {
    final data = await _guard(() => _client.rpc('dm_send', params: {
          'p_id': id,
          'p_thread': threadId,
          'p_body': body,
          'p_sent_at': sentAt.toUtc().toIso8601String(),
          'p_device': device,
        }));
    return DirectMessage.fromJson(Map<String, dynamic>.from(data as Map));
  }

  @override
  Future<void> hideMessage(String id) async => _guard(() => _client.rpc('dm_hide_message', params: {'p_id': id}));

  @override
  Future<void> clearThread(String threadId) async => _guard(() => _client.rpc('dm_clear_thread', params: {'p_thread': threadId}));

  @override
  Future<void> markRead(String threadId) async => _guard(() => _client.rpc('dm_mark_read', params: {'p_thread': threadId}));

  @override
  Stream<DirectSignal> directSignals() {
    late final StreamController<DirectSignal> controller;
    RealtimeChannel? channel;
    controller = StreamController<DirectSignal>(
      onListen: () {
        final created = _client.channel('kyra-dm-${DateTime.now().microsecondsSinceEpoch}');
        created.onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'dm_messages',
          callback: (payload) {
            final row = payload.eventType == PostgresChangeEvent.delete ? payload.oldRecord : payload.newRecord;
            controller.add(DirectSignal(
              payload.eventType == PostgresChangeEvent.delete ? SignalKind.deleted : SignalKind.changed,
              messageId: row['id'] as String?,
              threadId: row['thread_id'] as String?,
              senderId: row['sender_id'] as String?,
              body: payload.eventType == PostgresChangeEvent.insert ? row['body'] as String? : null,
            ));
          },
        );
        created.subscribe((status, error) {
          if (controller.isClosed) return;
          if (status == RealtimeSubscribeStatus.subscribed) {
            controller.add(const DirectSignal(SignalKind.connected));
          } else if (status == RealtimeSubscribeStatus.channelError || status == RealtimeSubscribeStatus.timedOut || status == RealtimeSubscribeStatus.closed) {
            controller.add(const DirectSignal(SignalKind.disconnected));
          }
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

  @override
  Future<List<AdminThread>> adminThreads() async => [for (final r in _rows(await _guard(() => _client.rpc('dm_admin_threads')))) AdminThread.fromJson(r)];

  @override
  Future<List<DirectMessage>> adminMessages(String threadId) async =>
      [for (final r in _rows(await _guard(() => _client.rpc('dm_admin_messages', params: {'p_thread': threadId})))) DirectMessage.fromJson(r)];

  @override
  Future<void> adminDeleteMessage(String id) async => _guard(() => _client.rpc('dm_admin_delete_message', params: {'p_id': id}));

  @override
  Future<void> adminDeleteThread(String threadId) async => _guard(() => _client.rpc('dm_admin_delete_thread', params: {'p_thread': threadId}));

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

  /// Sube filas por tandas: repetir una subida no duplica nada (`upsert` por su clave).
  Future<void> _upsert(String table, List<Map<String, Object?>> rows, String onConflict) async {
    for (var i = 0; i < rows.length; i += _pushChunk) {
      final chunk = rows.sublist(i, i + _pushChunk > rows.length ? rows.length : i + _pushChunk);
      await _guard(() => _client.from(table).upsert(chunk, onConflict: onConflict));
    }
  }

  /// Las filas de una tabla que cambiaron después de `since` (`synced_at`), por páginas.
  Future<List<Map<String, Object?>>> _readSince(String table, String? since) async {
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

  @override
  Future<void> push(TaskData changes) async {
    // las subtareas después de sus tareas (la clave ajena las pide ya guardadas)
    final tasks = [...changes.tasks]..sort((a, b) => (a.parentId == null ? 0 : 1).compareTo(b.parentId == null ? 0 : 1));
    await _upsert('tags', [for (final t in changes.tags) t.toJson()], 'id');
    await _upsert('tasks', [for (final t in tasks) t.toJson()], 'id');
    await _upsert('task_tags', [for (final l in changes.links) l.toJson()], 'task_id,tag_id');
  }

  @override
  Future<TaskData> pull({String? tasksSince, String? tagsSince, String? linksSince}) async {
    return TaskData(
      tags: [for (final r in await _readSince('tags', tagsSince)) Tag.fromJson(r)],
      tasks: [for (final r in await _readSince('tasks', tasksSince)) TaskItem.fromJson(r)],
      links: [for (final r in await _readSince('task_tags', linksSince)) TaskTag.fromJson(r)],
    );
  }

  // ---------- hábitos ----------

  @override
  Future<void> pushHabits(HabitData changes) async {
    // las marcas después de sus hábitos (la clave ajena los pide ya guardados)
    await _upsert('habits', [for (final h in changes.habits) h.toJson()], 'id');
    await _upsert('habit_checks', [for (final c in changes.checks) c.toJson()], 'habit_id,day');
  }

  @override
  Future<HabitData> pullHabits({String? habitsSince, String? checksSince}) async {
    return HabitData(
      habits: [for (final r in await _readSince('habits', habitsSince)) Habit.fromJson(r)],
      checks: [for (final r in await _readSince('habit_checks', checksSince)) HabitCheck.fromJson(r)],
    );
  }

  // ---------- el servidor y la nube (lo mismo que ve Merida) ----------

  @override
  Future<ServerStats> serverStats() async => parseStats(await _guard(() => _client.rpc('server_stats')));

  @override
  Future<List<CloudFile>> listCloud() async {
    final results = await Future.wait([
      _guard(() => _client.from('attachments').select('id, message_id, thumb_path, storage_path, file_name, mime_type, size_bytes, created_at, message:messages(sender_device, deleted_at)').order('created_at', ascending: false).limit(500)),
      _guard(() => _client.from('music_tracks').select('id, title, file_name, storage_path, mime_type, size_bytes, created_at, owner_id, recipient_id').order('created_at', ascending: false).limit(500)),
    ]);
    // los nombres de los pasantes, solo para decir a quién va cada canción (si no se pueden leer, se dice «un pasante»)
    final names = <String, String>{};
    try {
      final data = await _client.rpc('list_recipients');
      for (final r in (data as List<dynamic>? ?? const [])) {
        final m = Map<String, Object?>.from(r as Map);
        names[m['id'] as String] = (m['username'] as String?) ?? '';
      }
    } catch (_) {
      // no es administrador o no hay red: sin nombres
    }
    List<Map<String, Object?>> rows(Object list) => [for (final r in list as List) Map<String, Object?>.from(r as Map)];
    return mergeCloud(rows(results[0]), rows(results[1]), userId, names, await _uploads());
  }

  /// Lo que se subió a tu nube desde el teléfono (Storage `<tú>/cloud/`). Si no se puede leer, simplemente no sale.
  Future<List<CloudFile>> _uploads() async {
    final uid = userId;
    if (uid == null) return const [];
    try {
      final objects = await _client.storage.from(AppConfig.bucket).list(path: '$uid/cloud', searchOptions: const SearchOptions(limit: 500));
      return [
        for (final o in objects)
          if (o.id != null) cloudFileFromUpload(uid, {'name': o.name, 'id': o.id, 'created_at': o.createdAt ?? o.updatedAt, 'metadata': o.metadata}),
      ];
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> uploadCloudFile(String name, String mime, Uint8List bytes) async {
    final uid = userId;
    if (uid == null) throw const ChatException('Entra con tu cuenta para subir a la nube.');
    await _guard(() => _client.storage.from(AppConfig.bucket).uploadBinary(uploadPath(uid, name, DateTime.now()), bytes, fileOptions: FileOptions(contentType: mime)));
  }

  @override
  Future<String> cloudUrl(String path, {String? download}) => _guard(() => _client.storage.from(AppConfig.bucket).createSignedUrl(path, 3600, download: download == null ? null : DownloadBehavior.named(download))).then(_absolute);

  @override
  Future<CloudDeleteResult> deleteCloudFile(CloudFile file) async {
    final paths = [file.path, if (file.thumbPath != null) file.thumbPath!];
    await _guard(() => _client.storage.from(AppConfig.bucket).remove(paths));
    if (file.source == CloudSource.upload) return const CloudDeleteResult(); // solo vive en Storage: no hay fila que borrar
    if (file.source == CloudSource.music) {
      final rows = await _guard(() => _client.from('music_tracks').delete().eq('storage_path', file.path).select('id'));
      if ((rows as List).isEmpty) throw const ChatException('El servidor no dejó borrar esta canción (no es tuya).');
      return const CloudDeleteResult();
    }
    final attachmentId = file.id.substring('chat:'.length);
    final row = await _guard(() => _client.from('attachments').delete().eq('id', attachmentId).select('id'));
    if ((row as List).isEmpty) throw const ChatException('El servidor no dejó borrar este archivo.');
    final messageId = file.messageId;
    if (messageId == null) return const CloudDeleteResult();
    // ¿el mensaje se quedó sin nada? entonces se borra también (un mensaje vacío no sirve de nada)
    final msg = await _guard(() => _client.from('messages').select('id, body, attachments(id)').eq('id', messageId).maybeSingle());
    if (msg == null) return const CloudDeleteResult();
    final left = (msg['attachments'] as List?) ?? const [];
    if (((msg['body'] as String?) ?? '').trim().isEmpty && left.isEmpty) {
      await deleteMessage(messageId);
      return const CloudDeleteResult(messageDeleted: true);
    }
    return const CloudDeleteResult();
  }

  // ---------- recordatorios y eventos (las mismas tablas que la web) ----------

  /// Los recordatorios (`reminders`) en Supabase.
  RowBackend<Reminder> get reminderBackend => _SupabaseRows<Reminder>(this, 'reminders', Reminder.fromJson, (r) => r.toJson());

  /// Los eventos del calendario (`events`) en Supabase.
  RowBackend<CalendarEvent> get eventBackend => _SupabaseRows<CalendarEvent>(this, 'events', CalendarEvent.fromJson, (e) => e.toJson());

  /// Las categorías de las finanzas (`finance_categories`) en Supabase.
  RowBackend<FinanceCategory> get financeCategoryBackend =>
      _SupabaseRows<FinanceCategory>(this, 'finance_categories', FinanceCategory.fromJson, (c) => c.toJson());

  /// Los movimientos de las finanzas (`finance_entries`) en Supabase.
  RowBackend<FinanceEntry> get financeEntryBackend => _SupabaseRows<FinanceEntry>(this, 'finance_entries', FinanceEntry.fromJson, (e) => e.toJson());

  /// La bóveda de contraseñas (`vault_meta` y `vault_entries`) en Supabase: la misma que usa Merida.
  PasswordBackend get passwordBackend => _SupabasePasswords(this);

  /// Las mejoras pendientes (`feature_requests`) en Supabase: las mismas que usa Merida.
  ImprovementBackend get improvementBackend => _SupabaseImprovements(this);

  // ---------- tiempo real ----------

  /// Emite cada vez que cambia algo en esas tablas (y al conectarse), para ponerse al día sin esperar al siguiente reintento.
  @override
  Stream<void> changes(List<String> tables) {
    late final StreamController<void> controller;
    RealtimeChannel? channel;
    controller = StreamController<void>(
      onListen: () {
        final created = _client.channel('kyora-agenda-${DateTime.now().microsecondsSinceEpoch}');
        for (final table in tables) {
          created.onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: table, callback: (_) => controller.add(null));
        }
        created.subscribe((status, error) {
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

/// Una tabla de filas sincronizadas (recordatorios, eventos) sobre el mismo repositorio: sube por tandas con `upsert` y baja por `synced_at`.
class _SupabaseRows<T extends SyncRow> implements RowBackend<T> {
  _SupabaseRows(this._repo, this._table, this._read, this._write);

  final ChatRepository _repo;
  final String _table;
  final T Function(Map<String, Object?> json) _read;
  final Map<String, Object?> Function(T row) _write;

  @override
  Future<void> push(List<T> rows) => _repo._upsert(_table, [for (final r in rows) _write(r)], 'id');

  @override
  Future<List<T>> pull(String? since) async => [for (final r in await _repo._readSince(_table, since)) _read(r)];
}

ChatException explainAuth(AuthException e) {
  final code = e.code ?? '';
  final text = e.message.toLowerCase();
  if (code == 'invalid_credentials' || text.contains('invalid login')) {
    return ChatException('Usuario o contraseña incorrectos.', code: 'invalid_credentials');
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
  final missingFunction = code == 'PGRST202' || code == '42883' || text.contains('could not find the function');
  if (missingFunction && text.contains('server_stats')) {
    return ChatException('Falta la función server_stats en Supabase. Vuelve a ejecutar Server/supabase/schema.sql en el SQL Editor.', code: code);
  }
  if (missingFunction) {
    return ChatException('Falta crear la base de datos: ejecuta Server/supabase/schema.sql en Supabase.', code: code);
  }
  if ((code == 'PGRST205' || code == '42P01') && RegExp(r'\b(tasks|tags|task_tags)\b').hasMatch(text)) {
    return ChatException('Falta la parte de tareas: vuelve a ejecutar Server/supabase/schema.sql en Supabase.', code: code);
  }
  if ((code == 'PGRST205' || code == '42P01') && text.contains('finance_')) {
    return ChatException('Falta la parte de finanzas: vuelve a ejecutar Server/supabase/schema.sql en Supabase.', code: code);
  }
  if ((code == 'PGRST205' || code == '42P01') && text.contains('feature_requests')) {
    return ChatException('Falta la parte de mejoras: vuelve a ejecutar Server/supabase/schema.sql en Supabase.', code: code);
  }
  if ((code == 'PGRST205' || code == '42P01') && text.contains('vault_')) {
    return ChatException('Falta la parte de contraseñas: vuelve a ejecutar Server/supabase/schema.sql en Supabase.', code: code);
  }
  if (code == 'PGRST205' || code == '42P01' || text.contains('music_tracks')) {
    return ChatException('Falta la parte de música: vuelve a ejecutar Server/supabase/schema.sql en Supabase.', code: code);
  }
  if (code == 'PGRST301' || code == 'PGRST303' || code == '401' || text.contains('jwt')) {
    return ChatException('La sesión caducó: vuelve a entrar.', retryable: true, code: code);
  }
  if (text.contains('code_invalid')) return ChatException('Ese código no es correcto.', code: 'code_invalid');
  if (text.contains('code_expired')) return ChatException('El código caducó: pídele otro al administrador.', code: 'code_expired');
  if (text.contains('code_locked')) return ChatException('Demasiados intentos con el código: pídele otro al administrador.', code: 'code_locked');
  if (text.contains('dm_') && (code == 'PGRST202' || code == '42883')) {
    return ChatException('Falta el chat privado en el servidor: vuelve a ejecutar Server/supabase/schema.sql en Supabase.', code: code);
  }
  if (text.contains('not_verified')) return ChatException('Tu cuenta aún no está verificada: escribe tu código de 6 dígitos en Ajustes.', code: 'not_verified');
  if (text.contains('not_participant')) return ChatException('Esa conversación no es tuya.', code: 'not_participant');
  if (text.contains('user_not_found')) return ChatException('Esa persona ya no está disponible.', code: 'user_not_found');
  if (text.contains('admin_only')) return ChatException('Solo el administrador puede hacer eso.', code: 'admin_only');
  if (text.contains('not_family_member')) return ChatException('Tu cuenta aún no está verificada: escribe tu código de 6 dígitos en Ajustes.', code: 'not_verified');
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

/// La bóveda de contraseñas sobre el mismo repositorio: `vault_meta` (la prueba de la contraseña maestra) y `vault_entries` (cada entrada, cifrada).
class _SupabasePasswords implements PasswordBackend {
  _SupabasePasswords(this._repo);

  final ChatRepository _repo;

  @override
  Future<VaultMeta?> loadMeta() async {
    final row = await _repo._guard(() => _repo._client.from('vault_meta').select('salt,kdf_iter,verifier,version').maybeSingle());
    return row == null ? null : VaultMeta.fromJson(Map<String, Object?>.from(row));
  }

  @override
  Future<void> createMeta(VaultMeta meta) async {
    await _repo._guard(() => _repo._client.from('vault_meta').insert(meta.toJson()));
  }

  @override
  Future<List<VaultEntryRow>> loadRows() async {
    final rows = await _repo._guard(
      () => _repo._client.from('vault_entries').select('id,payload,version,created_at,updated_at').isFilter('deleted_at', null).limit(2000),
    );
    return [for (final r in rows) VaultEntryRow.fromJson(Map<String, Object?>.from(r))];
  }

  @override
  Future<void> saveRow(VaultEntryRow row) => _repo._upsert('vault_entries', [row.toJson()], 'id');

  @override
  Future<void> deleteRow(String id, DateTime at) async {
    final iso = at.toUtc().toIso8601String();
    await _repo._guard(() => _repo._client.from('vault_entries').update({'deleted_at': iso, 'updated_at': iso}).eq('id', id));
  }
}

/// Las mejoras pendientes sobre el mismo repositorio: leer, anotar (`upsert` por su id) y terminar (borrar de verdad).
class _SupabaseImprovements implements ImprovementBackend {
  _SupabaseImprovements(this._repo);

  final ChatRepository _repo;

  @override
  Future<List<Improvement>> list() async {
    final rows = await _repo._guard(
      () => _repo._client.from('feature_requests').select('id,section,functions,description,created_at').order('created_at', ascending: false).limit(500),
    );
    return [for (final r in rows) Improvement.fromJson(Map<String, Object?>.from(r))];
  }

  @override
  Future<void> add(Improvement item) => _repo._upsert('feature_requests', [item.toJson()], 'id');

  @override
  Future<void> finish(String id) async {
    await _repo._guard(() => _repo._client.from('feature_requests').delete().eq('id', id));
  }
}

/// Lo que respondió la función `admin-users` (su código de error), en español.
ChatException explainAdminError(String? code, int status) {
  switch (code) {
    case 'invalid_username':
      return const ChatException('El nombre debe tener de 3 a 24 caracteres: minúsculas, números, punto, guion o guion bajo.', code: 'invalid_username');
    case 'invalid_password':
      return const ChatException('La contraseña debe tener al menos 6 caracteres.', code: 'invalid_password');
    case 'username_taken':
      return const ChatException('Ese nombre de usuario ya existe.', code: 'username_taken');
    case 'not_admin':
      return const ChatException('Solo el administrador puede hacer eso.', code: 'not_admin');
    case 'unauthorized':
      return const ChatException('La sesión caducó: vuelve a entrar.', retryable: true, code: 'unauthorized');
    case 'cannot_change_self':
      return const ChatException('No puedes hacer eso con tu propia cuenta.', code: 'cannot_change_self');
    case 'user_not_found':
      return const ChatException('Esa cuenta ya no existe.', code: 'user_not_found');
  }
  if (status == 404) {
    return const ChatException('Falta desplegar la función admin-users en Supabase (ver Server/supabase/README.md).', code: 'function_missing');
  }
  return ChatException('No se pudo completar (${code ?? status}).', retryable: status >= 500, code: code);
}
