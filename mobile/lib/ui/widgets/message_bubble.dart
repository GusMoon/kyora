import 'package:flutter/material.dart';

import '../../models/message.dart';
import '../../state/chat_controller.dart';
import '../../theme.dart';
import '../../util/format.dart';
import 'attachment_view.dart';

/// Un mensaje, con el aire de un chat con un agente (como Claude): lo de este dispositivo en una burbuja gris a la derecha;
/// lo de los otros (la PC) como texto suelto a la izquierda, sin burbuja, firmado con un ✦ y el nombre del dispositivo.
/// Lleva la hora de envío y el estado: reloj «En espera», ✓ enviado, o el error con «Reintentar».
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
    final width = MediaQuery.sizeOf(context).width;
    final boxed = mine && message.hasText; // solo lo mío con texto va en burbuja; los adjuntos sueltos, como tarjetas
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: mine ? 4 : 6),
      child: Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: width * (mine ? 0.8 : 0.92)),
          child: Column(
            crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (showDevice)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4, top: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('✦', style: TextStyle(color: Palette.accent, fontSize: 15)),
                      const SizedBox(width: 6),
                      Text(message.device, style: const TextStyle(color: Palette.dim, fontSize: 13, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              GestureDetector(
                key: Key('bubble-${message.id}'),
                onLongPress: onLongPress,
                child: Container(
                  padding: boxed || failed ? const EdgeInsets.fromLTRB(14, 10, 14, 8) : const EdgeInsets.symmetric(vertical: 2),
                  decoration: BoxDecoration(
                    color: boxed ? Palette.mine : null,
                    borderRadius: BorderRadius.circular(18),
                    border: failed ? Border.all(color: Palette.warn) : null,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                    children: [
                      for (final attachment in message.attachments) AttachmentView(attachment: attachment, controller: controller),
                      if (message.hasText) Text(message.body!, style: const TextStyle(fontSize: 16, height: 1.35)),
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
    const small = TextStyle(color: Palette.dim, fontSize: 13);
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
