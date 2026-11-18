import 'dart:async';

import 'package:flutter/material.dart';

import '../data/chat_backend.dart';
import '../data/direct_backend.dart';
import '../models/message.dart';
import '../state/direct_chat_controller.dart';
import '../theme.dart';
import '../util/format.dart';
import 'widgets/flat_form.dart';
import 'widgets/focus_space.dart';
import 'widgets/pixel_glyph.dart';
import 'widgets/section_motion.dart';

/// **Chats** de KyraAdmin: el mismo chat privado 1 a 1 que tiene la familia («Mis chats»: escribirle a cualquiera) y la **supervisión**:
/// todas las conversaciones del servidor, leerlas enteras (también lo que alguien borró solo para sí) y **borrar de verdad** un mensaje o una
/// conversación de la base de datos.
class DirectChatsPage extends StatefulWidget {
  const DirectChatsPage({super.key, required this.chats, required this.backend});

  final DirectChatsController chats;
  final DirectBackend backend;

  @override
  State<DirectChatsPage> createState() => _DirectChatsPageState();
}

class _DirectChatsPageState extends State<DirectChatsPage> {
  bool _supervision = false;
  late final DirectSupervisionController _admin = DirectSupervisionController(widget.backend);

  @override
  void dispose() {
    _admin.dispose();
    super.dispose();
  }

  void _toggle(bool supervision) {
    setState(() => _supervision = supervision);
    if (supervision) unawaited(_admin.refresh());
  }

