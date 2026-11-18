import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/direct_backend.dart';
import '../../models/message.dart';
import '../../models/profile.dart';
import '../../state/direct_chat_controller.dart';
import '../../util/format.dart';
import 'neo_dialogs.dart';
import 'neo_pager.dart';
import 'neo_theme.dart';
import 'neo_widgets.dart';

/// El **chat privado** de KyraFamily: cada quien le escribe a quien quiera (uno a uno). Sin sesión o sin verificar la cuenta enseña qué
/// falta y lleva a Ajustes; con ella:
///  · la lista de tus conversaciones (la más reciente arriba, con los no leídos) y «Nuevo chat» para elegir a quién escribir de todas las
///    cuentas del servidor;
///  · la conversación: tus mensajes en el color «pop» a la derecha y los del otro a la izquierda. Mantener presionado un mensaje lo
///    **borra solo para ti**, y el menú ⋯ **vacía el chat solo para ti**. En el servidor nada se borra (eso solo lo hace el administrador).
class NeoChatPage extends StatelessWidget {
  const NeoChatPage({super.key, required this.signedIn, required this.verified, required this.controller, required this.onOpenSettings});

  final bool signedIn;
  final bool verified;

  /// El chat ya abierto (solo hay uno con sesión y cuenta verificada).
  final DirectChatsController? controller;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final chat = controller;
    if (!signedIn || !verified || chat == null) return _Locked(signedIn: signedIn, onOpenSettings: onOpenSettings);
    return DirectChatView(controller: chat);
  }
}

class _Locked extends StatelessWidget {
  const _Locked({required this.signedIn, required this.onOpenSettings});

