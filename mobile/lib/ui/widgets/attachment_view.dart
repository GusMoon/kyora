import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/message.dart';
import '../../state/chat_controller.dart';
import '../../theme.dart';
import '../image_viewer.dart';
import 'pixel_glyph.dart';
import 'lcd_image.dart';

/// Abre un adjunto: la foto a pantalla completa (la del teléfono si aún está, o la del servidor) o el archivo con la app que lo sepa abrir.
Future<void> openAttachment(BuildContext context, ChatController controller, Attachment attachment) =>
    attachment.isImage ? _openImage(context, controller, attachment) : _openFile(context, controller, attachment);

Future<void> _openImage(BuildContext context, ChatController controller, Attachment attachment) async {
  final navigator = Navigator.of(context);
  final local = _localFile(attachment);
  ImageProvider provider;
  if (local != null) {
    provider = FileImage(local);
  } else {
    try {
      provider = NetworkImage(await controller.urlFor(attachment));
    } catch (_) {
      return;
    }
  }
  await navigator.push(MaterialPageRoute<void>(builder: (_) => ImageViewerPage(image: provider, title: attachment.fileName)));
}

Future<void> _openFile(BuildContext context, ChatController controller, Attachment attachment) async {
  final messenger = ScaffoldMessenger.of(context);
  if (attachment.storagePath == null) {
    messenger.showSnackBar(const SnackBar(content: Text('El archivo aún no se ha enviado.')));
    return;
  }
  try {
    final url = await controller.urlFor(attachment);
    final opened = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!opened) messenger.showSnackBar(const SnackBar(content: Text('No hay ninguna app que pueda abrir este archivo.')));
  } catch (_) {
    messenger.showSnackBar(const SnackBar(content: Text('No se pudo abrir el archivo.')));
  }
}

/// La foto de un adjunto (la del teléfono si aún está; si no, la del servidor), en dos tonos con su trama, a [resolution] puntos.
class AttachmentPicture extends StatelessWidget {
  const AttachmentPicture({super.key, required this.attachment, required this.controller, this.resolution = 200});

  final Attachment attachment;
  final ChatController controller;
  final int resolution;

  @override
  Widget build(BuildContext context) {
    final local = _localFile(attachment);
    if (local != null) return LcdImage(image: FileImage(local), resolution: resolution, error: const _Broken(), placeholder: const _Loading());
    return FutureBuilder<String>(
      future: controller.urlFor(attachment),
      builder: (context, snapshot) {
        if (snapshot.hasError) return const _Broken();
        final url = snapshot.data;
        if (url == null || url.isEmpty) return const _Loading();
        return LcdImage(image: NetworkImage(url), resolution: resolution, error: const _Broken(), placeholder: const _Loading());
      },
    );
  }
}

File? _localFile(Attachment attachment) {
  final path = attachment.localPath;
  if (path == null) return null;
  final file = File(path);
  return file.existsSync() ? file : null;
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => Center(child: Text('cargando…', style: lcdStatus(color: context.colors.ink)));
}

class _Broken extends StatelessWidget {
  const _Broken();

  @override
  Widget build(BuildContext context) =>
      Center(child: LcdIcon(Icons.broken_image_outlined, color: context.colors.ink, size: 34));
}

IconData iconForMime(String mime) {
  final value = mime.toLowerCase();
  if (value == 'application/pdf') return Icons.picture_as_pdf_outlined;
  if (value.startsWith('audio/')) return Icons.audiotrack_outlined;
  if (value.startsWith('video/')) return Icons.videocam_outlined;
  if (value.contains('zip') || value.contains('rar') || value.contains('7z') || value.contains('tar')) return Icons.folder_zip_outlined;
  if (value.startsWith('text/') || value.contains('word') || value.contains('sheet') || value.contains('presentation')) {
    return Icons.description_outlined;
  }
  return Icons.insert_drive_file_outlined;
}
