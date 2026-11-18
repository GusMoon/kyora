import 'dart:async';

import 'package:flutter/material.dart';

import '../models/finance.dart';
import '../state/finance_controller.dart';
import '../state/task_controller.dart' show SyncState;
import '../theme.dart';
import '../util/finance.dart';
import 'widgets/flat_form.dart';
import 'widgets/focus_space.dart';
import 'widgets/pixel_glyph.dart';
import 'widgets/section_motion.dart';

/// **Finanzas**, como en Merida: ingresos y gastos por mes. Arriba el mes (con flechas), el resumen (ingresos, gastos y balance) y cuánto se va en
/// cada categoría; debajo, los movimientos (todos, solo ingresos o solo gastos, con buscador). Tocar uno lo edita o lo borra; «+» anota uno nuevo
/// y «Categorías» deja crear y borrar categorías. La moneda se elige arriba. Todo vive en el teléfono y se sincroniza con Supabase.
class FinancePage extends StatefulWidget {
  const FinancePage({super.key, required this.controller, this.now});

  final FinanceController controller;

  /// El reloj (en las pruebas, uno fijo).
  final DateTime Function()? now;

  @override
  State<FinancePage> createState() => _FinancePageState();
}

class _FinancePageState extends State<FinancePage> {
  final _search = TextEditingController();
  late String _month = monthOf(todayKey(_clock()));
  FinanceKind? _filter;

  DateTime _clock() => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    // se pone al día con Supabase al abrir (lo local ya se ve: `start` lo leyó antes)
    unawaited(widget.controller.sync());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  FinanceController get _ctrl => widget.controller;

