import 'package:flutter/material.dart';

import '../models/habit.dart' show dayKey;
import '../theme.dart';
import '../util/agenda.dart';
import '../util/format.dart' show weekdayLetters;

/// El color de algo del calendario: el suyo (los eventos) o el de su clase.
Color itemColor(BuildContext context, AgendaItem item) {
  final c = context.colors;
  return switch (item.kind) {
    AgendaKind.event => Color(colorValue(item.colorHex)),
    AgendaKind.task => c.tasks,
    AgendaKind.reminder => c.reminders,
    AgendaKind.habit => c.habits,
  };
}

/// Las marcas de un día: un cuadrito por cada clase de cosa que tiene (con el color de la primera de esa clase).
class DayDots extends StatelessWidget {
  const DayDots({super.key, required this.items, this.size = 8});

  final List<AgendaItem> items;
  final double size;

  @override
  Widget build(BuildContext context) {
    final seen = <AgendaKind>{};
    final dots = <Widget>[];
    for (final item in items) {
      if (!seen.add(item.kind)) continue;
      dots.add(Container(width: size, height: size, margin: const EdgeInsets.symmetric(horizontal: 1.5), color: itemColor(context, item)));
    }
    return Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: dots);
  }
}

/// El mes: seis semanas de lunes a domingo, cada día un cuadro suelto con un pequeño margen. Hoy, en un cuadro de acento; el día elegido, con
/// filo; los de otro mes, atenuados. Cada cuadro enseña con puntos de color qué clases de cosas tiene.
class MonthGrid extends StatelessWidget {
  const MonthGrid({super.key, required this.days, required this.selected, required this.today, required this.month, required this.itemsOf, required this.onTap});

  /// Los 42 días que se pintan.
  final List<DateTime> days;
  final DateTime selected;
  final DateTime today;

  /// El mes que se ve (los días de otro mes salen atenuados).
  final int month;
  final List<AgendaItem> Function(DateTime day) itemsOf;
  final ValueChanged<DateTime> onTap;

