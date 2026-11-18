import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/chat_notifier.dart';
import '../data/direct_backend.dart';
import '../models/profile.dart';
import '../state/appearance_controller.dart';
import '../state/direct_chat_controller.dart';
import '../state/local_music_controller.dart';
import '../state/music_controller.dart';
import '../state/player_controller.dart';
import '../data/favorites_store.dart';
import 'neo/neo_chat_page.dart';
import 'neo/neo_music_page.dart';
import 'neo/neo_pager.dart';
import 'neo/neo_settings_page.dart';
import 'neo/neo_theme.dart';
import 'neo/neo_widgets.dart';
import 'widgets/kyra_keyboard.dart';

/// Las pestañas del modo visitante.
enum GuestTab { music, chat, settings }

/// **El modo visitante** (KyraFamily): **Música**, **Chat** y **Ajustes**, con una barra de navegación abajo y deslizando a los lados para
/// pasar de una a otra. Todo con el diseño cyber-brutalista, en el tema de colores y el modo (claro u oscuro) elegidos en Ajustes.
class GuestShell extends StatefulWidget {
  const GuestShell({
    super.key,
    required this.music,
    required this.player,
    required this.local,
    required this.direct,
    required this.ownerId,
    required this.signedIn,
    required this.verified,
    required this.role,
    required this.username,
    required this.remembered,
    required this.onSignIn,
    required this.onClaim,
    required this.onForget,
    required this.onSignOut,
    this.onAdminLogin,
    this.notice,
    this.canExit,
    this.appearance,
    this.favorites,
    this.notifier,
    this.initial = GuestTab.music,
  });

  /// El tema de colores y el modo oscuro. Sin esto, el tema de siempre en claro.
  final AppearanceController? appearance;

  /// Las canciones favoritas (los corazones). Sin esto no hay corazones.
  final FavoritesController? favorites;

  final MusicController music;
  final PlayerController player;
  final LocalMusicController local;

  /// El chat privado en Supabase (sin esto no hay chat).
  final DirectBackend? direct;

  /// El aviso del teléfono cuando llega un mensaje con la app en segundo plano.
  final ChatNotifier? notifier;

  /// De quién es la sesión (cambia si entra otra cuenta: el chat se abre de nuevo).
  final String ownerId;
  final bool signedIn;
  final bool verified;
  final Role role;
  final String? username;
  final ValueListenable<String?> remembered;
  final Future<void> Function(String name, String password) onSignIn;
  final Future<void> Function(String code) onClaim;
  final Future<void> Function() onForget;
  final Future<void> Function() onSignOut;

  /// Abre el acceso del administrador (sin esto, KyraFamily, no hay ese acceso).
  final VoidCallback? onAdminLogin;

  /// Un aviso de la puerta de acceso; al llegar uno, la app va a Ajustes para enseñarlo.
  final ValueListenable<String?>? notice;

  /// ¿Atrás puede cerrar la app? (no, si Kyra es el launcher del teléfono).
  final bool Function()? canExit;
  final GuestTab initial;

  @override
  State<GuestShell> createState() => _GuestShellState();
}

class _GuestShellState extends State<GuestShell> {
  late GuestTab _tab = widget.initial;
  DirectChatsController? _chat;
  String? _chatOwner;

  bool get _chatReady => widget.signedIn && widget.verified && widget.direct != null;

  @override
  void initState() {
    super.initState();
    // el teclado del sistema (el de Kyra es del estilo sci-fi); después de pintar, para no avisar a nadie en pleno build
    WidgetsBinding.instance.addPostFrameCallback((_) => KyraKeyboardHost.useSystem.value = true);
    _syncChat();
    widget.notice?.addListener(_onNotice);
    if (widget.notice?.value != null) _tab = GuestTab.settings;
  }

  /// Llegó un aviso (por ejemplo, una cuenta que no puede entrar aquí): se va a Ajustes, que es donde se enseña.
  void _onNotice() {
    if (widget.notice?.value != null && mounted) {
      setState(() => _tab = GuestTab.settings);
    }
  }

  @override
  void didUpdateWidget(GuestShell old) {
    super.didUpdateWidget(old);
    if (old.notice != widget.notice) {
      old.notice?.removeListener(_onNotice);
      widget.notice?.addListener(_onNotice);
    }
    _syncChat();
  }

