import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'data/chat_repository.dart';
import 'data/music_store.dart';
import 'state/music_controller.dart';
import 'theme.dart';
import 'ui/chat_page.dart';
import 'ui/login_page.dart';
import 'ui/music_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!AppConfig.isConfigured) {
    runApp(const _MissingConfigApp());
    return;
  }
  await Supabase.initialize(url: AppConfig.supabaseUrl, publishableKey: AppConfig.supabaseAnonKey);
  final store = await PrefsMusicStore.open();
  runApp(KyoraChatApp(repository: ChatRepository(Supabase.instance.client), musicStore: store, saver: AndroidTrackSaver()));
}

class KyoraChatApp extends StatelessWidget {
  const KyoraChatApp({super.key, required this.repository, required this.musicStore, required this.saver});

  final ChatRepository repository;
  final MusicStore musicStore;
  final TrackSaver saver;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kyora Chat',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: _AuthGate(repository: repository, musicStore: musicStore, saver: saver),
    );
  }
}

/// Entra al chat si hay sesión guardada; si no, pide el correo y la contraseña. Al cerrar sesión vuelve al acceso.
/// Con sesión también arranca la música: así las canciones que baje la PC se guardan solas aunque estés en el chat.
class _AuthGate extends StatefulWidget {
  const _AuthGate({required this.repository, required this.musicStore, required this.saver});

  final ChatRepository repository;
  final MusicStore musicStore;
  final TrackSaver saver;

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  MusicController? _music;

  MusicController _musicController() {
    final existing = _music;
    if (existing != null) return existing;
    final created = MusicController(widget.repository, widget.musicStore, widget.saver);
    _music = created;
    created.start();
    return created;
  }

  void _stopMusic() {
    _music?.dispose();
    _music = null;
  }

  @override
  void dispose() {
    _stopMusic();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: widget.repository.authChanges,
      builder: (context, _) {
        if (widget.repository.signedIn) {
          final music = _musicController();
          return ChatPage(
            backend: widget.repository,
            onSignOut: widget.repository.signOut,
            onOpenMusic: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => MusicPage(controller: music))),
          );
        }
        _stopMusic();
        return LoginPage(onSignIn: widget.repository.signIn);
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