  final bool signedIn;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final s = context.neo;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
      children: [
        const NeoSlide(order: 0, child: NeoHero(index: '02', title: 'Chat', tagline: 'Privado. Uno a uno. Con quien quieras.')),
        const SizedBox(height: 22),
        NeoSlide(
          order: 1,
          child: NeoWindow(
            index: '01',
            title: signedIn ? 'Falta verificar' : 'Chat bloqueado',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(signedIn ? Icons.pin_outlined : Icons.lock_outline_rounded, size: 40, color: s.ink),
                const SizedBox(height: 12),
                Text(
                  key: const Key('neo-chat-locked'),
                  signedIn
                      ? 'Escribe el código de 6 dígitos que te dio el administrador para activar tu cuenta.'
                      : 'Inicia sesión con tu nombre y contraseña para escribirle a quien quieras.',
                  style: neoBody(color: s.ink),
                ),
                const SizedBox(height: 16),
                NeoButton(key: const Key('neo-chat-go-settings'), label: signedIn ? 'Escribir el código' : 'Ir a Ajustes', icon: Icons.settings_rounded, onTap: onOpenSettings),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// El chat con sesión: la lista, elegir persona o una conversación abierta (todo dentro de la misma pantalla; «atrás» vuelve un paso).
class DirectChatView extends StatefulWidget {
  const DirectChatView({super.key, required this.controller});

  final DirectChatsController controller;

  @override
  State<DirectChatView> createState() => _DirectChatViewState();
}

class _DirectChatViewState extends State<DirectChatView> {
  DirectThreadController? _thread;
  bool _picking = false;

  DirectChatsController get _chats => widget.controller;

  void _openThread(DirectThreadController thread) {
    setState(() {
      _thread = thread;
      _picking = false;
    });
    _chats.visibleThread = thread.thread.id;
    unawaited(thread.markRead());
  }

  Future<void> _startWith(ChatUser person) async {
    try {
      final thread = await _chats.openWith(person);
      if (mounted) _openThread(thread);
    } on Exception catch (e) {
      if (mounted) neoToast(context, e.toString());
    }
  }

  void _pick() {
    setState(() => _picking = true);
    unawaited(_chats.loadPeople());
  }

  void _back() {
    setState(() {
      _thread = null;
      _picking = false;
    });
    _chats.visibleThread = null;
  }

  @override
  void dispose() {
    _chats.visibleThread = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final thread = _thread;
    return PopScope(
      canPop: thread == null && !_picking,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: ListenableBuilder(
        listenable: _chats,
        builder: (context, _) {
          if (thread != null) return _ThreadView(controller: thread, onBack: _back);
          if (_picking) return _People(chats: _chats, onBack: _back, onPick: (p) => unawaited(_startWith(p)));
          return _Threads(chats: _chats, onNew: _pick, onOpen: (t) => _openThread(_chats.controllerFor(t)));
        },
      ),
    );
  }
}

// ---------- la lista de conversaciones ----------

class _Threads extends StatelessWidget {
  const _Threads({required this.chats, required this.onNew, required this.onOpen});

  final DirectChatsController chats;
  final VoidCallback onNew;
  final ValueChanged<DirectThread> onOpen;

  @override
  Widget build(BuildContext context) {
    final s = context.neo;
    return RefreshIndicator(
      onRefresh: chats.refresh,
      child: ListView(
        key: const Key('neo-chat-list'),
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
        children: [
          NeoSlide(
            order: 0,
            child: NeoHero(
              index: '02',
              title: 'Chat',
              tagline: 'Privado. Uno a uno. Con quien quieras.',
              trailing: NeoTag(chats.live ? 'En vivo' : 'Sin conexión', color: chats.live ? s.pop : Neo.warn),
            ),
          ),
          const SizedBox(height: 20),
          NeoSlide(order: 1, child: NeoButton(key: const Key('neo-new-chat'), label: 'Nuevo chat', icon: Icons.edit_square, onTap: onNew)),
          const SizedBox(height: 18),
          if (chats.error != null) ...[NeoNotice(chats.error!, noticeKey: const Key('neo-chat-error')), const SizedBox(height: 14)],
          if (chats.loading && chats.threads.isEmpty)
            const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(strokeWidth: 3)))
          else if (chats.threads.isEmpty)
            NeoSlide(
              order: 2,
              child: NeoWindow(
                index: '01',
                title: 'Sin conversaciones',
                child: Text('Aún no le has escrito a nadie. Toca «Nuevo chat» y elige a quién.', key: const Key('neo-chat-empty'), style: neoBody(color: s.ink)),
              ),
            )
          else
            NeoSlide(
              order: 2,
              child: Column(
                children: [
                  for (final t in chats.threads) ...[
                    _ThreadTile(thread: t, mine: t.last?.senderId == chats.userId, onTap: () => onOpen(t)),
                    const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ThreadTile extends StatelessWidget {
  const _ThreadTile({required this.thread, required this.mine, required this.onTap});

  final DirectThread thread;
  final bool mine;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.neo;
    final last = thread.last;
    return NeoPress(
      key: Key('neo-thread-${thread.other.username}'),
      strong: thread.unread > 0,
      padding: const EdgeInsets.all(12),
      onTap: onTap,
      child: Row(
        children: [
          _Avatar(person: thread.other),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(thread.other.username.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: neoLabel(size: 13, color: s.ink))),
                    if (last != null) Text(clockText(last.sentAt), style: neoLabel(size: 10, color: s.dim)),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  last == null ? '' : '${mine ? 'Tú: ' : ''}${last.body}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: neoBody(size: 14, color: thread.unread > 0 ? s.ink : s.dim, weight: thread.unread > 0 ? FontWeight.w700 : FontWeight.w500),
                ),
              ],
            ),
          ),
          if (thread.unread > 0) ...[const SizedBox(width: 8), NeoTag('${thread.unread}', key: Key('neo-unread-${thread.other.username}'))],
        ],
      ),
    );
  }
}

/// La inicial de una persona en un cuadrito del acento, con un punto si está en línea.
class _Avatar extends StatelessWidget {
  const _Avatar({required this.person, this.size = 42});

  final ChatUser person;
  final double size;

  @override
  Widget build(BuildContext context) {
    final s = context.neo;
    final initial = person.username.isEmpty ? '?' : person.username.characters.first.toUpperCase();
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: s.accent, border: Border.all(color: s.ink, width: Neo.border)),
            child: Text(initial, style: neoHeading(size: size * 0.5, color: s.onAccent)),
          ),
          if (person.online)
            Positioned(
              right: -3,
              bottom: -3,
              child: Container(width: 11, height: 11, decoration: BoxDecoration(color: Neo.ok, border: Border.all(color: s.paper, width: 2))),
            ),
        ],
      ),
    );
  }
}

// ---------- elegir a quién escribir ----------

