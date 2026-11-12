import 'package:flutter/material.dart';

import '../../state/chat_controller.dart';
import '../../theme.dart';
import '../../util/format.dart';
import '../../util/picker.dart';
import 'pixel_glyph.dart';
import 'focus_space.dart';

typedef Picker = Future<List<OutgoingFile>> Function(PickSource source);

/// El **prompt** de la terminal: `>` y lo que escribes en letra monoespaciada, un botón para adjuntar (foto de la galería, cámara o archivo)
/// y el de enviar (⏎).
/// Lo que se adjunta queda como fichas encima del campo hasta que se envía.
class Composer extends StatefulWidget {
  const Composer({super.key, required this.onSend, this.picker = pickOutgoing});

  /// Devuelve un mensaje de error si no se pudo preparar el envío (por ejemplo, un archivo demasiado grande).
  final String? Function(String text, List<OutgoingFile> files) onSend;
  final Picker picker;

  @override
  State<Composer> createState() => _ComposerState();
}

class _ComposerState extends State<Composer> {
  final _text = TextEditingController();
  final List<OutgoingFile> _files = [];

  bool get _canSend => _text.text.trim().isNotEmpty || _files.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _send() {
    if (!_canSend) return;
    final error = widget.onSend(_text.text, List.of(_files));
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    setState(() {
      _text.clear();
      _files.clear();
    });
  }

  Future<void> _attach() async {
    final source = await showFocusPanel<PickSource>(context, builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const Key('pick-gallery'),
              leading: LcdIcon(Icons.photo_library_outlined, color: context.colors.accent),
              title: const Text('Foto de la galería'),
              onTap: () => Navigator.pop(context, PickSource.gallery),
            ),
            ListTile(
              key: const Key('pick-camera'),
              leading: LcdIcon(Icons.photo_camera_outlined, color: context.colors.accent),
              title: const Text('Tomar una foto'),
              onTap: () => Navigator.pop(context, PickSource.camera),
            ),
            ListTile(
              key: const Key('pick-file'),
              leading: LcdIcon(Icons.attach_file, color: context.colors.accent),
              title: const Text('Archivo'),
              onTap: () => Navigator.pop(context, PickSource.file),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    try {
      final picked = await widget.picker(source);
      if (!mounted) return;
      setState(() {
        for (final file in picked) {
          if (!_files.any((known) => known.path == file.path)) _files.add(file);
        }
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo abrir el selector.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // el prompt, dentro de la terminal: «+» para adjuntar, «>» y lo escrito, y ⏎ para enviar
    final c = context.colors;
    return Material(
      color: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_files.isNotEmpty)
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final file in _files)
                      Padding(
                        padding: const EdgeInsets.only(right: 8, bottom: 6),
                        child: InputChip(
                          key: Key('staged-${file.path}'),
                          avatar: LcdIcon(file.mime.startsWith('image/') ? Icons.image_outlined : Icons.insert_drive_file_outlined, size: 18),
                          label: Text('${file.name} · ${humanSize(file.size)}', overflow: TextOverflow.ellipsis),
                          onDeleted: () => setState(() => _files.remove(file)),
                        ),
                      ),
                  ],
                ),
              ),
            Row(
              key: const Key('prompt'),
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  key: const Key('attach'),
                  tooltip: 'Adjuntar',
                  onPressed: _attach,
                  style: IconButton.styleFrom(minimumSize: const Size(40, 40), shape: const RoundedRectangleBorder()),
                  icon: LcdIcon(Icons.add_rounded, color: c.accent, size: 24),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 2, right: 6, bottom: 11),
                  child: Text('>', style: TextStyle(fontFamily: monoFont, fontSize: 17, fontWeight: FontWeight.w700, color: c.accent)),
                ),
                Expanded(
                  child: TextField(
                    key: const Key('message-field'),
                    controller: _text,
                    minLines: 1,
                    maxLines: 5,
                    textCapitalization: TextCapitalization.sentences,
                    style: TextStyle(fontFamily: monoFont, fontSize: 16, color: c.ink),
                    cursorColor: c.accent,
                    cursorWidth: 9,
                    decoration: const InputDecoration(
                      hintText: 'escribe y pulsa ⏎',
                      filled: false,
                      fillColor: Colors.transparent,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                      isDense: true,
                    ),
                  ),
                ),
                IconButton(
                  key: const Key('send'),
                  tooltip: 'Enviar',
                  onPressed: _canSend ? _send : null,
                  style: IconButton.styleFrom(
                    foregroundColor: c.accent,
                    disabledForegroundColor: c.dim.withValues(alpha: 0.5),
                    minimumSize: const Size(40, 40),
                    shape: const RoundedRectangleBorder(),
                  ),
                  icon: const LcdIcon(Icons.keyboard_return_rounded, size: 24),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
