import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../data/vault_source.dart';
import '../models/track.dart';
import '../state/cloud_controller.dart';
import '../state/player_controller.dart';
import '../state/vault_controller.dart';
import '../theme.dart';
import '../util/format.dart';
import 'vault_actions.dart';

/// Cómo se crea el reproductor de un vídeo del Vault (en las pruebas, uno falso: el real necesita el plugin de Android).
typedef VideoFactory = VideoPlayerController Function(String uri);

VideoPlayerController realVideo(String uri) => VideoPlayerController.contentUri(Uri.parse(uri));

/// Un texto plano del Vault (notas, registros, datos…), para leerlo sin salir de la app.
class VaultTextPage extends StatelessWidget {
  const VaultTextPage({super.key, required this.controller, required this.entry, this.cloud});

  final VaultController controller;
  final VaultEntry entry;
  final CloudController? cloud;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(entry.name, key: const Key('viewer-title'), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: appFont, fontSize: 16, color: c.ink)),
        actions: [VaultActionsButton(vault: controller, entry: entry, cloud: cloud)],
      ),
      body: FutureBuilder<Uint8List>(
        future: controller.read(entry),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('No se pudo abrir este archivo', style: TextStyle(fontFamily: monoFont, fontSize: 15, color: c.warn)));
          if (!snapshot.hasData) return const Center(child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.4)));
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: SelectableText(utf8.decode(snapshot.data!, allowMalformed: true), key: const Key('viewer-text'), style: TextStyle(fontFamily: monoFont, fontSize: 15, height: 1.4, color: c.ink)),
          );
        },
      ),
    );
  }
}

/// Un vídeo del Vault, reproducido dentro de la app: empieza solo, se toca para pausar y la barra deja saltar a otro punto.
class VaultVideoPage extends StatefulWidget {
  const VaultVideoPage({super.key, required this.controller, required this.entry, this.cloud, this.videoFactory = realVideo});

  final VaultController controller;
  final VaultEntry entry;
  final CloudController? cloud;
  final VideoFactory videoFactory;

  @override
  State<VaultVideoPage> createState() => _VaultVideoPageState();
}

