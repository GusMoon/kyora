import 'package:flutter/material.dart';

import '../models/habit.dart' show dayKey;
import '../theme.dart';
import '../util/agenda.dart';
import '../util/format.dart' show weekdayLetters;
import 'widgets/cyber_panel.dart';
import 'widgets/dot_matrix.dart';

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
  const DayDots({super.key, required this.items, this.size = 8, this.alignment = MainAxisAlignment.center});

  final List<AgendaItem> items;
  final double size;
  final MainAxisAlignment alignment;

  @override
  Widget build(BuildContext context) {
    final seen = <AgendaKind>{};
    final dots = <Widget>[];
    for (final item in items) {
      if (!seen.add(item.kind)) continue;
      dots.add(Container(width: size, height: size, margin: const EdgeInsets.symmetric(horizontal: 1.5), color: itemColor(context, item)));
    }
    return Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: alignment, children: dots);
  }
}

/// La cabecera de la vista mensual: el **número grande** del día elegido (en matriz de puntos cuadrados) con una etiqueta HUD a la derecha
/// («HOY», «MAÑANA», «EN 3 DÍAS»…), debajo el mes y el año y, a la derecha, el día de la semana.
class MonthHeader extends StatelessWidget {
  const MonthHeader({super.key, required this.day, required this.today});

  final DateTime day;
  final DateTime today;

  /// Lo que mide, para repartir la pantalla (el mes se estira con lo que queda).
  static const height = 150.0;

  /// «Mar», «Mié»…
  static String weekdayShort(DateTime day) => weekdayNames[day.weekday - 1].substring(0, 3);