  Future<void> _pickCurrency() async {
    final choice = await showFocusPanel<String>(
      context,
      title: 'Moneda',
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final code in financeCurrencies)
                ListTile(
                  key: Key('fin-currency-$code'),
                  dense: true,
                  title: Text(code),
                  trailing: code == _ctrl.currency ? LcdIcon(Icons.check_rounded, color: context.colors.accent) : null,
                  onTap: () => Navigator.of(context).pop(code),
                ),
            ],
          ),
        ),
      ),
    );
    if (choice != null) await _ctrl.setCurrency(choice);
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
            builder: (context, _) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FlyIn(
                    edge: MotionEdge.top,
                    order: 0,
                    child: FlatHeader(
                      title: 'FINANZAS',
                      actions: [
                        _SyncMark(controller: _ctrl),
                        TextButton(
                          key: const Key('fin-currency'),
                          onPressed: _pickCurrency,
                          child: Text(_ctrl.currency, style: TextStyle(fontFamily: monoFont, fontSize: 15, color: c.ink)),
                        ),
                        IconButton(
                          key: const Key('fin-categories'),
                          tooltip: 'Categorías',
                          icon: LcdIcon(Icons.label_outline_rounded, color: c.ink),
                          onPressed: () => unawaited(_openCategories()),
                        ),
                        IconButton(
                          key: const Key('fin-add'),
                          tooltip: 'Nuevo movimiento',
                          icon: LcdIcon(Icons.add_rounded, color: c.accent),
                          onPressed: () => unawaited(_openEntry()),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  FlyIn(edge: MotionEdge.left, order: 1, child: _monthBar(c)),
                  Expanded(
                    child: FlyIn(
                      edge: MotionEdge.bottom,
                      order: 2,
                      child: _body(context),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    ));
  }

  Widget _monthBar(KyoraColors c) {
    final thisMonth = monthOf(todayKey(_clock()));
    return Row(
      children: [
        IconButton(
          key: const Key('fin-prev'),
          tooltip: 'Mes anterior',
          icon: LcdIcon(Icons.chevron_left_rounded, color: c.ink),
          onPressed: () => setState(() => _month = shiftMonthKey(_month, -1)),
        ),
        Expanded(
          child: Center(
            child: Text(
              monthLabel(_month),
              key: const Key('fin-month'),
              style: TextStyle(fontFamily: monoFont, fontSize: 16, color: c.ink),
            ),
          ),
        ),
        if (_month != thisMonth) TextButton(key: const Key('fin-today'), onPressed: () => setState(() => _month = thisMonth), child: const Text('Hoy')),
        IconButton(
          key: const Key('fin-next'),
          tooltip: 'Mes siguiente',
          icon: LcdIcon(Icons.chevron_right_rounded, color: c.ink),
          onPressed: () => setState(() => _month = shiftMonthKey(_month, 1)),
        ),
      ],
    );
  }

  Widget _body(BuildContext context) {
    final c = context.colors;
    if (!_ctrl.loaded) return const Center(child: CircularProgressIndicator(strokeWidth: 2.4));
    final summary = _ctrl.summaryOf(_month);
    final query = _search.text.trim().toLowerCase();
    final all = _ctrl.monthEntries(_month);
    final shown = [
      for (final e in all)
        if ((_filter == null || e.kind == _filter) &&
            (query.isEmpty || '${e.description} ${_ctrl.categoryById(e.categoryId)?.name ?? ''}'.toLowerCase().contains(query)))
          e,
    ];
    final other = _ctrl.otherCurrencyCount(_month);
    final mono = TextStyle(fontFamily: monoFont, fontSize: 15, color: c.dim);
    return ListView(
      key: const Key('fin-list'),
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 16),
      children: [
        Row(
          children: [
            Expanded(
              child: _Stat(key: const Key('fin-income'), label: 'INGRESOS', value: formatMoney(summary.income, _ctrl.currency), color: c.ok),
            ),
            Expanded(
              child: _Stat(key: const Key('fin-expense'), label: 'GASTOS', value: formatMoney(summary.expense, _ctrl.currency), color: c.ink),
            ),
            Expanded(
              child: _Stat(
                key: const Key('fin-balance'),
                label: 'BALANCE',
                value: formatMoney(summary.balance, _ctrl.currency),
                color: summary.balance < 0 ? c.warn : c.accent,
              ),
            ),
          ],
        ),
        if (other > 0)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '$other ${other == 1 ? 'movimiento está' : 'movimientos están'} en otra moneda y no se suma${other == 1 ? '' : 'n'}.',
              key: const Key('fin-other-currency'),
              style: mono,
            ),
          ),
        if (summary.byCategory.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            'POR CATEGORÍA',
            style: TextStyle(fontFamily: monoFont, fontSize: 15, letterSpacing: 1.2, color: c.accent),
          ),
          const SizedBox(height: 6),
          for (final row in summary.byCategory)
            _CategoryBar(key: Key('fin-cat-${row.kind.wire}-${row.categoryId ?? 'none'}'), row: row, currency: _ctrl.currency),
        ],
        const SizedBox(height: 14),
        Wrap(
          spacing: 18,
          children: [
            for (final (kind, label) in [(null, 'Todos'), (FinanceKind.income, 'Ingresos'), (FinanceKind.expense, 'Gastos')])
              FlatChoice(key: Key('fin-filter-${kind?.wire ?? 'all'}'), label: label, selected: _filter == kind, onTap: () => setState(() => _filter = kind)),
          ],
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.edge), top: BorderSide(color: c.edge))),
          child: Row(
            children: [
              Text('> ', style: TextStyle(fontFamily: monoFont, fontSize: 17, color: c.accent)),
              Expanded(
                child: TextField(
                  key: const Key('fin-search'),
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  style: TextStyle(fontFamily: monoFont, fontSize: 16, color: c.ink),
                  decoration: flatInput(context, hint: 'buscar descripción o categoría'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        if (shown.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(all.isEmpty ? 'Este mes aún no hay movimientos.' : 'Ningún movimiento coincide.', key: const Key('fin-empty'), style: mono),
            ),
          )
        else
          for (final e in shown)
            _EntryRow(
              key: Key('fin-entry-${e.id}'),
              entry: e,
              category: _ctrl.categoryById(e.categoryId),
              onTap: () => unawaited(_openEntry(existing: e)),
            ),
      ],
    );
  }

  Future<void> _openEntry({FinanceEntry? existing}) => showFocusPanel<void>(
    context,
    builder: (_) => _EntryEditor(controller: _ctrl, existing: existing, month: _month, now: _clock()),
  );

  Future<void> _openCategories() => showFocusPanel<void>(
    context,
    title: 'Categorías',
    builder: (_) => _CategoriesEditor(controller: _ctrl),
  );
}

/// Si hay cambios por subir o sin conexión, una marca discreta.
class _SyncMark extends StatelessWidget {
  const _SyncMark({required this.controller});

