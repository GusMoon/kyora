import 'dart:async';

import 'package:flutter/material.dart';

import '../models/task.dart';
import '../state/task_controller.dart';
import '../theme.dart';
import '../util/task_format.dart';

/// Una tarea: nombre, descripción, estado, entrega, tiempo esperado, subtareas y etiquetas. Los cambios se guardan solos (al cambiar
/// el estado, la entrega o las etiquetas, al terminar de escribir y al salir).
class TaskDetailPage extends StatefulWidget {
  const TaskDetailPage({super.key, required this.controller, required this.taskId});

  final TaskController controller;
  final String taskId;

  @override
  State<TaskDetailPage> createState() => _TaskDetailPageState();
}

class _TaskDetailPageState extends State<TaskDetailPage> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _expected;
  final _sub = TextEditingController();
  String? _expectedError;
  bool _closing = false;

  TaskController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    final task = _c.byId(widget.taskId);
    _name = TextEditingController(text: task?.name ?? '');
    _description = TextEditingController(text: task?.description ?? '');
    _expected = TextEditingController(text: minutesLabel(task?.expectedMin));
  }

  @override
  void dispose() {
    _closing = true; // al salir se guarda lo escrito, pero ya no se pinta nada
    unawaited(_save());
    _name.dispose();
    _description.dispose();
    _expected.dispose();
    _sub.dispose();
    super.dispose();
  }

  /// Guarda lo escrito (si cambió algo). El tiempo esperado que no se entiende no se guarda.
  Future<void> _save() async {
    final task = _c.byId(widget.taskId);
    if (task == null) return;
    int? minutes = task.expectedMin;
    try {
      minutes = parseMinutes(_expected.text);
      if (mounted && !_closing) setState(() => _expectedError = null);
    } on FormatException catch (e) {
      if (mounted && !_closing) setState(() => _expectedError = e.message);
    }
    await _c.update(task, name: _name.text, description: _description.text, expectedMin: minutes);
  }

  Future<void> _pickDue(TaskItem task) async {
    final now = DateTime.now();
    final current = task.due?.toLocal();
    final day = await showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 10),
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: current == null ? const TimeOfDay(hour: 18, minute: 0) : TimeOfDay.fromDateTime(current),
    );
    if (time == null) return;
    await _c.update(task, due: DateTime(day.year, day.month, day.day, time.hour, time.minute).toUtc());
  }

  Future<String?> _ask(String title, String hint) => showDialog<String>(
        context: context,
        builder: (context) {
          final field = TextEditingController();
          return AlertDialog(
            title: Text(title),
            content: TextField(
              key: const Key('ask-field'),
              controller: field,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(hintText: hint),
              onSubmitted: (v) => Navigator.of(context).pop(v),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
              FilledButton(key: const Key('ask-ok'), style: FilledButton.styleFrom(minimumSize: const Size(0, 40)), onPressed: () => Navigator.of(context).pop(field.text), child: const Text('Aceptar')),
            ],
          );
        },
      );

  Future<bool> _confirm(String title, String body) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
            FilledButton(key: const Key('confirm-ok'), style: FilledButton.styleFrom(minimumSize: const Size(0, 40)), onPressed: () => Navigator.of(context).pop(true), child: const Text('Borrar')),
          ],
        ),
      ) ==
      true;

  Future<void> _delete(TaskItem task) async {
    final subs = _c.subtasksOf(task.id).length;
    final ok = await _confirm('¿Borrar la tarea?', subs > 0 ? '«${task.name}» y sus $subs subtareas se borrarán también en tus otros dispositivos.' : '«${task.name}» se borrará también en tus otros dispositivos.');
    if (!ok || !mounted) return;
    await _c.delete(task);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _addSub(TaskItem task) async {
    final text = _sub.text;
    if (text.trim().isEmpty) return;
    _sub.clear();
    await _c.add(text, parentId: task.id);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) {
        final task = _c.byId(widget.taskId);
        if (task == null) {
          // la borraron (aquí o desde otro dispositivo)
          return Scaffold(appBar: AppBar(), body: Center(child: Text('Esta tarea ya no existe.', style: TextStyle(color: context.colors.dim))));
        }
        final c = context.colors;
        final now = DateTime.now();
        final subs = _c.subtasksOf(task.id);
        final tagsOn = {for (final t in _c.tagsOf(task.id)) t.id};
        return Scaffold(
          appBar: AppBar(
            title: Text(task.isSub ? 'Subtarea' : 'Tarea', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
            actions: [IconButton(key: const Key('task-delete'), tooltip: 'Borrar', icon: const Icon(Icons.delete_outline), onPressed: () => _delete(task))],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            children: [
              TextField(
                key: const Key('task-name'),
                controller: _name,
                textCapitalization: TextCapitalization.sentences,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                decoration: const InputDecoration(hintText: 'Nombre'),
                onEditingComplete: () {
                  FocusScope.of(context).unfocus();
                  unawaited(_save());
                },
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (final s in TaskStatus.values)
                    ChoiceChip(
                      key: Key('status-${s.wire}'),
                      label: Text(s.label),
                      selected: task.status == s,
                      onSelected: (_) => unawaited(_c.setStatus(task, s)),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              ListTile(
                key: const Key('task-due'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_outlined),
                title: Text(task.due == null ? 'Sin fecha de entrega' : dueLabel(task.due!, now)),
                subtitle: Text('Entrega', style: TextStyle(color: c.dim)),
                trailing: task.due == null ? null : IconButton(key: const Key('task-due-clear'), tooltip: 'Quitar la fecha', icon: const Icon(Icons.close), onPressed: () => _c.update(task, due: null)),
                onTap: () => _pickDue(task),
              ),
              TextField(
                key: const Key('task-expected'),
                controller: _expected,
                keyboardType: TextInputType.text,
                decoration: InputDecoration(
                  labelText: 'Tiempo esperado',
                  hintText: 'Por ejemplo 90, 1:30 o 1 h 30 min',
                  errorText: _expectedError,
                  prefixIcon: const Icon(Icons.timer_outlined),
                ),
                onEditingComplete: () {
                  FocusScope.of(context).unfocus();
                  unawaited(_save());
                },
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('task-description'),
                controller: _description,
                minLines: 3,
                maxLines: 8,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(hintText: 'Descripción'),
                onTapOutside: (_) => unawaited(_save()),
              ),
              if (!task.isSub) ...[
                const SizedBox(height: 20),
                Text('Subtareas', style: TextStyle(color: c.accent, fontSize: 14, fontWeight: FontWeight.w700)),
                for (final s in subs)
                  Row(
                    key: Key('sub-${s.id}'),
                    children: [
                      IconButton(
                        key: Key('sub-check-${s.id}'),
                        icon: Icon(s.isDone ? Icons.check_circle : Icons.radio_button_unchecked, color: s.isDone ? c.accent : c.dim),
                        onPressed: () => unawaited(_c.toggleDone(s)),
                      ),
                      Expanded(
                        child: Text(s.name, style: TextStyle(color: s.isDone ? c.dim : c.ink, decoration: s.isDone ? TextDecoration.lineThrough : null)),
                      ),
                      IconButton(key: Key('sub-delete-${s.id}'), tooltip: 'Borrar', icon: Icon(Icons.close, color: c.dim), onPressed: () => unawaited(_c.delete(s))),
                    ],
                  ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('subtask-input'),
                        controller: _sub,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(hintText: 'Nueva subtarea'),
                        onSubmitted: (_) => _addSub(task),
                      ),
                    ),
                    IconButton(key: const Key('subtask-add'), tooltip: 'Añadir subtarea', icon: const Icon(Icons.add_rounded), onPressed: () => _addSub(task)),
                  ],
                ),
              ],
              const SizedBox(height: 20),
              Text('Etiquetas', style: TextStyle(color: c.accent, fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final t in _c.tags)
                    GestureDetector(
                      onLongPress: () async {
                        if (await _confirm('¿Borrar la etiqueta «${t.name}»?', 'Se quita de todas las tareas.') && mounted) await _c.deleteTag(t);
                      },
                      child: FilterChip(
                        key: Key('tag-${t.id}'),
                        avatar: CircleAvatar(backgroundColor: colorFromHex(t.color), radius: 5),
                        label: Text(t.name),
                        selected: tagsOn.contains(t.id),
                        onSelected: (_) => unawaited(_c.toggleTag(task.id, t)),
                      ),
                    ),
                  ActionChip(
                    key: const Key('tag-new'),
                    avatar: const Icon(Icons.add, size: 16),
                    label: const Text('Etiqueta'),
                    onPressed: () async {
                      final name = await _ask('Nueva etiqueta', 'Nombre');
                      if (name == null || !mounted) return;
                      final tag = await _c.createTag(name);
                      if (tag != null && !tagsOn.contains(tag.id)) await _c.toggleTag(task.id, tag);
                    },
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
