import 'package:flutter/material.dart';

import '../models/reminder.dart';
import '../state/reminder_controller.dart';
import '../theme.dart';
import '../util/task_format.dart';
import 'widgets/pixel_glyph.dart';
import 'widgets/focus_space.dart';

/// Crea un recordatorio, o edita `existing`: título, día, hora y notas. Uno nuevo empieza en `day` (sin él, hoy).
Future<void> showReminderEditor(BuildContext context, ReminderController controller, {Reminder? existing, DateTime? day}) {
  return showFocusPanel<void>(context, builder: (_) => _Editor(controller: controller, existing: existing, day: day),
  );
}

class _Editor extends StatefulWidget {
  const _Editor({required this.controller, this.existing, this.day});

  final ReminderController controller;
  final Reminder? existing;

  /// El día en que empieza uno nuevo.
  final DateTime? day;

  @override
  State<_Editor> createState() => _EditorState();
}

class _EditorState extends State<_Editor> {
  late final TextEditingController _title = TextEditingController(text: widget.existing?.title ?? '');
  late final TextEditingController _notes = TextEditingController(text: widget.existing?.notes ?? '');
  late DateTime _at = widget.existing?.at.toLocal() ?? _start(widget.day);
  String? _error;

  /// Un día que no es hoy empieza a las 9:00; hoy, a la próxima hora en punto.
  static DateTime _start(DateTime? day) {
    final now = DateTime.now();
    if (day != null && !(day.year == now.year && day.month == now.month && day.day == now.day)) return DateTime(day.year, day.month, day.day, 9);
    return _soon();
  }

  static DateTime _soon() {
    final t = DateTime.now().add(const Duration(hours: 1));
    return DateTime(t.year, t.month, t.day, t.hour, 0);
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDay() async {
    final now = DateTime.now();
    final day = await showDatePicker(context: context, initialDate: _at, firstDate: DateTime(now.year, now.month, now.day), lastDate: DateTime(now.year + 5));
    if (day != null) setState(() => _at = DateTime(day.year, day.month, day.day, _at.hour, _at.minute));
  }

  Future<void> _pickTime() async {
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_at));
    if (time != null) setState(() => _at = DateTime(_at.year, _at.month, _at.day, time.hour, time.minute));
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      setState(() => _error = 'Escribe qué quieres recordar.');
      return;
    }
    final existing = widget.existing;
    if (existing == null) {
      await widget.controller.add(_title.text, _at, notes: _notes.text);
    } else {
      await widget.controller.update(existing, title: _title.text, notes: _notes.text, at: _at);
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
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.existing == null ? 'Nuevo recordatorio' : 'Editar recordatorio', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            TextField(
              key: const Key('reminder-title'),
              controller: _title,
              autofocus: widget.existing == null,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(hintText: '¿Qué quieres recordar?', errorText: _error),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('reminder-day'),
                    onPressed: _pickDay,
                    icon: const LcdIcon(Icons.event_outlined),
                    label: Text(dueLabel(_at, DateTime.now()).replaceAll(RegExp(r'\s\d{2}:\d{2}$'), '')),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('reminder-time'),
                    onPressed: _pickTime,
                    icon: const LcdIcon(Icons.schedule),
                    label: Text('${_at.hour.toString().padLeft(2, '0')}:${_at.minute.toString().padLeft(2, '0')}'),
                  ),
                ),
              ],
            ),
            if (!_at.isAfter(DateTime.now()))
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Esa hora ya pasó: no habrá aviso.', style: TextStyle(color: c.warn, fontSize: 15)),
              ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('reminder-notes'),
              controller: _notes,
              minLines: 2,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'Notas (opcional)'),
            ),
            const SizedBox(height: 14),
            FilledButton(key: const Key('reminder-save'), onPressed: _save, child: const Text('Guardar')),
            if (widget.existing != null) ...[
              const SizedBox(height: 6),
              TextButton(
                key: const Key('reminder-delete'),
                onPressed: _delete,
                child: Text('Borrar el recordatorio', style: TextStyle(color: c.warn)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
