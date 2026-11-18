import 'dart:async';

import 'package:flutter/material.dart';

import '../data/chat_backend.dart';
import '../data/password_vault.dart';
import '../state/passwords_controller.dart';
import '../theme.dart';
import 'widgets/flat_form.dart';
import 'widgets/focus_space.dart';
import 'widgets/pixel_glyph.dart';
import 'widgets/section_motion.dart';

/// **Contraseñas**: la misma bóveda que la de Merida (mismas tablas y mismo cifrado). Sin crear, pide una **contraseña maestra** (mínimo 12 caracteres y
/// sin forma de recuperarla); creada, se abre con ella. Abierta, enseña las entradas con buscador (por servicio, correo, usuario y URL): tocar una la
/// despliega, con **copiar** en cada dato y mostrar u ocultar la contraseña; «+» crea una (con generador y medidor de fuerza) y desde la entrada se
/// edita o se borra. La clave solo vive en memoria: se bloquea sola a los 5 minutos sin tocar, al salir de la pantalla y al irse la app a segundo
/// plano; lo copiado se borra del portapapeles a los 30 segundos.
class PasswordsPage extends StatefulWidget {
  const PasswordsPage({super.key, required this.backend, this.create});

  final PasswordBackend backend;

  /// Cómo se crea el controlador (en las pruebas, con menos vueltas de cifrado y relojes cortos).
  final PasswordsController Function(PasswordBackend backend)? create;

  @override
  State<PasswordsPage> createState() => _PasswordsPageState();
}

class _PasswordsPageState extends State<PasswordsPage> with WidgetsBindingObserver {
  late final PasswordsController _ctrl = (widget.create ?? PasswordsController.new)(widget.backend);
  final _search = TextEditingController();
  String? _openId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_ctrl.refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // al irse a segundo plano la bóveda se cierra: al volver hay que escribir la maestra otra vez
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden || state == AppLifecycleState.detached) _ctrl.lock();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _search.dispose();
    _ctrl.dispose(); // suelta la clave y lo descifrado
    super.dispose();
  }

  Future<void> _copy(String label, String text) async {
    await _ctrl.copy(text);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$label copiado. Se borrará del portapapeles en 30 segundos.')));
  }

  Future<void> _edit({VaultItem? existing}) => showFocusPanel<void>(
    context,
    builder: (_) => _ItemEditor(controller: _ctrl, existing: existing),
  );

  Future<void> _delete(VaultItem item) async {
    final sure = await showFocusPanel<bool>(
      context,
      title: 'Borrar entrada',
      builder: (context) => FocusDialog(
        content: Text('¿Borrar «${item.service}»? No se puede deshacer.', key: const Key('pw-delete-text')),
        actions: [
          TextButton(key: const Key('pw-delete-cancel'), onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
          FilledButton(
            key: const Key('pw-delete-confirm'),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 40), backgroundColor: context.colors.warn),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (sure != true) return;
    try {
      await _ctrl.remove(item);
    } on ChatException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // tocar la pantalla reinicia el reloj del bloqueo automático
    return FlatBackdrop(child: Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _ctrl.touch(),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: ListenableBuilder(
              listenable: _ctrl,
              builder: (context, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FlyIn(
                    edge: MotionEdge.top,
                    order: 0,
                    child: FlatHeader(
                      title: 'CONTRASEÑAS',
                      actions: [
                        if (_ctrl.unlocked) ...[
                          IconButton(
                            key: const Key('pw-add'),
                            tooltip: 'Nueva entrada',
                            icon: LcdIcon(Icons.add_rounded, color: c.accent),
                            onPressed: () => unawaited(_edit()),
                          ),
                          IconButton(
                            key: const Key('pw-lock'),
                            tooltip: 'Bloquear la bóveda',
                            icon: LcdIcon(Icons.lock_outline_rounded, color: c.ink),
                            onPressed: _ctrl.lock,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: FlyIn(
                      edge: MotionEdge.bottom,
                      order: 1,
                      child: _body(context),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ));
  }

  Widget _body(BuildContext context) {
    final c = context.colors;
    switch (_ctrl.state) {
      case VaultState.loading:
        return const Center(child: CircularProgressIndicator(strokeWidth: 2.4));
      case VaultState.error:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _ctrl.error ?? 'No se pudo abrir la bóveda.',
                  key: const Key('pw-error'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.warn, fontSize: 16),
                ),
                const SizedBox(height: 12),
                OutlinedButton(key: const Key('pw-retry'), onPressed: () => unawaited(_ctrl.refresh()), child: const Text('Reintentar')),
              ],
            ),
          ),
        );
      case VaultState.none:
        return _CreateForm(controller: _ctrl);
      case VaultState.locked:
        return _UnlockForm(controller: _ctrl);
      case VaultState.unlocked:
        final items = _ctrl.search(_search.text);
        return ListView(
          key: const Key('pw-list'),
          padding: const EdgeInsets.fromLTRB(2, 6, 2, 16),
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.edge))),
              child: Row(
                children: [
                  Text('> ', style: TextStyle(fontFamily: monoFont, fontSize: 17, color: c.accent)),
                  Expanded(
                    child: TextField(
                      key: const Key('pw-search'),
                      controller: _search,
                      onChanged: (_) => setState(() {}),
                      style: TextStyle(fontFamily: monoFont, fontSize: 16, color: c.ink),
                      decoration: flatInput(context, hint: 'buscar servicio, correo, usuario o URL'),
                    ),
                  ),
                ],
              ),
            ),
            if (_ctrl.broken > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _ctrl.broken == 1 ? '1 entrada no se pudo descifrar (no se perdió).' : '${_ctrl.broken} entradas no se pudieron descifrar (no se perdieron).',
                  key: const Key('pw-broken'),
                  style: TextStyle(color: c.warn, fontSize: 15),
                ),
              ),
            const SizedBox(height: 8),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    _ctrl.items.isEmpty ? 'La bóveda está vacía. Toca «+» para guardar la primera.' : 'Ninguna entrada coincide.',
                    key: const Key('pw-empty'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: c.dim, fontSize: 16),
                  ),
                ),
              )
            else
              for (final item in items)
                _ItemTile(
                  key: Key('pw-item-${item.id}'),
                  item: item,
                  open: _openId == item.id,
                  onToggle: () => setState(() => _openId = _openId == item.id ? null : item.id),
                  onCopy: _copy,
                  onEdit: () => unawaited(_edit(existing: item)),
                  onDelete: () => unawaited(_delete(item)),
                ),
          ],
        );
    }
  }
}

