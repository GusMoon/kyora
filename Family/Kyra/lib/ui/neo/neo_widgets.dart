import 'package:flutter/material.dart';

import 'neo_theme.dart';

/// Las piezas del diseño cyber-brutalista de KyraFamily: fondo con cuadrícula, cajas de filo fino, botones llenos con la flecha de acento,
/// etiquetas mono con su número (`/01`), avisos y la barra de navegación de abajo. Todas toman sus colores de `context.neo`.

/// El fondo de las pantallas: una **cuadrícula** muy tenue y unas crucecitas (`+`) en algunos cruces, del color del texto.
class NeoGridPainter extends CustomPainter {
  const NeoGridPainter(this.ink);

  final Color ink;

  static const cell = 28.0;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..strokeWidth = 1
      ..color = ink.withValues(alpha: 0.045);
    for (var x = 0.0; x <= size.width; x += cell) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (var y = 0.0; y <= size.height; y += cell) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final plus = Paint()
      ..strokeWidth = 1
      ..color = ink.withValues(alpha: 0.26);
    for (var x = cell * 4; x < size.width; x += cell * 4) {
      for (var y = cell * 4; y < size.height; y += cell * 4) {
        canvas.drawLine(Offset(x - 3, y), Offset(x + 3, y), plus);
        canvas.drawLine(Offset(x, y - 3), Offset(x, y + 3), plus);
      }
    }
  }

  @override
  bool shouldRepaint(covariant NeoGridPainter old) => old.ink != ink;
}

/// Una caja de filo fino: relleno plano (sin él, el de las tarjetas) y un borde de 1 px (el de las tarjetas, o el del texto si es `strong`).
class NeoBox extends StatelessWidget {
  const NeoBox({super.key, required this.child, this.color, this.padding = const EdgeInsets.all(14), this.strong = false, this.borderColor});

  final Widget child;
  final Color? color;
  final EdgeInsetsGeometry padding;
  final bool strong;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final s = context.neo;
    return Container(
      padding: padding,
      decoration: BoxDecoration(color: color ?? s.paper, border: Border.all(color: borderColor ?? (strong ? s.ink : s.line), width: Neo.border)),
      child: child,
    );
  }
}

/// Algo que se pulsa: mientras se mantiene presionado baja un píxel y se tiñe un poco del acento.
class NeoPress extends StatefulWidget {
  const NeoPress({
    super.key,
    required this.child,
    required this.onTap,
    this.onLongPress,
    this.color,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    this.strong = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Color? color;
  final EdgeInsetsGeometry padding;
  final bool strong;

  @override
  State<NeoPress> createState() => _NeoPressState();
}

class _NeoPressState extends State<NeoPress> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final s = context.neo;
    final enabled = widget.onTap != null || widget.onLongPress != null;
    final pressed = _down && enabled;
    final base = widget.color ?? s.paper;
    final fill = !enabled ? s.soft : (pressed ? Color.lerp(base, s.accent, 0.28)! : base);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => setState(() => _down = true) : null,
      onTapUp: enabled ? (_) => setState(() => _down = false) : null,
      onTapCancel: enabled ? () => setState(() => _down = false) : null,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: Transform.translate(
        offset: Offset(0, pressed ? 1 : 0),
        child: NeoBox(color: fill, padding: widget.padding, strong: widget.strong, child: widget.child),
      ),
    );
  }
}

/// Un botón: lleno (sin `color`, del color del texto: negro en claro, blanco en oscuro) con el texto en mayúsculas a la izquierda y el icono
/// (la flecha) a la derecha en el color de acento. Con otro relleno (`paper`, el pop, el acento) el texto se ajusta solo.
class NeoButton extends StatelessWidget {
  const NeoButton({super.key, required this.label, required this.onTap, this.icon, this.color, this.busy = false, this.expand = true, this.danger = false});

  final String label;
  final VoidCallback? onTap;

  /// El icono de la derecha; sin él, una flecha `↗`.
  final IconData? icon;
  final Color? color;
  final bool busy;
  final bool expand;

