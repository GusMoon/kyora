import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/reminder.dart';

/// Lo que los recordatorios necesitan del teléfono: programar y cancelar el aviso. Lo real usa las notificaciones de Android
/// (suenan con la app cerrada); las pruebas usan uno falso.
abstract class ReminderScheduler {
  /// Prepara las notificaciones. Se llama una vez al empezar.
  Future<void> init();

  /// Pide los permisos (notificaciones y alarmas exactas si hacen falta). `true` si los avisos van a poder salir.
  Future<bool> ensurePermissions();

  /// Programa el aviso del recordatorio a su hora (si ya tenía uno, lo reemplaza).
  Future<void> schedule(Reminder reminder);

  /// Programa un aviso que se repite cada semana ese día (`DateTime.weekday`, 1 = lunes) a esa hora local (si ya había uno con ese número,
  /// lo reemplaza). Es el de los hábitos.
  Future<void> scheduleWeekly({required int id, required String title, required int weekday, required int hour, required int minute});

  Future<void> cancel(int notifId);
}

class LocalNotificationScheduler implements ReminderScheduler {
  LocalNotificationScheduler([FlutterLocalNotificationsPlugin? plugin]) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  static const _channel = AndroidNotificationDetails(
    'com.kyora.kyora_chat.reminders',
    'Recordatorios',
    channelDescription: 'Avisos de tus recordatorios',
    importance: Importance.high,
    priority: Priority.high,
  );

  static const _habitChannel = AndroidNotificationDetails(
    'com.kyora.kyora_chat.habits',
    'Hábitos',
    channelDescription: 'El aviso de tus hábitos, los días que tocan',
    importance: Importance.high,
    priority: Priority.high,
  );

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  @override
  Future<void> init() async {
    tzdata.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation((await FlutterTimezone.getLocalTimezone()).identifier));
    } catch (_) {
      tz.setLocalLocation(tz.UTC); // sin saber la zona, los avisos saldrían a la hora UTC: mejor que no programar nada
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

  @override
  Future<void> schedule(Reminder reminder) async {
    final android = _android;
    if (android == null) return;
    final exact = await android.canScheduleExactNotifications() == true;
    await android.zonedSchedule(
      id: reminder.notifId,
      title: reminder.title,
      body: reminder.notes.isEmpty ? null : reminder.notes,
      scheduledDate: tz.TZDateTime.from(reminder.at, tz.local),
      notificationDetails: _channel,
      scheduleMode: exact ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  @override
  Future<void> scheduleWeekly({required int id, required String title, required int weekday, required int hour, required int minute}) async {
    final android = _android;
    if (android == null) return;
    final now = tz.TZDateTime.now(tz.local);
    var next = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    // el próximo de ese día de la semana (con el constructor y no sumando horas: así un cambio de horario no lo mueve)
    while (next.weekday != weekday || !next.isAfter(now)) {
      next = tz.TZDateTime(tz.local, next.year, next.month, next.day + 1, hour, minute);
    }
    final exact = await android.canScheduleExactNotifications() == true;
    await android.zonedSchedule(
      id: id,
      title: title,
      body: 'Hoy toca',
      scheduledDate: next,
      notificationDetails: _habitChannel,
      scheduleMode: exact ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
    );
  }

  @override
  Future<void> cancel(int notifId) async {
    await _android?.cancel(id: notifId);
  }
}
