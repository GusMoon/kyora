import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../data/chat_backend.dart';
import '../../models/profile.dart';
import '../../state/appearance_controller.dart';
import 'neo_pager.dart';
import 'neo_theme.dart';
import 'neo_themes.dart';
import 'neo_widgets.dart';

/// **Ajustes** de KyraFamily. Aquí viven:
///  · el acceso: la primera vez, nombre + contraseña (y el código de 6 dígitos que le dio el administrador); después, en ese teléfono, solo la
///    contraseña (la app recuerda quién es);
///  · la **apariencia**: el modo oscuro y uno de los 10 temas de colores;
///  · (solo si se da `onAdminLogin`) el acceso del administrador.
class NeoSettingsPage extends StatelessWidget {
  const NeoSettingsPage({
    super.key,
    required this.signedIn,
    required this.verified,
    required this.username,
    required this.role,
    required this.remembered,
    required this.onSignIn,
    required this.onClaim,
    required this.onForget,
    required this.onSignOut,
    this.onAdminLogin,
    this.notice,
    this.appearance,
  });

  /// Un aviso de la puerta de acceso (por ejemplo, «las cuentas de administrador entran en KyraAdmin»).
  final ValueListenable<String?>? notice;

  /// El tema de colores y el modo oscuro. Sin esto no sale la ventana «Apariencia».
  final AppearanceController? appearance;

  final bool signedIn;
  final bool verified;
  final String? username;
  final Role role;

  /// El nombre del visitante que ya entró en este teléfono (`null` = nadie).
  final ValueListenable<String?> remembered;

  final Future<void> Function(String name, String password) onSignIn;
  final Future<void> Function(String code) onClaim;
  final Future<void> Function() onForget;
  final Future<void> Function() onSignOut;

  /// Abre el acceso del administrador. Sin esto (KyraFamily) no sale la ventana «Administrador»: ahí no entran administradores.
  final VoidCallback? onAdminLogin;

