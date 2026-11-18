import 'dart:async';

import 'package:flutter/material.dart';

import '../data/improvement_backend.dart';
import '../models/improvement.dart';
import '../state/improvements_controller.dart';
import '../theme.dart';
import 'widgets/flat_form.dart';
import 'widgets/focus_space.dart';
import 'widgets/pixel_glyph.dart';
import 'widgets/section_motion.dart';

/// **Mejoras**: lo que se quiere agregar o mejorar en el proyecto (Merida y Kyra comparten la lista, en Supabase). «+» abre el formulario: la sección,
/// las funciones que se quieren (una por línea) y una descripción. Cada mejora pendiente enseña eso mismo y un botón **Hecho**: al terminar la función
/// se pulsa, se pide confirmar y la mejora se borra de la base de datos y deja de verse.
class ImprovementsPage extends StatefulWidget {
  const ImprovementsPage({super.key, required this.backend, this.create});

  final ImprovementBackend backend;

  /// Cómo se crea el controlador (en las pruebas, con un reloj y unos ids fijos).
  final ImprovementsController Function(ImprovementBackend backend)? create;

  @override
  State<ImprovementsPage> createState() => _ImprovementsPageState();
}

class _ImprovementsPageState extends State<ImprovementsPage> {
  late final ImprovementsController _ctrl = (widget.create ?? ImprovementsController.new)(widget.backend);

  @override
  void initState() {
    super.initState();
    unawaited(_ctrl.refresh());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _new() => showFocusPanel<void>(
    context,
    title: 'Nueva mejora',
    builder: (_) => _Form(controller: _ctrl),
  );

  Future<void> _done(Improvement item) async {
    final sure = await showFocusPanel<bool>(
      context,
      title: 'Marcar como hecha',
      builder: (context) => FocusDialog(
        content: Text('¿Marcar «${item.section}» como hecha? Se borrará de la lista y de la base de datos.', key: const Key('imp-done-text')),
        actions: [
          TextButton(key: const Key('imp-done-cancel'), onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
          FilledButton(
            key: const Key('imp-done-confirm'),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Hecho'),
          ),
        ],
      ),
    );
    if (sure == true) await _ctrl.finish(item);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return FlatBackdrop(child: Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: ListenableBuilder(
            listenable: _ctrl,
            builder: (context, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FlyIn(
                  edge: MotionEdge.top,
                  order: 0,
                  child: FlatHeader(
                    title: 'MEJORAS',
                    count: _ctrl.state == ImprovementsState.ready ? '${_ctrl.items.length}' : null,
                    countKey: const Key('imp-count'),
                    actions: [
                      IconButton(
                        key: const Key('imp-refresh'),
                        tooltip: 'Actualizar',
                        icon: LcdIcon(Icons.refresh_rounded, color: c.ink),
                        onPressed: () => unawaited(_ctrl.refresh()),
                      ),
                      IconButton(
                        key: const Key('imp-add'),
                        tooltip: 'Nueva mejora',
                        icon: LcdIcon(Icons.add_rounded, color: c.accent),
                        onPressed: () => unawaited(_new()),
                      ),
                    ],
                  ),
                ),
                if (_ctrl.notice != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _ctrl.notice!,
                      key: const Key('imp-notice'),
                      style: TextStyle(color: c.warn, fontSize: 15),
                    ),
                  ),
                const SizedBox(height: 10),
                Expanded(
                  child: FlyIn(
                    edge: MotionEdge.bottom,
                    order: 1,
                    child: _body(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ));
  }

  Widget _body(BuildContext context) {
    final c = context.colors;
    switch (_ctrl.state) {
      case ImprovementsState.loading:
        return const Center(child: CircularProgressIndicator(strokeWidth: 2.4));
      case ImprovementsState.error:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _ctrl.error ?? 'No se pudieron leer las mejoras.',
                  key: const Key('imp-error'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.warn, fontSize: 16),
                ),
                const SizedBox(height: 12),
                OutlinedButton(key: const Key('imp-retry'), onPressed: () => unawaited(_ctrl.refresh()), child: const Text('Reintentar')),
              ],
            ),
          ),
        );
      case ImprovementsState.ready:
        if (_ctrl.items.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'No hay mejoras pendientes.\nToca «+» para anotar la primera idea.',
                key: const Key('imp-empty'),
                textAlign: TextAlign.center,
                style: TextStyle(color: c.dim, fontSize: 16),
              ),
            ),
          );
        }
        return ListView(
          key: const Key('imp-list'),
          padding: const EdgeInsets.fromLTRB(2, 4, 2, 16),
          children: [for (final item in _ctrl.items) _Card(key: Key('imp-card-${item.id}'), item: item, onDone: () => unawaited(_done(item)))],
        );
    }
  }
}

