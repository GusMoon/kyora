import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/chat_backend.dart';
import '../theme.dart';
import 'widgets/pixel_glyph.dart';

/// El acceso del **administrador**: su correo y contraseña (los mismos que la PC). La sesión queda guardada en el teléfono; la contraseña no.
/// Ya no se puede crear una cuenta aquí: las cuentas las crea el administrador (los visitantes entran por Ajustes, con su nombre).
class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.onSignIn, this.notice});

  final Future<void> Function(String email, String password) onSignIn;

  /// Un aviso de la puerta de acceso (por ejemplo, «esa cuenta no es de administrador»): sale aunque esta pantalla se haya vuelto a abrir.
  final ValueListenable<String?>? notice;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _hide = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_email.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Escribe tu correo y tu contraseña.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSignIn(_email.text, _password.text);
      // Al entrar, la pantalla cambia sola (la puerta de acceso escucha la sesión).
    } on ChatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 76,
                      height: 76,
                      color: context.colors.accent,
                      child: LcdIcon(Icons.forum_rounded, size: 38, color: context.colors.onAccent),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text('Kyra', textAlign: TextAlign.center, style: display(size: 48, color: context.colors.ink)),
                  const SizedBox(height: 6),
                  Text(
                    'Acceso de administrador: tu correo y contraseña.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: context.colors.dim),
                  ),
                  const SizedBox(height: 30),
                  TextField(
                    key: const Key('email'),
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(hintText: 'Correo'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('password'),
                    controller: _password,
                    obscureText: _hide,
                    autofillHints: const [AutofillHints.password],
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      hintText: 'Contraseña',
                      suffixIcon: IconButton(
                        tooltip: _hide ? 'Mostrar' : 'Ocultar',
                        icon: LcdIcon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: context.colors.dim),
                        onPressed: () => setState(() => _hide = !_hide),
                      ),
                    ),
                  ),
                  if (widget.notice != null)
                    ValueListenableBuilder<String?>(
                      valueListenable: widget.notice!,
                      builder: (context, text, _) => text == null
                          ? const SizedBox.shrink()
                          : Padding(
                              padding: const EdgeInsets.only(top: 14),
                              child: Text(text, key: const Key('login-notice'), textAlign: TextAlign.center, style: TextStyle(color: context.colors.warn)),
                            ),
                    ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Text(_error!, key: const Key('login-error'), textAlign: TextAlign.center, style: TextStyle(color: context.colors.warn)),
                  ],
                  const SizedBox(height: 22),
                  FilledButton(
                    key: const Key('login-button'),
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4))
                        : const Text('Entrar'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