/// Un campo de contraseña con el ojo para mostrarla u ocultarla.
class _SecretField extends StatefulWidget {
  const _SecretField({required this.fieldKey, required this.controller, required this.hint, this.autofocus = false, this.onSubmitted, this.errorText});

  final Key fieldKey;
  final TextEditingController controller;
  final String hint;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;
  final String? errorText;

  @override
  State<_SecretField> createState() => _SecretFieldState();
}

class _SecretFieldState extends State<_SecretField> {
  bool _show = false;

  @override
  Widget build(BuildContext context) => TextField(
    key: widget.fieldKey,
    controller: widget.controller,
    autofocus: widget.autofocus,
    obscureText: !_show,
    autocorrect: false,
    enableSuggestions: false,
    onSubmitted: widget.onSubmitted,
    decoration: flatInput(
      context,
      hint: widget.hint,
      error: widget.errorText,
      suffix: IconButton(
        key: Key('${(widget.fieldKey as ValueKey).value}-eye'),
        tooltip: _show ? 'Ocultar' : 'Mostrar',
        icon: Icon(_show ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: context.colors.dim),
        onPressed: () => setState(() => _show = !_show),
      ),
    ),
  );
}

/// Sin bóveda todavía: crear la contraseña maestra.
class _CreateForm extends StatefulWidget {
  const _CreateForm({required this.controller});

  final PasswordsController controller;

  @override
  State<_CreateForm> createState() => _CreateFormState();
}

