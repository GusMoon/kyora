import 'package:flutter/material.dart';

import '../../theme.dart';
import 'hack_text.dart';

/// Las piezas del estilo **plano** de Kyra (el de la ficha de una tarea y el detalle del clima): sin paneles ni campos con caja; un rótulo
/// apagado en mayúsculas, debajo el dato y una línea fina entre un dato y el siguiente.

/// El fondo de una pantalla plana: un velo oscuro sobre el fondo de pantalla de la app, para que el texto (que ya no va sobre paneles) se lea
/// bien. Sin desenfoque.
class FlatBackdrop extends StatelessWidget {
  const FlatBackdrop({super.key, required this.child, this.dim = dimAmount});

  /// Lo oscurecido que queda el fondo.
  static const dimAmount = 0.5;

  final double dim;
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      IgnorePointer(child: ColoredBox(key: const Key('flat-backdrop'), color: Colors.black.withValues(alpha: dim))),
      child,
    ],
  );
}

/// La cabecera de una sección: `> TÍTULO` en el acento, a la derecha una cuenta y los botones, y una línea fina debajo.
class FlatHeader extends StatelessWidget {
  const FlatHeader({super.key, required this.title, this.count, this.countKey, this.actions = const []});

  final String title;

  /// Un dato a la derecha (cuántas hay…).
  final String? count;
  final Key? countKey;

  /// Los botones de la esquina.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(2, 4, 0, 4),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.edge))),
      child: Row(
        children: [
          Text('> ', style: TextStyle(fontFamily: monoFont, fontSize: 17, color: c.accent)),
          Expanded(child: HackText(title, maxLines: 1, style: TextStyle(fontFamily: monoFont, fontSize: 17, letterSpacing: 1.6, fontWeight: FontWeight.w600, color: c.accent))),
          if (count != null) Padding(padding: const EdgeInsets.only(right: 4), child: Text(count!, key: countKey, style: TextStyle(fontFamily: monoFont, fontSize: 15, color: c.dim))),
          ...actions,
        ],
      ),
    );
  }
}

/// Un dato: su rótulo apagado en mayúsculas (y, a la derecha, una cuenta) y debajo el dato; una línea fina lo separa del siguiente.
class FlatStat extends StatelessWidget {
  const FlatStat({super.key, required this.label, required this.child, this.count, this.last = false, this.padding = const EdgeInsets.symmetric(vertical: 12)});

  final String label;
  final String? count;
  final bool last;
  final EdgeInsets padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: padding,
      decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: c.edge))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(label.toUpperCase(), style: TextStyle(fontFamily: monoFont, fontSize: 15, letterSpacing: 1.2, color: c.dim))),
              if (count != null) Text(count!, style: TextStyle(fontFamily: monoFont, fontSize: 15, color: c.accent)),
            ],
          ),
          const SizedBox(height: 4),
          child,
        ],
      ),
    );
  }
}

/// Una opción (un estado, un filtro, una etiqueta): solo texto con un cuadrito delante; la elegida va en el acento y subrayada.
class FlatChoice extends StatelessWidget {
  const FlatChoice({super.key, required this.label, required this.onTap, this.color, this.icon, this.selected = false});

  final String label;
  final Color? color;
  final IconData? icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 36),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) Icon(icon!, size: 16, color: c.accent) else Container(width: 8, height: 8, color: selected ? (color ?? c.accent) : (color ?? c.dim).withValues(alpha: 0.5)),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(fontFamily: monoFont, fontSize: 15, fontWeight: selected ? FontWeight.w700 : FontWeight.w400, color: selected ? c.accent : c.ink, decoration: selected ? TextDecoration.underline : null, decorationColor: c.accent),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Un campo que se ve como texto: sin caja, sin relleno y sin línea. Solo el cursor dice que se puede escribir.
InputDecoration flatInput(BuildContext context, {required String hint, String? error, Widget? suffix, Widget? prefix}) {
  final c = context.colors;
  return InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: c.dim.withValues(alpha: 0.7)),
    errorText: error,
    filled: false,
    isDense: true,
    counterText: '',
    contentPadding: const EdgeInsets.symmetric(vertical: 6),
    prefixIcon: prefix,
    prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
    suffixIcon: suffix,
    suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
    border: InputBorder.none,
    enabledBorder: InputBorder.none,
    focusedBorder: InputBorder.none,
    errorBorder: InputBorder.none,
    focusedErrorBorder: InputBorder.none,
  );
}

/// Un botón de texto en el acento (o en el de aviso) con un icono, sin caja: la acción de una ficha plana.
class FlatAction extends StatelessWidget {
  const FlatAction({super.key, required this.label, required this.onTap, this.icon, this.warn = false});

  final String label;
  final IconData? icon;
  final bool warn;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = onTap == null ? c.dim : (warn ? c.warn : c.accent);
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[Icon(icon, size: 18, color: color), const SizedBox(width: 6)],
                Flexible(child: Text(label.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: monoFont, fontSize: 15, letterSpacing: 0.8, color: color))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
