import 'package:flutter/material.dart';

import '../models/event.dart';
import '../state/event_controller.dart';
import '../theme.dart';
import '../util/agenda.dart';
import 'widgets/cut_border.dart';
import 'widgets/focus_space.dart';
import 'widgets/pixel_glyph.dart';

/// Crea un evento, o edita `existing`: título, día, hora de inicio y fin (o todo el día), color y notas. Uno nuevo empieza en `day` (sin él, hoy)
/// y, si se da, a `minutes` desde medianoche.
Future<void> showEventEditor(BuildContext context, EventController controller, {CalendarEvent? existing, DateTime? day, int? minutes}) {
  return showFocusPanel<void>(context, builder: (_) => _EventEditor(controller: controller, existing: existing, day: day, minutes: minutes));
}

class _EventEditor extends StatefulWidget {
  const _EventEditor({required this.controller, this.existing, this.day, this.minutes});

  final EventController controller;
  final CalendarEvent? existing;
  final DateTime? day;
  final int? minutes;

  @override
  State<_EventEditor> createState() => _EventEditorState();
}

class _EventEditorState extends State<_EventEditor> {
  late final TextEditingController _title = TextEditingController(text: widget.existing?.title ?? '');
  late final TextEditingController _notes = TextEditingController(text: widget.existing?.description ?? '');
  late DateTime _start = widget.existing?.startsAt.toLocal() ?? _initial();
  late DateTime? _end = widget.existing?.endsAt?.toLocal();
  late bool _allDay = widget.existing?.allDay ?? false;
  late String _color = widget.existing?.color ?? eventColors.first;
  String? _error;

  DateTime _initial() {
    final day = dateOnly(widget.day ?? DateTime.now());
    final m = widget.minutes ?? 9 * 60;
    return DateTime(day.year, day.month, day.day, m ~/ 60, m % 60);
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDay() async {
    final day = await showDatePicker(context: context, initialDate: _start, firstDate: DateTime(2000), lastDate: DateTime(2100));
    if (day == null) return;
    setState(() {
      final length = _end?.difference(_start);
      _start = DateTime(day.year, day.month, day.day, _start.hour, _start.minute);
      if (length != null) _end = _start.add(length);
    });
  }

  Future<void> _pickStart() async {
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_start));
    if (time == null) return;
    setState(() {
      final length = _end?.difference(_start);
      _start = DateTime(_start.year, _start.month, _start.day, time.hour, time.minute);
      if (length != null) _end = _start.add(length);
    });
  }

  Future<void> _pickEnd() async {
    final time = await showTimePicker(context: context, initialTime: _end == null ? TimeOfDay.fromDateTime(_start.add(const Duration(hours: 1))) : TimeOfDay.fromDateTime(_end!));
    if (time == null) return;
    setState(() => _end = DateTime(_start.year, _start.month, _start.day, time.hour, time.minute));
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      setState(() => _error = 'Escribe el título del evento.');
      return;
    }
    final start = _allDay ? DateTime(_start.year, _start.month, _start.day) : _start;
    final end = _allDay ? null : _end;
    if (end != null && end.isBefore(start)) {
      setState(() => _error = 'El fin no puede ser antes del inicio.');
      return;
    }
    final existing = widget.existing;
    if (existing == null) {
      await widget.controller.add(_title.text, start, endsAt: end, allDay: _allDay, description: _notes.text, color: _color);
    } else {
      await widget.controller.update(existing, title: _title.text, description: _notes.text, startsAt: start, endsAt: end, allDay: _allDay, color: _color);
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    await widget.controller.delete(widget.existing!);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    String hhmm(DateTime t) => minutesLabel(t.hour * 60 + t.minute);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.existing == null ? 'Nuevo evento' : 'Editar evento', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            TextField(
              key: const Key('event-title'),
              controller: _title,
              autofocus: widget.existing == null,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(hintText: '¿Qué pasa?', errorText: _error),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('event-day'),
              onPressed: _pickDay,
              icon: const LcdIcon(Icons.event_outlined),
              label: Text('${weekdayNames[_start.weekday - 1]} ${_start.day} ${monthNames[_start.month - 1].toLowerCase()} ${_start.year}'),
            ),
            SwitchListTile(
              key: const Key('event-allday'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Todo el día'),
              value: _allDay,
              onChanged: (v) => setState(() => _allDay = v),
            ),
            if (!_allDay)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(key: const Key('event-start'), onPressed: _pickStart, icon: const LcdIcon(Icons.schedule), label: Text(hhmm(_start))),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const Key('event-end'),
                      onPressed: _pickEnd,
                      icon: const LcdIcon(Icons.schedule_outlined),
                      label: Text(_end == null ? 'Sin fin' : hhmm(_end!)),
                    ),
                  ),
                  if (_end != null)
                    IconButton(key: const Key('event-end-clear'), tooltip: 'Quitar la hora de fin', onPressed: () => setState(() => _end = null), icon: const Icon(Icons.close_rounded)),
                ],
              ),
            const SizedBox(height: 10),
            Row(
              children: [
                for (final hex in eventColors)
                  Expanded(
                    child: Semantics(
                      button: true,
                      selected: hex == _color,
                      label: 'Color $hex',
                      child: GestureDetector(
                        key: Key('event-color-$hex'),
                        behavior: HitTestBehavior.opaque,
                        onTap: () => setState(() => _color = hex),
                        child: Container(
                          height: 40,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: ShapeDecoration(
                            color: Color(colorValue(hex)),
                            shape: CutBorder(side: BorderSide(color: hex == _color ? c.ink : Colors.transparent, width: 2)),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('event-notes'),
              controller: _notes,
              minLines: 2,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'Notas (opcional)'),
            ),
            const SizedBox(height: 14),
            FilledButton(key: const Key('event-save'), onPressed: _save, child: const Text('Guardar')),
            if (widget.existing != null) ...[
              const SizedBox(height: 6),
              TextButton(key: const Key('event-delete'), onPressed: _delete, child: Text('Borrar el evento', style: TextStyle(color: c.warn))),
            ],
          ],
        ),
      ),
    );
  }
}
