import 'dart:async';

import 'package:flutter/material.dart';

import '../models/task.dart';
import '../state/task_controller.dart';
import '../theme.dart';
import '../util/task_format.dart';
import 'widgets/flat_form.dart';
import 'widgets/focus_space.dart';
import 'widgets/pixel_glyph.dart';

/// Una tarea: nombre, estado, entrega y tiempo esperado, descripción, subtareas y etiquetas, planos como el detalle del clima: un rótulo
/// apagado (ENTREGA) y debajo el dato, sin paneles ni campos con caja. Los cambios se guardan solos (al cambiar el estado, la entrega o las
/// etiquetas, al terminar de escribir y al salir).
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

  Future<String?> _ask(String title, String hint) => showFocusPanel<String>(
        context,
        title: title,
        builder: (context) {
          final field = TextEditingController();
          return FocusDialog(
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
      await showFocusPanel<bool>(
        context,
        title: title,
        builder: (context) => FocusDialog(
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
        final doneSubs = subs.where((s) => s.isDone).length;
        return FlatBackdrop(child: Scaffold(
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            titleSpacing: 0,
            title: Row(
              children: [
                Text('> ', style: TextStyle(fontFamily: monoFont, fontSize: 15, color: c.accent)),
                Text(task.isSub ? 'SUBTAREA' : 'TAREA', style: TextStyle(fontFamily: monoFont, fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: 1.2, color: c.ink)),
              ],
            ),
            actions: [IconButton(key: const Key('task-delete'), tooltip: 'Borrar', icon: LcdIcon(Icons.delete_outline, color: c.warn), onPressed: () => _delete(task))],
          ),
          // como el detalle del clima: sin paneles ni campos con caja; un rótulo apagado encima de cada dato y el dato debajo, tal cual
          body: ListView(
            padding: EdgeInsets.fromLTRB(20, 4, 20, 32 + MediaQuery.paddingOf(context).bottom),
            children: [
              TextField(
                key: const Key('task-name'),
                controller: _name,
                textCapitalization: TextCapitalization.sentences,
                style: display(size: 28, color: c.ink, weight: FontWeight.w600).copyWith(height: 1.1),
                decoration: flatInput(context, hint: 'Nombre'),
                maxLines: null,
                onEditingComplete: () {
                  FocusScope.of(context).unfocus();
                  unawaited(_save());
                },
              ),
              const SizedBox(height: 18),
              FlatStat(
                label: 'Estado',
                child: Wrap(
                  spacing: 18,
                  runSpacing: 6,
                  children: [
                    for (final s in TaskStatus.values) FlatChoice(key: Key('status-${s.wire}'), label: s.label, selected: task.status == s, onTap: () => unawaited(_c.setStatus(task, s))),
                  ],
                ),
              ),
              FlatStat(
                label: 'Entrega',
                child: InkWell(
                  key: const Key('task-due'),
                  onTap: () => _pickDue(task),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(child: Text(task.due == null ? 'Sin fecha' : dueLabel(task.due!, now), style: TextStyle(fontFamily: monoFont, fontSize: 15, color: task.due == null ? c.dim : c.ink))),
                        if (task.due != null) GestureDetector(key: const Key('task-due-clear'), behavior: HitTestBehavior.opaque, onTap: () => _c.update(task, due: null), child: Padding(padding: const EdgeInsets.all(8), child: LcdIcon(Icons.close, size: 18, color: c.dim))),
                      ],
                    ),
                  ),
                ),
              ),
              FlatStat(
                label: 'Tiempo esperado',
                child: TextField(
                  key: const Key('task-expected'),
                  controller: _expected,
                  keyboardType: TextInputType.text,
                  style: TextStyle(fontFamily: monoFont, fontSize: 15, color: c.ink),
                  decoration: flatInput(context, hint: '90, 1:30 o 1 h 30 min', error: _expectedError),
                  onEditingComplete: () {
                    FocusScope.of(context).unfocus();
                    unawaited(_save());
                  },
                ),
              ),
              FlatStat(
                label: 'Descripción',
                child: TextField(
                  key: const Key('task-description'),
                  controller: _description,
                  minLines: 1,
                  maxLines: 8,
                  textCapitalization: TextCapitalization.sentences,
                  style: TextStyle(fontSize: 16, height: 1.3, color: c.ink),
                  decoration: flatInput(context, hint: 'Escribe los detalles…'),
                  onTapOutside: (_) => unawaited(_save()),
                ),
              ),
              if (!task.isSub)
                FlatStat(
                  label: 'Subtareas',
                  count: subs.isEmpty ? null : '${doneSubs.toString().padLeft(2, '0')}/${subs.length.toString().padLeft(2, '0')}',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final s in subs)
                        Row(
                          key: Key('sub-${s.id}'),
                          children: [
                            GestureDetector(
                              key: Key('sub-check-${s.id}'),
                              behavior: HitTestBehavior.opaque,
                              onTap: () => unawaited(_c.toggleDone(s)),
                              child: Padding(padding: const EdgeInsets.only(right: 12, top: 8, bottom: 8), child: LcdIcon(s.isDone ? Icons.check_box_outlined : Icons.check_box_outline_blank, size: 22, color: s.isDone ? c.accent : c.dim)),
                            ),
                            Expanded(child: Text(s.name, style: TextStyle(fontSize: 16, color: s.isDone ? c.dim : c.ink, decoration: s.isDone ? TextDecoration.lineThrough : null))),
                            GestureDetector(key: Key('sub-delete-${s.id}'), behavior: HitTestBehavior.opaque, onTap: () => unawaited(_c.delete(s)), child: Padding(padding: const EdgeInsets.all(10), child: LcdIcon(Icons.close, size: 18, color: c.dim))),
                          ],
                        ),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              key: const Key('subtask-input'),
                              controller: _sub,
                              textCapitalization: TextCapitalization.sentences,
                              style: TextStyle(fontSize: 16, color: c.ink),
                              decoration: flatInput(context, hint: 'Nueva subtarea'),
                              onSubmitted: (_) => _addSub(task),
                            ),
                          ),
                          IconButton(key: const Key('subtask-add'), tooltip: 'Añadir subtarea', icon: LcdIcon(Icons.add_rounded, color: c.accent), onPressed: () => _addSub(task)),
                        ],
                      ),
                    ],
                  ),
                ),
              FlatStat(
                label: 'Etiquetas',
                last: true,
                child: Wrap(
                  spacing: 18,
                  runSpacing: 6,
                  children: [
                    for (final t in _c.tags)
                      GestureDetector(
                        onLongPress: () async {
                          if (await _confirm('¿Borrar la etiqueta «${t.name}»?', 'Se quita de todas las tareas.') && mounted) await _c.deleteTag(t);
                        },
                        child: FlatChoice(key: Key('tag-${t.id}'), label: t.name, color: colorFromHex(t.color), selected: tagsOn.contains(t.id), onTap: () => unawaited(_c.toggleTag(task.id, t))),
                      ),
                    FlatChoice(
                      key: const Key('tag-new'),
                      label: 'Etiqueta',
                      icon: Icons.add,
                      onTap: () async {
                        final name = await _ask('Nueva etiqueta', 'Nombre');
                        if (name == null || !mounted) return;
                        final tag = await _c.createTag(name);
                        if (tag != null && !tagsOn.contains(tag.id)) await _c.toggleTag(task.id, tag);
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ));
      },
    );
  }
}
