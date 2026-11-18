import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// El aviso del teléfono cuando llega un mensaje del chat con la app en segundo plano: «Nuevo mensaje de X» y lo que dice. (La voz de
/// KyraAdmin, con la pantalla apagada, lo lee en voz alta.)
abstract class ChatNotifier {
  Future<void> show({required String threadId, required String sender, required String body});
}

/// El real: un canal propio de Android, «Mensajes».
class LocalChatNotifier implements ChatNotifier {
  LocalChatNotifier([FlutterLocalNotificationsPlugin? plugin]) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _ready = false;

  static const _channel = AndroidNotificationDetails(
    'com.kyora.kyora_chat.dm',
    'Mensajes',
    channelDescription: 'Los mensajes nuevos del chat de Kyra',
    importance: Importance.high,
    priority: Priority.high,
    category: AndroidNotificationCategory.message,
  );

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  @override
  Future<void> show({required String threadId, required String sender, required String body}) async {
    final android = _android;
    if (android == null) return;
    if (!_ready) {
      await android.initialize(settings: const AndroidInitializationSettings('@mipmap/ic_launcher'));
      await android.requestNotificationsPermission();
      _ready = true;
    }
    // un aviso por conversación: el nuevo reemplaza al anterior de la misma persona
    await android.show(id: threadId.hashCode & 0x7fffffff, title: sender, body: body, notificationDetails: _channel);
  }
}

/// Para las pruebas: recuerda lo que se avisó.
class FakeChatNotifier implements ChatNotifier {
  final List<(String sender, String body)> shown = [];

  @override
  Future<void> show({required String threadId, required String sender, required String body}) async => shown.add((sender, body));
}
