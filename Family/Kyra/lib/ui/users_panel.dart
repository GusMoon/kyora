import 'dart:async';

import 'package:flutter/material.dart';

import '../models/presence.dart';
import '../models/profile.dart';
import '../state/users_controller.dart';
import '../theme.dart';
import 'settings_rows.dart';

/// El panel **Usuarios** del administrador (en Configuración): todas las cuentas con un punto verde si están en línea (o hace cuánto se
/// vieron), su rol y si ya verificaron su código. Desde aquí se **crea** una cuenta (nombre y contraseña, sin correo) y se le entrega su código
/// de 6 dígitos, y se cambia el rol, se pide un código nuevo o se quita el acceso.
class UsersPanel extends StatelessWidget {
  const UsersPanel({super.key, required this.controller, this.now});

  final UsersController controller;

  /// El reloj (en las pruebas, uno fijo).
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final entries = controller.entries;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                'Las cuentas las creas tú. ${controller.onlineCount} en línea de ${entries.length}.',
                key: const Key('users-count'),
                style: lcdStatus(size: 15, color: c.dim),
              ),
            ),
            SettingsRow(
              key: const Key('users-create'),
              icon: Icons.person_add_alt_1_outlined,
              title: 'Crear cuenta',
              subtitle: 'Nombre y contraseña; te da un código de 6 dígitos',
              trailing: Icon(Icons.chevron_right, color: c.dim),
              onTap: controller.busy ? null : () => unawaited(_create(context)),
            ),
            Divider(height: 1, thickness: 1, color: c.edge),
            SettingsRow(
              key: const Key('users-refresh'),
              icon: Icons.refresh_rounded,
              title: 'Actualizar',
              onTap: () => unawaited(controller.refresh()),
            ),
            if (controller.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(controller.error!, key: const Key('users-error'), style: lcdStatus(size: 15, color: c.warn)),
              ),
            const SizedBox(height: 8),
            if (controller.loading)
              const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)))
            else
              for (final e in entries) ...[
                Divider(height: 1, thickness: 1, color: c.edge),
                _Row(entry: e, now: (now ?? DateTime.now)(), onTap: () => unawaited(_actions(context, e))),
              ],
          ],
        );
      },
    );
  }

  Future<void> _create(BuildContext context) async {
    final request = await showDialog<_NewAccount>(context: context, builder: (_) => const _CreateDialog());
    if (request == null || !context.mounted) return;
    final issued = await controller.create(username: request.username, password: request.password, role: request.role);
    if (!context.mounted) return;
    if (issued == null) return; // el motivo queda en controller.error
    await _showCode(context, issued, created: true);
  }

  Future<void> _actions(BuildContext context, PresenceEntry e) async {
    if (e.me) return; // con tu propia cuenta no se hace nada desde aquí
    final choice = await showDialog<_Action>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(e.username),
        children: [
          SimpleDialogOption(
            key: const Key('users-act-role'),
            onPressed: () => Navigator.of(context).pop(_Action.role),
            child: Text(e.role == Role.admin ? 'Pasar a visitante' : 'Pasar a administrador'),
          ),
          SimpleDialogOption(key: const Key('users-act-code'), onPressed: () => Navigator.of(context).pop(_Action.code), child: const Text('Código nuevo (pide verificar otra vez)')),
          SimpleDialogOption(key: const Key('users-act-remove'), onPressed: () => Navigator.of(context).pop(_Action.remove), child: Text('Quitar acceso', style: TextStyle(color: context.colors.warn))),
        ],
      ),
    );
    if (choice == null || !context.mounted) return;
    switch (choice) {
      case _Action.role:
        await controller.changeRole(e, e.role == Role.admin ? Role.intern : Role.admin);
      case _Action.code:
        final issued = await controller.newCode(e);
        if (issued != null && context.mounted) await _showCode(context, issued, created: false);
      case _Action.remove:
        final yes = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('¿Quitar a ${e.username}?'),
            content: const Text('Pierde el acceso y su cuenta se borra.'),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
              TextButton(key: const Key('users-confirm-remove'), onPressed: () => Navigator.of(context).pop(true), child: Text('Quitar', style: TextStyle(color: context.colors.warn))),
            ],
          ),
        );
        if (yes == true) await controller.remove(e);
    }
  }

  Future<void> _showCode(BuildContext context, IssuedCode issued, {required bool created}) => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(created ? 'Cuenta creada' : 'Código nuevo'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Entrégale a ${issued.username} este código. Lo escribe una sola vez al entrar y caduca en 72 horas.'),
              const SizedBox(height: 16),
              Center(
                child: SelectableText(
                  issued.code,
                  key: const Key('users-code'),
                  style: TextStyle(fontFamily: monoFont, fontSize: 40, fontWeight: FontWeight.w700, letterSpacing: 8, color: context.colors.accent),
                ),
              ),
              const SizedBox(height: 12),
              Text('No se vuelve a mostrar. Si se pierde, pide uno nuevo.', style: lcdStatus(size: 14, color: context.colors.dim)),
            ],
          ),
          actions: [TextButton(key: const Key('users-code-done'), onPressed: () => Navigator.of(context).pop(), child: const Text('Listo'))],
        ),
      );
}