  /// Algo que no se puede deshacer (borrar): rojo.
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final s = context.neo;
    final fill = danger ? Neo.warn : (color ?? s.ink);
    final onColor = danger ? Neo.white : s.onColor(fill);
    // la flecha va en el acento sobre el botón principal (ajustado para que se vea también sobre el blanco del modo oscuro)
    final arrowColor = fill == s.ink ? NeoScheme.readableOn(s.accent, s.ink, 3) : onColor;
    final row = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      children: [
        Flexible(child: Text(label.toUpperCase(), overflow: TextOverflow.ellipsis, style: neoLabel(size: 13, color: onColor))),
        if (expand) const Spacer() else const SizedBox(width: 16),
        if (busy)
          SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.5, color: onColor))
        else
          Icon(icon ?? Icons.north_east_rounded, size: 20, color: arrowColor),
      ],
    );
    return NeoPress(color: fill, onTap: busy ? null : onTap, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15), child: row);
  }
}

/// Un botón cuadrado con un icono (los controles del reproductor, cerrar…). Sin `color`, del color de las tarjetas.
class NeoIconButton extends StatelessWidget {
  const NeoIconButton({super.key, required this.icon, required this.onTap, this.color, this.size = 44, this.tooltip, this.iconColor});

  final IconData icon;
  final VoidCallback? onTap;
  final Color? color;
  final double size;
  final String? tooltip;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final s = context.neo;
    final fill = color ?? s.paper;
    final button = NeoPress(
      color: fill,
      onTap: onTap,
      padding: EdgeInsets.zero,
      child: SizedBox(width: size, height: size, child: Icon(icon, size: size * 0.5, color: iconColor ?? s.onColor(fill))),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

/// Una etiquetita: texto mono en mayúsculas sobre el pop (o el color que se dé): el rol, «EN VIVO», un número…
class NeoTag extends StatelessWidget {
  const NeoTag(this.text, {super.key, this.color, this.textColor});

  final String text;
  final Color? color;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    final s = context.neo;
    final fill = color ?? s.pop;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: fill, border: Border.all(color: s.ink, width: Neo.border)),
      child: Text(text.toUpperCase(), style: neoLabel(size: 11, color: textColor ?? s.onColor(fill))),
    );
  }
}

/// Una sección: un rótulo `/01 TÍTULO` (el número en el acento, el título mono) con una línea fina debajo, y el contenido en una caja.
class NeoWindow extends StatelessWidget {
  const NeoWindow({super.key, required this.title, required this.child, this.color, this.trailing, this.index, this.padding = const EdgeInsets.all(14)});

  final String title;
  final Widget child;
  final Color? color;
  final Widget? trailing;
  final String? index;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final s = context.neo;
    return Container(
      decoration: BoxDecoration(color: color ?? s.paper, border: Border.all(color: s.line, width: Neo.border)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: s.line, width: Neo.border))),
            child: Row(
              children: [
                Text('/${index ?? ''}', style: neoLabel(size: 12, color: s.accentDeep)),
                const SizedBox(width: 10),
                Expanded(child: Text(title.toUpperCase(), overflow: TextOverflow.ellipsis, style: neoLabel(size: 12, color: s.ink))),
                ?trailing,
              ],
            ),
          ),
          Padding(padding: padding, child: child),
        ],
      ),
    );
  }
}

/// La cabecera grande de una pantalla, como la de la referencia: el número `/01`, el título enorme y condensado, y debajo una frase corta
/// en mayúsculas en el color de acento.
class NeoHero extends StatelessWidget {
  const NeoHero({super.key, required this.index, required this.title, required this.tagline, this.trailing});

  final String index;
  final String title;
  final String tagline;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final s = context.neo;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('/$index', style: neoLabel(size: 12, color: s.accentDeep)),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(child: Text(title.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: neoHeading(size: 44, color: s.ink))),
            ?trailing,
          ],
        ),
        const SizedBox(height: 8),
        Text(tagline.toUpperCase(), style: neoLabel(size: 12, color: s.accentDeep)),
      ],
    );
  }
}

/// Un campo de escribir: rótulo mono arriba y el campo con filo fino.
class NeoField extends StatelessWidget {
  const NeoField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.obscure = false,
    this.keyboardType,
    this.textInputAction,
    this.onSubmitted,
    this.onChanged,
    this.autofocus = false,
    this.maxLength,
    this.fieldKey,
    this.textAlign = TextAlign.start,
    this.style,
    this.suffix,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool obscure;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final bool autofocus;
  final int? maxLength;
  final Key? fieldKey;
  final TextAlign textAlign;
  final TextStyle? style;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    final s = context.neo;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: neoLabel(size: 11, color: s.dim)),
        const SizedBox(height: 6),
        TextField(
          key: fieldKey,
          controller: controller,
          obscureText: obscure,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          onSubmitted: onSubmitted,
          onChanged: onChanged,
          autofocus: autofocus,
          maxLength: maxLength,
          textAlign: textAlign,
          style: style ?? neoBody(weight: FontWeight.w700, color: s.ink),
          decoration: InputDecoration(hintText: hint, counterText: '', suffixIcon: suffix),
        ),
      ],
    );
  }
}

