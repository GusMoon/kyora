import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../util/agenda.dart';
import 'cyber_panel.dart';
import 'pixel_glyph.dart';

/// El icono de cada clase de cosa del calendario.
IconData agendaKindIcon(AgendaKind kind) => switch (kind) {
      AgendaKind.event => Icons.event_outlined,
      AgendaKind.task => Icons.check_box_outlined,
      AgendaKind.reminder => Icons.notifications_none_rounded,
      AgendaKind.habit => Icons.repeat_rounded,
    };

/// Una **tarjeta** de la agenda (evento, tarea, recordatorio u hábito): a la izquierda un bloque del color de su clase con la hora (y, debajo,
/// la fecha); a la derecha el título con su flecha `›`, el subtítulo, una línea y un pie con un icono y un dato (con la casilla al final si se
/// puede marcar). Lo hecho va tachado y lo vencido, en el color de aviso. Sin esquinas redondeadas: el filo y las marcas son los de `CyberPanel`.
class AgendaCard extends StatelessWidget {
  const AgendaCard({super.key, required this.item, required this.color, this.check, this.overdue = false, this.onTap});

  final AgendaItem item;

  /// El color de su clase (el del evento, si lo trae).
  final Color color;

  /// La casilla de marcar (`SquareCheck`); sin ella (los eventos) no hay.
  final Widget? check;

  /// Vencido: el bloque de la hora va en el color de aviso.
  final bool overdue;
  final VoidCallback? onTap;

  /// El ancho del bloque de color.
  static const blockWidth = 76.0;

  /// «9 DIC».
  static String dateText(DateTime day) => '${day.day} ${monthNames[day.month - 1].substring(0, 3).toUpperCase()}';

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tone = overdue ? c.warn : color;
    final on = tone.computeLuminance() > 0.18 ? const Color(0xFF0A0B0D) : const Color(0xFFFFFFFF);
    final timed = !item.allDay && item.start != null;
    final (hour, ampm) = timed ? hourParts(item.start!) : ('', '');
    return CyberPanel(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: blockWidth,
                child: Column(
                  children: [
                    Expanded(
                      child: ColoredBox(
                        key: Key('card-time-${item.kind.name}-${item.id}'),
                        color: tone,
                        child: Center(
                          child: timed
                              ? Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(hour, style: display(size: 30, color: on, weight: FontWeight.w800)),
                                    Text(ampm, style: TextStyle(fontFamily: monoFont, fontSize: 15, fontWeight: FontWeight.w600, color: on)),
                                  ],
                                )
                              : Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text('TODO', style: TextStyle(fontFamily: monoFont, fontSize: 15, fontWeight: FontWeight.w700, color: on)),
                                    Text('DÍA', style: TextStyle(fontFamily: monoFont, fontSize: 15, fontWeight: FontWeight.w700, color: on)),
                                  ],
                                ),
                        ),
                      ),
                    ),
                    SizedBox(
                      height: 28,
                      child: ColoredBox(
                        color: Color.alphaBlend(Colors.black.withValues(alpha: 0.28), tone),
                        child: Center(child: Text(dateText(item.day), style: TextStyle(fontFamily: monoFont, fontSize: 15, fontWeight: FontWeight.w600, color: on))),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 6, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              item.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontFamily: appFont, fontSize: 17, fontWeight: FontWeight.w600, height: 1.2, color: item.done ? c.dim : c.ink, decoration: item.done ? TextDecoration.lineThrough : null),
                            ),
                          ),
                          Icon(Icons.chevron_right_rounded, color: c.dim, size: 24),
                        ],
                      ),
                      if (item.subtitle.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(item.subtitle, key: Key('card-subtitle-${item.kind.name}-${item.id}'), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, height: 1.25, color: c.dim)),
                      ],
                      const SizedBox(height: 8),
                      ColoredBox(color: c.edge, child: const SizedBox(height: 1, width: double.infinity)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          LcdIcon(agendaKindIcon(item.kind), size: 18, color: tone),
                          const SizedBox(width: 8),
                          Expanded(child: Text(item.footer.isEmpty ? agendaKindLabel[item.kind]! : item.footer, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: monoFont, fontSize: 15, color: c.dim))),
                          if (check != null) Padding(padding: const EdgeInsets.only(right: 6), child: check),
                        ],
                      ),
                    ],
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

/// Una casilla cuadrada: vacía, o rellena con ✓. Sin `onTap` queda apagada (un día que todavía no llega). Con [color] va del color de su tipo
/// (recordatorio, tarea, hábito); sin él, del acento.
class SquareCheck extends StatelessWidget {
  const SquareCheck({super.key, required this.done, required this.onTap, this.label, this.color});

  final bool done;
  final VoidCallback? onTap;
  final String? label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final enabled = onTap != null;
    final tone = color ?? c.accent;
    final on = tone.computeLuminance() > 0.18 ? const Color(0xFF0A0B0D) : const Color(0xFFFFFFFF);
    return Semantics(
      button: true,
      checked: done,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Align(
            alignment: Alignment.centerRight,
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: done ? tone : tone.withValues(alpha: enabled ? 0.08 : 0),
                border: Border.all(color: done ? tone : (enabled ? tone.withValues(alpha: 0.75) : c.edge), width: 1.5),
              ),
              child: done ? LcdIcon(Icons.check_rounded, size: 18, color: on) : null,
            ),
          ),
        ),
      ),
    );
  }
}
