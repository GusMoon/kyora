import 'package:flutter/material.dart';

import '../data/chat_backend.dart';
import '../theme.dart';

/// Lo que devuelve la pantalla al cerrarse cuando la cuenta se creó pero Supabase pide confirmar el correo antes de entrar.
const confirmEmailNotice = 'Cuenta creada. Confirma tu correo y luego entra con él.';

/// Lo mínimo que acepta Supabase en este proyecto para una contraseña.
const minPasswordLength = 6;

/// Un requisito de la contraseña y si ya se cumple.
class PasswordRule {
  const PasswordRule(this.id, this.label, this.met);

  final String id;
  final String label;
  final bool met;
}

/// Los requisitos de la contraseña, en el orden en que se enseñan. Se ponen en verde a medida que se cumplen.
List<PasswordRule> passwordRules(String password, String repeat) => [
      PasswordRule('length', 'Al menos $minPasswordLength caracteres', password.length >= minPasswordLength),
      PasswordRule('letter', 'Una letra', RegExp(r'\p{L}', unicode: true).hasMatch(password)),
      PasswordRule('number', 'Un número', RegExp(r'\d').hasMatch(password)),
      PasswordRule('match', 'Las dos contraseñas son iguales', password.isNotEmpty && password == repeat),
    ];

/// El nombre de usuario: de 3 a 24 caracteres (letras, números, espacios, punto, guion o guion bajo). `null` si está bien.
String? usernameProblem(String username) {
  final name = username.trim();
  if (name.length < 3 || name.length > 24) return 'Entre 3 y 24 caracteres.';
  if (!RegExp(r'^[\p{L}\p{N} _.-]+$', unicode: true).hasMatch(name)) return 'Solo letras, números, espacios, punto, guion y guion bajo.';
  return null;
}

/// Vale cualquier correo con forma de correo (nombre@dominio): Gmail, Outlook, Hotmail u otro, también uno inventado.
String? emailProblem(String email) {
  if (!RegExp(r'^[^\s@]+@[^\s@]+$').hasMatch(email.trim())) return 'Escribe un correo con @ (ejemplo: nombre@gmail.com).';
  return null;
}

/// Crea una cuenta de pasante: nombre de usuario, correo y contraseña. Solo se hace la primera vez; después la sesión
/// queda guardada en el teléfono y la app abre sin pedir nada. El botón se activa cuando todo está bien (los requisitos de
/// la contraseña se ven en vivo y se ponen en verde al cumplirse).
class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key, required this.onSignUp});

  /// `true` si la cuenta ya quedó dentro; `false` si falta confirmar el correo.
  final Future<bool> Function(String username, String email, String password) onSignUp;

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _repeat = TextEditingController();
  bool _busy = false;
  bool _hide = true;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _email.dispose();
    _password.dispose();
    _repeat.dispose();
    super.dispose();
  }

  bool get _ready =>
      usernameProblem(_username.text) == null &&
      emailProblem(_email.text) == null &&
      passwordRules(_password.text, _repeat.text).every((rule) => rule.met);

  Future<void> _submit() async {
    if (_busy || !_ready) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final signedIn = await widget.onSignUp(_username.text.trim(), _email.text.trim(), _password.text);
      // Si quedó dentro, la puerta de acceso cambia sola de pantalla: esta se cierra para no quedar encima.
      if (mounted) Navigator.of(context).pop(signedIn ? null : confirmEmailNotice);
    } on ChatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// El aviso en rojo bajo un campo, solo cuando ya escribió algo que no sirve.
  String? _hint(TextEditingController controller, String? Function(String) check) =>
      controller.text.isEmpty ? null : check(controller.text);

  @override
  Widget build(BuildContext context) {
    final rules = passwordRules(_password.text, _repeat.text);
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Crear cuenta', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 26)),
                  const SizedBox(height: 6),
                  Text(
                    'Solo la primera vez. Después la app abre sin pedirte nada.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: context.colors.dim),
                  ),
                  const SizedBox(height: 26),
                  TextField(
                    key: const Key('reg-username'),
                    controller: _username,
                    onChanged: (_) => setState(() {}),
                    autofillHints: const [AutofillHints.newUsername],
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(hintText: 'Nombre de usuario', errorText: _hint(_username, usernameProblem)),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('reg-email'),
                    controller: _email,
                    onChanged: (_) => setState(() {}),
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(hintText: 'Correo (Gmail, Outlook u otro)', errorText: _hint(_email, emailProblem)),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('reg-password'),
                    controller: _password,
                    onChanged: (_) => setState(() {}),
                    obscureText: _hide,
                    autofillHints: const [AutofillHints.newPassword],
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      hintText: 'Contraseña nueva',
                      suffixIcon: IconButton(
                        tooltip: _hide ? 'Mostrar' : 'Ocultar',
                        icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: context.colors.dim),
                        onPressed: () => setState(() => _hide = !_hide),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('reg-repeat'),
                    controller: _repeat,
                    onChanged: (_) => setState(() {}),
                    obscureText: _hide,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
                    decoration: const InputDecoration(hintText: 'Repite la contraseña'),
                  ),
                  const SizedBox(height: 14),
                  for (final rule in rules) _RuleRow(rule: rule),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Text(_error!, key: const Key('reg-error'), textAlign: TextAlign.center, style: TextStyle(color: context.colors.warn)),
                  ],
                  const SizedBox(height: 22),
                  FilledButton(
                    key: const Key('reg-button'),
                    onPressed: _busy || !_ready ? null : _submit,
                    child: _busy
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4))
                        : const Text('Crear cuenta'),
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

/// Una línea de la lista de requisitos: gris con un círculo vacío, y verde con una palomita cuando se cumple.
class _RuleRow extends StatelessWidget {
  const _RuleRow({required this.rule});

  final PasswordRule rule;

  @override
  Widget build(BuildContext context) {
    final color = rule.met ? context.colors.ok : context.colors.dim;
    return Padding(
      key: Key('rule-${rule.id}'),
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(rule.met ? Icons.check_circle : Icons.radio_button_unchecked, key: Key('rule-${rule.id}-${rule.met ? 'ok' : 'todo'}'), size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(rule.label, style: TextStyle(color: color, fontSize: 14))),
        ],
      ),
    );
  }
}
