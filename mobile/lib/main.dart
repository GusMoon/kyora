import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'data/chat_repository.dart';
import 'theme.dart';
import 'ui/chat_page.dart';
import 'ui/login_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!AppConfig.isConfigured) {
    runApp(const _MissingConfigApp());
    return;
  }
  await Supabase.initialize(url: AppConfig.supabaseUrl, publishableKey: AppConfig.supabaseAnonKey);
  runApp(KyoraChatApp(repository: ChatRepository(Supabase.instance.client)));
}

class KyoraChatApp extends StatelessWidget {
  const KyoraChatApp({super.key, required this.repository});

  final ChatRepository repository;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kyora Chat',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: _AuthGate(repository: repository),
    );
  }
}

/// Entra al chat si hay sesión guardada; si no, pide el correo y la contraseña. Al cerrar sesión vuelve al acceso.
class _AuthGate extends StatelessWidget {
  const _AuthGate({required this.repository});

  final ChatRepository repository;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: repository.authChanges,
      builder: (context, _) {
        if (repository.signedIn) {
          return ChatPage(backend: repository, onSignOut: repository.signOut);
        }
        return LoginPage(onSignIn: repository.signIn);
      },
    );
  }
}

/// Se ve solo si la app se compiló sin los datos de Supabase (falta env.json).
class _MissingConfigApp extends StatelessWidget {
  const _MissingConfigApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: buildTheme(),
      home: const Scaffold(
        body: Padding(
          padding: EdgeInsets.all(28),
          child: Center(
            child: Text(
              'Esta app se compiló sin los datos de Supabase.\n\n'
              'Ejecuta scripts\\preparar_movil.bat (crea mobile\\env.json desde supabase\\.env) y vuelve a compilarla.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
