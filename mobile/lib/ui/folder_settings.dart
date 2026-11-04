import 'package:flutter/material.dart';

import '../data/music_store.dart';
import '../state/music_controller.dart';
import '../theme.dart';

/// Abre la hoja de «Carpeta de las canciones» y, si se pulsa «Listo», guarda los cambios.
Future<void> showFolderSettings(BuildContext context, MusicController controller) async {
  final next = await showModalBottomSheet<MusicSettings>(
    context: context,
    isScrollControlled: true,
    builder: (context) => FolderSettingsSheet(initial: controller.settings, pickFolder: controller.pickFolder),
  );
  if (next != null) await controller.updateSettings(next);
}

/// Los ajustes de la carpeta: la que elijas con el selector de Android o, si no, Música/Descargas con su subcarpeta; y si se
/// guardan solas las canciones nuevas. Se devuelven al pulsar «Listo»; cerrar la hoja de otro modo no cambia nada.
class FolderSettingsSheet extends StatefulWidget {
  const FolderSettingsSheet({super.key, required this.initial, required this.pickFolder});

  final MusicSettings initial;
  final Future<PickedFolder?> Function() pickFolder;

  @override
  State<FolderSettingsSheet> createState() => FolderSettingsSheetState();
}

class FolderSettingsSheetState extends State<FolderSettingsSheet> {
  late MusicSettings _next = widget.initial;
  late final TextEditingController _folder = TextEditingController(text: widget.initial.folder);
  String? _pickError;

  @override
  void dispose() {
    _folder.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    try {
      final picked = await widget.pickFolder();
      if (picked != null && mounted) {
        setState(() {
          _next = _next.withTree(picked.uri, picked.name);
          _pickError = null;
        });
      }
    } on TrackSaveException catch (e) {
      if (mounted) setState(() => _pickError = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Carpeta de las canciones', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Se guardan en ${_next.copyWith(folder: _folder.text).where}.', style: TextStyle(color: context.colors.dim)),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            key: const Key('pick-folder'),
            onPressed: _pick,
            icon: const Icon(Icons.folder_open_outlined),
            label: Text(_next.hasTree ? 'Cambiar carpeta' : 'Elegir carpeta'),
          ),
          if (_pickError != null) ...[
            const SizedBox(height: 8),
            Text(_pickError!, key: const Key('pick-error'), style: TextStyle(color: context.colors.warn)),
          ],
          const SizedBox(height: 12),
          if (_next.hasTree)
            TextButton(
              key: const Key('use-default-folder'),
              onPressed: () => setState(() => _next = _next.withoutTree()),
              child: const Text('Usar Música/Descargas otra vez'),
            )
          else ...[
            Text('O una de las carpetas de siempre:', style: TextStyle(color: context.colors.dim)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final base in MusicBase.values)
                  ChoiceChip(
                    key: Key('base-${base.name}'),
                    label: Text(base.label),
                    selected: _next.base == base,
                    onSelected: (_) => setState(() => _next = _next.copyWith(base: base)),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('folder-field'),
              controller: _folder,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Subcarpeta (puede ir vacía)', hintText: 'Kyora'),
            ),
          ],
          const SizedBox(height: 6),
          SwitchListTile(
            key: const Key('auto-switch'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Guardar solas las canciones nuevas'),
            subtitle: Text('Con la app abierta, lo que te manden llega aquí y se guarda.', style: TextStyle(color: context.colors.dim)),
            value: _next.auto,
            onChanged: (value) => setState(() => _next = _next.copyWith(auto: value)),
          ),
          const SizedBox(height: 10),
          FilledButton(
            key: const Key('settings-save'),
            onPressed: () => Navigator.pop(context, _next.copyWith(folder: _folder.text)),
            child: const Text('Listo'),
          ),
        ],
      ),
    );
  }
}
