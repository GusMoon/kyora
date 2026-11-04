import 'package:flutter/material.dart';

import '../data/chat_backend.dart';
import '../theme.dart';
import 'register_page.dart';

/// La pantalla de acceso: tu correo y contraseña (el administrador usa los mismos que la PC). La sesión queda guardada en el
/// teléfono; la contraseña no. Con `onSignUp`, quien aún no tiene cuenta puede crearla (pasantes).
class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.onSignIn, this.onSignUp});

  final Future<void> Function(String email, String password) onSignIn;
  final Future<bool> Function(String username, String email, String password)? onSignUp;

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

  Future<void> _createAccount() async {
    final notice = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(builder: (_) => RegisterPage(onSignUp: widget.onSignUp!)),
    );
    if (notice != null && mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(notice)));
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
                  Icon(Icons.forum_rounded, size: 56, color: context.colors.accent),
                  const SizedBox(height: 14),
                  Text('Kyra', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 26)),
                  const SizedBox(height: 6),
                  Text(
                    'Entra con tu correo y contraseña.',
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
                        icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: context.colors.dim),
                        onPressed: () => setState(() => _hide = !_hide),
                      ),
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
                  if (widget.onSignUp != null) ...[
                    const SizedBox(height: 10),
                    TextButton(key: const Key('create-account'), onPressed: _busy ? null : _createAccount, child: const Text('Crear cuenta')),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