  static const gap = 3.0;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Center(child: Text(weekdayLetters[i], style: TextStyle(fontFamily: monoFont, color: c.dim, fontSize: 15))),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Expanded(
          child: Column(
            children: [
              for (var w = 0; w < 6; w++)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: w == 5 ? 0 : gap),
                    child: Row(
                      children: [
                        for (var d = 0; d < 7; d++)
                          Expanded(
                            child: Padding(
                              padding: EdgeInsets.only(right: d == 6 ? 0 : gap),
                              child: _Cell(
                                day: days[w * 7 + d],
                                inMonth: days[w * 7 + d].month == month,
                                isToday: days[w * 7 + d] == today,
                                isSelected: days[w * 7 + d] == selected,
                                items: itemsOf(days[w * 7 + d]),
                                onTap: onTap,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.day, required this.inMonth, required this.isToday, required this.isSelected, required this.items, required this.onTap});

  final DateTime day;
  final bool inMonth;
  final bool isToday;
  final bool isSelected;
  final List<AgendaItem> items;
  final ValueChanged<DateTime> onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final shown = day.day == 1 ? '${day.day} ${monthNames[day.month - 1].substring(0, 3).toLowerCase()}' : '${day.day}';
    final label = '$shown${items.isEmpty ? '' : ', ${items.length} ${items.length == 1 ? 'cosa' : 'cosas'}'}';
    return Semantics(
      button: true,
      selected: isSelected,
      label: label,
      child: GestureDetector(
        key: Key('cal-cell-${dayKey(day)}'),
        behavior: HitTestBehavior.opaque,
        onTap: () => onTap(day),
        child: Container(
          decoration: BoxDecoration(
            color: isToday ? c.accent.withValues(alpha: 0.22) : c.field.withValues(alpha: inMonth ? 0.7 : 0.3),
            border: Border.all(color: isSelected ? c.accent : (isToday ? c.accent.withValues(alpha: 0.6) : c.edge.withValues(alpha: inMonth ? 0.7 : 0.3)), width: isSelected ? 2 : 1),
          ),
          padding: const EdgeInsets.fromLTRB(2, 2, 2, 2),
          child: Column(
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    shown,
                    maxLines: 1,
                    style: TextStyle(fontFamily: monoFont, fontSize: 15, fontWeight: isToday ? FontWeight.w700 : FontWeight.w500, color: isToday ? c.accent : (inMonth ? c.ink : c.dim.withValues(alpha: 0.55))),
                  ),
                ),
              ),
              SizedBox(height: 7, child: DayDots(items: items, size: 6)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Los siete días de la semana en una tira: letra, número y puntos de color. Tocar uno lo elige.
class WeekStrip extends StatelessWidget {
  const WeekStrip({super.key, required this.days, required this.selected, required this.today, required this.itemsOf, required this.onTap});

  final List<DateTime> days;
  final DateTime selected;
  final DateTime today;
  final List<AgendaItem> Function(DateTime day) itemsOf;
  final ValueChanged<DateTime> onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        for (var i = 0; i < days.length; i++)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: i == days.length - 1 ? 0 : MonthGrid.gap),
              child: GestureDetector(
                key: Key('cal-strip-${dayKey(days[i])}'),
                behavior: HitTestBehavior.opaque,
                onTap: () => onTap(days[i]),
                child: Container(
                  height: 62,
                  decoration: BoxDecoration(
                    color: days[i] == today ? c.accent.withValues(alpha: 0.22) : c.field.withValues(alpha: 0.7),
                    border: Border.all(color: days[i] == selected ? c.accent : c.edge.withValues(alpha: 0.7), width: days[i] == selected ? 2 : 1),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(weekdayLetters[i], style: TextStyle(fontFamily: monoFont, color: c.dim, fontSize: 15)),
                      Text('${days[i].day}', style: TextStyle(fontFamily: monoFont, color: days[i] == today ? c.accent : c.ink, fontSize: 16, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 3),
                      SizedBox(height: 8, child: DayDots(items: itemsOf(days[i]), size: 6)),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// El día en 24 horas: lo de todo el día arriba y, debajo, la columna de horas con cada cosa en su hora (en carriles si se solapan) y la línea
/// roja de «ahora». Mantener el dedo en un hueco crea un evento a esa hora.
class DayTimeline extends StatefulWidget {
  const DayTimeline({super.key, required this.day, required this.items, required this.now, required this.allDay, required this.onOpen, required this.onToggle, required this.canToggle, required this.onCreateAt});

  final DateTime day;

  /// Todo lo del día (la columna solo dibuja lo que tiene hora).
  final List<AgendaItem> items;
  final DateTime now;

  /// Lo de todo el día, ya dibujado (con sus casillas).
  final List<Widget> allDay;
  final ValueChanged<AgendaItem> onOpen;
  final ValueChanged<AgendaItem> onToggle;
  final bool Function(AgendaItem item) canToggle;

  /// Mantener el dedo en un hueco: minutos desde medianoche.
  final ValueChanged<int> onCreateAt;

  static const hour = 60.0;
  static const gutter = 52.0;

  @override
  State<DayTimeline> createState() => _DayTimelineState();
}

class _DayTimelineState extends State<DayTimeline> {
  late final ScrollController _scroll = ScrollController(initialScrollOffset: _initialOffset());

  double _initialOffset() {
    final isToday = dateOnly(widget.day) == dateOnly(widget.now);
    final h = isToday ? (widget.now.hour - 1).clamp(0, 22) : 7;
    return h * DayTimeline.hour;
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final placed = layoutDay(widget.items);
    final isToday = dateOnly(widget.day) == dateOnly(widget.now);
    final nowMinutes = widget.now.hour * 60 + widget.now.minute;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.allDay.isNotEmpty) ...[
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 120),
            child: SingleChildScrollView(child: Column(children: widget.allDay)),
          ),
          const SizedBox(height: 4),
        ],
        Expanded(
          child: SingleChildScrollView(
            key: const Key('cal-timeline'),
            controller: _scroll,
            child: SizedBox(
              height: 24 * DayTimeline.hour,
              child: LayoutBuilder(
                builder: (context, box) {
                  final width = box.maxWidth - DayTimeline.gutter;
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onLongPressStart: (d) {
                      final m = minutesAtY(d.localPosition.dy, 24 * DayTimeline.hour);
                      if (m != null && d.localPosition.dx > DayTimeline.gutter) widget.onCreateAt(m);
                    },
                    child: Stack(
                      children: [
                        for (var h = 0; h < 24; h++) ...[
                          Positioned(left: 0, top: h * DayTimeline.hour - 9, width: DayTimeline.gutter - 6, child: Text(minutesLabel(h * 60), textAlign: TextAlign.right, style: TextStyle(fontFamily: monoFont, color: c.dim, fontSize: 15))),
                          Positioned(left: DayTimeline.gutter, right: 0, top: h * DayTimeline.hour, height: 1, child: ColoredBox(color: c.edge.withValues(alpha: 0.6))),
                        ],
                        for (final p in placed) _block(context, p, width),
                        if (isToday)
                          Positioned(
                            left: DayTimeline.gutter - 4,
                            right: 0,
                            top: nowMinutes / 60 * DayTimeline.hour - 1,
                            height: 2,
                            child: ColoredBox(key: const Key('cal-now'), color: c.warn),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _block(BuildContext context, Placed p, double width) {
    final c = context.colors;
    final color = itemColor(context, p.item);
    final laneWidth = width / p.lanes;
    final toggle = widget.canToggle(p.item);
    return Positioned(
      left: DayTimeline.gutter + p.lane * laneWidth,
      width: laneWidth - 2,
      top: p.top / 60 * DayTimeline.hour,
      height: p.len / 60 * DayTimeline.hour - 1,
      child: GestureDetector(
        key: Key('cal-block-${p.item.kind.name}-${p.item.id}'),
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onOpen(p.item),
        child: Container(
          decoration: BoxDecoration(
            color: Color.alphaBlend(color.withValues(alpha: p.item.done ? 0.10 : 0.24), Colors.black.withValues(alpha: 0.55)),
            border: Border(left: BorderSide(color: color, width: 4)),
          ),
          padding: const EdgeInsets.only(left: 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  p.item.title,
                  maxLines: p.len >= 60 ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: p.item.done ? c.dim : c.ink, fontSize: 15, height: 1.15, decoration: p.item.done ? TextDecoration.lineThrough : null),
                ),
              ),
              if (p.item.kind != AgendaKind.event)
                GestureDetector(
                  key: Key('cal-block-check-${p.item.id}'),
                  behavior: HitTestBehavior.opaque,
                  onTap: toggle ? () => widget.onToggle(p.item) : null,
                  child: SizedBox(
                    width: 34,
                    child: Center(
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(color: p.item.done ? color : null, border: Border.all(color: toggle || p.item.done ? color : c.edge, width: 1.5)),
                        child: p.item.done ? Icon(Icons.check_rounded, size: 14, color: color.computeLuminance() > 0.18 ? const Color(0xFF0A0B0D) : Colors.white) : null,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Un recuadro de color con un número y una etiqueta, para las clases que se muestran u ocultan.
class KindChip extends StatelessWidget {
  const KindChip({super.key, required this.kind, required this.label, required this.count, required this.on, required this.color, required this.onTap});

  final AgendaKind kind;
  final String label;
  final int count;
  final bool on;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      toggled: on,
      label: 'Mostrar ${label.toLowerCase()}',
      child: GestureDetector(
        key: Key('cal-show-${kind.name}'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          decoration: BoxDecoration(
            color: on ? color.withValues(alpha: 0.16) : null,
            border: Border.all(color: on ? color : c.edge),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 10, height: 10, color: on ? color : color.withValues(alpha: 0.3)),
              const SizedBox(width: 7),
              Text(label, style: TextStyle(fontSize: 15, color: on ? c.ink : c.dim)),
              const SizedBox(width: 6),
              Text('$count', style: TextStyle(fontFamily: monoFont, fontSize: 15, color: c.dim)),
            ],
          ),
        ),
      ),
    );
  }
}