  /// El chat se abre cuando hay sesión y la cuenta está verificada, y se cierra al salir (o al entrar otra cuenta).
  void _syncChat() {
    final ready = _chatReady;
    if (_chat != null && (!ready || _chatOwner != widget.ownerId)) {
      _chat!.dispose();
      _chat = null;
      _chatOwner = null;
    }
    if (ready && _chat == null) {
      _chat = DirectChatsController(widget.direct!, notifier: widget.notifier)..start().ignore();
      _chatOwner = widget.ownerId;
    }
  }

  @override
  void dispose() {
    widget.notice?.removeListener(_onNotice);
    KyraKeyboardHost.useSystem.value = false;
    _chat?.dispose();
    super.dispose();
  }

  void _select(int i) => setState(() => _tab = GuestTab.values[i]);

  void _back(bool didPop, Object? result) {
    if (didPop) return;
    if (_tab != GuestTab.music) {
      setState(() => _tab = GuestTab.music);
    } else if (widget.canExit?.call() ?? true) {
      unawaited(SystemNavigator.pop());
    }
  }

  NeoScheme? _schemeOf;
  ThemeData? _theme;

  /// El tema para esos colores (se vuelve a calcular solo cuando cambian).
  ThemeData _themeFor(NeoScheme scheme) {
    if (_schemeOf == scheme && _theme != null) return _theme!;
    _schemeOf = scheme;
    return _theme = neoTheme(scheme);
  }

  @override
  Widget build(BuildContext context) {
    final appearance = widget.appearance;
    if (appearance == null) return _shell(context, NeoScheme.standard);
    // los colores cambian en cuanto se elige otro tema o el modo oscuro en Ajustes
    return ListenableBuilder(listenable: appearance, builder: (context, _) => _shell(context, appearance.scheme));
  }

  Widget _shell(BuildContext context, NeoScheme scheme) {
    final needsCode = widget.signedIn && !widget.verified;
    return AnimatedTheme(
      data: _themeFor(scheme),
      duration: const Duration(milliseconds: 220),
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: scheme.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        child: PopScope(
          canPop: false,
          onPopInvokedWithResult: _back,
          // el fondo (liso con la cuadrícula) va por detrás de todo, quieto aunque salga el teclado
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(key: const Key('neo-background'), color: scheme.bg),
              CustomPaint(painter: NeoGridPainter(scheme.ink)),
              Scaffold(
                backgroundColor: Colors.transparent,
                resizeToAvoidBottomInset: true,
                body: SafeArea(
                  bottom: false,
                  // deslizar a los lados cambia de pantalla: los bloques corren borrosos y llegan los nuevos
                  child: NeoPager(
                    index: _tab.index,
                    onChanged: _select,
                    children: [
                      NeoMusicPage(controller: widget.music, player: widget.player, local: widget.local, favorites: widget.favorites),
                      NeoChatPage(
                        signedIn: widget.signedIn,
                        verified: widget.verified,
                        controller: _chat,
                        onOpenSettings: () => _select(GuestTab.settings.index),
                      ),
                      NeoSettingsPage(
                        signedIn: widget.signedIn,
                        verified: widget.verified,
                        username: widget.username,
                        role: widget.role,
                        remembered: widget.remembered,
                        onSignIn: widget.onSignIn,
                        onClaim: widget.onClaim,
                        onForget: widget.onForget,
                        onSignOut: widget.onSignOut,
                        onAdminLogin: widget.onAdminLogin,
                        notice: widget.notice,
                        appearance: widget.appearance,
                      ),
                    ],
                  ),
                ),
                bottomNavigationBar: ListenableBuilder(
                  listenable: _chat ?? const _Never(),
                  builder: (context, _) => NeoBottomNav(
                    index: _tab.index,
                    onSelect: _select,
                    items: [
                      const NeoNavItem(id: 'music', label: 'Música', icon: Icons.music_note_rounded),
                      NeoNavItem(id: 'chat', label: 'Chat', icon: Icons.chat_bubble_rounded, badge: (_chat?.unread ?? 0) > 0),
                      NeoNavItem(id: 'settings', label: 'Ajustes', icon: Icons.settings_rounded, badge: needsCode),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Un aviso que nunca suena (cuando aún no hay chat).
class _Never implements Listenable {
  const _Never();

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}
