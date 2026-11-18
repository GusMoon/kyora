import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/account_backend.dart';
import '../data/chat_backend.dart';
import '../data/cloud_files.dart';
import '../data/server_stats.dart';
import '../state/cloud_controller.dart';
import '../state/player_controller.dart';
import '../state/server_controller.dart';
import '../state/vault_controller.dart';
import '../theme.dart';
import 'chat_page.dart';
import 'image_viewer.dart';
import 'vault_page.dart';
import 'widgets/cut_border.dart';
import 'widgets/cyber_panel.dart';
import 'widgets/focus_space.dart';
import 'widgets/pixel_glyph.dart';

/// Abre una dirección con la app que toque (el navegador, un visor de PDF…). `true` si alguien la abrió.
typedef UrlOpener = Future<bool> Function(String url);

Future<bool> _launch(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

/// Las pestañas de la Nube.
enum NubeTab { cloud, local, chat }

/// La **Nube**: una sola sección con lo del servidor y lo que hay en el teléfono, en tres pestañas.
///  - **Nube**: cuánto ocupa tu proyecto de Supabase (con la advertencia al llegar al 80 %) y los archivos que hay en el servidor, que se abren,
///    se bajan y se borran de verdad (lo mismo que ve Merida).
///  - **Local**: el Vault, la carpeta de tu almacenamiento donde se guarda lo tuyo (se elige en Configuración): ver imágenes, vídeos, audios y
///    textos, exportar archivos de otros sitios, compartir, subir a tu nube, cambiar nombres y ver atributos.
///  - **Chat**: el chat con la PC (solo el administrador).
/// Local funciona siempre; Nube y Chat necesitan sesión y lo dicen si no la hay.
class NubePage extends StatefulWidget {
  const NubePage({
    super.key,
    required this.account,
    this.admin = false,
    this.server,
    this.cloud,
    this.vault,
    this.chat,
    this.player,
    this.onOpenSettings,
    this.onSignIn,
    this.openUrl = _launch,
    this.now,
    this.initial = NubeTab.cloud,
  });

  final AccountBackend account;

  /// Solo el administrador tiene la pestaña del chat.
  final bool admin;
  final ServerController? server;
  final CloudController? cloud;
  final VaultController? vault;
  final ChatBackend? chat;

  /// El reproductor de la app (para los audios del Vault) y cómo se abre Configuración (donde se elige la carpeta del Vault).
  final PlayerController? player;
  final VoidCallback? onOpenSettings;

  /// Abre el acceso (entrar o crear cuenta). Sin esto no sale el botón de «Iniciar sesión».
  final VoidCallback? onSignIn;

  /// Cómo se abre una dirección (en las pruebas, una falsa).
  final UrlOpener openUrl;

  /// El reloj (en las pruebas, uno fijo).
  final DateTime Function()? now;
  final NubeTab initial;

  @override
  State<NubePage> createState() => _NubePageState();
}

class _NubePageState extends State<NubePage> with WidgetsBindingObserver {
  late NubeTab _tab = _tabs.isEmpty || _tabs.contains(widget.initial) ? widget.initial : _tabs.first;
  final Set<NubeTab> _visited = {};

  List<NubeTab> get _tabs => [
    if (widget.server != null || widget.cloud != null) NubeTab.cloud,
    if (widget.vault != null) NubeTab.local,
    if (widget.admin && widget.chat != null) NubeTab.chat,
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _visited.add(_tab);
    if (_tab == NubeTab.cloud) _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _tab == NubeTab.cloud) _refresh();
  }

  /// Vuelve a leer el servidor y a medir lo que ocupa (solo con sesión).
  void _refresh() {
    if (!widget.account.signedIn) return;
    unawaited(widget.cloud?.load());
    unawaited(widget.server?.measure());
  }

  void _select(NubeTab tab) {
    if (tab == _tab) return;
    setState(() {
      _tab = tab;
      _visited.add(tab);
    });
    if (tab == NubeTab.cloud) _refresh();
  }

  Widget _needsSession(String what) => _Note(
    key: const Key('nube-signed-out'),
    text: 'Entra con tu cuenta para $what.',
    action: widget.onSignIn == null ? null : ('Iniciar sesión', widget.onSignIn!),
  );

  Widget _body(NubeTab tab) {
    switch (tab) {
      case NubeTab.cloud:
        return StreamBuilder<void>(
          stream: widget.account.authChanges,
          builder: (context, _) {
            if (!widget.account.signedIn) return _needsSession('ver lo que hay en el servidor');
            return _CloudTab(server: widget.server, cloud: widget.cloud, openUrl: widget.openUrl, now: widget.now ?? DateTime.now, onRefresh: _refresh);
          },
        );
      case NubeTab.local:
        return VaultPage(controller: widget.vault!, cloud: widget.cloud, player: widget.player, onOpenSettings: widget.onOpenSettings);
      case NubeTab.chat:
        return StreamBuilder<void>(
          stream: widget.account.authChanges,
          builder: (context, _) => widget.account.signedIn ? ChatPage(backend: widget.chat!) : _needsSession('usar el chat'),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tabs = _tabs;
    if (tabs.isEmpty) return const SizedBox.shrink();
    final current = tabs.contains(_tab) ? _tab : tabs.first;
    final top = MediaQuery.paddingOf(context).top;
    return Scaffold(
      key: const Key('nube-page'),
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: EdgeInsets.only(top: top),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (tabs.length > 1) _Tabs(tabs: tabs, active: current, onTap: _select),
            Expanded(
              // el espacio de arriba ya lo puso la barra de pestañas: lo de dentro no lo repite
              child: MediaQuery.removePadding(
                context: context,
                removeTop: true,
                child: IndexedStack(
                  index: tabs.indexOf(current),
                  children: [
                    for (final t in tabs)
                      // Local y el Vault solo se montan cuando se ven (su «atrás» sube de carpeta); lo demás se queda vivo una vez abierto
                      if (t == NubeTab.local ? t == current : _visited.contains(t) || t == current) _body(t) else const SizedBox.shrink(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const _tabLabels = {NubeTab.cloud: 'NUBE', NubeTab.local: 'LOCAL', NubeTab.chat: 'CHAT'};

/// Las pestañas, en una sola barra con filo (como las de la agenda): la que se ve, encendida y entre corchetes.
class _Tabs extends StatelessWidget {
  const _Tabs({required this.tabs, required this.active, required this.onTap});

  final List<NubeTab> tabs;
  final NubeTab active;
  final ValueChanged<NubeTab> onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: DecoratedBox(
        decoration: cutDecoration(color: c.field, edge: c.edge),
        child: Row(
          children: [
            for (final t in tabs)
              Expanded(
                child: Semantics(
                  button: true,
                  selected: t == active,
                  label: _tabLabels[t],
                  child: GestureDetector(
                    key: Key('nube-tab-${t.name}'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onTap(t),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      padding: const EdgeInsets.only(top: 11),
                      color: t == active ? c.accent.withValues(alpha: 0.12) : Colors.transparent,
                      child: Column(
                        children: [
                          Text(
                            t == active ? '[${_tabLabels[t]}]' : _tabLabels[t]!,
                            style: TextStyle(fontFamily: monoFont, fontSize: 15, letterSpacing: 0.5, fontWeight: t == active ? FontWeight.w700 : FontWeight.w400, color: t == active ? c.accent : c.dim),
                          ),
                          const SizedBox(height: 8),
                          AnimatedContainer(duration: const Duration(milliseconds: 220), height: 2, color: t == active ? c.accent : Colors.transparent),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Un aviso en el centro, con un botón opcional.
class _Note extends StatelessWidget {
  const _Note({super.key, required this.text, this.action});

  final String text;
  final (String, VoidCallback)? action;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: CyberPanel(
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.cloud_off_outlined, size: 44, color: c.accent),
                const SizedBox(height: 12),
                Text('> $text', textAlign: TextAlign.center, style: TextStyle(fontFamily: monoFont, fontSize: 15, color: c.dim)),
                if (action != null) ...[
                  const SizedBox(height: 14),
                  FilledButton(key: const Key('nube-sign-in'), onPressed: action!.$2, child: Text(action!.$1)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------- la pestaña Nube ----------

class _CloudTab extends StatelessWidget {
  const _CloudTab({required this.server, required this.cloud, required this.openUrl, required this.now, required this.onRefresh});

  final ServerController? server;
  final CloudController? cloud;
  final UrlOpener openUrl;
  final DateTime Function() now;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final bottom = 20 + MediaQuery.paddingOf(context).bottom;
    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      child: ListView(
        key: const Key('nube-cloud'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(12, 0, 12, bottom),
        children: [
          if (server != null) ServerPanel(controller: server!),
          if (cloud != null) CloudFiles(controller: cloud!, openUrl: openUrl, now: now),
        ],
      ),
    );
  }
}

// ---------- el servidor ----------

/// Cuánto ocupa tu proyecto de Supabase: la advertencia al llegar al 80 %, dos medidores (base de datos y archivos) con una marca en el 80 %, el
/// desglose (archivos por bucket y las tablas más grandes) y «Medir ahora».
class ServerPanel extends StatefulWidget {
  const ServerPanel({super.key, required this.controller});

  final ServerController controller;

  @override
  State<ServerPanel> createState() => _ServerPanelState();
}

class _ServerPanelState extends State<ServerPanel> {
  bool _more = false;

  Color _levelColor(KyoraColors c, QuotaLevel level) => switch (level) {
        QuotaLevel.ok => c.accent,
        QuotaLevel.warn => c.reminders,
        QuotaLevel.critical => c.warn,
      };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final ctl = widget.controller;
        final stats = ctl.stats;
        final warnings = ctl.warnings;
        final over = warnings.any((q) => q.ratio >= 1);
        final warnColor = warnings.any((q) => q.level == QuotaLevel.critical) ? c.warn : c.reminders;
        return Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 10),
          child: CyberPanel(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
              child: Column(
                key: const Key('srv'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(width: 9, height: 9, color: c.accent),
                      const SizedBox(width: 10),
                      Expanded(child: Text('SERVIDOR · SUPABASE', style: hudLabel(color: c.accent))),
                      if (ctl.measuring) SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2.2, color: c.accent)),
                    ],
                  ),
                  if (ctl.error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(ctl.error!, key: const Key('srv-error'), style: lcdStatus(color: c.warn)),
                    ),
                  if (warnings.isNotEmpty)
                    Container(
                      key: const Key('srv-warn'),
                      margin: const EdgeInsets.only(top: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: cutDecoration(color: warnColor.withValues(alpha: 0.12), edge: warnColor.withValues(alpha: 0.7)),
                      child: Semantics(
                        liveRegion: true,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(over ? 'Superaste un límite del plan gratuito.' : 'Tu servidor se está llenando.', style: lcdLabel(color: warnColor)),
                            for (final q in warnings) Padding(padding: const EdgeInsets.only(top: 4), child: Text(warningText(q), style: lcdStatus(color: c.ink))),
                          ],
                        ),
                      ),
                    ),
                  if (stats == null && ctl.error == null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text('Midiendo el servidor…', key: const Key('srv-loading'), style: lcdStatus(color: c.dim)),
                    ),
                  for (final q in ctl.quotaList) _Meter(quota: q, color: _levelColor(c, q.level)),
                  if (stats != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      '${stats.storageObjects} ${stats.storageObjects == 1 ? 'archivo' : 'archivos'} en Storage${stats.at == null ? '' : ' · medido ${_hhmm(stats.at!)}'}',
                      style: lcdStatus(color: c.dim),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Wrap(
                    children: [
                      TextButton(
                        key: const Key('srv-measure'),
                        onPressed: ctl.measuring ? null : () => unawaited(ctl.measure()),
                        child: Text('Medir ahora', style: TextStyle(color: c.accent)),
                      ),
                      if (stats != null)
                        TextButton(
                          key: const Key('srv-more'),
                          onPressed: () => setState(() => _more = !_more),
                          child: Text(_more ? 'Ocultar desglose' : 'Desglose', style: TextStyle(color: c.dim)),
                        ),
                    ],
                  ),
                  if (_more && stats != null) _Breakdown(stats: stats),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _hhmm(DateTime t) {
    final l = t.toLocal();
    return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }
}

/// Un medidor: nombre, porcentaje, la barra con una marca en el 80 % y cuánto llevas de cuánto.
class _Meter extends StatelessWidget {
  const _Meter({required this.quota, required this.color});

  final Quota quota;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final id = quota.id.name;
    return Padding(
      key: Key('srv-meter-$id'),
      padding: const EdgeInsets.only(top: 12),
      child: Semantics(
        label: '${quota.label}: ${percent(quota.ratio)}',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(quota.label, style: lcdLabel(color: c.ink))),
                Text(percent(quota.ratio), key: Key('srv-pct-$id'), style: TextStyle(fontFamily: monoFont, fontSize: 15, fontWeight: FontWeight.w700, color: color)),
              ],
            ),
            const SizedBox(height: 6),
            LayoutBuilder(
              builder: (context, box) => SizedBox(
                height: 12,
                child: Stack(
                  children: [
                    Positioned.fill(child: ColoredBox(color: c.edge)),
                    Positioned(left: 0, top: 0, bottom: 0, width: box.maxWidth * quota.ratio.clamp(0.0, 1.0), child: ColoredBox(key: Key('srv-bar-$id'), color: color)),
                    // la marca del 80 %: de aquí en adelante hay advertencia
                    Positioned(left: box.maxWidth * warnAt - 1, top: 0, bottom: 0, width: 2, child: ColoredBox(key: Key('srv-mark-$id'), color: c.ink.withValues(alpha: 0.7))),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text('${formatBytes(quota.used)} de ${formatBytes(quota.limit)}', style: lcdStatus(color: c.dim)),
          ],
        ),
      ),
    );
  }
}

/// Los archivos por bucket y las tablas más grandes.
class _Breakdown extends StatelessWidget {
  const _Breakdown({required this.stats});

  final ServerStats stats;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget line(String left, String right) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [Expanded(child: Text(left, style: lcdStatus(color: c.ink))), Text(right, style: TextStyle(fontFamily: monoFont, fontSize: 15, color: c.dim))]),
    );
    return Column(
      key: const Key('srv-breakdown'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('ARCHIVOS POR BUCKET', style: hudLabel(color: c.dim)),
        if (stats.buckets.isEmpty) Text('Sin archivos.', style: lcdStatus(color: c.dim)),
        for (final b in stats.buckets) line(b.bucket, '${b.objects} · ${formatBytes(b.bytes)}'),
        const SizedBox(height: 8),
        Text('TABLAS MÁS GRANDES', style: hudLabel(color: c.dim)),
        for (final t in stats.tables) line(t.name, '${t.rows} filas · ${formatBytes(t.bytes)}'),
        const SizedBox(height: 8),
        Text('El tráfico del mes y los usuarios activos no se pueden medir desde la app: míralos en Supabase → Settings → Usage.', style: lcdStatus(color: c.dim)),
        const SizedBox(height: 4),
      ],
    );
  }
}

// ---------- los archivos de la nube ----------

/// Los archivos que hay en el servidor, con filtros por tipo. Tocar uno lo abre; cada uno se puede bajar y borrar de verdad (con confirmación).
class CloudFiles extends StatelessWidget {
  const CloudFiles({super.key, required this.controller, required this.openUrl, required this.now});

  final CloudController controller;
  final UrlOpener openUrl;
  final DateTime Function() now;

  Future<void> _open(BuildContext context, CloudFile file) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final navigator = Navigator.of(context);
    final url = await controller.url(file);
    if (url == null) {
      messenger?.showSnackBar(const SnackBar(content: Text('No se pudo abrir el archivo.')));
      return;
    }
    if (file.kind == CloudKind.image) {
      await navigator.push(MaterialPageRoute<void>(builder: (_) => ImageViewerPage(image: NetworkImage(url), title: file.name)));
      return;
    }
    final opened = await openUrl(url);
    if (!opened) messenger?.showSnackBar(const SnackBar(content: Text('No hay ninguna app que pueda abrir este archivo.')));
  }

  Future<void> _download(BuildContext context, CloudFile file) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final url = await controller.url(file, download: true);
    final ok = url != null && await openUrl(url);
    if (!ok) messenger?.showSnackBar(const SnackBar(content: Text('No se pudo bajar el archivo.')));
  }

  Future<void> _delete(BuildContext context, CloudFile file) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final sure = await showFocusPanel<bool>(
      context,
      title: '¿Borrar del servidor?',
      builder: (context) => FocusDialog(
        content: Text(
          file.source == CloudSource.music
              ? '«${file.name}» se borra de verdad del servidor, para todos los que la tenían. No se puede deshacer.'
              : '«${file.name}» se borra de verdad del servidor: ya no se podrá abrir en ningún dispositivo. No se puede deshacer.',
        ),
        actions: [
          TextButton(key: const Key('cloud-cancel'), onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          TextButton(key: const Key('cloud-confirm'), onPressed: () => Navigator.pop(context, true), child: Text('Borrar', style: TextStyle(color: context.colors.warn))),
        ],
      ),
    );
    if (sure != true) return;
    final error = await controller.delete(file);
    messenger?.showSnackBar(SnackBar(content: Text(error ?? 'Borrado del servidor.')));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final totals = controller.totals;
        final shown = controller.visible;
        return Column(
          key: const Key('cloud-files'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    controller.error ??
                        (!controller.loaded
                            ? 'Leyendo el servidor…'
                            : totals.count == 0
                                ? 'No hay archivos en el servidor.'
                                : '${totals.count} ${totals.count == 1 ? 'archivo' : 'archivos'} en el servidor (${formatBytes(totals.bytes)}).'),
                    key: const Key('cloud-statement'),
                    style: lcdStatus(color: controller.error != null ? c.warn : c.dim),
                  ),
                ),
                IconButton(
                  key: const Key('cloud-refresh'),
                  tooltip: 'Actualizar',
                  onPressed: controller.loading ? null : () => unawaited(controller.load()),
                  icon: controller.loading ? SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: c.accent)) : Icon(Icons.refresh_rounded, color: c.ink),
                ),
              ],
            ),
            if (totals.count > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _FilterChip(keyName: 'all', label: 'Todo', count: totals.count, on: controller.filter == null, onTap: () => controller.setFilter(null)),
                    for (final k in CloudKind.values)
                      if (totals.byKind[k]! > 0) _FilterChip(keyName: k.name, label: cloudKindLabel[k]!, count: totals.byKind[k]!, on: controller.filter == k, onTap: () => controller.setFilter(controller.filter == k ? null : k)),
                  ],
                ),
              ),
            for (final f in shown) _FileRow(file: f, controller: controller, now: now, onOpen: () => unawaited(_open(context, f)), onDownload: () => unawaited(_download(context, f)), onDelete: () => unawaited(_delete(context, f))),
          ],
        );
      },
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.keyName, required this.label, required this.count, required this.on, required this.onTap});

  final String keyName;
  final String label;
  final int count;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      selected: on,
      label: label,
      child: GestureDetector(
        key: Key('cloud-filter-$keyName'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: on ? c.accent.withValues(alpha: 0.16) : null, border: Border.all(color: on ? c.accent : c.edge)),
          child: Text('$label $count', style: TextStyle(fontSize: 15, color: on ? c.ink : c.dim)),
        ),
      ),
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({required this.file, required this.controller, required this.now, required this.onOpen, required this.onDownload, required this.onDelete});

  final CloudFile file;
  final CloudController controller;
  final DateTime Function() now;
  final VoidCallback onOpen;
  final VoidCallback onDownload;
  final VoidCallback onDelete;

  static IconData _icon(CloudKind k) => switch (k) {
        CloudKind.image => Icons.image_outlined,
        CloudKind.audio => Icons.music_note_outlined,
        CloudKind.video => Icons.movie_outlined,
        CloudKind.doc => Icons.description_outlined,
        CloudKind.other => Icons.insert_drive_file_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fallback = LcdIcon(_icon(file.kind), color: c.accent);
    return Container(
      key: Key('cloud-file-${file.id}'),
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(color: c.field.withValues(alpha: 0.7), border: Border.all(color: c.edge)),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              key: Key('cloud-open-${file.id}'),
              behavior: HitTestBehavior.opaque,
              onTap: onOpen,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    SizedBox.square(
                      dimension: 44,
                      child: file.kind == CloudKind.image
                          ? FutureBuilder<String?>(
                              future: controller.thumbUrl(file),
                              builder: (context, snap) => snap.data == null
                                  ? Center(child: fallback)
                                  : Image.network(snap.data!, fit: BoxFit.cover, cacheWidth: 96, gaplessPlayback: true, errorBuilder: (_, _, _) => Center(child: fallback)),
                            )
                          : Center(child: fallback),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16, color: c.ink)),
                          Text('${formatBytes(file.size)} · ${file.from} · ${agoLabel(file.at, now())}', maxLines: 1, overflow: TextOverflow.ellipsis, style: lcdStatus(color: c.dim)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(key: Key('cloud-download-${file.id}'), tooltip: 'Bajar', onPressed: onDownload, icon: Icon(Icons.download_outlined, color: c.ink)),
          IconButton(key: Key('cloud-delete-${file.id}'), tooltip: 'Borrar del servidor', onPressed: onDelete, icon: Icon(Icons.delete_outline, color: c.warn)),
        ],
      ),
    );
  }
}
