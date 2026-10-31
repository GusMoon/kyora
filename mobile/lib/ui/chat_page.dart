import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/chat_backend.dart';
import '../models/message.dart';
import '../state/chat_controller.dart';
import '../theme.dart';
import '../util/format.dart';
import '../util/picker.dart';
import 'widgets/composer.dart';
import 'widgets/message_bubble.dart';

/// El chat: los mensajes de la PC y los de este móvil, con la conexión arriba y el campo para escribir abajo.
class ChatPage extends StatefulWidget {
  const ChatPage({super.key, required this.backend, this.onSignOut, this.controller, this.picker, this.onOpenMusic});

  final ChatBackend backend;
  final Future<void> Function()? onSignOut;

  /// Abre la pantalla de música (las canciones que baja la PC). Sin esto no sale el botón.
  final VoidCallback? onOpenMusic;

  /// Para las pruebas: un controlador ya hecho (si no, la página crea el suyo y lo cierra).
  final ChatController? controller;
  final Picker? picker;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  late final ChatController _controller;
  late final bool _ownsController;
  final _scroll = ScrollController();
  StreamSubscription<String>? _notices;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? ChatController(widget.backend);
    _scroll.addListener(() {
      if (_scroll.hasClients && _scroll.position.extentAfter < 400) unawaited(_controller.loadOlder());
    });
    _notices = _controller.notices.listen((text) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    });
    if (_ownsController) unawaited(_controller.start());
  }

  @override
  void dispose() {
    unawaited(_notices?.cancel());
    _scroll.dispose();
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  String? _send(String text, List<OutgoingFile> files) {
    try {
      _controller.send(text: text, files: files);
    } on ChatException catch (e) {
      return e.message;
    }
    if (_scroll.hasClients) {
      unawaited(_scroll.animateTo(0, duration: const Duration(milliseconds: 220), curve: Curves.easeOut));
    }
    return null;
  }

  Future<void> _menu(Message message) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (message.hasText)
              ListTile(
                key: const Key('menu-copy'),
                leading: const Icon(Icons.copy, color: Palette.accent),
                title: const Text('Copiar texto'),
                onTap: () => Navigator.pop(context, 'copy'),
              ),
            ListTile(
              key: const Key('menu-delete'),
              leading: const Icon(Icons.delete_outline, color: Palette.warn),
              title: const Text('Borrar'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'copy') {
      await Clipboard.setData(ClipboardData(text: message.body ?? ''));
    } else if (action == 'delete') {
      final sure = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('¿Borrar el mensaje?'),
          content: Text(message.state == SendState.sent ? 'Se borra también en la PC.' : 'Todavía no se había enviado.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
            TextButton(
              key: const Key('confirm-delete'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Borrar', style: TextStyle(color: Palette.warn)),
            ),
          ],
        ),
      );
      if (sure == true) await _controller.delete(message.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            titleSpacing: 16,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Chat', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
                _Status(controller: _controller),
              ],
            ),
            actions: [
              if (widget.onOpenMusic != null)
                IconButton(key: const Key('open-music'), tooltip: 'Música', onPressed: widget.onOpenMusic, icon: const Icon(Icons.music_note_outlined)),
              if (widget.onSignOut != null)
                PopupMenuButton<String>(
                  key: const Key('account-menu'),
                  onSelected: (_) => widget.onSignOut!(),
                  itemBuilder: (_) => const [PopupMenuItem(value: 'out', child: Text('Cerrar sesión'))],
                ),
            ],
          ),
          body: Column(
            children: [
              Expanded(child: _list()),
              Composer(onSend: _send, picker: widget.picker ?? pickOutgoing),
            ],
          ),
        );
      },
    );
  }

  Widget _list() {
    final messages = _controller.messages;
    if (messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            _controller.connection == Connection.connecting
                ? 'Cargando tus mensajes…'
                : 'Aún no hay mensajes.\nLo que mandes desde la PC aparece aquí.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Palette.dim),
          ),
        ),
      );
    }
    return ListView.builder(
      key: const Key('message-list'),
      controller: _scroll,
      reverse: true, // el más nuevo abajo, pegado al campo de escribir
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: messages.length + (_controller.loadingOlder ? 1 : 0),
      itemBuilder: (context, i) {
        if (i == messages.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.2))),
          );
        }
        final index = messages.length - 1 - i;
        final message = messages[index];
        final previous = index > 0 ? messages[index - 1] : null;
        final newDay = previous == null || !sameDay(previous.sentAt, message.sentAt);
        final mine = message.device == _controller.device;
        final bubble = MessageBubble(
          message: message,
          mine: mine,
          showDevice: !mine && (newDay || previous.device != message.device),
          controller: _controller,
          onLongPress: () => unawaited(_menu(message)),
          onRetry: () => _controller.retry(message.id),
        );
        if (!newDay) return bubble;
        return Column(children: [_DayChip(label: dayLabel(message.sentAt)), bubble]);
      },
    );
  }
}

/// «Hoy», «Ayer»... separando los días.
class _DayChip extends StatelessWidget {
  const _DayChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    // solo el texto atenuado en el centro, sin cápsula (como en la PC)
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(child: Text(label, style: const TextStyle(color: Palette.dim, fontSize: 13, fontWeight: FontWeight.w700))),
    );
  }
}

/// La conexión, en una línea bajo el título.
class _Status extends StatelessWidget {
  const _Status({required this.controller});

  final ChatController controller;

  @override
  Widget build(BuildContext context) {
    final (text, color) = switch (controller.connection) {
      Connection.online => ('En línea', Palette.accent),
      Connection.connecting => ('Conectando…', Palette.dim),
      Connection.offline => (
          controller.hasPending ? 'Sin conexión · los mensajes saldrán al volver' : 'Sin conexión',
          Palette.warn,
        ),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Flexible(child: Text(text, key: const Key('status'), overflow: TextOverflow.ellipsis, style: TextStyle(color: color, fontSize: 13))),
      ],
    );
  }
}
