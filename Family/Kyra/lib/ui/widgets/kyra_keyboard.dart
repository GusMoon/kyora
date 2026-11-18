import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme.dart';
import 'section_motion.dart';

/// Qué teclas se enseñan: letras, números y signos, o más signos (los símbolos de un teclado de texto), y el pad numérico de los campos de
/// números y teléfonos.
enum KeyLayer { letters, symbols, more }

/// El estado de la tecla de mayúsculas: apagada, para una sola letra, o fija.
enum ShiftState { off, once, locked }

/// El **teclado de Kyra**: sustituye al del sistema en toda la app (se instala con `TextInput.setInputControl`, así que vale para cualquier
/// campo de texto sin tocarlo). Sabe escribir en el campo que tiene el foco: poner texto, borrar, mover el cursor, mayúsculas (también solas, al
/// empezar una frase), acentos al mantener una vocal, y el pad numérico para números y teléfonos.
class KyraKeyboardController extends ChangeNotifier with TextInputControl {
  TextInputClient? _client;
  TextInputConfiguration _config = const TextInputConfiguration();
  TextEditingValue _value = TextEditingValue.empty;

  bool visible = false;
  KeyLayer layer = KeyLayer.letters;
  ShiftState shift = ShiftState.off;

  /// Las variantes de la tecla que se mantiene presionada (á é í…); vacío si no hay.
  List<String> variants = const [];

  TextInputConfiguration get config => _config;
  TextEditingValue get value => _value;

  /// ¿Hay un campo al que escribir?
  bool get attached => _client != null;

  /// El pad numérico (números, teléfonos y fechas) en vez del teclado de texto.
  bool get numeric => switch (_config.inputType.index) {
    2 || 3 || 4 => true,
    _ => false,
  };
  bool get phone => _config.inputType.index == 3;
  bool get decimal => _config.inputType.decimal ?? false;
  bool get signed => _config.inputType.signed ?? false;
  bool get email => _config.inputType.index == 5;
  bool get url => _config.inputType.index == 6;
  bool get multiline => _config.inputType == TextInputType.multiline || _config.inputAction == TextInputAction.newline;

  // ---- lo que pide el framework ----

  @override
  void attach(TextInputClient client, TextInputConfiguration configuration) {
    _client = client;
    _config = configuration;
    layer = KeyLayer.letters;
    variants = const [];
    shift = ShiftState.off;
    notifyListeners();
  }

  @override
  void detach(TextInputClient client) {
    if (!identical(_client, client)) return;
    _client = null;
    variants = const [];
    // esconderse lo pide el framework un instante después (`hide`), y solo si no entró otro campo: pasar de uno a otro no parpadea
  }

  @override
  void show() {
    if (visible) return;
    visible = true;
    notifyListeners();
  }

  @override
  void hide() {
    if (!visible) return;
    visible = false;
    variants = const [];
    notifyListeners();
  }

  @override
  void updateConfig(TextInputConfiguration configuration) {
    _config = configuration;
    notifyListeners();
  }

  @override
  void setEditingState(TextEditingValue value) {
    _value = value;
    _autoShift();
    notifyListeners();
  }

  // ---- lo que hace quien escribe ----

  /// Pone `text` donde está el cursor (o en lugar de lo elegido).
  void type(String text) {
    if (_client == null) return;
    final sel = _selection;
    _apply(TextEditingValue(text: sel.textBefore(_value.text) + text + sel.textAfter(_value.text), selection: TextSelection.collapsed(offset: sel.start + text.length)));
    if (shift == ShiftState.once) shift = ShiftState.off;
    variants = const [];
    _autoShift();
    notifyListeners();
  }

  /// Borra lo elegido o, sin elección, la letra de antes del cursor (una letra entera, aunque lleve acento o sea un emoji).
  void backspace() {
    if (_client == null) return;
    final sel = _selection;
    if (!sel.isCollapsed) {
      _apply(TextEditingValue(text: sel.textBefore(_value.text) + sel.textAfter(_value.text), selection: TextSelection.collapsed(offset: sel.start)));
    } else if (sel.start > 0) {
      final before = sel.textBefore(_value.text).characters.skipLast(1).toString();
      _apply(TextEditingValue(text: before + sel.textAfter(_value.text), selection: TextSelection.collapsed(offset: before.length)));
    }
    variants = const [];
    _autoShift();
    notifyListeners();
  }