  final FinanceController controller;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (text, color) = switch (controller.syncState) {
      SyncState.offline => ('sin conexión', c.warn),
      SyncState.error => ('error', c.warn),
      SyncState.syncing => ('subiendo…', c.dim),
      _ => controller.pending > 0 ? ('${controller.pending} por subir', c.dim) : ('', c.dim),
    };
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Text(
        text,
        key: const Key('fin-sync'),
        style: TextStyle(fontFamily: monoFont, fontSize: 15, color: color),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({super.key, required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontFamily: monoFont, fontSize: 15, letterSpacing: 1, color: c.dim),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            key: Key('${key is ValueKey ? (key as ValueKey).value : label}-value'),
            style: display(size: 20, color: color, weight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}

class _CategoryBar extends StatelessWidget {
  const _CategoryBar({super.key, required this.row, required this.currency});

  final CategoryTotal row;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = Color(colorValueOf(row.color));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(width: 10, height: 10, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  row.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: monoFont, fontSize: 15, color: c.ink),
                ),
              ),
              Text(
                '${row.kind == FinanceKind.income ? '+' : '-'}${formatMoney(row.total, currency)}',
                style: TextStyle(fontFamily: monoFont, fontSize: 15, color: c.dim),
              ),
            ],
          ),
          const SizedBox(height: 3),
          LayoutBuilder(
            builder: (context, box) => Stack(
              children: [
                Container(height: 4, color: c.edge.withValues(alpha: 0.5)),
                Container(height: 4, width: box.maxWidth * row.share.clamp(0.0, 1.0), color: color),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({super.key, required this.entry, required this.category, required this.onTap});

  final FinanceEntry entry;
  final FinanceCategory? category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final income = entry.kind == FinanceKind.income;
    final title = entry.description.isEmpty ? (category?.name ?? 'Sin categoría') : entry.description;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.edge.withValues(alpha: 0.6)))),
        child: Row(
          children: [
            Container(width: 4, height: 34, color: Color(colorValueOf(category?.color ?? '#9aa1ac'))),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontFamily: monoFont, fontSize: 16, color: c.ink),
                  ),
                  Text(
                    '${entry.occurredOn} · ${category?.name ?? 'Sin categoría'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontFamily: monoFont, fontSize: 15, color: c.dim),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${income ? '+' : '-'}${formatMoney(entry.amountCents, entry.currency)}',
              style: TextStyle(fontFamily: monoFont, fontSize: 16, fontWeight: FontWeight.w700, color: income ? c.ok : c.ink),
            ),
          ],
        ),
      ),
    );
  }
}

/// Anota un movimiento, o edita `existing`: tipo, importe, categoría, día y descripción.
class _EntryEditor extends StatefulWidget {
  const _EntryEditor({required this.controller, required this.month, required this.now, this.existing});

  final FinanceController controller;
  final FinanceEntry? existing;
  final String month;
  final DateTime now;

  @override
  State<_EntryEditor> createState() => _EntryEditorState();
}

class _EntryEditorState extends State<_EntryEditor> {
  late FinanceKind _kind = widget.existing?.kind ?? FinanceKind.expense;
  late final _amount = TextEditingController(text: widget.existing == null ? '' : _plain(widget.existing!.amountCents));
  late final _description = TextEditingController(text: widget.existing?.description ?? '');
  late String? _categoryId = widget.existing?.categoryId;
  late String _day = widget.existing?.occurredOn ?? (widget.month == monthOf(todayKey(widget.now)) ? todayKey(widget.now) : '${widget.month}-01');
  String? _error;