/// Un aviso: sin color es un error (filo rojo y una barra a la izquierda); con otro color (el pop…) va relleno.
class NeoNotice extends StatelessWidget {
  const NeoNotice(this.text, {super.key, this.color = Neo.warn, this.noticeKey});

  final String text;
  final Color color;
  final Key? noticeKey;

  @override
  Widget build(BuildContext context) {
    final s = context.neo;
    final error = color == Neo.warn;
    return Container(
      decoration: BoxDecoration(color: error ? s.paper : color, border: Border.all(color: error ? Neo.warn : s.ink, width: Neo.border)),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (error) Container(width: 5, color: Neo.warn),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  text,
                  key: noticeKey,
                  style: neoBody(size: 14, color: error ? NeoScheme.readableOn(Neo.warn, s.paper, 4.5) : s.onColor(color), weight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Un interruptor neo: una cajita con un cuadrado que va de un lado a otro; encendido se llena del acento.
class NeoSwitch extends StatelessWidget {
  const NeoSwitch({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final s = context.neo;
    return Semantics(
      toggled: value,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 52,
          height: 28,
          padding: const EdgeInsets.all(3),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          decoration: BoxDecoration(color: value ? s.accent : s.paper, border: Border.all(color: s.ink, width: Neo.border)),
          child: Container(width: 20, height: 20, color: value ? s.onAccent : s.ink),
        ),
      ),
    );
  }
}

/// El texto de un enlace pequeño (`NO SOY YO`, `SALIR`): mono, subrayado.
TextStyle neoLink(Color color) => neoLabel(size: 12, color: color).copyWith(decoration: TextDecoration.underline, decorationColor: color);

/// La barra de navegación de abajo: celdas iguales que **no cambian de tamaño**. En la elegida el icono **crece** y se pinta del color de
/// acento (igual que su nombre); las demás quedan en gris. Se toca para ir directo a una, o se desliza la pantalla a los lados.
class NeoBottomNav extends StatelessWidget {
  const NeoBottomNav({super.key, required this.items, required this.index, required this.onSelect});

  final List<NeoNavItem> items;
  final int index;
  final ValueChanged<int> onSelect;

  static const height = 64.0;

  /// Cuánto crece el icono de la pantalla elegida.
  static const growth = 1.4;

  @override
  Widget build(BuildContext context) {
    final s = context.neo;
    return Container(
      decoration: BoxDecoration(color: s.paper, border: Border(top: BorderSide(color: s.ink, width: Neo.border))),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: height,
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++) Expanded(child: _NavCell(item: items[i], selected: i == index, onTap: () => onSelect(i))),
            ],
          ),
        ),
      ),
    );
  }
}

class NeoNavItem {
  const NeoNavItem({required this.id, required this.label, required this.icon, this.badge});

  final String id;
  final String label;
  final IconData icon;

  /// Algo pequeño que mostrar sobre el icono (por ejemplo, un punto de aviso).
  final bool? badge;
}

class _NavCell extends StatelessWidget {
  const _NavCell({required this.item, required this.selected, required this.onTap});

  final NeoNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.neo;
    const duration = Duration(milliseconds: 220);
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: GestureDetector(
        key: Key('nav-${item.id}'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: TweenAnimationBuilder<Color?>(
          duration: duration,
          tween: ColorTween(end: selected ? s.accent : s.dim),
          builder: (context, color, _) => Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedScale(
                key: Key('nav-icon-${item.id}'),
                scale: selected ? NeoBottomNav.growth : 1,
                duration: duration,
                curve: Curves.easeOutBack,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(item.icon, size: 22, color: color),
                    if (item.badge == true)
                      Positioned(
                        right: -5,
                        top: -3,
                        child: Container(width: 9, height: 9, decoration: BoxDecoration(color: Neo.warn, border: Border.all(color: s.paper, width: 1.5))),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 9),
              Text(item.label.toUpperCase(), maxLines: 1, overflow: TextOverflow.clip, style: neoLabel(size: 10, color: color)),
            ],
          ),
        ),
      ),
    );
  }
}