class _CreateFormState extends State<_CreateForm> {
  final _master = TextEditingController();
  final _again = TextEditingController();
  bool _ack = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _master.dispose();
    _again.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_master.text.length < PasswordsController.minMaster) {
      setState(() => _error = 'Debe tener al menos ${PasswordsController.minMaster} caracteres.');
      return;
    }
    if (_master.text != _again.text) {
      setState(() => _error = 'Las dos contraseñas no coinciden.');
      return;
    }
    if (!_ack) {
      setState(() => _error = 'Confirma que entiendes que no hay forma de recuperarla.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.controller.create(_master.text);
    } on VaultException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on ChatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Crea tu bóveda',
            style: display(size: 24, color: c.ink, weight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            'Tus contraseñas se cifran aquí, en el teléfono, con una contraseña maestra que nunca sale de él: ni Supabase ni nadie más puede leerlas. Es la misma bóveda de Merida.',
            style: TextStyle(color: c.dim, fontSize: 15),
          ),
          const SizedBox(height: 10),
          FlatStat(label: 'Contraseña maestra', child: _SecretField(fieldKey: const Key('pw-master'), controller: _master, hint: 'Mínimo ${PasswordsController.minMaster} caracteres', autofocus: true)),
          FlatStat(label: 'Repítela', child: _SecretField(fieldKey: const Key('pw-master2'), controller: _again, hint: 'La misma otra vez', errorText: _error)),
          const SizedBox(height: 4),
          CheckboxListTile(
            key: const Key('pw-ack'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _ack,
            onChanged: (v) => setState(() => _ack = v ?? false),
            title: Text('Entiendo que si la olvido no hay forma de recuperar mis contraseñas.', style: TextStyle(color: c.ink, fontSize: 15)),
          ),
          const SizedBox(height: 6),
          Align(alignment: Alignment.centerRight, child: FlatAction(key: const Key('pw-create'), icon: Icons.lock_outline_rounded, label: _busy ? 'Creando…' : 'Crear la bóveda', onTap: _busy ? null : _create)),
        ],
      ),
    );
  }
}

/// Bóveda creada pero bloqueada: pide la contraseña maestra.
class _UnlockForm extends StatefulWidget {
  const _UnlockForm({required this.controller});

  final PasswordsController controller;

  @override
  State<_UnlockForm> createState() => _UnlockFormState();
}

class _UnlockFormState extends State<_UnlockForm> {
  final _master = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _master.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    if (_master.text.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ok = await widget.controller.unlock(_master.text);
      if (!ok && mounted) setState(() => _error = 'Contraseña incorrecta.');
    } on ChatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              LcdIcon(Icons.lock_outline_rounded, color: c.accent),
              const SizedBox(width: 10),
              Expanded(child: Text('Bóveda bloqueada', maxLines: 1, overflow: TextOverflow.ellipsis, style: display(size: 24, color: c.ink, weight: FontWeight.w600))),
            ],
          ),
          const SizedBox(height: 10),
          FlatStat(
            label: 'Contraseña maestra',
            last: true,
            child: _SecretField(
              fieldKey: const Key('pw-master'),
              controller: _master,
              hint: 'Escríbela para abrir',
              autofocus: true,
              errorText: _error,
              onSubmitted: (_) => unawaited(_unlock()),
            ),
          ),
          const SizedBox(height: 8),
          Align(alignment: Alignment.centerRight, child: FlatAction(key: const Key('pw-unlock'), icon: Icons.lock_open_rounded, label: _busy ? 'Abriendo…' : 'Abrir', onTap: _busy ? null : _unlock)),
        ],
      ),
    );
  }
}

/// Una entrada: cerrada, el servicio y el correo; abierta, cada dato con su botón de copiar, la contraseña oculta y los botones de editar y borrar.
class _ItemTile extends StatefulWidget {
  const _ItemTile({
    super.key,
    required this.item,
    required this.open,
    required this.onToggle,
    required this.onCopy,
    required this.onEdit,
    required this.onDelete,
  });

  final VaultItem item;
  final bool open;
  final VoidCallback onToggle;
  final Future<void> Function(String label, String text) onCopy;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  State<_ItemTile> createState() => _ItemTileState();
}

