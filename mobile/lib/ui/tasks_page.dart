import 'dart:async';

import 'package:flutter/material.dart';

import '../models/task.dart';
import '../state/task_controller.dart';
import '../theme.dart';
import '../util/task_format.dart';
import 'task_detail_page.dart';
import 'widgets/app_backdrop.dart';

/// Las tareas: filtros por estado arriba, la lista y, abajo, el campo para anotar una nueva. Tocar una abre su detalle; la casilla de la
/// izquierda la finaliza. Todo se guarda en el teléfono al instante y sube a Supabase cuando hay internet.
class TasksPage extends StatefulWidget {
  const TasksPage({super.key, required this.controller});

  final TaskController controller;

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> with WidgetsBindingObserver {
  final _input = TextEditingController();
  final _focus = FocusNode();

  /// El filtro elegido: `null` = las que no están finalizadas.
  TaskStatus? _status;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // al abrir la pantalla se ponen al día; después de construir, porque `sync` avisa a quien escucha (como Inicio) y no se puede avisar
    // a otra pantalla en mitad de una construcción
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(widget.controller.sync());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(widget.controller.sync());
  }

  Future<void> _add() async {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    _input.clear();
    await widget.controller.add(text);
    _focus.requestFocus();
  }

  void _open(TaskItem task) {
    unawaited(Navigator.of(context).push(QuickPageRoute<void>(builder: (_) => TaskDetailPage(controller: widget.controller, taskId: task.id))));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final c = widget.controller;
        final tasks = c.roots(status: _status, active: _status == null);
        return Scaffold(
          appBar: AppBar(
            title: const Text('Tareas', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
            actions: [_SyncBadge(controller: c)],
          ),
          body: Column(
            children: [
              _Filters(controller: c, selected: _status, onSelected: (s) => setState(() => _status = s)),
              Expanded(
                child: tasks.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                            !c.loaded
                                ? 'Cargando…'
                                : _status == null
                                    ? 'No tienes tareas pendientes.\nAnota una abajo.'
                                    : 'No hay tareas «${_status!.label}».',
                            key: const Key('tasks-empty'),
                            textAlign: TextAlign.center,
                            style: TextStyle(color: context.colors.dim),
                          ),
                        ),
                      )
                    : ListView.builder(
                        key: const Key('task-list'),
                        padding: const EdgeInsets.only(bottom: 12),
                        itemCount: tasks.length,
                        itemBuilder: (context, i) => _TaskTile(task: tasks[i], controller: c, onOpen: () => _open(tasks[i])),
                      ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: const Key('task-input'),
                          controller: _input,
                          focusNode: _focus,
                          textCapitalization: TextCapitalization.sentences,
                          textInputAction: TextInputAction.done,
                          decoration: const InputDecoration(hintText: 'Nueva tarea'),
                          onSubmitted: (_) => _add(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        key: const Key('task-add'),
                        tooltip: 'Añadir',
                        onPressed: _add,
                        icon: const Icon(Icons.add_rounded),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Los filtros por estado, con cuántas hay en cada uno.
class _Filters extends StatelessWidget {
  const _Filters({required this.controller, required this.selected, required this.onSelected});

  final TaskController controller;
  final TaskStatus? selected;
  final ValueChanged<TaskStatus?> onSelected;

  @override
  Widget build(BuildContext context) {
    Widget chip(Key key, String label, int count, TaskStatus? value) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            key: key,
            label: Text('$label · $count'),
            selected: selected == value,
            onSelected: (_) => onSelected(value),
          ),
        );
    return SizedBox(
      height: 46,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
        child: Row(
          children: [
            chip(const Key('filter-active'), 'Activas', controller.count(null), null),
            for (final s in TaskStatus.values) chip(Key('filter-${s.wire}'), s.label, controller.count(s), s),
          ],
        ),
      ),
    );
  }
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({required this.task, required this.controller, required this.onOpen});

  final TaskItem task;
  final TaskController controller;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final now = DateTime.now();
    final due = task.due;
    final overdue = due != null && !task.isDone && due.isBefore(now.toUtc());
    final progress = controller.progress(task);
    final tags = controller.tagsOf(task.id);
    final bits = <Widget>[
      if (task.status != TaskStatus.pending) Text(task.status.label, style: TextStyle(color: c.accent, fontSize: 12.5, fontWeight: FontWeight.w600)),
      if (due != null) Text(dueLabel(due, now), style: TextStyle(color: overdue ? c.warn : c.dim, fontSize: 12.5)),
      if (progress.total > 0) Text('${progress.done}/${progress.total} subtareas', style: TextStyle(color: c.dim, fontSize: 12.5)),
      for (final t in tags)
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: colorFromHex(t.color), shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text(t.name, style: TextStyle(color: c.dim, fontSize: 12.5)),
        ]),
    ];
    return InkWell(
      key: Key('task-${task.id}'),
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 2, 12, 2),
        child: Row(
          children: [
            IconButton(
              key: Key('task-check-${task.id}'),
              tooltip: task.isDone ? 'Volver a pendiente' : 'Finalizar',
              icon: Icon(task.isDone ? Icons.check_circle : Icons.radio_button_unchecked, color: task.isDone ? c.accent : c.dim),
              onPressed: () => unawaited(controller.toggleDone(task)),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                      color: task.isDone ? c.dim : c.ink,
                      decoration: task.isDone ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  if (bits.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Wrap(spacing: 10, runSpacing: 2, children: bits)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: c.dim),
          ],
        ),
      ),
    );
  }
}

/// Cómo va la sincronización: al día, subiendo, sin conexión (con cuántas faltan por subir) o con un error.
class _SyncBadge extends StatelessWidget {
  const _SyncBadge({required this.controller});

  final TaskController controller;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final IconData icon;
    final Color color;
    final String tip;
    switch (controller.syncState) {
      case SyncState.syncing:
        icon = Icons.cloud_sync_outlined;
        color = c.dim;
        tip = 'Sincronizando…';
      case SyncState.offline:
        icon = Icons.cloud_off_outlined;
        color = c.dim;
        tip = controller.pending > 0 ? 'Sin conexión: ${controller.pending} por subir' : 'Sin conexión';
      case SyncState.error:
        icon = Icons.error_outline;
        color = c.warn;
        tip = controller.syncError ?? 'No se pudo sincronizar';
      case SyncState.idle:
        icon = controller.pending > 0 ? Icons.cloud_upload_outlined : Icons.cloud_done_outlined;
        color = controller.pending > 0 ? c.dim : c.accent;
        tip = controller.pending > 0 ? '${controller.pending} por subir' : 'Todo sincronizado';
    }
    return IconButton(
      key: Key('sync-${controller.syncState.name}'),
      tooltip: tip,
      icon: Icon(icon, color: color),
      onPressed: () {
        unawaited(controller.sync());
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tip)));
      },
    );
  }
}