class _VaultVideoPageState extends State<VaultVideoPage> {
  VideoPlayerController? _video;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      final video = widget.videoFactory(widget.entry.uri);
      _video = video;
      await video.initialize();
      if (!mounted) return;
      setState(() {});
      await video.play();
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo reproducir este vídeo.');
    }
  }

  @override
  void dispose() {
    unawaited(_video?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final video = _video;
    final ready = video != null && video.value.isInitialized && _error == null;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(widget.entry.name, key: const Key('viewer-title'), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: appFont, fontSize: 16, color: c.ink)),
        actions: [VaultActionsButton(vault: widget.controller, entry: widget.entry, cloud: widget.cloud)],
      ),
      body: _error != null
          ? Center(child: Text(_error!, key: const Key('video-error'), style: TextStyle(fontFamily: monoFont, fontSize: 15, color: c.warn)))
          : !ready
          ? const Center(child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.4)))
          : Column(
              children: [
                Expanded(
                  child: GestureDetector(
                    key: const Key('video-surface'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => video.value.isPlaying ? video.pause() : video.play(),
                    child: Center(child: AspectRatio(aspectRatio: video.value.aspectRatio, child: VideoPlayer(video))),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(12, 4, 12, 12 + MediaQuery.paddingOf(context).bottom),
                  child: ValueListenableBuilder<VideoPlayerValue>(
                    valueListenable: video,
                    builder: (context, value, _) => Row(
                      children: [
                        IconButton(
                          key: const Key('video-toggle'),
                          icon: Icon(value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 30, color: c.accent),
                          onPressed: () => value.isPlaying ? video.pause() : video.play(),
                        ),
                        Expanded(child: VideoProgressIndicator(video, allowScrubbing: true, colors: VideoProgressColors(playedColor: c.accent, bufferedColor: c.accent.withValues(alpha: 0.3), backgroundColor: c.edge))),
                        const SizedBox(width: 10),
                        Text('${clock(value.position)} / ${clock(value.duration)}', style: TextStyle(fontFamily: monoFont, fontSize: 15, color: c.dim)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

/// Un audio del Vault, con el reproductor de la app (suena aunque salgas; las demás canciones de la carpeta quedan en la cola): su nombre,
/// el avance con una barra para saltar y los botones de anterior, pausa y siguiente.
class VaultAudioPage extends StatefulWidget {
  const VaultAudioPage({super.key, required this.controller, required this.player, required this.entries, required this.index, this.cloud});

  final VaultController controller;
  final PlayerController player;

  /// Los audios de la carpeta y cuál se abrió.
  final List<VaultEntry> entries;
  final int index;
  final CloudController? cloud;

  /// La canción del reproductor que corresponde a un audio del Vault.
  static Track trackOf(VaultEntry e) {
    final dot = e.name.lastIndexOf('.');
    return Track(
      id: 'vault:${e.uri}',
      title: dot > 0 ? e.name.substring(0, dot) : e.name,
      fileName: e.name,
      storagePath: '',
      sizeBytes: e.size,
      createdAt: DateTime.fromMillisecondsSinceEpoch(e.modified, isUtc: true),
      mimeType: e.mime.isEmpty ? 'audio/mpeg' : e.mime,
      playlist: 'Vault',
      localUri: e.uri,
    );
  }

  @override
  State<VaultAudioPage> createState() => _VaultAudioPageState();
}

class _VaultAudioPageState extends State<VaultAudioPage> {
  @override
  void initState() {
    super.initState();
    final tracks = [for (final e in widget.entries) VaultAudioPage.trackOf(e)];
    unawaited(widget.player.play(tracks[widget.index], tracks));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final player = widget.player;
    return ListenableBuilder(
      listenable: player,
      builder: (context, _) {
        final track = player.current;
        final entry = widget.entries.firstWhere((e) => 'vault:${e.uri}' == track?.id, orElse: () => widget.entries[widget.index]);
        return Scaffold(
          key: const Key('vault-audio'),
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            title: Text(entry.name, key: const Key('viewer-title'), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: appFont, fontSize: 16, color: c.ink)),
            actions: [VaultActionsButton(vault: widget.controller, entry: entry, cloud: widget.cloud)],
          ),
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.graphic_eq_rounded, size: 96, color: c.accent),
                const SizedBox(height: 20),
                Text(track?.title ?? entry.name, key: const Key('vault-audio-title'), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: display(size: 22, color: c.ink)),
                const SizedBox(height: 24),
                ValueListenableBuilder<Duration>(
                  valueListenable: player.positionListenable,
                  builder: (context, position, _) {
                    final total = player.duration;
                    final max = total.inMilliseconds <= 0 ? 1.0 : total.inMilliseconds.toDouble();
                    return Column(
                      children: [
                        Slider(
                          key: const Key('vault-audio-seek'),
                          value: position.inMilliseconds.clamp(0, max.toInt()).toDouble(),
                          max: max,
                          onChanged: total.inMilliseconds <= 0 ? null : (v) => unawaited(player.seek(Duration(milliseconds: v.round()))),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(clock(position), style: TextStyle(fontFamily: monoFont, fontSize: 15, color: c.dim)),
                            Text(clock(total), style: TextStyle(fontFamily: monoFont, fontSize: 15, color: c.dim)),
                          ],
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(key: const Key('vault-audio-prev'), iconSize: 36, icon: Icon(Icons.skip_previous_rounded, color: c.ink), onPressed: () => unawaited(player.previous())),
                    const SizedBox(width: 12),
                    IconButton(
                      key: const Key('vault-audio-toggle'),
                      iconSize: 56,
                      icon: Icon(player.playing ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded, color: c.accent),
                      onPressed: () => unawaited(player.toggle()),
                    ),
                    const SizedBox(width: 12),
                    IconButton(key: const Key('vault-audio-next'), iconSize: 36, icon: Icon(Icons.skip_next_rounded, color: c.ink), onPressed: () => unawaited(player.next())),
                  ],
                ),
                if (player.error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(player.error!, style: TextStyle(fontFamily: monoFont, fontSize: 15, color: c.warn))),
              ],
            ),
          ),
        );
      },
    );
  }
}