class _ItemTileState extends State<_ItemTile> {
  bool _show = false;

  Widget _row(BuildContext context, String id, String label, String value, {bool secret = false}) {
    if (value.isEmpty) return const SizedBox.shrink();
    final c = context.colors;
    final shown = secret && !_show ? '•' * 10 : value;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          SizedBox(
            width: 86,
            child: Text(
              label,
              style: TextStyle(fontFamily: monoFont, fontSize: 15, color: c.dim),
            ),
          ),
          Expanded(
            child: Text(
              shown,
              key: Key('pw-value-$id-${widget.item.id}'),
              maxLines: id == 'notes' ? 6 : 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: monoFont, fontSize: 15, color: c.ink),
            ),
          ),
          if (secret)
            IconButton(
              key: Key('pw-eye-${widget.item.id}'),
              tooltip: _show ? 'Ocultar' : 'Mostrar',
              visualDensity: VisualDensity.compact,
              icon: Icon(_show ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20, color: c.dim),
              onPressed: () => setState(() => _show = !_show),
            ),
          IconButton(
            key: Key('pw-copy-$id-${widget.item.id}'),
            tooltip: 'Copiar',
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.copy_rounded, size: 20, color: c.accent),
            onPressed: () => unawaited(widget.onCopy(label, value)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final item = widget.item;
    return Container(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.edge), left: BorderSide(color: widget.open ? c.accent : Colors.transparent, width: 2))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            key: Key('pw-head-${item.id}'),
            onTap: widget.onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.service,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontFamily: monoFont, fontSize: 16, fontWeight: FontWeight.w700, color: c.ink),
                        ),
                        if (item.email.isNotEmpty || item.username.isNotEmpty)
                          Text(
                            item.email.isNotEmpty ? item.email : item.username,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontFamily: monoFont, fontSize: 15, color: c.dim),
                          ),
                      ],
                    ),
                  ),
                  Icon(widget.open ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: c.dim),
                ],
              ),
            ),
          ),
          if (widget.open)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 4, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _row(context, 'email', 'CORREO', item.email),
                  _row(context, 'username', 'USUARIO', item.username),
                  _row(context, 'password', 'CLAVE', item.password, secret: true),
                  _row(context, 'url', 'URL', item.url),
                  _row(context, 'notes', 'NOTAS', item.notes),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      FlatAction(key: Key('pw-edit-${item.id}'), icon: Icons.edit_outlined, label: 'Editar', onTap: widget.onEdit),
                      FlatAction(key: Key('pw-del-${item.id}'), icon: Icons.delete_outline_rounded, label: 'Borrar', warn: true, onTap: widget.onDelete),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Crea una entrada, o edita `existing`: servicio, correo, usuario, contraseña (con generador y medidor de fuerza), URL y notas.
class _ItemEditor extends StatefulWidget {
  const _ItemEditor({required this.controller, this.existing});

  final PasswordsController controller;
  final VaultItem? existing;

  @override
  State<_ItemEditor> createState() => _ItemEditorState();
}

class _ItemEditorState extends State<_ItemEditor> {
  late final _service = TextEditingController(text: widget.existing?.service ?? '');
  late final _email = TextEditingController(text: widget.existing?.email ?? '');
  late final _username = TextEditingController(text: widget.existing?.username ?? '');
  late final _password = TextEditingController(text: widget.existing?.password ?? '');
  late final _url = TextEditingController(text: widget.existing?.url ?? '');
  late final _notes = TextEditingController(text: widget.existing?.notes ?? '');
  int _length = 20;
  bool _symbols = true;
  String? _error;
  bool _busy = false;

  static const lengths = [12, 16, 20, 24, 32];

  @override
  void dispose() {
    for (final t in [_service, _email, _username, _password, _url, _notes]) {
      t.dispose();
    }
    super.dispose();
  }

  void _generate() => setState(() => _password.text = VaultCrypto.generatePassword(length: _length, symbols: _symbols));

