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
import 'widgets/file_tile.dart';
import 'widgets/terminal_line.dart';
import 'widgets/terminal_window.dart';
import 'widgets/section_motion.dart';
import 'widgets/pixel_glyph.dart';
import 'widgets/hack_text.dart';
import 'widgets/focus_space.dart';

/// El chat como una **terminal**: un registro de lo que escribes (desde la PC o desde este móvil), cada línea con una barra del color del dispositivo.
/// Un botón enseña arriba, fuera de la terminal, la tira de los archivos enviados; el prompt para escribir va abajo, dentro de la ventana, y la
/// conexión en su cabecera.
class ChatPage extends StatefulWidget {
  const ChatPage({super.key, required this.backend, this.controller, this.picker});

  final ChatBackend backend;

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
  /// Los mensajes que ya estaban cuando se abrió la página (salen sin escribirse) y los que ya se escribieron.
  Set<String>? _baseline;
  final Set<String> _typed = {};
  bool _showFiles = false; // la tira de archivos solo sale si se pide
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
      unawaited(_scroll.animateTo(0, duration: const Duration(milliseconds: 220), curve: Curves.easeOutCubic));
    }
    return null;
  }

  Future<void> _menu(Message message) async {
    final action = await showFocusPanel<String>(context, builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (message.hasText)
              ListTile(
                key: const Key('menu-copy'),
                leading: LcdIcon(Icons.copy, color: context.colors.accent),
                title: const Text('Copiar texto'),
                onTap: () => Navigator.pop(context, 'copy'),
              ),
            ListTile(
              key: const Key('menu-delete'),
              leading: LcdIcon(Icons.delete_outline, color: context.colors.warn),
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
      final sure = await showFocusPanel<bool>(
        context,
        title: '¿Borrar el mensaje?',
        builder: (context) => FocusDialog(
          content: Text(message.state == SendState.sent ? 'Se borra también en la PC.' : 'Todavía no se había enviado.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
            TextButton(
              key: const Key('confirm-delete'),
              onPressed: () => Navigator.pop(context, true),
              child: Text('Borrar', style: TextStyle(color: context.colors.warn)),
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
        if (_baseline == null && _controller.connection != Connection.connecting) _baseline = {for (final m in _controller.messages) m.id};
        final files = [
          for (final message in _controller.messages.reversed) ...message.attachments,
        ];
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_showFiles) FlyIn(edge: MotionEdge.top, child: _FilesStrip(files: files, controller: _controller)),
                  Expanded(
                    child: FlyIn(
                      edge: MotionEdge.top,
                      child: TerminalWindow(
                        key: const Key('chat-terminal'),
                        title: 'KYORA :: TERMINAL',
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _Status(controller: _controller),
                            const SizedBox(width: 4),
                            IconButton(
                              key: const Key('chat-files-toggle'),
                              tooltip: _showFiles ? 'Ocultar archivos' : 'Mostrar archivos',
                              visualDensity: VisualDensity.compact,
                              onPressed: () => setState(() => _showFiles = !_showFiles),
                              icon: LcdIcon(_showFiles ? Icons.folder_open_outlined : Icons.folder_outlined, size: 22, color: _showFiles ? context.colors.accent : context.colors.dim),
                            ),
                          ],
                        ),
                        footer: Composer(onSend: _send, picker: widget.picker ?? pickOutgoing),
                        child: FlyIn(edge: MotionEdge.left, order: 2, child: _list()),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _list() {
    final messages = _controller.messages;
    final mono = TextStyle(fontFamily: monoFont, fontSize: 15, height: 1.4, color: context.colors.dim);
    if (messages.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: HackText(
          _controller.connection == Connection.connecting
              ? '> cargando registros…'
              : '> sin registros.\n> lo que escribas desde la PC o desde el móvil se guarda aquí_',
          textKey: const Key('chat-empty'),
          order: 2,
          style: mono,
        ),
      );
    }
    return ListView.builder(
      key: const Key('message-list'),
      controller: _scroll,
      reverse: true, // el más nuevo abajo, pegado al prompt
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: messages.length + (_controller.loadingOlder ? 1 : 0),
      itemBuilder: (context, i) {
        if (i == messages.length) {
          return Padding(padding: const EdgeInsets.all(16), child: Text('> cargando más…', style: mono));
        }
        final index = messages.length - 1 - i;
        final message = messages[index];
        final previous = index > 0 ? messages[index - 1] : null;
        final newDay = previous == null || !sameDay(previous.sentAt, message.sentAt);
        final line = TerminalLine(
          message: message,
          controller: _controller,
          fromHere: message.device == _controller.device,
          // solo se escriben los mensajes nuevos, una vez
          animate: _baseline != null && !_baseline!.contains(message.id) && _typed.add(message.id),
          onLongPress: () => unawaited(_menu(message)),
          onRetry: () => _controller.retry(message.id),
        );
        if (!newDay) return line;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [_DayChip(label: dayLabel(message.sentAt)), line]);
      },
    );
  }
}

/// La tira de los archivos enviados, del más nuevo al más viejo, **fuera de la terminal**: fichas de enfoque con la miniatura de las fotos y el
/// icono y la extensión de los documentos. Tocar una la abre.
class _FilesStrip extends StatelessWidget {
  const _FilesStrip({required this.files, required this.controller});

  final List<Attachment> files;
  final ChatController controller;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (files.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text('> sin archivos enviados', key: const Key('chat-files-empty'), style: TextStyle(fontFamily: monoFont, fontSize: 15, color: c.dim)),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SizedBox(
        key: const Key('chat-files'),
        height: 84,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: files.length,
          separatorBuilder: (_, _) => const SizedBox(width: 6),
          itemBuilder: (context, i) => KeyedSubtree(key: Key('strip-file-${files[i].id}'), child: FileTile(file: files[i], controller: controller)),
        ),
      ),
    );
  }
}

/// «Hoy», «Ayer»... separando los días.
class _DayChip extends StatelessWidget {
  const _DayChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    // ── HOY ── : una regla fina a cada lado, como en una terminal
    final c = context.colors;
    final rule = Expanded(child: Container(height: 1, color: c.accent.withValues(alpha: 0.25)));
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      child: Row(
        children: [
          rule,
          Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Text(label.toUpperCase(), style: TextStyle(fontFamily: monoFont, fontSize: 15, letterSpacing: 1.5, color: c.dim))),
          rule,
        ],
      ),
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
      Connection.online => ('En línea', context.colors.accent),
      Connection.connecting => ('Conectando…', context.colors.dim),
      Connection.offline => (
          controller.hasPending ? 'Sin conexión · los mensajes saldrán al volver' : 'Sin conexión',
          context.colors.warn,
        ),
    };
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 170),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 8, height: 8, color: color),
          const SizedBox(width: 6),
          Flexible(child: HackText(text.toLowerCase(), textKey: const Key('status'), order: 1, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: monoFont, fontSize: 15, color: color))),
        ],
      ),
    );
  }
}
