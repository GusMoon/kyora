import 'package:flutter/material.dart';

import '../../models/message.dart';
import '../../state/chat_controller.dart';
import '../../theme.dart';
import 'attachment_view.dart';
import 'cut_border.dart';
import 'pixel_glyph.dart';

/// Una ficha de archivo, al estilo de los iconos de referencia: una placa oscura de esquinas cortadas con las cuatro marcas de enfoque por
/// fuera y, dentro, la miniatura (fotos) o el icono y la extensión (documentos). Tocarla abre el archivo.
class FileTile extends StatelessWidget {
  const FileTile({super.key, required this.file, required this.controller, this.size = 84});

  final Attachment file;
  final ChatController controller;
  final double size;

  static String extensionOf(String name) {
    final dot = name.lastIndexOf('.');
    return dot < 0 || dot == name.length - 1 ? 'FILE' : name.substring(dot + 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    const inset = 6.0;
    const plate = CutBorder(cut: 12, all: true);
    return Semantics(
      button: true,
      label: file.fileName,
      child: GestureDetector(
        onTap: () => openAttachment(context, controller, file),
        child: SizedBox.square(
          dimension: size,
          child: CustomPaint(
            foregroundPainter: _ReticlePainter(c.accent),
            child: Padding(
              padding: const EdgeInsets.all(inset),
              child: DecoratedBox(
                decoration: ShapeDecoration(color: Colors.black.withValues(alpha: 0.82), shape: plate),
                child: ClipPath(
                  clipper: const ShapeBorderClipper(shape: plate),
                  child: file.isImage
                      ? AttachmentPicture(attachment: file, controller: controller, resolution: 100)
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            LcdIcon(iconForMime(file.mimeType), size: 26, color: c.accent),
                            const SizedBox(height: 2),
                            Text(extensionOf(file.fileName), maxLines: 1, overflow: TextOverflow.clip, style: TextStyle(fontFamily: monoFont, fontSize: 15, color: c.ink)),
                          ],
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Las cuatro marcas de enfoque en las esquinas, por fuera de la placa.
class _ReticlePainter extends CustomPainter {
  const _ReticlePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..style = PaintingStyle.stroke..strokeWidth = 2..strokeCap = StrokeCap.square..color = color.withValues(alpha: 0.85);
    const l = 9.0;
    const o = 1.0;
    final w = size.width - o, h = size.height - o;
    canvas.drawPath(Path()..moveTo(o, o + l)..lineTo(o, o)..lineTo(o + l, o), p);
    canvas.drawPath(Path()..moveTo(w - l, o)..lineTo(w, o)..lineTo(w, o + l), p);
    canvas.drawPath(Path()..moveTo(o, h - l)..lineTo(o, h)..lineTo(o + l, h), p);
    canvas.drawPath(Path()..moveTo(w - l, h)..lineTo(w, h)..lineTo(w, h - l), p);
  }

  @override
  bool shouldRepaint(covariant _ReticlePainter old) => old.color != color;
}