enum _Action { role, code, remove }

class _Row extends StatelessWidget {
  const _Row({required this.entry, required this.now, required this.onTap});

  final PresenceEntry entry;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final status = lastSeenText(entry, now);
    final extra = [
      roleLabel(entry.role),
      if (!entry.verified) (entry.codePending ? 'código pendiente' : 'sin verificar'),
      status,
    ].join(' · ');
    return SettingsRow(
      key: Key('users-row-${entry.username}'),
      leading: Padding(padding: const EdgeInsets.all(5), child: Icon(Icons.circle, size: 14, color: entry.online ? c.ok : c.dim)),
      title: entry.me ? '${entry.username} (tú)' : entry.username,
      subtitle: extra,
      trailing: entry.me ? null : Icon(Icons.more_horiz, color: c.dim),
      onTap: entry.me ? null : onTap,
    );
  }
}

class _NewAccount {
  const _NewAccount(this.username, this.password, this.role);

  final String username;
  final String password;
  final Role role;
}

class _CreateDialog extends StatefulWidget {
  const _CreateDialog();

  @override
  State<_CreateDialog> createState() => _CreateDialogState();
}

class _CreateDialogState extends State<_CreateDialog> {
  final _name = TextEditingController();
  final _password = TextEditingController();
  Role _role = Role.intern;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim().toLowerCase();
    if (!RegExp(r'^[a-z0-9][a-z0-9._-]{1,22}[a-z0-9]$').hasMatch(name) || name.contains('..')) {
      setState(() => _error = 'El nombre: 3 a 24 caracteres, minúsculas, números, punto, guion o guion bajo.');
      return;
    }
    if (_password.text.length < 6) {
      setState(() => _error = 'La contraseña debe tener al menos 6 caracteres.');
      return;
    }
    Navigator.of(context).pop(_NewAccount(name, _password.text, _role));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Crear cuenta'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(key: const Key('users-new-name'), controller: _name, autofocus: true, decoration: const InputDecoration(hintText: 'Nombre de usuario')),
            const SizedBox(height: 12),
            TextField(key: const Key('users-new-password'), controller: _password, decoration: const InputDecoration(hintText: 'Contraseña')),
            const SizedBox(height: 14),
            SegmentedButton<Role>(
              key: const Key('users-new-role'),
              segments: const [
                ButtonSegment(value: Role.intern, label: Text('Visitante')),
                ButtonSegment(value: Role.admin, label: Text('Admin')),
              ],
              selected: {_role},
              onSelectionChanged: (s) => setState(() => _role = s.first),
            ),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, key: const Key('users-new-error'), style: TextStyle(color: context.colors.warn))),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        TextButton(key: const Key('users-new-submit'), onPressed: _submit, child: const Text('Crear')),
      ],
    );
  }
}
