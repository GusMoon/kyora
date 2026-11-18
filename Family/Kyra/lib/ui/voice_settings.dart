import 'dart:async';

import 'package:flutter/material.dart';

import '../data/voice_reader.dart';
import '../state/dock_controller.dart';
import '../state/voice_controller.dart';
import '../theme.dart';
import 'settings_rows.dart';
import 'widgets/pixel_glyph.dart';

/// Lo de dentro de la ficha «Voz» (KyraAdmin): encenderla, el acceso a notificaciones (con su botón), probarla y las apps que se leen: el
/// chat de Kyra (fijo, arriba) y todas las del teléfono, con un buscador. Al volver de los ajustes de Android se vuelve a mirar el permiso.
class VoiceRows extends StatefulWidget {
  const VoiceRows({super.key, required this.voice, this.dock});

  final VoiceController voice;

  /// Las apps del teléfono (las del disco de Inicio). Sin esto solo sale el chat de Kyra.
  final DockController? dock;

  @override
  State<VoiceRows> createState() => _VoiceRowsState();
}

class _VoiceRowsState extends State<VoiceRows> with WidgetsBindingObserver {
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(widget.voice.refresh());
    final dock = widget.dock;
    if (dock != null && !dock.loaded) unawaited(dock.refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(widget.voice.refresh()); // al volver de dar el permiso
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final voice = widget.voice;
    return ListenableBuilder(
      listenable: Listenable.merge([voice, ?widget.dock]),
      builder: (context, _) {
        final q = _query.trim().toLowerCase();
        final apps = [for (final a in widget.dock?.alphabetical ?? const []) if (q.isEmpty || a.label.toLowerCase().contains(q)) a];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SettingsRow(
              key: const Key('voice-enabled'),
              icon: Icons.record_voice_over_outlined,
              title: 'Leer mensajes en voz alta',
              subtitle: 'Con la pantalla apagada, Kyra dice quién te escribió, desde qué app y qué dice. Al encender la pantalla se calla.',
              trailing: Switch(value: voice.enabled, onChanged: (v) => unawaited(voice.setEnabled(v))),
              onTap: () => unawaited(voice.setEnabled(!voice.enabled)),
            ),
            Divider(height: 1, color: c.edge),
            SettingsRow(
              key: const Key('voice-access'),
              icon: voice.granted == true ? Icons.verified_user_outlined : Icons.notifications_off_outlined,
              title: voice.granted == true ? 'Acceso a notificaciones: concedido' : 'Dar acceso a notificaciones',
              subtitle: voice.granted == true ? 'Kyra puede leer los avisos que lleguen.' : 'Android lo pide para poder leer los avisos. Busca «Voz de Kyra» y actívalo.',
              subtitleColor: voice.granted == true ? c.accent : c.warn,
              trailing: LcdIcon(Icons.chevron_right, color: c.dim),
              onTap: () => unawaited(voice.openAccessSettings()),
            ),
            Divider(height: 1, color: c.edge),
            SettingsRow(key: const Key('voice-test'), icon: Icons.volume_up_outlined, title: 'Probar voz', subtitle: 'Dice un mensaje de ejemplo.', onTap: () => unawaited(voice.test())),
            const SizedBox(height: 12),
            Text('APPS QUE SE LEEN', style: hudLabel(size: 13, color: c.dim)),
            CheckboxListTile(
              key: const Key('voice-app-kyra'),
              contentPadding: EdgeInsets.zero,
              value: voice.reads(kyraChatPackage),
              onChanged: (_) => unawaited(voice.toggle(kyraChatPackage)),
              secondary: LcdIcon(Icons.forum_outlined, color: c.accent),
              title: Text('Chat de Kyra', style: TextStyle(color: c.ink)),
              subtitle: Text('Los mensajes privados de Kyra', style: TextStyle(color: c.dim)),
            ),
            if (widget.dock != null) ...[
              TextField(
                key: const Key('voice-search'),
                onChanged: (v) => setState(() => _query = v),
                decoration: const InputDecoration(hintText: 'Buscar app', prefixIcon: Icon(Icons.search_rounded)),
              ),
              const SizedBox(height: 6),
              if (!widget.dock!.loaded) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator(strokeWidth: 2.4))),
              for (final app in apps)
                CheckboxListTile(
                  key: Key('voice-app-${app.package}'),
                  contentPadding: EdgeInsets.zero,
                  value: voice.reads(app.package),
                  onChanged: (_) => unawaited(voice.toggle(app.package)),
                  secondary: Image.memory(app.icon, width: 32, height: 32, gaplessPlayback: true),
                  title: Text(app.label, style: TextStyle(color: c.ink)),
                ),
            ],
          ],
        );
      },
    );
  }
}
