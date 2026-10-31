import 'package:flutter/material.dart';

import '../../models/message.dart';
import '../../state/chat_controller.dart';
import '../../theme.dart';
import '../../util/format.dart';
import 'attachment_view.dart';

/// Una burbuja de mensaje: las de este dispositivo a la derecha, las de los otros (la PC) a la izquierda con el nombre del
/// dispositivo. Lleva la hora de envío y el estado: reloj «En espera», ✓ enviado, o el error con «Reintentar».
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.mine,
    required this.showDevice,
    required this.controller,
    required this.onLongPress,
    required this.onRetry,
  });

  final Message message;
  final bool mine;
  final bool showDevice;
  final ChatController controller;
  final VoidCallback onLongPress;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final failed = message.state == SendState.failed;
    final maxWidth = MediaQuery.sizeOf(context).width * 0.8;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Column(
            crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (showDevice)
                Padding(
                  padding: const EdgeInsets.only(left: 6, bottom: 2, top: 4),
                  child: Text(message.device, style: const TextStyle(color: Palette.dim, fontSize: 13, fontWeight: FontWeight.w700)),
                ),
              GestureDetector(
                key: Key('bubble-${message.id}'),
                onLongPress: onLongPress,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                  decoration: BoxDecoration(
                    color: mine ? Palette.mine : Palette.plate,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: failed ? Palette.warn : Palette.edge),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final attachment in message.attachments) AttachmentView(attachment: attachment, controller: controller),
                      if (message.hasText) Text(message.body!, style: const TextStyle(fontSize: 16, height: 1.25)),
                      const SizedBox(height: 4),
                      _Meta(message: message, mine: mine, onRetry: onRetry),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.message, required this.mine, required this.onRetry});

  final Message message;
  final bool mine;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    const small = TextStyle(color: Palette.dim, fontSize: 12);
    final state = message.state;
    if (state == SendState.failed) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('No se envió: ${message.error ?? 'error'}', style: const TextStyle(color: Palette.warn, fontSize: 13)),
          const SizedBox(height: 2),
          GestureDetector(
            key: Key('retry-${message.id}'),
            onTap: onRetry,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Text('Reintentar', style: TextStyle(color: Palette.accent, fontWeight: FontWeight.w700, fontSize: 14)),
            ),
          ),
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(clockText(message.sentAt), style: small),
        if (state == SendState.pending) ...[
          const SizedBox(width: 6),
          const Text('En espera', key: Key('waiting'), style: small),
          const SizedBox(width: 4),
          const Icon(Icons.schedule, size: 14, color: Palette.dim),
        ] else if (mine) ...[
          const SizedBox(width: 6),
          const Icon(Icons.check, key: Key('sent'), size: 15, color: Palette.accent),
        ],
      ],
    );
  }
}