  Future<void> _newChat() async {
    unawaited(widget.chats.loadPeople());
    final person = await showFocusPanel<ChatUser>(context, title: '¿A quién le escribes?', builder: (_) => _PeoplePicker(chats: widget.chats));
    if (person == null || !mounted) return;
    try {
      final thread = await widget.chats.openWith(person);
      if (mounted) await _openThread(thread);
    } on ChatException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _openThread(DirectThreadController thread) async {
    widget.chats.visibleThread = thread.thread.id;
    unawaited(thread.markRead());
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _ThreadPage(controller: thread)));
    widget.chats.visibleThread = null;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return FlatBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: ListenableBuilder(
              listenable: Listenable.merge([widget.chats, _admin]),
              builder: (context, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FlyIn(
                    edge: MotionEdge.top,
                    order: 0,
                    child: FlatHeader(
                      title: 'CHATS',
                      count: _supervision ? '${_admin.threads.length}' : '${widget.chats.threads.length}',
                      actions: [
                        IconButton(
                          key: const Key('dm-refresh'),
                          tooltip: 'Actualizar',
                          icon: LcdIcon(Icons.refresh_rounded, color: c.ink),
                          onPressed: () => unawaited(_supervision ? _admin.refresh() : widget.chats.refresh()),
                        ),
                        if (!_supervision)
                          IconButton(key: const Key('dm-new'), tooltip: 'Nuevo chat', icon: LcdIcon(Icons.add_rounded, color: c.accent), onPressed: () => unawaited(_newChat())),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  FlyIn(
                    edge: MotionEdge.top,
                    order: 1,
                    child: Row(
                      children: [
                        Expanded(child: FlatChoice(key: const Key('dm-tab-mine'), label: 'Mis chats', selected: !_supervision, onTap: () => _toggle(false))),
                        const SizedBox(width: 8),
                        Expanded(child: FlatChoice(key: const Key('dm-tab-admin'), label: 'Supervisión', selected: _supervision, onTap: () => _toggle(true))),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(child: FlyIn(edge: MotionEdge.bottom, order: 2, child: _supervision ? _supervisionList(context) : _mine(context))),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _mine(BuildContext context) {
    final c = context.colors;
    final chats = widget.chats;
    if (chats.loading && chats.threads.isEmpty) return const Center(child: CircularProgressIndicator(strokeWidth: 2.4));
    if (chats.error != null && chats.threads.isEmpty) return Center(child: Text(chats.error!, style: TextStyle(color: c.warn)));
    if (chats.threads.isEmpty) {
      return Center(child: Text('Aún no hay conversaciones. Toca «+» para escribirle a alguien.', key: const Key('dm-empty'), textAlign: TextAlign.center, style: TextStyle(color: c.dim)));
    }
    return ListView.separated(
      itemCount: chats.threads.length,
      separatorBuilder: (_, _) => Divider(color: c.edge),
      itemBuilder: (context, i) {
        final t = chats.threads[i];
        final last = t.last;
        return ListTile(
          key: Key('dm-thread-${t.other.username}'),
          contentPadding: EdgeInsets.zero,
          leading: LcdIcon(t.other.online ? Icons.circle : Icons.circle_outlined, color: t.other.online ? c.ok : c.dim, size: 14),
          title: Text(t.other.username, style: lcdLabel(color: c.ink)),
          subtitle: Text(last == null ? '' : '${last.senderId == chats.userId ? 'Tú: ' : ''}${last.body}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.dim)),
          trailing: t.unread > 0
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  color: c.accent,
                  child: Text('${t.unread}', style: TextStyle(color: c.onAccent, fontWeight: FontWeight.w700)),
                )
              : null,
          onTap: () => unawaited(_openThread(chats.controllerFor(t))),
        );
      },
    );
  }

  Widget _supervisionList(BuildContext context) {
    final c = context.colors;
    if (_admin.loading && _admin.threads.isEmpty) return const Center(child: CircularProgressIndicator(strokeWidth: 2.4));
    if (_admin.error != null) return Center(child: Text(_admin.error!, style: TextStyle(color: c.warn)));
    if (_admin.threads.isEmpty) return Center(child: Text('No hay conversaciones en el servidor.', style: TextStyle(color: c.dim)));
    return ListView.separated(
      itemCount: _admin.threads.length,
      separatorBuilder: (_, _) => Divider(color: c.edge),
      itemBuilder: (context, i) {
        final t = _admin.threads[i];
        return ListTile(
          key: Key('dm-admin-${t.a.username}-${t.b.username}'),
          contentPadding: EdgeInsets.zero,
          leading: LcdIcon(Icons.forum_outlined, color: c.accent),
          title: Text('${t.a.username}  ↔  ${t.b.username}', style: lcdLabel(color: c.ink)),
          subtitle: Text('${t.count} ${t.count == 1 ? 'mensaje' : 'mensajes'}${t.lastMessageAt == null ? '' : ' · ${clockText(t.lastMessageAt!)}'}', style: TextStyle(color: c.dim)),
          onTap: () => unawaited(Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _SupervisionPage(admin: _admin, thread: t)))),
        );
      },
    );
  }
}

/// Elegir a quién escribir: todas las cuentas verificadas del servidor.
class _PeoplePicker extends StatelessWidget {
  const _PeoplePicker({required this.chats});

  final DirectChatsController chats;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListenableBuilder(
      listenable: chats,
      builder: (context, _) {
        if (chats.loadingPeople) return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)));
        if (chats.people.isEmpty) return Padding(padding: const EdgeInsets.all(20), child: Text('Aún no hay más cuentas.', style: TextStyle(color: c.dim)));
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.6),
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final p in chats.people)
                ListTile(
                  key: Key('dm-person-${p.username}'),
                  leading: LcdIcon(p.online ? Icons.circle : Icons.circle_outlined, color: p.online ? c.ok : c.dim, size: 14),
                  title: Text(p.username, style: lcdLabel(color: c.ink)),
                  trailing: Text(p.role.name == 'admin' ? 'ADMIN' : '', style: hudLabel(size: 12, color: c.accent)),
                  onTap: () => Navigator.of(context).pop(p),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Una conversación propia: los mensajes y escribir. Mantener presionado un mensaje lo borra solo para mí; el menú vacía el chat solo para mí.
class _ThreadPage extends StatefulWidget {
  const _ThreadPage({required this.controller});

  final DirectThreadController controller;

  @override
  State<_ThreadPage> createState() => _ThreadPageState();
}

class _ThreadPageState extends State<_ThreadPage> {
  final _text = TextEditingController();
  String? _lastSeen;

  DirectThreadController get _chat => widget.controller;

  @override
  void initState() {
    super.initState();
    _chat.addListener(_onChange);
  }

  @override
  void dispose() {
    _chat.removeListener(_onChange);
    _text.dispose();
    super.dispose();
  }

  void _onChange() {
    final last = _chat.messages.lastOrNull;
    if (last == null || last.id == _lastSeen) return;
    _lastSeen = last.id;
    if (!_chat.isMine(last)) unawaited(_chat.markRead());
  }

  Future<void> _send() async {
    final body = _text.text;
    if (body.trim().isEmpty) return;
    _text.clear();
    await _chat.send(body);
  }

  Future<void> _clear() async {
    final sure = await _confirm(context, 'Vaciar chat', 'Los mensajes dejarán de verse en tu teléfono. ${_chat.thread.other.username} los seguirá viendo.', 'Vaciar');
    if (sure) await _chat.clear();
  }

  Future<void> _hide(DirectMessage m) async {
    final sure = await _confirm(context, 'Borrar para mí', 'El mensaje dejará de verse en tu teléfono. ${_chat.thread.other.username} lo seguirá viendo.', 'Borrar');
    if (sure) await _chat.hide(m.id);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return FlatBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(_chat.thread.other.username.toUpperCase()),
          actions: [IconButton(key: const Key('dm-clear'), tooltip: 'Vaciar chat (solo para mí)', onPressed: () => unawaited(_clear()), icon: const LcdIcon(Icons.cleaning_services_outlined))],
        ),
        body: ListenableBuilder(
          listenable: _chat,
          builder: (context, _) {
            final messages = _chat.messages.reversed.toList();
            return Column(
              children: [
                Expanded(
                  child: _chat.loading && messages.isEmpty
                      ? const Center(child: CircularProgressIndicator(strokeWidth: 2.4))
                      : ListView.builder(
                          reverse: true,
                          padding: const EdgeInsets.all(16),
                          itemCount: messages.length,
                          itemBuilder: (context, i) {
                            final m = messages[i];
                            final mine = _chat.isMine(m);
                            return Align(
                              alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                              child: GestureDetector(
                                onLongPress: () => unawaited(_hide(m)),
                                onTap: m.state == SendState.failed ? () => unawaited(_chat.retry(m.id)) : null,
                                child: Container(
                                  key: Key('dm-msg-${m.id}'),
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                                  constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
                                  color: m.state == SendState.failed ? c.warn : (mine ? c.accent : c.plate),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(m.body, style: TextStyle(color: mine ? c.onAccent : c.ink)),
                                      const SizedBox(height: 3),
                                      Text(
                                        m.state == SendState.failed ? 'NO SE ENVIÓ · TOCA PARA REINTENTAR' : (m.isPending ? 'ENVIANDO…' : clockText(m.sentAt)),
                                        style: hudLabel(size: 10, color: (mine ? c.onAccent : c.dim).withValues(alpha: 0.8)),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            key: const Key('dm-composer'),
                            controller: _text,
                            minLines: 1,
                            maxLines: 4,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => unawaited(_send()),
                            decoration: const InputDecoration(hintText: 'Escribe un mensaje'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(key: const Key('dm-send'), tooltip: 'Enviar', onPressed: () => unawaited(_send()), icon: LcdIcon(Icons.send_rounded, color: c.accent)),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// La supervisión de una conversación: todos sus mensajes (también los que alguien borró solo para sí) con quién los mandó. Mantener presionado
/// un mensaje lo borra de la base de datos; el botón de arriba borra la conversación entera. Las dos cosas piden confirmar.
class _SupervisionPage extends StatefulWidget {
  const _SupervisionPage({required this.admin, required this.thread});

  final DirectSupervisionController admin;
  final AdminThread thread;

  @override
  State<_SupervisionPage> createState() => _SupervisionPageState();
}

class _SupervisionPageState extends State<_SupervisionPage> {
  List<DirectMessage>? _messages;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final found = await widget.admin.messagesOf(widget.thread.id);
      if (mounted) setState(() => _messages = found);
    } on ChatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _deleteMessage(DirectMessage m) async {
    if (!await _confirm(context, 'Borrar mensaje', 'Se borrará de la base de datos para los dos. No se puede deshacer.', 'Borrar')) return;
    try {
      await widget.admin.deleteMessage(m.id);
      if (mounted) setState(() => _messages = _messages?.where((x) => x.id != m.id).toList());
    } on ChatException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _deleteThread() async {
    final t = widget.thread;
    if (!await _confirm(context, 'Borrar conversación', 'Se borrará de la base de datos la conversación entre ${t.a.username} y ${t.b.username} con todos sus mensajes. No se puede deshacer.', 'Borrar')) {
      return;
    }
    try {
      await widget.admin.deleteThread(t.id);
      if (mounted) Navigator.of(context).pop();
    } on ChatException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = widget.thread;
    final messages = _messages;
    return FlatBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text('${t.a.username} ↔ ${t.b.username}'),
          actions: [IconButton(key: const Key('dm-admin-delete-thread'), tooltip: 'Borrar conversación', onPressed: () => unawaited(_deleteThread()), icon: LcdIcon(Icons.delete_forever_outlined, color: c.warn))],
        ),
        body: _error != null
            ? Center(child: Text(_error!, style: TextStyle(color: c.warn)))
            : messages == null
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2.4))
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: messages.length,
                    separatorBuilder: (_, _) => Divider(color: c.edge),
                    itemBuilder: (context, i) {
                      final m = messages[i];
                      return ListTile(
                        key: Key('dm-admin-msg-${m.id}'),
                        contentPadding: EdgeInsets.zero,
                        title: Text(m.body, style: TextStyle(color: c.ink)),
                        subtitle: Text('${(m.senderName ?? '?').toUpperCase()} · ${clockText(m.sentAt)}', style: hudLabel(size: 11, color: c.dim)),
                        onLongPress: () => unawaited(_deleteMessage(m)),
                      );
                    },
                  ),
      ),
    );
  }
}

Future<bool> _confirm(BuildContext context, String title, String text, String confirm) async {
  final sure = await showFocusPanel<bool>(
    context,
    title: title,
    builder: (context) => FocusDialog(
      content: Text(text),
      actions: [
        TextButton(key: const Key('dm-confirm-cancel'), onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
        FilledButton(
          key: const Key('dm-confirm-ok'),
          style: FilledButton.styleFrom(minimumSize: const Size(0, 40), backgroundColor: context.colors.warn),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirm),
        ),
      ],
    ),
  );
  return sure ?? false;
}