  /// Mueve el cursor `delta` letras (negativo, a la izquierda).
  void moveCursor(int delta) {
    if (_client == null) return;
    final text = _value.text;
    final sel = _selection;
    final head = text.substring(0, sel.extentOffset.clamp(0, text.length)).characters;
    var offset = sel.extentOffset;
    if (delta < 0) {
      offset = head.skipLast(-delta).string.length;
    } else {
      final tail = text.substring(offset).characters.take(delta).string;
      offset += tail.length;
    }
    _apply(TextEditingValue(text: text, selection: TextSelection.collapsed(offset: offset.clamp(0, text.length))));
    notifyListeners();
  }

  /// La tecla de intro: un salto de línea en los campos de varias líneas y, en los demás, la acción del campo (siguiente, listo, buscar…).
  void enter() {
    final client = _client;
    if (client == null) return;
    if (multiline) {
      type('\n');
      return;
    }
    client.performAction(_config.inputAction == TextInputAction.unspecified ? TextInputAction.done : _config.inputAction);
  }

  void toggleShift() {
    shift = switch (shift) {
      ShiftState.off => ShiftState.once,
      ShiftState.once => ShiftState.locked,
      ShiftState.locked => ShiftState.off,
    };
    notifyListeners();
  }

  void setLayer(KeyLayer next) {
    layer = next;
    variants = const [];
    notifyListeners();
  }

  void showVariants(List<String> list) {
    variants = list;
    notifyListeners();
  }

  void closeVariants() {
    if (variants.isEmpty) return;
    variants = const [];
    notifyListeners();
  }

  /// Esconde el teclado quitándole el foco al campo.
  void dismiss() => FocusManager.instance.primaryFocus?.unfocus();

  // ---- por dentro ----

  TextSelection get _selection {
    final sel = _value.selection;
    final len = _value.text.length;
    if (!sel.isValid) return TextSelection.collapsed(offset: len);
    return TextSelection(baseOffset: sel.start.clamp(0, len), extentOffset: sel.end.clamp(0, len));
  }

  void _apply(TextEditingValue next) {
    _value = next;
    TextInput.updateEditingValue(next);
  }

  /// Mayúscula sola al empezar una frase, una palabra o todo en mayúsculas, según pida el campo.
  void _autoShift() {
    if (shift == ShiftState.locked && _config.textCapitalization != TextCapitalization.characters) return;
    final before = _selection.textBefore(_value.text);
    final wants = switch (_config.textCapitalization) {
      TextCapitalization.characters => true,
      TextCapitalization.words => before.isEmpty || RegExp(r'\s$').hasMatch(before),
      TextCapitalization.sentences => before.isEmpty || RegExp(r'([.!?¿¡]\s+|\n)$').hasMatch(before),
      TextCapitalization.none => false,
    };
    if (_config.obscureText || email || url || numeric) {
      shift = ShiftState.off;
      return;
    }
    if (wants) {
      shift = _config.textCapitalization == TextCapitalization.characters ? ShiftState.locked : ShiftState.once;
    } else if (shift == ShiftState.once) {
      shift = ShiftState.off;
    }
  }

}

/// Las variantes con acento de una tecla (se ven al mantenerla presionada).
const kKeyVariants = {
  'a': ['á', 'à', 'â', 'ä', 'ã'],
  'e': ['é', 'è', 'ê', 'ë'],
  'i': ['í', 'ì', 'î', 'ï'],
  'o': ['ó', 'ò', 'ô', 'ö', 'õ'],
  'u': ['ú', 'ù', 'û', 'ü'],
  'n': ['ñ'],
  'c': ['ç'],
  '.': ['…', '·'],
  '?': ['¿'],
  '!': ['¡'],
  '-': ['–', '—'],
  r'$': ['€', '£', '¥'],
};

