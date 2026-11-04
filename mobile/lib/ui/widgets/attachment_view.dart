import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/message.dart';
import '../../state/chat_controller.dart';
import '../../theme.dart';
import '../../util/format.dart';
import '../image_viewer.dart';

/// Un adjunto dentro de una burbuja: la foto (con miniatura, y a pantalla completa al tocarla) o el archivo como tarjeta.
class AttachmentView extends StatelessWidget {
  const AttachmentView({super.key, required this.attachment, required this.controller});

  final Attachment attachment;
  final ChatController controller;

  @override
  Widget build(BuildContext context) =>
      attachment.isImage ? _ImageAttachment(attachment: attachment, controller: controller) : _FileAttachment(attachment: attachment, controller: controller);
}

File? _localFile(Attachment attachment) {
  final path = attachment.localPath;
  if (path == null) return null;
  final file = File(path);
  return file.existsSync() ? file : null;
}

class _ImageAttachment extends StatelessWidget {
  const _ImageAttachment({required this.attachment, required this.controller});

  final Attachment attachment;
  final ChatController controller;

  double get _ratio {
    final w = attachment.width, h = attachment.height;
    if (w == null || h == null || w <= 0 || h <= 0) return 4 / 3;
    return (w / h).clamp(0.6, 1.8);
  }

  Future<void> _open(BuildContext context) async {
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

  @override
  Widget build(BuildContext context) {
    final local = _localFile(attachment);
    final Widget image = local != null
        ? Image.file(local, fit: BoxFit.cover, cacheWidth: 900, errorBuilder: (_, _, _) => const _Broken())
        : FutureBuilder<String>(
            future: controller.urlFor(attachment),
            builder: (context, snapshot) {
              if (snapshot.hasError) return const _Broken();
              final url = snapshot.data;
              if (url == null || url.isEmpty) return const _Loading();
              return Image.network(
                url,
                fit: BoxFit.cover,
                cacheWidth: 900,
                loadingBuilder: (context, child, progress) => progress == null ? child : const _Loading(),
                errorBuilder: (_, _, _) => const _Broken(),
              );
            },
          );
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: GestureDetector(
        key: Key('image-${attachment.id}'),
        onTap: () => _open(context),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 260),
          child: AspectRatio(
            aspectRatio: _ratio,
            child: ClipRRect(borderRadius: BorderRadius.circular(12), child: image),
          ),
        ),
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: Color(0x14FFFFFF),
        child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.2, color: context.colors.dim))),
      );
}

class _Broken extends StatelessWidget {
  const _Broken();

  @override
  Widget build(BuildContext context) =>
      ColoredBox(color: Color(0x14FFFFFF), child: Center(child: Icon(Icons.broken_image_outlined, color: context.colors.dim, size: 34)));
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

class _FileAttachment extends StatelessWidget {
  const _FileAttachment({required this.attachment, required this.controller});

  final Attachment attachment;
  final ChatController controller;

  Future<void> _open(BuildContext context) async {
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

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        key: Key('file-${attachment.id}'),
        borderRadius: BorderRadius.circular(12),
        onTap: () => _open(context),
        child: Container(
          constraints: const BoxConstraints(minWidth: 240),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          // una tarjeta lisa con borde fino, como las de la PC
          decoration: BoxDecoration(color: context.colors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: context.colors.edge)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(iconForMime(attachment.mimeType), color: context.colors.accent, size: 30),
              const SizedBox(width: 12),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(attachment.fileName, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(humanSize(attachment.sizeBytes), style: TextStyle(color: context.colors.dim, fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