  static String _plain(int cents) => '${cents ~/ 100}.${(cents % 100).toString().padLeft(2, '0')}';

  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickDay() async {
    final parts = _day.split('-').map(int.parse).toList();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(parts[0], parts[1], parts[2]),
      firstDate: DateTime(2000),
      lastDate: DateTime(widget.now.year + 5),
    );
    if (picked != null) setState(() => _day = todayKey(picked));
  }

  Future<void> _save() async {
    final cents = parseAmount(_amount.text);
    if (cents == null) {
      setState(() => _error = 'Escribe un importe mayor que cero.');
      return;
    }
    final existing = widget.existing;
    if (existing == null) {
      await widget.controller.addEntry(kind: _kind, amountCents: cents, categoryId: _categoryId, description: _description.text, occurredOn: _day);
    } else {
      await widget.controller.updateEntry(existing, kind: _kind, amountCents: cents, categoryId: _categoryId, description: _description.text, occurredOn: _day);
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    await widget.controller.deleteEntry(widget.existing!);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final categories = widget.controller.categoriesOf(_kind);
    // la categoría elegida es de otro tipo (se cambió Ingreso/Gasto): se deja sin categoría
    final selected = categories.any((x) => x.id == _categoryId) ? _categoryId : null;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.existing == null ? 'Nuevo movimiento' : 'Editar movimiento', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            FlatStat(
              label: 'Tipo',
              child: Wrap(
                key: const Key('fin-kind'),
                spacing: 18,
                children: [
                  for (final k in FinanceKind.values) FlatChoice(key: Key('fin-kind-${k.wire}'), label: k.label, selected: _kind == k, onTap: () => setState(() => _kind = k)),
                ],
              ),
            ),
            FlatStat(
              label: 'Importe (${widget.controller.currency})',
              child: TextField(
                key: const Key('fin-amount'),
                controller: _amount,
                autofocus: widget.existing == null,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: display(size: 24, color: c.ink, weight: FontWeight.w500),
                decoration: flatInput(context, hint: '0.00', error: _error),
              ),
            ),
            FlatStat(
              label: 'Categoría',
              child: Wrap(
                key: const Key('fin-category'),
                spacing: 18,
                runSpacing: 2,
                children: [
                  FlatChoice(key: const Key('fin-category-none'), label: 'Sin categoría', selected: selected == null, onTap: () => setState(() => _categoryId = null)),
                  for (final category in categories)
                    FlatChoice(key: Key('fin-category-${category.id}'), label: category.name, color: Color(colorValueOf(category.color)), selected: selected == category.id, onTap: () => setState(() => _categoryId = category.id)),
                ],
              ),
            ),
            FlatStat(
              label: 'Día',
              child: InkWell(
                key: const Key('fin-day'),
                onTap: _pickDay,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [LcdIcon(Icons.event_outlined, color: c.accent), const SizedBox(width: 12), Text(_day, style: TextStyle(fontFamily: monoFont, fontSize: 15, color: c.ink))]),
                ),
              ),
            ),
            FlatStat(
              label: 'Descripción',
              last: true,
              child: TextField(
                key: const Key('fin-description'),
                controller: _description,
                textCapitalization: TextCapitalization.sentences,
                decoration: flatInput(context, hint: 'Opcional'),
              ),
            ),
            const SizedBox(height: 8),
            Align(alignment: Alignment.centerRight, child: FlatAction(key: const Key('fin-save'), icon: Icons.check_rounded, label: 'Guardar', onTap: _save)),
            if (widget.existing != null) ...[
              const SizedBox(height: 6),
              Align(alignment: Alignment.centerRight, child: FlatAction(key: const Key('fin-delete'), icon: Icons.delete_outline_rounded, label: 'Borrar el movimiento', warn: true, onTap: _delete)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Las categorías: las de cada tipo (con su color), borrar una (sus movimientos quedan «sin categoría»), crear una y poner las de siempre.
class _CategoriesEditor extends StatefulWidget {
  const _CategoriesEditor({required this.controller});

  final FinanceController controller;

  @override
  State<_CategoriesEditor> createState() => _CategoriesEditorState();
}

class _CategoriesEditorState extends State<_CategoriesEditor> {
  final _name = TextEditingController();
  FinanceKind _kind = FinanceKind.expense;
  String _color = financeColors.first;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final created = await widget.controller.addCategory(_name.text, _kind, _color);
    if (created != null) _name.clear();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final ctrl = widget.controller;
        final all = [...ctrl.categoriesOf(FinanceKind.income), ...ctrl.categoriesOf(FinanceKind.expense)];
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 12, 12 + MediaQuery.viewInsetsOf(context).bottom),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (all.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8, right: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Aún no hay categorías.',
                            key: const Key('fin-no-categories'),
                            style: TextStyle(color: c.dim, fontSize: 15),
                          ),
                          FlatAction(key: const Key('fin-seed'), icon: Icons.auto_awesome_outlined, label: 'Crear las básicas', onTap: () => unawaited(ctrl.addDefaultCategories())),
                        ],
                      ),
                    ),
                  for (final category in all)
                    Row(
                      key: Key('fin-cat-row-${category.id}'),
                      children: [
                        Container(width: 10, height: 10, color: Color(colorValueOf(category.color))),
                        const SizedBox(width: 10),
                        Expanded(child: Text(category.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
                        Text(category.kind.label, style: TextStyle(color: c.dim, fontSize: 15)),
                        IconButton(
                          key: Key('fin-cat-del-${category.id}'),
                          tooltip: 'Borrar',
                          icon: LcdIcon(Icons.delete_outline_rounded, color: c.warn),
                          onPressed: () => unawaited(ctrl.deleteCategory(category)),
                        ),
                      ],
                    ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FlatStat(
                          label: 'Nueva categoría',
                          child: TextField(
                            key: const Key('fin-cat-name'),
                            controller: _name,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: flatInput(context, hint: 'Nombre'),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          key: const Key('fin-cat-kind'),
                          spacing: 18,
                          children: [
                            for (final k in FinanceKind.values) FlatChoice(key: Key('fin-cat-kind-${k.wire}'), label: k.label, selected: _kind == k, onTap: () => setState(() => _kind = k)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            for (final color in financeColors)
                              GestureDetector(
                                key: Key('fin-color-$color'),
                                onTap: () => setState(() => _color = color),
                                child: Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: Color(colorValueOf(color)),
                                    border: Border.all(color: color == _color ? c.ink : Colors.transparent, width: 2),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Align(alignment: Alignment.centerRight, child: FlatAction(key: const Key('fin-cat-add'), icon: Icons.add_rounded, label: 'Crear categoría', onTap: _add)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
