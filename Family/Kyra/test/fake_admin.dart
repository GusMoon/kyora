import 'package:kyora_chat/data/admin_backend.dart';
import 'package:kyora_chat/data/chat_backend.dart';
import 'package:kyora_chat/models/presence.dart';
import 'package:kyora_chat/models/profile.dart';

/// El panel del administrador y la presencia en memoria, para las pruebas.
class FakeAdminBackend implements AdminBackend {
  FakeAdminBackend([List<PresenceEntry>? entries]) : entries = entries ?? [];

  final List<PresenceEntry> entries;
  int touches = 0;
  int lists = 0;
  ChatException? error;
  String nextCode = '482913';
  final List<String> calls = [];

  @override
  Future<void> touchPresence() async {
    touches++;
    final e = error;
    if (e != null) throw e;
  }

  @override
  Future<List<PresenceEntry>> listPresence() async {
    lists++;
    final e = error;
    if (e != null) throw e;
    return List.of(entries);
  }

  @override
  Future<IssuedCode> createAccount({required String username, required String password, required Role role}) async {
    calls.add('create:$username:${role.name}');
    final e = error;
    if (e != null) throw e;
    entries.add(PresenceEntry(id: 'id-$username', username: username, role: role, verified: false, online: false, codePending: true));
    return IssuedCode(username: username, code: nextCode);
  }

  @override
  Future<void> setRole(String userId, Role role) async {
    calls.add('role:$userId:${role.name}');
    final e = error;
    if (e != null) throw e;
    final i = entries.indexWhere((x) => x.id == userId);
    final old = entries[i];
    entries[i] = PresenceEntry(id: old.id, username: old.username, role: role, verified: old.verified, online: old.online, lastSeen: old.lastSeen);
  }

  @override
  Future<IssuedCode> regenerateCode(String userId, String username) async {
    calls.add('code:$userId');
    final e = error;
    if (e != null) throw e;
    return IssuedCode(username: username, code: nextCode);
  }

  @override
  Future<void> removeAccount(String userId) async {
    calls.add('remove:$userId');
    final e = error;
    if (e != null) throw e;
    entries.removeWhere((x) => x.id == userId);
  }
}