  /// Cuánto falta (o pasó) desde hoy: «HOY», «MAÑANA», «AYER», «EN 3 DÍAS», «HACE 2 DÍAS».
  static String relative(DateTime day, DateTime today) {
    final n = (dateOnly(day).difference(dateOnly(today)).inHours / 24).round();
    return switch (n) {
      0 => 'HOY',
      1 => 'MAÑANA',
      -1 => 'AYER',
      > 1 => 'EN $n DÍAS',
      _ => 'HACE ${-n} DÍAS',
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isToday = day == today;
    return SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DotMatrixText('${day.day}', key: const Key('cal-month-day'), height: 56, color: c.accent, glow: false, dimOff: false, square: true),
                const Spacer(),
                Container(
                  key: const Key('cal-month-relative'),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: isToday ? c.accent.withValues(alpha: 0.16) : null, border: Border.all(color: isToday ? c.accent : c.edge)),
                  child: Text(relative(day, today), style: hudLabel(color: isToday ? c.accent : c.dim)),
                ),
              ],
            ),
            const Spacer(),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(monthNames[day.month - 1].toUpperCase(), key: const Key('cal-month-name'), maxLines: 1, overflow: TextOverflow.ellipsis, style: display(size: 28, color: c.ink, weight: FontWeight.w800)),
                      Text('${day.year}', style: display(size: 28, color: c.dim, weight: FontWeight.w400)),
                    ],
                  ),
                ),
                Text(weekdayShort(day), key: const Key('cal-month-weekday'), style: display(size: 28, color: c.dim, weight: FontWeight.w500)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// El mes: la fila de letras de la semana (la del día de hoy, en acento) y seis semanas de lunes a domingo, cada día un **cuadro** suelto con un
/// pequeño margen, dentro de un panel ciberpunk. La cuadrícula **llena el alto que se le da** (con un mínimo de [minHeight]). Lo ya pasado va
/// relleno; lo que falta, oscuro; hoy, en acento; el día elegido, con filo y marcas en las esquinas; los de otro mes, solo el contorno. Cada
/// cuadro enseña con puntos de color qué clases de cosas tiene.
class MonthGrid extends StatelessWidget {
  const MonthGrid({super.key, required this.days, required this.selected, required this.today, required this.month, required this.itemsOf, required this.onTap});

  /// Los 42 días que se pintan.
  final List<DateTime> days;
  final DateTime selected;
  final DateTime today;

  /// El mes que se ve (los días de otro mes salen solo con el contorno).
  final int month;
  final List<AgendaItem> Function(DateTime day) itemsOf;
  final ValueChanged<DateTime> onTap;

  static const gap = 3.0;

  /// Lo mínimo que necesita para que cada fila tenga 44 px: las letras, seis filas, sus márgenes y el relleno del panel.
  static const minHeight = 26 + 6 * 44 + 5 * gap + 20.0;

  /// Lo que se deja libre bajo la cuadrícula para las tarjetas del día (si no, no se vería ninguna sin deslizar).
  static const cardsReserve = 200.0;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return CyberPanel(
      active: 0.25,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 26,
              child: Row(
                children: [
                  for (var i = 0; i < 7; i++)
                    Expanded(
                      child: Center(
                        child: Text(
                          weekdayLetters[i],
                          key: Key('cal-letter-$i'),
                          style: TextStyle(fontFamily: monoFont, fontSize: 15, fontWeight: i == today.weekday - 1 ? FontWeight.w700 : FontWeight.w400, color: i == today.weekday - 1 ? c.accent : c.dim),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            for (var w = 0; w < 6; w++)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(top: w == 0 ? 0 : gap),
                  child: Row(
                    children: [
                      for (var d = 0; d < 7; d++)
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(left: d == 0 ? 0 : gap),
                            child: _Cell(
                              day: days[w * 7 + d],
                              inMonth: days[w * 7 + d].month == month,
                              today: today,
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
    );
  }
}

/// Cómo se ve un cuadro del mes según el día que es.
enum CellState { outside, past, today, future }

CellState cellStateOf(DateTime day, DateTime today, {required bool inMonth}) {
  if (!inMonth) return CellState.outside;
  if (day == today) return CellState.today;
  return day.isBefore(today) ? CellState.past : CellState.future;
}

class _Cell extends StatelessWidget {
  const _Cell({required this.day, required this.inMonth, required this.today, required this.isSelected, required this.items, required this.onTap});

  final DateTime day;
  final bool inMonth;
  final DateTime today;
  final bool isSelected;
  final List<AgendaItem> items;
  final ValueChanged<DateTime> onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final state = cellStateOf(day, today, inMonth: inMonth);
    final shown = day.day == 1 ? '${day.day} ${monthNames[day.month - 1].substring(0, 3).toLowerCase()}' : '${day.day}';
    final label = '$shown${items.isEmpty ? '' : ', ${items.length} ${items.length == 1 ? 'cosa' : 'cosas'}'}';
    final fill = switch (state) {
      CellState.outside => Colors.transparent,
      CellState.past => c.pick,
      CellState.today => c.accent,
      CellState.future => c.field,
    };
    final numberColor = switch (state) {
      CellState.outside => c.dim.withValues(alpha: 0.5),
      CellState.past => c.ink,
      CellState.today => c.onAccent,
      CellState.future => c.dim,
    };
    final mark = state == CellState.today ? c.ink : c.accent;
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
            color: fill,
            border: Border.all(
              color: isSelected ? mark : (state == CellState.outside ? c.edge.withValues(alpha: 0.35) : c.edge),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: CustomPaint(
            painter: _CellOverlay(state: state, selected: isSelected, mark: mark, edge: c.edge, hasItems: items.isNotEmpty),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(5, 3, 3, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.topLeft,
                    child: Text(shown, maxLines: 1, style: TextStyle(fontFamily: monoFont, fontSize: 15, fontWeight: state == CellState.today ? FontWeight.w800 : FontWeight.w500, color: numberColor)),
                  ),
                  const Spacer(),
                  SizedBox(height: 7, child: DayDots(items: items, size: 6, alignment: MainAxisAlignment.start)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// El acabado sci-fi de un cuadro: líneas de barrido finas (en los días de este mes), una muesca en la esquina de lo que tiene cosas y, en el día
/// elegido, marcas en las cuatro esquinas. Sin sombras ni bordes redondeados.
class _CellOverlay extends CustomPainter {
  const _CellOverlay({required this.state, required this.selected, required this.mark, required this.edge, required this.hasItems});

  final CellState state;
  final bool selected;
  final Color mark;
  final Color edge;
  final bool hasItems;

  @override
  void paint(Canvas canvas, Size size) {
    if (state != CellState.outside) {
      final scan = Paint()..color = Colors.black.withValues(alpha: state == CellState.today ? 0.14 : 0.22)..strokeWidth = 1;
      for (var y = 2.0; y < size.height; y += 3) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), scan);
      }
    }
    final tick = Paint()..style = PaintingStyle.stroke..strokeWidth = 2..strokeCap = StrokeCap.square..color = selected ? mark : edge;
    const l = 7.0;
    const m = 2.0;
    if (selected) {
      final w = size.width, h = size.height;
      canvas.drawPath(Path()..moveTo(m, m + l)..lineTo(m, m)..lineTo(m + l, m), tick);
      canvas.drawPath(Path()..moveTo(w - m - l, m)..lineTo(w - m, m)..lineTo(w - m, m + l), tick);
      canvas.drawPath(Path()..moveTo(m, h - m - l)..lineTo(m, h - m)..lineTo(m + l, h - m), tick);
      canvas.drawPath(Path()..moveTo(w - m - l, h - m)..lineTo(w - m, h - m)..lineTo(w - m, h - m - l), tick);
    } else if (state != CellState.outside) {
      // la muesca de la esquina de abajo a la derecha: más viva si ese día tiene cosas
      final w = size.width, h = size.height;
      final notch = Paint()..style = PaintingStyle.stroke..strokeWidth = 2..strokeCap = StrokeCap.square..color = hasItems ? mark.withValues(alpha: 0.9) : edge;
      canvas.drawPath(Path()..moveTo(w - m - 6, h - m)..lineTo(w - m, h - m)..lineTo(w - m, h - m - 6), notch);
    }
  }

  @override
  bool shouldRepaint(covariant _CellOverlay old) => old.state != state || old.selected != selected || old.mark != mark || old.edge != edge || old.hasItems != hasItems;
}

/// El acabado sci-fi de una banda cerrada de la semana: líneas de barrido finas y una marca vertical a la izquierda.
class _BandPainter extends CustomPainter {
  const _BandPainter({required this.mark});

  final Color mark;

  @override
  void paint(Canvas canvas, Size size) {
    final scan = Paint()..color = Colors.black.withValues(alpha: 0.2)..strokeWidth = 1;
    for (var y = 2.0; y < size.height; y += 3) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), scan);
    }
    canvas.drawRect(Rect.fromLTWH(0, 0, 3, size.height), Paint()..color = mark);
  }

  @override
  bool shouldRepaint(covariant _BandPainter old) => old.mark != mark;
}

/// Un día de la vista semanal: una banda con su nombre en letras grandes y cuántas cosas tiene. Las bandas se apilan y se van oscureciendo
/// ([index], de 0 a 6); la del día **abierto** es un panel que enseña su fecha y [children] (sus tarjetas y el campo de «añadir una tarea»).
class WeekDayBand extends StatelessWidget {
  const WeekDayBand({super.key, required this.day, required this.index, required this.today, required this.open, required this.count, required this.dateLine, required this.onTap, this.children = const []});

  final DateTime day;
  final int index;
  final DateTime today;
  final bool open;
  final int count;

  /// «Noviembre 5, 2026 · 10:30».
  final String dateLine;
  final VoidCallback onTap;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isToday = day == today;
    final head = GestureDetector(
      key: Key('cal-week-day-${dayKey(day)}'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, open ? 16 : 18, 16, open ? 4 : 18),
        child: Row(
          children: [
            Expanded(
              child: Text(
                weekdayNames[day.weekday - 1].toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: display(size: 28, color: open ? c.ink : (isToday ? c.accent : c.dim), weight: open ? FontWeight.w800 : FontWeight.w700),
              ),
            ),
            if (isToday && !open) Text('HOY', style: hudLabel(color: c.accent)),
            if (count > 0) ...[
              const SizedBox(width: 10),
              Container(
                key: Key('cal-week-count-${dayKey(day)}'),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                decoration: BoxDecoration(border: Border.all(color: c.edge)),
                child: Text('$count', style: TextStyle(fontFamily: monoFont, fontSize: 15, color: c.dim)),
              ),
            ],
          ],
        ),
      ),
    );
    if (!open) {
      // una banda de cristal oscuro (deja ver el fondo), con el tinte del acento que se apaga de arriba a abajo, líneas de barrido y una marca a la izquierda
      final tint = Color.alphaBlend(c.accent.withValues(alpha: 0.12 - 0.014 * index), Colors.black.withValues(alpha: 0.46 + 0.05 * index));
      return DecoratedBox(
        decoration: BoxDecoration(color: tint, border: Border(top: BorderSide(color: c.accent.withValues(alpha: 0.22)))),
        child: CustomPaint(painter: _BandPainter(mark: isToday ? c.accent : c.accent.withValues(alpha: 0.35)), child: head),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: CyberPanel(
        active: 0.4,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            head,
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(dateLine, key: Key('cal-week-date-${dayKey(day)}'), style: TextStyle(fontFamily: monoFont, fontSize: 15, color: c.dim)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
            ),
          ],
        ),
      ),
    );
  }
}
