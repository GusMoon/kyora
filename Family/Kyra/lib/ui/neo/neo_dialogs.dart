import 'dart:async';

import 'package:flutter/material.dart';

import 'neo_theme.dart';
import 'neo_widgets.dart';

/// Una opción de un menú neo (`showNeoMenu`).
class NeoMenuOption<T> {
  const NeoMenuOption({required this.value, required this.label, required this.icon, this.danger = false, this.key});

  final T value;
  final String label;
  final IconData icon;

  /// Algo que no se puede deshacer (borrar): en rojo.
  final bool danger;
  final Key? key;
}

/// Un menú de acciones que sube desde abajo, en el estilo de KyraFamily: el título mono y una fila por opción. Devuelve la elegida o `null`.
Future<T?> showNeoMenu<T>(BuildContext context, {required String title, required List<NeoMenuOption<T>> options}) {
  return showModalBottomSheet<T>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (context) {
      final s = context.neo;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text.rich(
                TextSpan(children: [
                  TextSpan(text: '/ ', style: neoLabel(size: 12, color: s.accentDeep)),
                  TextSpan(text: title.toUpperCase(), style: neoLabel(size: 12, color: s.ink)),
                ]),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              for (final o in options)
                InkWell(
                  key: o.key,
                  onTap: () => Navigator.of(context).pop(o.value),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(border: Border(top: BorderSide(color: s.line, width: Neo.border))),
                    child: Row(
                      children: [
                        Icon(o.icon, size: 20, color: o.danger ? Neo.warn : s.ink),
                        const SizedBox(width: 14),
                        Expanded(child: Text(o.label.toUpperCase(), style: neoLabel(size: 13, color: o.danger ? Neo.warn : s.ink))),
                        Icon(Icons.north_east_rounded, size: 16, color: o.danger ? Neo.warn : s.accent),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

/// Un cuadro neo: título mono, el contenido y los botones abajo.
class NeoDialog extends StatelessWidget {
  const NeoDialog({super.key, required this.title, required this.child, required this.actions});

  final String title;
  final Widget child;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final s = context.neo;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title.toUpperCase(), style: neoHeading(size: 24, color: s.ink)),
            const SizedBox(height: 12),
            child,
            const SizedBox(height: 18),
            for (var i = 0; i < actions.length; i++) ...[if (i > 0) const SizedBox(height: 10), actions[i]],
          ],
        ),
      ),
    );
  }
}

/// ¿Seguro? Un cuadro con el texto y dos botones (el de confirmar en rojo si `danger`). `true` si se confirma.
Future<bool> neoConfirm(
  BuildContext context, {
  required String title,
  required String text,
  required String confirm,
  bool danger = true,
  Key? confirmKey,
  Key? textKey,
}) async {
  final sure = await showDialog<bool>(
    context: context,
    builder: (context) => NeoDialog(
      title: title,
      actions: [
        NeoButton(key: confirmKey ?? const Key('neo-confirm'), label: confirm, icon: danger ? Icons.delete_outline_rounded : Icons.check_rounded, danger: danger, onTap: () => Navigator.of(context).pop(true)),
        NeoButton(key: const Key('neo-cancel'), label: 'Cancelar', icon: Icons.close_rounded, color: context.neo.paper, onTap: () => Navigator.of(context).pop(false)),
      ],
      child: Text(text, key: textKey, style: neoBody(color: context.neo.ink)),
    ),
  );
  return sure ?? false;
}

/// Pide un texto (con `initial` ya escrito). `null` si se cancela o se deja vacío.
Future<String?> neoAskText(BuildContext context, {required String title, required String hint, required String confirm, String initial = ''}) {
  return showDialog<String>(context: context, builder: (context) => _AskText(title: title, hint: hint, confirm: confirm, initial: initial));
}

class _AskText extends StatefulWidget {
  const _AskText({required this.title, required this.hint, required this.confirm, required this.initial});

  final String title;
  final String hint;
  final String confirm;
  final String initial;

  @override
  State<_AskText> createState() => _AskTextState();
}

class _AskTextState extends State<_AskText> {
  late final _text = TextEditingController(text: widget.initial)..selection = TextSelection(baseOffset: 0, extentOffset: widget.initial.length);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _done() {
    final value = _text.text.trim();
    if (value.isEmpty) return;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return NeoDialog(
      title: widget.title,
      actions: [
        NeoButton(key: const Key('neo-ask-ok'), label: widget.confirm, icon: Icons.check_rounded, onTap: _done),
        NeoButton(key: const Key('neo-cancel'), label: 'Cancelar', icon: Icons.close_rounded, color: context.neo.paper, onTap: () => Navigator.of(context).pop()),
      ],
      child: NeoField(
        fieldKey: const Key('neo-ask-field'),
        controller: _text,
        label: widget.hint,
        autofocus: true,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _done(),
      ),
    );
  }
}

/// Un aviso corto abajo (lo que pasó o el error).
void neoToast(BuildContext context, String text) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger?.hideCurrentSnackBar();
  messenger?.showSnackBar(SnackBar(content: Text(text)));
}

/// Para lanzar sin esperar desde un `onTap`.
void neoRun(Future<void> Function() action) => unawaited(action());
