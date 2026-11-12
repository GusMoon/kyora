import 'package:flutter/material.dart';

import '../../models/message.dart';
import '../../state/chat_controller.dart';
import '../../theme.dart';
import '../../util/format.dart';
import 'attachment_view.dart';
import 'cut_border.dart';
import 'hack_text.dart';

/// Cómo se llama un dispositivo: `movil` → «MÓVIL», `pc` → «PC»; cualquier otro, en mayúsculas. (Ya no se escribe en la terminal: el
/// dispositivo se reconoce por su icono; sirve de etiqueta para accesibilidad.)
String deviceLabel(String device) => switch (device.toLowerCase()) {
  'movil' || 'móvil' || 'phone' || 'telefono' || 'teléfono' => 'MÓVIL',
  'pc' => 'PC',
  _ => device.toUpperCase(),
};

/// El icono de un dispositivo, en lugar de su nombre: el móvil, un teléfono; la PC, una pantalla de computadora; cualquier otro, «otros
/// dispositivos». Todos los mensajes van del mismo color: solo el icono dice de dónde vienen.
IconData deviceIcon(String device) => switch (deviceLabel(device)) {
  'MÓVIL' => Icons.smartphone_rounded,
  'PC' => Icons.desktop_windows_rounded,
  _ => Icons.devices_other_rounded,
};

/// Un mensaje como **línea de terminal**: una barra vertical al principio (siempre del acento, igual en todos los mensajes), el **icono** del
/// dispositivo desde el que se escribió (un teléfono o una computadora: así no hay que leer «PC» o «MÓVIL»), el texto y, debajo, la hora pequeña. Los archivos van como líneas simples `:: nombre · tamaño` (tocables) y, si
/// aún no salió o falló, el aviso en la misma fila de la hora.
class TerminalLine extends StatelessWidget {
  const TerminalLine({super.key, required this.message, required this.controller, required this.onLongPress, required this.onRetry, this.fromHere = false, this.animate = false});

  final Message message;

  /// Se escribió desde este dispositivo: lleva la marca de recibido (lo que llega de la PC ya está recibido por definición).
  final bool fromHere;

  /// El texto se escribe solo (mensajes nuevos, no el historial).
  final bool animate;
  final ChatController controller;
  final VoidCallback onLongPress;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = c.accent;
    final mono = TextStyle(fontFamily: monoFont, fontSize: 16, height: 1.35, color: c.ink);
    return GestureDetector(
      key: Key('bubble-${message.id}'),
      behavior: HitTestBehavior.opaque,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        child: Semantics(
          label: deviceLabel(message.device),
          child: DecoratedBox(
            key: Key('bar-${message.id}'),
            decoration: BoxDecoration(border: Border(left: BorderSide(color: color, width: 3))),
            child: Padding(
              padding: const EdgeInsets.only(left: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // el icono del dispositivo, a la altura de la primera línea de texto
                  Padding(
                    padding: const EdgeInsets.only(top: 2, right: 10),
                    child: Icon(deviceIcon(message.device), key: Key('device-${message.id}'), size: 20, color: color),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (message.hasText) HackText(message.body!, animate: animate, style: mono),
                        for (final attachment in message.attachments) _AttachmentLine(attachment: attachment, controller: controller, color: color),
                        _Footer(message: message, onRetry: onRetry, fromHere: fromHere),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Un archivo en su línea: `:: nombre · tamaño`, sin flechas ni subrayados, tocable.
class _AttachmentLine extends StatelessWidget {
  const _AttachmentLine({required this.attachment, required this.controller, required this.color});

  final Attachment attachment;
  final ChatController controller;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final mono = TextStyle(fontFamily: monoFont, fontSize: 15, height: 1.35, color: color);
    return GestureDetector(
      key: Key(attachment.isImage ? 'image-${attachment.id}' : 'file-${attachment.id}'),
      behavior: HitTestBehavior.opaque,
      onTap: () => openAttachment(context, controller, attachment),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(text: ':: ', style: mono.copyWith(fontWeight: FontWeight.w700)),
              TextSpan(text: attachment.fileName, style: mono),
              TextSpan(text: ' · ${humanSize(attachment.sizeBytes)}', style: mono.copyWith(color: c.dim)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bajo el mensaje: la hora, pequeña y apagada, y el estado: `en cola` mientras espera, `✓` cuando llegó (lo escrito desde aquí), o el error
/// con «Reintentar».
class _Footer extends StatelessWidget {
  const _Footer({required this.message, required this.onRetry, required this.fromHere});

  final Message message;
  final bool fromHere;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final small = TextStyle(fontFamily: monoFont, fontSize: 15, height: 1.3, color: c.dim.withValues(alpha: 0.75));
    final time = Text(clockText(message.sentAt), key: Key('time-${message.id}'), style: small);
    if (message.state == SendState.failed) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          time,
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('ERR · No se envió: ${message.error ?? 'error'} ', style: small.copyWith(color: c.warn)),
              GestureDetector(
                key: Key('retry-${message.id}'),
                onTap: onRetry,
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: cutDecoration(edge: c.accent, cut: 5),
                  child: Text('Reintentar', style: small.copyWith(color: c.accent, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        time,
        if (message.state == SendState.pending) Text('  en cola', key: const Key('waiting'), style: small)
        else if (fromHere) Text('  ✓', key: const Key('sent'), style: small.copyWith(color: c.accent.withValues(alpha: 0.8))),
      ],
    );
  }
}
