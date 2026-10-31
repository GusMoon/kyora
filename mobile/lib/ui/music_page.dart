import 'dart:async';

import 'package:flutter/material.dart';

import '../data/music_store.dart';
import '../models/track.dart';
import '../state/music_controller.dart';
import '../theme.dart';
import '../util/format.dart';

/// La música de la PC: las canciones que bajas allá con «Descargar» llegan aquí y se guardan en la carpeta que elijas.
class MusicPage extends StatefulWidget {
  const MusicPage({super.key, required this.controller});

  final MusicController controller;

  @override
  State<MusicPage> createState() => _MusicPageState();
}

class _MusicPageState extends State<MusicPage> {
  StreamSubscription<String>? _notices;

  @override
  void initState() {
    super.initState();
    _notices = widget.controller.notices.listen((text) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    });
  }

  @override
  void dispose() {
    unawaited(_notices?.cancel());
    super.dispose();
  }

  Future<void> _settings() async {
    final controller = widget.controller;
    final next = await showModalBottomSheet<MusicSettings>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _SettingsSheet(initial: controller.settings),
    );
    if (next != null) await controller.updateSettings(next);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final c = widget.controller;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Música', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
            actions: [
              IconButton(key: const Key('music-settings'), tooltip: 'Carpeta', onPressed: _settings, icon: const Icon(Icons.folder_open_outlined)),
            ],
          ),
          body: Column(
            children: [
              _Banner(controller: c),
              Expanded(child: _body(c)),
            ],
          ),
        );
      },
    );
  }

  Widget _body(MusicController c) {
    if (c.loading) return const Center(child: CircularProgressIndicator(strokeWidth: 2.4));
    if (c.error != null && c.tracks.isEmpty) {
      return _Message(c.error!, warn: true, onRetry: c.refresh);
    }
    if (c.tracks.isEmpty) {
      return const _Message('Aún no hay canciones.\nLas que bajes en la PC con «Descargar» aparecen aquí.');
    }
    return ListView.builder(
      key: const Key('track-list'),
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: c.tracks.length,
      itemBuilder: (context, i) => _TrackTile(track: c.tracks[i], controller: c),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.controller});

  final MusicController controller;

  @override
  Widget build(BuildContext context) {
    final pending = controller.pendingCount;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              pending == 0 ? 'Todo guardado en ${controller.settings.where}.' : '$pending por guardar en ${controller.settings.where}.',
              key: const Key('music-banner'),
              style: const TextStyle(color: Palette.dim, fontSize: 14),
            ),
          ),
          if (pending > 0)
            TextButton(key: const Key('save-all'), onPressed: controller.saveAll, child: const Text('Guardar todas')),
        ],
      ),
    );
  }
}

class _TrackTile extends StatelessWidget {
  const _TrackTile({required this.track, required this.controller});

  final Track track;
  final MusicController controller;

  @override
  Widget build(BuildContext context) {
    final state = controller.stateOf(track);
    final failure = controller.failureOf(track);
    final parts = [if (track.playlist != null) track.playlist!, humanSize(track.sizeBytes)];
    return ListTile(
      key: Key('track-${track.id}'),
      leading: switch (state) {
        TrackState.saving => const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.4)),
        TrackState.saved => const Icon(Icons.check_circle, key: Key('saved'), color: Palette.accent),
        TrackState.failed => const Icon(Icons.error_outline, color: Palette.warn),
        TrackState.pending => const Icon(Icons.download_outlined, color: Palette.dim),
      },
      title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        state == TrackState.failed ? '${failure ?? 'No se pudo guardar'} · toca para reintentar' : parts.join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: state == TrackState.failed ? Palette.warn : Palette.dim, fontSize: 13),
      ),
      onTap: state == TrackState.pending || state == TrackState.failed ? () => unawaited(controller.save(track)) : null,
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text, {this.warn = false, this.onRetry});

  final String text;
  final bool warn;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text, textAlign: TextAlign.center, style: TextStyle(color: warn ? Palette.warn : Palette.dim)),
            if (onRetry != null) TextButton(onPressed: onRetry, child: const Text('Reintentar')),
          ],
        ),
      ),
    );
  }
}

/// Los ajustes de la carpeta: Música o Descargas, la subcarpeta y si se guardan solas las canciones nuevas. Se devuelven
/// al pulsar «Listo»; cerrar la hoja de otro modo no cambia nada.
class _SettingsSheet extends StatefulWidget {
  const _SettingsSheet({required this.initial});

  final MusicSettings initial;

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  late MusicSettings _next = widget.initial;
  late final TextEditingController _folder = TextEditingController(text: widget.initial.folder);

  @override
  void dispose() {
    _folder.dispose();
    super.dispose();
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
          Text('Se guardan en ${_next.copyWith(folder: _folder.text).where}.', style: const TextStyle(color: Palette.dim)),
          const SizedBox(height: 14),
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
          const SizedBox(height: 6),
          SwitchListTile(
            key: const Key('auto-switch'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Guardar solas las canciones nuevas'),
            subtitle: const Text('Con la app abierta, lo que bajes en la PC llega aquí y se guarda.', style: TextStyle(color: Palette.dim)),
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
