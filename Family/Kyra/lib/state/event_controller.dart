import 'package:uuid/uuid.dart';

import '../models/event.dart';
import 'row_controller.dart';

/// Los eventos del calendario: se guardan en el teléfono y se sincronizan con Supabase (ver [RowController]).
class EventController extends RowController<CalendarEvent> {
  EventController(super.store, super.backend, {super.now, super.retry, String Function()? newId}) : _newId = newId ?? (() => const Uuid().v4());

  final String Function() _newId;

  /// Los eventos sin borrar, por hora de inicio.
  List<CalendarEvent> get items => rows..sort((a, b) => a.startsAt.compareTo(b.startsAt));

  CalendarEvent? byId(String id) => rowById(id);

  /// Un evento nuevo. Un título vacío no crea nada. Sin fin, dura lo que dure su inicio (todo el día o un instante).
  Future<CalendarEvent?> add(String title, DateTime startsAt, {DateTime? endsAt, bool allDay = false, String description = '', String color = '#35d4ff'}) async {
    final clean = title.trim();
    if (clean.isEmpty) return null;
    final t = now();
    final event = CalendarEvent(
      id: _newId(),
      title: clean,
      description: description.trim(),
      startsAt: startsAt.toUtc(),
      endsAt: endsAt?.toUtc(),
      allDay: allDay,
      color: color,
      createdAt: t,
      updatedAt: t,
    );
    await put([event]);
    return event;
  }

  Future<void> update(CalendarEvent event, {String? title, String? description, DateTime? startsAt, Object? endsAt = _unchanged, bool? allDay, String? color}) async {
    final current = byId(event.id) ?? event;
    final clean = title?.trim();
    if (clean != null && clean.isEmpty) return;
    final next = identical(endsAt, _unchanged)
        ? current.copyWith(title: clean, description: description?.trim(), startsAt: startsAt?.toUtc(), allDay: allDay, color: color, updatedAt: stamp(current.updatedAt))
        : current.copyWith(title: clean, description: description?.trim(), startsAt: startsAt?.toUtc(), endsAt: (endsAt as DateTime?)?.toUtc(), allDay: allDay, color: color, updatedAt: stamp(current.updatedAt));
    await put([next]);
  }

  /// Mueve el evento a otro momento sin cambiar lo que dura.
  Future<void> moveTo(CalendarEvent event, DateTime startsAt) async {
    final current = byId(event.id) ?? event;
    final length = current.endsAt?.difference(current.startsAt);
    await update(current, startsAt: startsAt, endsAt: length == null ? null : startsAt.add(length));
  }

  /// Borra el evento (borrado suave: llega también a Supabase y a los demás dispositivos).
  Future<void> delete(CalendarEvent event) async {
    final current = byId(event.id) ?? event;
    await put([current.copyWith(deletedAt: now(), updatedAt: stamp(current.updatedAt))]);
  }
}

const _unchanged = Object();
