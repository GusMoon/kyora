import 'dart:typed_data';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Lo que las alarmas necesitan del teléfono: que suene un aviso a una hora, una vez o cada semana. Lo real usa las notificaciones de Android
/// con categoría de alarma (suenan con la app cerrada); las pruebas usan uno falso. **Todo es local**: no hay servidor.
abstract class AlarmScheduler {
  /// Prepara las notificaciones y la zona horaria. Se llama una vez al empezar.
  Future<void> init();

  /// Pide los permisos (notificaciones y alarmas exactas). `true` si las alarmas van a poder sonar.
  Future<bool> ensurePermissions();

  /// Programa un aviso que suena una vez a esa hora (si ya había uno con ese número, lo reemplaza).
  Future<void> scheduleOnce({required int id, required String title, required String body, required DateTime at});

  /// Programa un aviso que suena cada semana ese día (`DateTime.weekday`, 1 = lunes) a esa hora local.
  Future<void> scheduleWeekly({required int id, required String title, required String body, required int weekday, required int hour, required int minute});

  Future<void> cancel(int id);
}

class LocalAlarmScheduler implements AlarmScheduler {
  LocalAlarmScheduler([FlutterLocalNotificationsPlugin? plugin]) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  /// Insistente (el sonido se repite hasta que se cierra el aviso), con el volumen y el sonido de las alarmas del teléfono y encima de la
  /// pantalla de bloqueo.
  static final _details = AndroidNotificationDetails(
    'com.kyora.kyora_chat.alarms',
    'Alarmas',
    channelDescription: 'Las alarmas del reloj',
    importance: Importance.max,
    priority: Priority.max,
    category: AndroidNotificationCategory.alarm,
    fullScreenIntent: true,
    audioAttributesUsage: AudioAttributesUsage.alarm,
    sound: const UriAndroidNotificationSound('content://settings/system/alarm_alert'),
    playSound: true,
    enableVibration: true,
    vibrationPattern: Int64List.fromList([0, 600, 400, 600, 400, 600]),
    additionalFlags: Int32List.fromList([4]), // FLAG_INSISTENT
    autoCancel: true,
  );

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  @override
  Future<void> init() async {
    tzdata.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation((await FlutterTimezone.getLocalTimezone()).identifier));
    } catch (_) {
      tz.setLocalLocation(tz.UTC);
    }
    await _android?.initialize(settings: const AndroidInitializationSettings('@mipmap/ic_launcher'));
  }

  @override
  Future<bool> ensurePermissions() async {
    final android = _android;
    if (android == null) return false;
    final notifications = await android.requestNotificationsPermission() ?? true;
    if (await android.canScheduleExactNotifications() != true) await android.requestExactAlarmsPermission();
    return notifications;
  }

  Future<AndroidScheduleMode> _mode(AndroidFlutterLocalNotificationsPlugin android) async =>
      await android.canScheduleExactNotifications() == true ? AndroidScheduleMode.alarmClock : AndroidScheduleMode.inexactAllowWhileIdle;

  @override
  Future<void> scheduleOnce({required int id, required String title, required String body, required DateTime at}) async {
    final android = _android;
    if (android == null) return;
    await android.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: tz.TZDateTime.from(at, tz.local),
      notificationDetails: _details,
      scheduleMode: await _mode(android),
    );
  }

  @override
  Future<void> scheduleWeekly({required int id, required String title, required String body, required int weekday, required int hour, required int minute}) async {
    final android = _android;
    if (android == null) return;
    final now = tz.TZDateTime.now(tz.local);
    var next = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    // el próximo de ese día de la semana (con el constructor y no sumando horas: así un cambio de horario no lo mueve)
    while (next.weekday != weekday || !next.isAfter(now)) {
      next = tz.TZDateTime(tz.local, next.year, next.month, next.day + 1, hour, minute);
    }
    await android.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: next,
      notificationDetails: _details,
      scheduleMode: await _mode(android),
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
    );
  }

  @override
  Future<void> cancel(int id) async => _android?.cancel(id: id);
}