/// El anfitrión del teclado: instala el [KyraKeyboardController] como teclado de toda la app, dibuja el teclado abajo de la pantalla y le avisa
/// a lo de arriba de cuánto espacio ocupa (como el teclado del sistema, con `MediaQuery.viewInsets`), para que las pantallas y los paneles
/// se suban solos.
class KyraKeyboardHost extends StatefulWidget {
  const KyraKeyboardHost({super.key, required this.controller, required this.child});

  /// `true` mientras se ve el modo visitante (neo-brutalista): ahí se usa el teclado del sistema, no el de Kyra, que es del estilo sci-fi.
  static final ValueNotifier<bool> useSystem = ValueNotifier<bool>(false);

  final KyraKeyboardController controller;
  final Widget child;

  @override
  State<KyraKeyboardHost> createState() => _KyraKeyboardHostState();
}

class _KyraKeyboardHostState extends State<KyraKeyboardHost> with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 220), reverseDuration: const Duration(milliseconds: 150));

  @override
  void initState() {
    super.initState();
    _applyInput();
    KyraKeyboardHost.useSystem.addListener(_applyInput);
    widget.controller.addListener(_sync);
    _anim.addStatusListener((status) {
      // ya a la vista, el campo se sube si el teclado lo tapaba
      if (status == AnimationStatus.completed) {
        unawaited(Future<void>.microtask(() => FocusManager.instance.primaryFocus?.context?.findRenderObject()?.showOnScreen(duration: const Duration(milliseconds: 150))));
      }
    });
  }

  @override
  void didUpdateWidget(KyraKeyboardHost old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_sync);
      widget.controller.addListener(_sync);
      _applyInput();
    }
  }

  /// El teclado de Kyra o, en el modo visitante, el del sistema.
  void _applyInput() {
    if (KyraKeyboardHost.useSystem.value) {
      widget.controller.hide();
      TextInput.restorePlatformInputControl();
    } else {
      TextInput.setInputControl(widget.controller);
    }
  }

  @override
  void dispose() {
    KyraKeyboardHost.useSystem.removeListener(_applyInput);
    widget.controller.removeListener(_sync);
    TextInput.restorePlatformInputControl();
    _anim.dispose();
    super.dispose();
  }

  void _sync() {
    if (widget.controller.visible) {
      if (_anim.status != AnimationStatus.forward && _anim.status != AnimationStatus.completed) unawaited(_anim.forward());
    } else if (_anim.status != AnimationStatus.reverse && _anim.status != AnimationStatus.dismissed) {
      unawaited(_anim.reverse());
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final ctl = widget.controller;
    return ListenableBuilder(
      listenable: Listenable.merge([_anim, ctl]),
      child: widget.child,
      builder: (context, child) {
        final raw = _anim.value;
        final t = Curves.easeOutCubic.transform(raw);
        final height = KyraKeyboard.heightFor(numeric: ctl.numeric, safeBottom: media.padding.bottom);
        final lifted = height * t;
        final leaving = _anim.status == AnimationStatus.reverse;
        return Stack(
          fit: StackFit.expand,
          children: [
            MediaQuery(
              data: media.copyWith(
                viewInsets: media.viewInsets.copyWith(bottom: lifted > media.viewInsets.bottom ? lifted : media.viewInsets.bottom),
                padding: lifted > 0 ? media.padding.copyWith(bottom: 0) : media.padding,
              ),
              child: child!,
            ),
            if (raw > 0)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: height,
                child: TextFieldTapRegion(
                  child: Opacity(
                    opacity: leaving ? SectionMotion.quietOpacity(raw) : SectionMotion.glitchOpacity(t, 12),
                    child: Transform.translate(
                      offset: Offset(0, (1 - t) * height * 0.25),
                      child: Material(type: MaterialType.transparency, child: KyraKeyboard(key: const Key('kyra-keyboard'), controller: ctl)),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  bool get numeric => widget.controller.numeric;
}

/// El teclado dibujado: una barra de arriba (nombre, cursor y esconder) y las filas de teclas cuadradas, con filo de neón, en el estilo de Kyra.
class KyraKeyboard extends StatelessWidget {
  const KyraKeyboard({super.key, required this.controller});

  final KyraKeyboardController controller;

  static const rowHeight = 48.0;
  static const gap = 4.0;
  static const barHeight = 40.0;

  /// Cuánto mide: la barra, las filas (4 de texto o 5 del pad numérico) y el aire de abajo (más la zona de gestos del sistema).
  static double heightFor({required bool numeric, double safeBottom = 0}) => barHeight + (numeric ? 5 : 4) * (rowHeight + gap) + 8 + safeBottom;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final safe = MediaQuery.paddingOf(context).bottom;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => DecoratedBox(
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.94), border: Border(top: BorderSide(color: c.accent.withValues(alpha: 0.7)))),
        child: Padding(
          padding: EdgeInsets.fromLTRB(6, 0, 6, 6 + safe),
          child: Column(
            children: [
              _Bar(controller: controller),
              Expanded(child: controller.numeric ? _numeric(context) : _text(context)),
            ],
          ),
        ),
      ),
    );
  }

  // ---- el teclado de texto ----

  Widget _row(List<Widget> keys) => Expanded(child: Padding(padding: const EdgeInsets.only(bottom: gap), child: Row(children: keys)));

  String _cased(String ch) => controller.shift == ShiftState.off ? ch : ch.toUpperCase();

  Widget _char(String ch, {int flex = 2}) {
    final c = controller;
    final shown = _cased(ch);
    return _Key(
      key: Key('kb-key-$ch'),
      label: shown,
      flex: flex,
      onTap: () => c.type(shown),
      onHold: kKeyVariants.containsKey(ch.toLowerCase()) ? () => c.showVariants([for (final v in kKeyVariants[ch.toLowerCase()]!) _cased(v)]) : null,
    );
  }

  Widget _text(BuildContext context) {
    final c = controller;
    final layer = c.layer;
    final List<List<String>> rows;
    switch (layer) {
      case KeyLayer.letters:
        rows = [
          ['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p'],
          ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l', 'ñ'],
          ['z', 'x', 'c', 'v', 'b', 'n', 'm'],
        ];
      case KeyLayer.symbols:
        rows = [
          ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'],
          ['-', '/', ':', ';', '(', ')', r'$', '&', '@', '"'],
          ['.', ',', '?', '!', "'"],
        ];
      case KeyLayer.more:
        rows = [
          ['[', ']', '{', '}', '#', '%', '^', '*', '+', '='],
          ['_', r'\', '|', '~', '<', '>', '€', '£', '¥', '•'],
          ['.', ',', '?', '!', "'"],
        ];
    }
    final letters = layer == KeyLayer.letters;
    return Column(
      children: [
        _row([for (final k in rows[0]) _char(k)]),
        _row([if (letters) const Spacer(flex: 1), for (final k in rows[1]) _char(k), if (letters) const Spacer(flex: 1)]),
        _row([
          if (letters)
            _Key(key: const Key('kb-shift'), icon: c.shift == ShiftState.locked ? Icons.keyboard_capslock_rounded : Icons.arrow_upward_rounded, flex: 3, kind: c.shift == ShiftState.off ? _KeyKind.special : _KeyKind.active, onTap: c.toggleShift)
          else
            _Key(key: const Key('kb-more'), label: layer == KeyLayer.symbols ? '=\\<' : '123', flex: 3, kind: _KeyKind.special, onTap: () => c.setLayer(layer == KeyLayer.symbols ? KeyLayer.more : KeyLayer.symbols)),
          for (final k in rows[2]) _char(k, flex: letters ? 2 : 3),
          _Key(key: const Key('kb-back'), icon: Icons.backspace_outlined, flex: 3, kind: _KeyKind.special, onTap: c.backspace, repeat: true),
        ]),
        _row([
          _Key(key: const Key('kb-layer'), label: letters ? '?123' : 'ABC', flex: 3, kind: _KeyKind.special, onTap: () => c.setLayer(letters ? KeyLayer.symbols : KeyLayer.letters)),
          _Key(key: const Key('kb-comma'), label: ',', flex: 2, onTap: () => c.type(',')),
          if (c.email) _Key(key: const Key('kb-at'), label: '@', flex: 2, onTap: () => c.type('@')),
          if (c.url) _Key(key: const Key('kb-slash'), label: '/', flex: 2, onTap: () => c.type('/')),
          _Key(key: const Key('kb-space'), label: 'KYRA', flex: 8, kind: _KeyKind.space, onTap: () => c.type(' ')),
          _Key(key: const Key('kb-dot'), label: '.', flex: 2, onTap: () => c.type('.'), onHold: () => c.showVariants(kKeyVariants['.']!)),
          if (c.email || c.url) _Key(key: const Key('kb-com'), label: '.com', flex: 3, onTap: () => c.type('.com')),
          _Key(key: const Key('kb-enter'), icon: _enterIcon(c), flex: 3, kind: _KeyKind.accent, onTap: c.enter),
        ]),
      ],
    );
  }

  // ---- el pad numérico ----

  Widget _numeric(BuildContext context) {
    final c = controller;
    Widget digit(String d) => _Key(key: Key('kb-key-$d'), label: d, flex: 1, onTap: () => c.type(d));
    final sep = c.phone ? '+' : (c.decimal ? '.' : (c.signed ? '-' : ','));
    return Column(
      children: [
        _row([digit('1'), digit('2'), digit('3')]),
        _row([digit('4'), digit('5'), digit('6')]),
        _row([digit('7'), digit('8'), digit('9')]),
        _row([
          _Key(key: const Key('kb-sep'), label: sep, flex: 1, kind: _KeyKind.special, onTap: () => c.type(sep)),
          digit('0'),
          _Key(key: const Key('kb-back'), icon: Icons.backspace_outlined, flex: 1, kind: _KeyKind.special, onTap: c.backspace, repeat: true),
        ]),
        _row([
          if (c.phone) _Key(key: const Key('kb-star'), label: '*', flex: 1, kind: _KeyKind.special, onTap: () => c.type('*')),
          if (c.phone) _Key(key: const Key('kb-hash'), label: '#', flex: 1, kind: _KeyKind.special, onTap: () => c.type('#')),
          if (!c.phone && c.signed && c.decimal) _Key(key: const Key('kb-dot'), label: '.', flex: 1, kind: _KeyKind.special, onTap: () => c.type('.')),
          _Key(key: const Key('kb-enter'), icon: _enterIcon(c), flex: 2, kind: _KeyKind.accent, onTap: c.enter),
        ]),
      ],
    );
  }

  IconData _enterIcon(KyraKeyboardController c) => switch (c.config.inputAction) {
    TextInputAction.search => Icons.search_rounded,
    TextInputAction.next => Icons.keyboard_tab_rounded,
    TextInputAction.send => Icons.send_rounded,
    TextInputAction.go => Icons.arrow_forward_rounded,
    TextInputAction.newline => Icons.keyboard_return_rounded,
    _ => c.multiline ? Icons.keyboard_return_rounded : Icons.check_rounded,
  };
}

/// La barra de arriba: el nombre del teclado, o las variantes de la tecla que se mantiene presionada; y los botones del cursor y de esconder.
class _Bar extends StatelessWidget {
  const _Bar({required this.controller});

  final KyraKeyboardController controller;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final variants = controller.variants;
    Widget tool(String id, IconData icon, VoidCallback onTap) => Semantics(
      button: true,
      label: id,
      child: GestureDetector(
        key: Key('kb-$id'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(width: 44, height: KyraKeyboard.barHeight, child: Icon(icon, size: 22, color: c.ink)),
      ),
    );
    return SizedBox(
      height: KyraKeyboard.barHeight,
      child: Row(
        children: [
          Expanded(
            child: variants.isEmpty
                ? Padding(padding: const EdgeInsets.only(left: 6), child: Text('> KYRA//INPUT', maxLines: 1, style: TextStyle(fontFamily: monoFont, fontSize: 15, letterSpacing: 1.2, color: c.dim)))
                : Row(
                    key: const Key('kb-variants'),
                    children: [
                      for (final v in variants) _Key(key: Key('kb-variant-$v'), label: v, flex: 1, kind: _KeyKind.active, onTap: () => controller.type(v)),
                    ],
                  ),
          ),
          if (variants.isEmpty) ...[
            tool('left', Icons.chevron_left_rounded, () => controller.moveCursor(-1)),
            tool('right', Icons.chevron_right_rounded, () => controller.moveCursor(1)),
          ] else
            tool('close-variants', Icons.close_rounded, controller.closeVariants),
          tool('hide', Icons.keyboard_hide_outlined, controller.dismiss),
        ],
      ),
    );
  }
}

enum _KeyKind { normal, special, accent, active, space }

/// Una tecla: un cuadrado de esquinas rectas con filo fino. Se enciende mientras se pulsa y escribe al soltar; mantenida, abre sus variantes
/// (si tiene) y la de borrar se repite.
class _Key extends StatefulWidget {
  const _Key({super.key, this.label, this.icon, required this.flex, required this.onTap, this.onHold, this.kind = _KeyKind.normal, this.repeat = false});

  final String? label;
  final IconData? icon;
  final int flex;
  final VoidCallback onTap;
  final VoidCallback? onHold;
  final _KeyKind kind;
  final bool repeat;

  @override
  State<_Key> createState() => _KeyState();
}

class _KeyState extends State<_Key> {
  bool _down = false;
  bool _held = false;
  Timer? _timer;

  static const _holdAfter = Duration(milliseconds: 380);
  static const _repeatEvery = Duration(milliseconds: 55);

  void _press() {
    setState(() => _down = true);
    _held = false;
    _timer?.cancel();
    if (widget.repeat) {
      widget.onTap();
      _held = true; // ya escribió al pulsar: al soltar no repite
      _timer = Timer(_holdAfter, () => _timer = Timer.periodic(_repeatEvery, (_) => widget.onTap()));
    } else if (widget.onHold != null) {
      _timer = Timer(_holdAfter, () {
        _held = true;
        widget.onHold!();
      });
    }
  }

  void _release({required bool cancel}) {
    _timer?.cancel();
    if (mounted) setState(() => _down = false);
    if (!cancel && !_held) widget.onTap();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (fill, edge, ink) = switch (widget.kind) {
      _KeyKind.accent => (c.accent, c.accent, c.onAccent),
      _KeyKind.active => (c.accent.withValues(alpha: 0.28), c.accent, c.accent),
      _KeyKind.special => (c.accent.withValues(alpha: 0.12), c.accent.withValues(alpha: 0.45), c.accent),
      _KeyKind.space => (Colors.white.withValues(alpha: 0.03), c.edge, c.dim),
      _KeyKind.normal => (Colors.white.withValues(alpha: 0.05), c.edge, c.ink),
    };
    final pressed = _down;
    return Expanded(
      flex: widget.flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: KyraKeyboard.gap / 2),
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (_) => _press(),
          onPointerUp: (_) => _release(cancel: false),
          onPointerCancel: (_) => _release(cancel: true),
          child: Semantics(
            button: true,
            label: widget.label ?? 'tecla',
            excludeSemantics: true,
            child: DecoratedBox(
              decoration: BoxDecoration(color: pressed ? c.accent : fill, border: Border.all(color: pressed ? c.accent : edge)),
              child: Center(
                child: widget.icon != null
                    ? Icon(widget.icon, size: 22, color: pressed ? c.onAccent : ink)
                    : Text(
                        widget.label!,
                        maxLines: 1,
                        style: widget.kind == _KeyKind.normal || widget.kind == _KeyKind.active
                            ? display(size: 22, color: pressed ? c.onAccent : ink, weight: FontWeight.w500)
                            : TextStyle(fontFamily: monoFont, fontSize: 15, letterSpacing: widget.kind == _KeyKind.space ? 2 : 0.4, fontWeight: FontWeight.w600, color: pressed ? c.onAccent : ink),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