class _People extends StatelessWidget {
  const _People({required this.chats, required this.onBack, required this.onPick});

  final DirectChatsController chats;
  final VoidCallback onBack;
  final ValueChanged<ChatUser> onPick;

  @override
  Widget build(BuildContext context) {
    final s = context.neo;
    return ListView(
      key: const Key('neo-people-list'),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
      children: [
        Row(
          children: [
            NeoIconButton(key: const Key('neo-people-back'), icon: Icons.arrow_back_rounded, tooltip: 'Volver', onTap: onBack),
            const SizedBox(width: 12),
            Expanded(child: Text('¿A QUIÉN LE ESCRIBES?', style: neoHeading(size: 24, color: s.ink))),
          ],
        ),
        const SizedBox(height: 18),
        if (chats.loadingPeople)
          const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(strokeWidth: 3)))
        else if (chats.people.isEmpty)
          NeoWindow(title: 'Nadie todavía', child: Text('Aún no hay más cuentas en el servidor.', style: neoBody(color: s.ink)))
        else
          for (final p in chats.people) ...[
            NeoPress(
              key: Key('neo-person-${p.username}'),
              strong: false,
              padding: const EdgeInsets.all(12),
              onTap: () => onPick(p),
              child: Row(
                children: [
                  _Avatar(person: p, size: 38),
                  const SizedBox(width: 12),
                  Expanded(child: Text(p.username.toUpperCase(), style: neoLabel(size: 13, color: s.ink))),
                  if (p.role == Role.admin) NeoTag('Admin', color: s.accent),
                  const SizedBox(width: 8),
                  Icon(Icons.north_east_rounded, size: 18, color: s.accent),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
      ],
    );
  }
}

// ---------- una conversación ----------

class _ThreadView extends StatefulWidget {
  const _ThreadView({required this.controller, required this.onBack});

  final DirectThreadController controller;
  final VoidCallback onBack;

  @override
  State<_ThreadView> createState() => _ThreadViewState();
}

class _ThreadViewState extends State<_ThreadView> {
  final _text = TextEditingController();
  bool _sending = false;
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

  /// Llegó algo nuevo del otro mientras se ve la conversación: se da por leído.
  void _onChange() {
    final last = _chat.messages.lastOrNull;
    if (last == null || last.id == _lastSeen) return;
    _lastSeen = last.id;
    if (!_chat.isMine(last)) unawaited(_chat.markRead());
  }

  Future<void> _send() async {
    if (_sending || _text.text.trim().isEmpty) return;
    final body = _text.text;
    setState(() => _sending = true);
    _text.clear();
    try {
      await _chat.send(body);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _messageMenu(DirectMessage m) async {
    final choice = await showNeoMenu<String>(
      context,
      title: 'Mensaje',
      options: [
        const NeoMenuOption(value: 'hide', label: 'Borrar para mí', icon: Icons.visibility_off_outlined, danger: true, key: Key('neo-msg-hide')),
      ],
    );
    if (choice == 'hide') await _chat.hide(m.id);
  }

  Future<void> _threadMenu() async {
    final choice = await showNeoMenu<String>(
      context,
      title: _chat.thread.other.username,
      options: [
        const NeoMenuOption(value: 'clear', label: 'Vaciar chat (solo para mí)', icon: Icons.cleaning_services_outlined, danger: true, key: Key('neo-thread-clear')),
      ],
    );
    if (choice != 'clear' || !mounted) return;
    final sure = await neoConfirm(
      context,
      title: 'Vaciar chat',
      text: 'Los mensajes de esta conversación dejarán de verse en tu teléfono. ${_chat.thread.other.username} los seguirá viendo.',
      confirm: 'Vaciar',
      confirmKey: const Key('neo-thread-clear-confirm'),
    );
    if (sure) await _chat.clear();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.neo;
    final other = _chat.thread.other;
    return ListenableBuilder(
      listenable: _chat,
      builder: (context, _) {
        final messages = _chat.messages.reversed.toList(); // la lista va al revés: lo más nuevo, abajo
        return Column(
          children: [
            NeoSlide(
              order: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: s.line, width: Neo.border))),
                child: Row(
                  children: [
                    NeoIconButton(key: const Key('neo-thread-back'), icon: Icons.arrow_back_rounded, tooltip: 'Volver', size: 40, onTap: widget.onBack),
                    const SizedBox(width: 12),
                    _Avatar(person: other, size: 38),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(other.username.toUpperCase(), key: const Key('neo-thread-title'), maxLines: 1, overflow: TextOverflow.ellipsis, style: neoHeading(size: 20, color: s.ink)),
                          Text(other.online ? 'EN LÍNEA' : 'PRIVADO', style: neoLabel(size: 10, color: other.online ? Neo.ok : s.dim)),
                        ],
                      ),
                    ),
                    IconButton(key: const Key('neo-thread-menu'), tooltip: 'Opciones', onPressed: () => unawaited(_threadMenu()), icon: Icon(Icons.more_vert_rounded, color: s.ink)),
                  ],
                ),
              ),
            ),
            Expanded(
              child: NeoSlide(
                order: 1,
                child: _chat.loading && messages.isEmpty
                    ? const Center(child: CircularProgressIndicator(strokeWidth: 3))
                    : (_chat.error != null && messages.isEmpty)
                        ? Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                NeoNotice(_chat.error!),
                                const SizedBox(height: 12),
                                NeoButton(label: 'Reintentar', icon: Icons.refresh_rounded, onTap: () => unawaited(_chat.refresh())),
                              ],
                            ),
                          )
                        : messages.isEmpty
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Text('Escríbele a ${other.username}.', key: const Key('neo-thread-empty'), textAlign: TextAlign.center, style: neoBody(color: s.dim)),
                                ),
                              )
                            : ListView.separated(
                                key: const Key('neo-thread-list'),
                                reverse: true,
                                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                                itemCount: messages.length,
                                separatorBuilder: (_, _) => const SizedBox(height: 10),
                                itemBuilder: (context, i) {
                                  final m = messages[i];
                                  return _Bubble(
                                    message: m,
                                    mine: _chat.isMine(m),
                                    onRetry: m.state == SendState.failed ? () => unawaited(_chat.retry(m.id)) : null,
                                    onMenu: () => unawaited(_messageMenu(m)),
                                  );
                                },
                              ),
              ),
            ),
            NeoSlide(order: 2, child: _Composer(controller: _text, sending: _sending, onSend: () => unawaited(_send()))),
          ],
        );
      },
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.mine, required this.onMenu, this.onRetry});

  final DirectMessage message;
  final bool mine;
  final VoidCallback onMenu;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final s = context.neo;
    final failed = onRetry != null;
    final fill = failed ? Neo.warn : (mine ? s.pop : s.paper);
    final text = failed ? Neo.white : s.onColor(fill);
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.8),
        child: GestureDetector(
          onLongPress: onMenu,
          child: NeoBox(
            key: Key('neo-msg-${message.id}'),
            color: fill,
            strong: mine || failed,
            padding: const EdgeInsets.fromLTRB(12, 9, 12, 7),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(message.body, style: neoBody(color: text, weight: FontWeight.w600)),
                const SizedBox(height: 5),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(clockText(message.sentAt), style: neoLabel(size: 10, color: text.withValues(alpha: 0.7))),
                    if (message.isPending) ...[const SizedBox(width: 6), Icon(Icons.schedule_rounded, size: 13, color: text)],
                    if (failed) ...[
                      const SizedBox(width: 8),
                      GestureDetector(key: const Key('neo-retry'), onTap: onRetry, child: Text('REINTENTAR', style: neoLink(text))),
                    ],
                  ],
                ),
                if (failed && message.error != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(message.error!, style: neoBody(size: 12, color: text))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({required this.controller, required this.sending, required this.onSend});

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final s = context.neo;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(color: s.paper, border: Border(top: BorderSide(color: s.ink, width: Neo.border))),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              key: const Key('neo-composer'),
              controller: controller,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              style: neoBody(weight: FontWeight.w700, color: s.ink),
              decoration: const InputDecoration(hintText: 'Escribe un mensaje'),
            ),
          ),
          const SizedBox(width: 10),
          NeoIconButton(key: const Key('neo-send'), icon: Icons.send_rounded, tooltip: 'Enviar', color: s.ink, iconColor: NeoScheme.readableOn(s.pop, s.ink, 3), size: 50, onTap: sending ? null : onSend),
        ],
      ),
    );
  }
}
