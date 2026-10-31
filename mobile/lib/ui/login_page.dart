import 'package:flutter/material.dart';

import '../data/chat_backend.dart';
import '../theme.dart';

/// La pantalla de acceso: el mismo correo y contraseña que usa la PC (el usuario que creaste en Supabase). La sesión queda
/// guardada en el teléfono; la contraseña no.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.onSignIn});

  final Future<void> Function(String email, String password) onSignIn;

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
                  const Icon(Icons.forum_rounded, size: 56, color: Palette.accent),
                  const SizedBox(height: 14),
                  Text('Kyora Chat', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 26)),
                  const SizedBox(height: 6),
                  const Text(
                    'Entra con el mismo correo y contraseña de tu Kyora en la PC.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Palette.dim),
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
                        icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: Palette.dim),
                        onPressed: () => setState(() => _hide = !_hide),
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Text(_error!, key: const Key('login-error'), textAlign: TextAlign.center, style: const TextStyle(color: Palette.warn)),
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