class _Card extends StatelessWidget {
  const _Card({super.key, required this.item, required this.onDone});

  final Improvement item;
  final VoidCallback onDone;

  static String _day(DateTime t) {
    final l = t.toLocal();
    return '${l.day.toString().padLeft(2, '0')}/${l.month.toString().padLeft(2, '0')}/${l.year}';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final lines = item.functionLines;
    return Container(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 4),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.edge))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  item.section,
                  key: Key('imp-section-${item.id}'),
                  style: TextStyle(fontFamily: monoFont, fontSize: 16, fontWeight: FontWeight.w700, color: c.ink),
                ),
              ),
              Text(
                _day(item.createdAt),
                style: TextStyle(fontFamily: monoFont, fontSize: 15, color: c.dim),
              ),
            ],
          ),
          if (lines.isNotEmpty) ...[
            const SizedBox(height: 6),
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('■ ', style: TextStyle(fontSize: 9, height: 2, color: c.accent)),
                    Expanded(
                      child: Text(line, style: TextStyle(fontSize: 15, color: c.ink)),
                    ),
                  ],
                ),
              ),
          ],
          if (item.description.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              item.description,
              key: Key('imp-desc-${item.id}'),
              style: TextStyle(fontSize: 15, color: c.dim),
            ),
          ],
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              key: Key('imp-done-${item.id}'),
              onPressed: onDone,
              icon: LcdIcon(Icons.check_rounded, color: c.accent),
              label: Text('HECHO', style: TextStyle(fontFamily: monoFont, fontSize: 15, letterSpacing: 0.8, color: c.accent)),
            ),
          ),
        ],
      ),
    );
  }
}

/// El formulario de una mejora nueva: la sección, las funciones (una por línea) y la descripción.
class _Form extends StatefulWidget {
  const _Form({required this.controller});

  final ImprovementsController controller;

  @override
  State<_Form> createState() => _FormState();
}

class _FormState extends State<_Form> {
  final _section = TextEditingController();
  final _functions = TextEditingController();
  final _description = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _section.dispose();
    _functions.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final problem = await widget.controller.add(section: _section.text, functions: _functions.text, description: _description.text);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Nueva mejora', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              FlatStat(
                label: 'Sección',
                child: TextField(
                  key: const Key('imp-section'),
                  controller: _section,
                  autofocus: true,
                  maxLength: Improvement.maxSection,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: flatInput(context, hint: 'Sección a agregar o mejorar'),
                ),
              ),
              FlatStat(
                label: 'Funciones',
                child: TextField(
                  key: const Key('imp-functions'),
                  controller: _functions,
                  minLines: 2,
                  maxLines: 6,
                  maxLength: Improvement.maxText,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: flatInput(context, hint: 'Una por línea'),
                ),
              ),
              FlatStat(
                label: 'Descripción',
                last: true,
                child: TextField(
                  key: const Key('imp-description'),
                  controller: _description,
                  minLines: 1,
                  maxLines: 5,
                  maxLength: Improvement.maxText,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: flatInput(context, hint: 'Qué se quiere lograr'),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _error!,
                    key: const Key('imp-form-error'),
                    style: TextStyle(color: c.warn, fontSize: 15),
                  ),
                ),
              const SizedBox(height: 14),
              Align(alignment: Alignment.centerRight, child: FlatAction(key: const Key('imp-save'), icon: Icons.check_rounded, label: 'Registrar', onTap: _save)),
            ],
          ),
        ),
      ),
    );
  }
}