  @override
  Widget build(BuildContext context) {
    final s = context.neo;
    return SafeArea(
      bottom: false,
      child: ListView(
        key: const Key('neo-settings-list'),
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
        children: [
          const NeoSlide(order: 0, child: NeoHero(index: '03', title: 'Ajustes', tagline: 'Tu cuenta. Tus colores. Tu Kyra.')),
          const SizedBox(height: 22),
          if (notice != null)
            ValueListenableBuilder<String?>(
              valueListenable: notice!,
              builder: (context, text, _) => text == null
                  ? const SizedBox.shrink()
                  : Padding(padding: const EdgeInsets.only(bottom: 18), child: NeoNotice(text, noticeKey: const Key('neo-access-notice'))),
            ),
          NeoSlide(
            order: 1,
            child: signedIn && !verified
                ? _Verify(onClaim: onClaim, onSignOut: onSignOut)
                : signedIn
                    ? _Account(username: username, role: role, onSignOut: onSignOut)
                    : ValueListenableBuilder<String?>(
                        valueListenable: remembered,
                        builder: (context, name, _) => _SignIn(remembered: name, onSignIn: onSignIn, onForget: onForget),
                      ),
          ),
          if (appearance != null) ...[
            const SizedBox(height: 26),
            NeoSlide(order: 2, child: _Appearance(controller: appearance!)),
          ],
          if (onAdminLogin != null) ...[
            const SizedBox(height: 26),
            NeoSlide(
              order: 3,
              child: NeoWindow(
                index: '03',
                title: 'Administrador',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Si eres el administrador, entra con tu cuenta de Kyra para ver todo.', style: neoBody(size: 15, color: s.ink)),
                    const SizedBox(height: 14),
                    NeoButton(key: const Key('neo-admin-login'), label: 'Acceso administrador', icon: Icons.admin_panel_settings_rounded, color: s.accent, onTap: onAdminLogin),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// «Apariencia»: el modo oscuro y los 10 temas de colores, agrupados por estilo. Cada muestra enseña sus dos colores; la elegida va marcada.
class _Appearance extends StatelessWidget {
  const _Appearance({required this.controller});

  final AppearanceController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final s = context.neo;
        return NeoWindow(
          index: '02',
          title: 'Apariencia',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(controller.dark ? Icons.dark_mode_rounded : Icons.light_mode_rounded, size: 20, color: s.ink),
                  const SizedBox(width: 10),
                  Expanded(child: Text('MODO OSCURO', style: neoLabel(size: 12, color: s.ink))),
                  NeoSwitch(key: const Key('neo-dark-toggle'), value: controller.dark, onChanged: (v) => unawaited(controller.setDark(v))),
                ],
              ),
              for (final group in NeoThemeGroup.values) ...[
                const SizedBox(height: 18),
                Text(group.label.toUpperCase(), style: neoLabel(size: 11, color: s.dim)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final theme in NeoThemes.all.where((t) => t.group == group))
                      _Swatch(theme: theme, selected: theme.id == controller.theme.id, dark: controller.dark, onTap: () => unawaited(controller.setTheme(theme))),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Una muestra de tema: sus dos colores (ya ajustados al modo de ahora) y su nombre. La elegida lleva el filo marcado y una palomita.
class _Swatch extends StatelessWidget {
  const _Swatch({required this.theme, required this.selected, required this.dark, required this.onTap});

  final NeoThemeSpec theme;
  final bool selected;
  final bool dark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.neo;
    final preview = NeoScheme.of(theme, dark: dark);
    return Semantics(
      button: true,
      selected: selected,
      label: theme.name,
      child: GestureDetector(
        key: Key('neo-theme-${theme.id}'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 96,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: s.paper, border: Border.all(color: selected ? s.ink : s.line, width: selected ? 2 : Neo.border)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 28,
                child: Row(
                  children: [
                    Expanded(child: Container(color: preview.accent)),
                    Expanded(child: Container(color: preview.pop, child: selected ? Icon(Icons.check_rounded, size: 18, color: preview.onPop) : null)),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(theme.name.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: neoLabel(size: 10, color: s.ink)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Un texto de error con su caja.
Widget _errorBox(String? text) => text == null
    ? const SizedBox.shrink()
    : Padding(padding: const EdgeInsets.only(top: 14), child: NeoNotice(text, noticeKey: const Key('neo-error')));

class _SignIn extends StatefulWidget {
  const _SignIn({required this.remembered, required this.onSignIn, required this.onForget});

  final String? remembered;
  final Future<void> Function(String name, String password) onSignIn;
  final Future<void> Function() onForget;

  @override
  State<_SignIn> createState() => _SignInState();
}

class _SignInState extends State<_SignIn> {
  final _name = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _hide = true;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final name = widget.remembered ?? _name.text.trim();
    if (name.isEmpty || _password.text.isEmpty) {
      setState(() => _error = widget.remembered == null ? 'Escribe tu nombre y tu contraseña.' : 'Escribe tu contraseña.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSignIn(name, _password.text);
      _password.clear();
    } on ChatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final known = widget.remembered;
    return NeoWindow(
      title: known == null ? 'Entrar' : 'Bienvenido',
      index: '01',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (known != null) ...[
            Text('HOLA,', style: neoLabel(size: 12, color: context.neo.accentDeep)),
            Text(known.toUpperCase(), key: const Key('neo-remembered'), style: neoHeading(size: 30, color: context.neo.ink)),
            const SizedBox(height: 16),
          ] else ...[
            NeoField(
              fieldKey: const Key('neo-name'),
              controller: _name,
              label: 'Nombre',
              hint: 'tu nombre de usuario',
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 14),
          ],
          NeoField(
            fieldKey: const Key('neo-password'),
            controller: _password,
            label: 'Contraseña',
            obscure: _hide,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => unawaited(_submit()),
            suffix: IconButton(
              tooltip: _hide ? 'Mostrar' : 'Ocultar',
              icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: context.neo.ink),
              onPressed: () => setState(() => _hide = !_hide),
            ),
          ),
          _errorBox(_error),
          const SizedBox(height: 18),
          NeoButton(key: const Key('neo-sign-in'), label: 'Entrar', icon: Icons.login_rounded, busy: _busy, onTap: () => unawaited(_submit())),
          if (known != null) ...[
            const SizedBox(height: 14),
            Center(
              child: GestureDetector(
                key: const Key('neo-forget'),
                onTap: _busy ? null : () => unawaited(widget.onForget()),
                child: Text('NO SOY YO', style: neoLink(context.neo.ink)),
              ),
            ),
          ] else ...[
            const SizedBox(height: 14),
            Text('¿No tienes cuenta? Las cuentas las crea el administrador.', textAlign: TextAlign.center, style: neoBody(size: 13, color: context.neo.dim)),
          ],
        ],
      ),
    );
  }
}

class _Verify extends StatefulWidget {
  const _Verify({required this.onClaim, required this.onSignOut});

  final Future<void> Function(String code) onClaim;
  final Future<void> Function() onSignOut;

  @override
  State<_Verify> createState() => _VerifyState();
}

class _VerifyState extends State<_Verify> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final code = _code.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() => _error = 'El código tiene 6 dígitos.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onClaim(code);
    } on ChatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return NeoWindow(
      title: 'Verifica tu cuenta',
      index: '01',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Escribe el código de 6 dígitos que te dio el administrador. Solo se pide esta vez.', style: neoBody(color: context.neo.ink)),
          const SizedBox(height: 16),
          NeoField(
            fieldKey: const Key('neo-code'),
            controller: _code,
            label: 'Código',
            hint: '000000',
            keyboardType: TextInputType.number,
            maxLength: 6,
            textAlign: TextAlign.center,
            style: neoHeading(size: 30, color: context.neo.ink).copyWith(fontFamily: 'IBM Plex Mono', letterSpacing: 8),
            onSubmitted: (_) => unawaited(_submit()),
          ),
          _errorBox(_error),
          const SizedBox(height: 18),
          NeoButton(key: const Key('neo-verify'), label: 'Verificar', icon: Icons.verified_rounded, busy: _busy, onTap: () => unawaited(_submit())),
          const SizedBox(height: 14),
          Center(
            child: GestureDetector(
              onTap: _busy ? null : () => unawaited(widget.onSignOut()),
              child: Text('SALIR', style: neoLink(context.neo.ink)),
            ),
          ),
        ],
      ),
    );
  }
}

class _Account extends StatefulWidget {
  const _Account({required this.username, required this.role, required this.onSignOut});

  final String? username;
  final Role role;
  final Future<void> Function() onSignOut;

  @override
  State<_Account> createState() => _AccountState();
}

class _AccountState extends State<_Account> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return NeoWindow(
      index: '01',
      title: 'Tu cuenta',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('SESIÓN INICIADA', style: neoLabel(size: 12, color: context.neo.dim)),
          const SizedBox(height: 6),
          Text((widget.username ?? '').toUpperCase(), key: const Key('neo-username'), style: neoHeading(size: 30, color: context.neo.ink)),
          const SizedBox(height: 10),
          Align(alignment: Alignment.centerLeft, child: NeoTag(roleLabel(widget.role), color: context.neo.accent)),
          const SizedBox(height: 18),
          NeoButton(
            key: const Key('neo-sign-out'),
            label: 'Cerrar sesión',
            icon: Icons.logout_rounded,
            color: context.neo.paper,
            busy: _busy,
            onTap: () async {
              setState(() => _busy = true);
              try {
                await widget.onSignOut();
              } finally {
                if (mounted) setState(() => _busy = false);
              }
            },
          ),
        ],
      ),
    );
  }
}