  /// Solo direcciones http o https.
  static bool _validUrl(String text) {
    final uri = Uri.tryParse(text.trim());
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty;
  }

  Future<void> _save() async {
    if (_service.text.trim().isEmpty) {
      setState(() => _error = 'Escribe el nombre del servicio.');
      return;
    }
    if (_email.text.trim().isEmpty && _username.text.trim().isEmpty && _password.text.isEmpty) {
      setState(() => _error = 'Anota al menos el correo, el usuario o la contraseña.');
      return;
    }
    if (_url.text.trim().isNotEmpty && !_validUrl(_url.text)) {
      setState(() => _error = 'La URL debe empezar con http:// o https://.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final existing = widget.existing;
      if (existing == null) {
        await widget.controller.add(
          service: _service.text,
          email: _email.text,
          username: _username.text,
          password: _password.text,
          url: _url.text,
          notes: _notes.text,
        );
      } else {
        await widget.controller.update(
          existing,
          service: _service.text,
          email: _email.text,
          username: _username.text,
          password: _password.text,
          url: _url.text,
          notes: _notes.text,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } on ChatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on VaultException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final strength = VaultCrypto.strength(_password.text);
    const labels = ['muy débil', 'débil', 'regular', 'buena', 'fuerte'];
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.existing == null ? 'Nueva entrada' : 'Editar entrada', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              FlatStat(
                label: 'Servicio',
                child: TextField(
                  key: const Key('pw-service'),
                  controller: _service,
                  autofocus: widget.existing == null,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: flatInput(context, hint: 'Servicio o aplicación'),
                ),
              ),
              FlatStat(
                label: 'Correo',
                child: TextField(
                  key: const Key('pw-email'),
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: flatInput(context, hint: 'correo@ejemplo.com'),
                ),
              ),
              FlatStat(
                label: 'Usuario',
                child: TextField(
                  key: const Key('pw-username'),
                  controller: _username,
                  autocorrect: false,
                  decoration: flatInput(context, hint: 'Nombre de usuario'),
                ),
              ),
              FlatStat(
                label: 'Contraseña',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _SecretField(fieldKey: const Key('pw-password'), controller: _password, hint: 'Contraseña'),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: LinearProgressIndicator(
                            key: const Key('pw-strength'),
                            value: (strength + 1) / 5,
                            minHeight: 4,
                            color: strength < 2 ? c.warn : c.ok,
                            backgroundColor: c.edge,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _password.text.isEmpty ? '' : labels[strength],
                          key: const Key('pw-strength-label'),
                          style: TextStyle(fontFamily: monoFont, fontSize: 15, color: c.dim),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 14,
                      runSpacing: 2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        for (final n in lengths) FlatChoice(key: Key('pw-length-$n'), label: '$n', selected: _length == n, onTap: () => setState(() => _length = n)),
                        FlatChoice(key: const Key('pw-symbols'), label: 'símbolos', selected: _symbols, onTap: () => setState(() => _symbols = !_symbols)),
                        FlatAction(key: const Key('pw-generate'), icon: Icons.casino_outlined, label: 'Generar', onTap: _generate),
                      ],
                    ),
                  ],
                ),
              ),
              FlatStat(
                label: 'URL',
                child: TextField(
                  key: const Key('pw-url'),
                  controller: _url,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: flatInput(context, hint: 'https://… (opcional)'),
                ),
              ),
              FlatStat(
                label: 'Notas',
                last: true,
                child: TextField(
                  key: const Key('pw-notes'),
                  controller: _notes,
                  minLines: 1,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: flatInput(context, hint: 'Opcional'),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _error!,
                    key: const Key('pw-form-error'),
                    style: TextStyle(color: c.warn, fontSize: 15),
                  ),
                ),
              const SizedBox(height: 14),
              Align(alignment: Alignment.centerRight, child: FlatAction(key: const Key('pw-save'), icon: Icons.check_rounded, label: _busy ? 'Guardando…' : 'Guardar', onTap: _busy ? null : _save)),
            ],
          ),
        ),
      ),
    );
  }
}
