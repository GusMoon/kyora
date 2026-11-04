import 'dart:async';

import 'package:flutter/material.dart';

import '../models/reminder.dart';
import '../state/reminder_controller.dart';
import '../theme.dart';
import '../util/task_format.dart';

/// Los recordatorios: una lista por hora, con la casilla para marcarlos como hechos. Cada uno avisa con una notificación a su hora,
/// aunque la app esté cerrada. Por ahora solo viven en este teléfono.
class RemindersPage extends StatelessWidget {
  const RemindersPage({super.key, required this.controller});

  final ReminderController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = context.colors;
        final items = controller.items;
        return Scaffold(
          appBar: AppBar(title: const Text('Recordatorios', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700))),
          floatingActionButton: FloatingActionButton.extended(
            key: const Key('reminder-new'),
            backgroundColor: c.accent,
            foregroundColor: c.onAccent,
            onPressed: () => unawaited(showReminderEditor(context, controller)),
            icon: const Icon(Icons.add_alert_outlined),
            label: const Text('Nuevo'),
          ),
          body: Column(
            children: [
              if (controller.notificationsBlocked)
                Container(
                  key: const Key('reminders-blocked'),
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: c.plate, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.warn.withValues(alpha: 0.6))),
                  child: Text(
                    'Las notificaciones están desactivadas: los recordatorios se guardan pero no sonarán. Actívalas para esta app en los ajustes del teléfono.',
                    style: TextStyle(color: c.warn, fontSize: 13.5),
                  ),
                ),
              Expanded(
                child: items.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                            controller.loaded ? 'No tienes recordatorios.\nCrea uno con «Nuevo».' : 'Cargando…',
                            key: const Key('reminders-empty'),
                            textAlign: TextAlign.center,
                            style: TextStyle(color: c.dim),
                          ),
                        ),
                      )
                    : ListView.builder(
                        key: const Key('reminder-list'),
                        padding: const EdgeInsets.only(bottom: 88),
                        itemCount: items.length,
                        itemBuilder: (context, i) => _ReminderTile(reminder: items[i], controller: controller),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ReminderTile extends StatelessWidget {
  const _ReminderTile({required this.reminder, required this.controller});

  final Reminder reminder;
  final ReminderController controller;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final overdue = controller.isOverdue(reminder);
    return InkWell(
      key: Key('reminder-${reminder.id}'),
      onTap: () => unawaited(showReminderEditor(context, controller, existing: reminder)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 2, 4, 2),
        child: Row(
          children: [
            IconButton(
              key: Key('reminder-check-${reminder.id}'),
              tooltip: reminder.done ? 'Volver a pendiente' : 'Marcar como hecho',
              icon: Icon(reminder.done ? Icons.check_circle : Icons.radio_button_unchecked, color: reminder.done ? c.accent : c.dim),
              onPressed: () => unawaited(controller.toggleDone(reminder)),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    reminder.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: reminder.done ? c.dim : c.ink, decoration: reminder.done ? TextDecoration.lineThrough : null),
                  ),
                  Text(dueLabel(reminder.at, DateTime.now()), style: TextStyle(fontSize: 13, color: overdue ? c.warn : c.dim)),
                  if (reminder.notes.isNotEmpty) Text(reminder.notes, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: c.dim)),
                ],
              ),
            ),
            IconButton(key: Key('reminder-delete-${reminder.id}'), tooltip: 'Borrar', icon: Icon(Icons.delete_outline, color: c.dim), onPressed: () => unawaited(controller.delete(reminder))),
          ],
        ),
      ),
    );
  }
}

/// Crea un recordatorio, o edita `existing`: título, día, hora y notas.
Future<void> showReminderEditor(BuildContext context, ReminderController controller, {Reminder? existing}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _Editor(controller: controller, existing: existing),
  );
}

class _Editor extends StatefulWidget {
  const _Editor({required this.controller, this.existing});

  final ReminderController controller;
  final Reminder? existing;

  @override
  State<_Editor> createState() => _EditorState();
}

class _EditorState extends State<_Editor> {
  late final TextEditingController _title = TextEditingController(text: widget.existing?.title ?? '');
  late final TextEditingController _notes = TextEditingController(text: widget.existing?.notes ?? '');
  late DateTime _at = widget.existing?.at.toLocal() ?? _soon();
  String? _error;

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
                Expanded(child: OutlinedButton.icon(key: const Key('reminder-day'), onPressed: _pickDay, icon: const Icon(Icons.event_outlined), label: Text(dueLabel(_at, DateTime.now()).replaceAll(RegExp(r'\s\d{2}:\d{2}$'), '')))),
                const SizedBox(width: 8),
                Expanded(child: OutlinedButton.icon(key: const Key('reminder-time'), onPressed: _pickTime, icon: const Icon(Icons.schedule), label: Text('${_at.hour.toString().padLeft(2, '0')}:${_at.minute.toString().padLeft(2, '0')}'))),
              ],
            ),
            if (!_at.isAfter(DateTime.now())) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Esa hora ya pasó: no habrá aviso.', style: TextStyle(color: c.warn, fontSize: 13))),
            const SizedBox(height: 8),
            TextField(key: const Key('reminder-notes'), controller: _notes, minLines: 2, maxLines: 4, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(hintText: 'Notas (opcional)')),
            const SizedBox(height: 14),
            FilledButton(key: const Key('reminder-save'), onPressed: _save, child: const Text('Guardar')),
          ],
        ),
      ),
    );
  }
}
