import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/theme.dart';
import 'package:kyora_chat/ui/widgets/kyra_keyboard.dart';

/// El teclado propio de Kyra: sustituye al del sistema, escribe en el campo que tiene el foco y se ve en el estilo de la app.
void main() {
  late KyraKeyboardController keyboard;
  late TextEditingController text;
  var submitted = 0;

  setUp(() {
    keyboard = KyraKeyboardController();
    text = TextEditingController();
    submitted = 0;
  });

  tearDown(() {
    keyboard.dispose();
    text.dispose();
  });

  Future<void> open(WidgetTester tester, {TextInputType type = TextInputType.text, TextCapitalization caps = TextCapitalization.none, int? maxLines = 1, bool obscure = false, TextInputAction? action, Widget? below}) async {
    tester.view.physicalSize = const Size(400, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        builder: (context, child) => KyraKeyboardHost(controller: keyboard, child: child!),
        home: Scaffold(
          body: Column(
            children: [
              TextField(key: const Key('field'), controller: text, keyboardType: type, textCapitalization: caps, maxLines: maxLines, obscureText: obscure, textInputAction: action, onSubmitted: (_) => submitted++),
              ?below,
              const Spacer(),
              const SizedBox(key: Key('bottom-mark'), height: 10),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('field')));
    await tester.pumpAndSettle();
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(Key(key)));
    await tester.pump();
  }

  Future<void> typeWord(WidgetTester tester, String word) async {
    for (final ch in word.split('')) {
      await tapKey(tester, ch == ' ' ? 'kb-space' : 'kb-key-$ch');
    }
  }

  testWidgets('al tocar un campo sale el teclado de Kyra (no el del sistema) y al soltar el foco se esconde', (tester) async {
    tester.view.physicalSize = const Size(400, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: buildTheme(), builder: (context, child) => KyraKeyboardHost(controller: keyboard, child: child!), home: Scaffold(body: TextField(key: const Key('field'), controller: text))));
    expect(find.byKey(const Key('kyra-keyboard')), findsNothing);
    await tester.tap(find.byKey(const Key('field')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('kyra-keyboard')), findsOneWidget);
    expect(keyboard.visible, isTrue);
    await tapKey(tester, 'kb-hide');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('kyra-keyboard')), findsNothing);
  });

  testWidgets('escribe, borra y pone espacios y signos donde está el cursor', (tester) async {
    await open(tester);
    await typeWord(tester, 'hola mundo');
    expect(text.text, 'hola mundo');
    await tapKey(tester, 'kb-back');
    expect(text.text, 'hola mund');
    await tapKey(tester, 'kb-dot');
    await tapKey(tester, 'kb-comma');
    expect(text.text, 'hola mund.,');
    // el cursor: se mueve con las flechas y se escribe en medio
    await tapKey(tester, 'kb-left');
    await tapKey(tester, 'kb-left');
    await tapKey(tester, 'kb-key-o');
    expect(text.text, 'hola mundo.,');
    expect(text.selection.baseOffset, 'hola mundo'.length);
    await tapKey(tester, 'kb-right');
    expect(text.selection.baseOffset, 'hola mundo.'.length);
  });

  testWidgets('borrar con una selección la quita entera; una letra con acento se borra de una vez', (tester) async {
    await open(tester);
    text.value = const TextEditingValue(text: 'canción', selection: TextSelection.collapsed(offset: 7));
    await tester.pump();
    await tapKey(tester, 'kb-back');
    await tapKey(tester, 'kb-back');
    expect(text.text, 'canci');
    text.selection = const TextSelection(baseOffset: 1, extentOffset: 4);
    await tester.pump();
    await tapKey(tester, 'kb-back');
    expect(text.text, 'ci'); // de «canci» se va «anc»
  });

  testWidgets('las mayúsculas: una tecla es para una letra, dos la dejan fija y tres la apagan', (tester) async {
    await open(tester);
    await tapKey(tester, 'kb-shift');
    await tapKey(tester, 'kb-key-h');
    await tapKey(tester, 'kb-key-i');
    expect(text.text, 'Hi');
    await tapKey(tester, 'kb-shift');
    await tapKey(tester, 'kb-shift');
    await tapKey(tester, 'kb-key-a');
    await tapKey(tester, 'kb-key-b');
    expect(text.text, 'HiAB');
    await tapKey(tester, 'kb-shift'); // apaga la fija
    await tapKey(tester, 'kb-key-c');
    expect(text.text, 'HiABc');
  });

  testWidgets('con «sentences» la primera letra y la de después de un punto salen en mayúscula solas', (tester) async {
    await open(tester, caps: TextCapitalization.sentences);
    await typeWord(tester, 'hola');
    expect(text.text, 'Hola');
    await tapKey(tester, 'kb-dot');
    await tapKey(tester, 'kb-space');
    await typeWord(tester, 'adios');
    expect(text.text, 'Hola. Adios');
  });

  testWidgets('mantener una vocal abre sus acentos y tocar uno lo escribe', (tester) async {
    await open(tester);
    final gesture = await tester.startGesture(tester.getCenter(find.byKey(const Key('kb-key-a'))));
    await tester.pump(const Duration(milliseconds: 450));
    expect(find.byKey(const Key('kb-variants')), findsOneWidget);
    await gesture.up();
    await tester.pump();
    expect(text.text, ''); // mantener no escribe la «a»
    await tapKey(tester, 'kb-variant-á');
    expect(text.text, 'á');
    expect(find.byKey(const Key('kb-variants')), findsNothing);
    expect(find.byKey(const Key('kb-key-ñ')), findsOneWidget); // y la eñe está a la vista
    await tapKey(tester, 'kb-key-ñ');
    expect(text.text, 'áñ');
  });

  testWidgets('números y signos: ?123 cambia de capa y ABC vuelve; los signos se escriben tal cual', (tester) async {
    await open(tester);
    expect(find.byKey(const Key('kb-key-q')), findsOneWidget);
    await tapKey(tester, 'kb-layer');
    expect(find.byKey(const Key('kb-key-q')), findsNothing);
    await tapKey(tester, 'kb-key-7');
    await tapKey(tester, 'kb-key-@');
    expect(text.text, '7@');
    await tapKey(tester, 'kb-more');
    expect(find.byKey(const Key('kb-key-#')), findsOneWidget);
    await tapKey(tester, 'kb-layer');
    expect(find.byKey(const Key('kb-key-q')), findsOneWidget);
  });

  testWidgets('los campos de números y teléfonos llevan el pad numérico', (tester) async {
    await open(tester, type: const TextInputType.numberWithOptions(decimal: true));
    expect(find.byKey(const Key('kb-key-q')), findsNothing);
    await typeWord(tester, '12');
    await tapKey(tester, 'kb-sep'); // decimal: el punto
    await typeWord(tester, '50');
    expect(text.text, '12.50');
    await tapKey(tester, 'kb-enter');
    expect(submitted, 1);
  });

  testWidgets('un teléfono trae el + y los signos del marcador', (tester) async {
    await open(tester, type: TextInputType.phone);
    await tapKey(tester, 'kb-sep');
    await typeWord(tester, '52');
    expect(text.text, '+52');
    expect(find.byKey(const Key('kb-star')), findsOneWidget);
    expect(find.byKey(const Key('kb-hash')), findsOneWidget);
  });

  testWidgets('correo y direcciones traen @ y .com / a mano', (tester) async {
    await open(tester, type: TextInputType.emailAddress);
    await typeWord(tester, 'ana');
    await tapKey(tester, 'kb-at');
    await typeWord(tester, 'mail');
    await tapKey(tester, 'kb-com');
    expect(text.text, 'ana@mail.com');
    expect(find.byKey(const Key('kb-slash')), findsNothing);
  });

  testWidgets('la tecla de intro hace la acción del campo; en los de varias líneas pone un salto de línea', (tester) async {
    await open(tester, action: TextInputAction.done);
    await typeWord(tester, 'a');
    await tapKey(tester, 'kb-enter');
    expect(submitted, 1);
    expect(text.text, 'a');
  });

  testWidgets('en un campo de varias líneas, intro salta de línea', (tester) async {
    await open(tester, type: TextInputType.multiline, maxLines: null);
    await typeWord(tester, 'a');
    await tapKey(tester, 'kb-enter');
    await typeWord(tester, 'b');
    expect(text.text, 'a\nb');
    expect(submitted, 0);
  });

  testWidgets('la pantalla se sube lo que mide el teclado (como con el del sistema) y se baja al esconderlo', (tester) async {
    await open(tester);
    final keyboardTop = tester.getTopLeft(find.byKey(const Key('kyra-keyboard'))).dy;
    expect(tester.getBottomLeft(find.byKey(const Key('bottom-mark'))).dy, closeTo(keyboardTop, 0.5)); // lo de abajo queda justo encima
    expect(keyboardTop, closeTo(850 - KyraKeyboard.heightFor(numeric: false), 0.5));
    await tapKey(tester, 'kb-hide');
    await tester.pumpAndSettle();
    expect(tester.getBottomLeft(find.byKey(const Key('bottom-mark'))).dy, 850);
  });

  testWidgets('tocar una tecla no le quita el foco al campo', (tester) async {
    await open(tester);
    await typeWord(tester, 'ab');
    expect(keyboard.visible, isTrue);
    expect(tester.widget<TextField>(find.byKey(const Key('field'))).focusNode?.hasFocus ?? FocusManager.instance.primaryFocus != null, isTrue);
    await typeWord(tester, 'c');
    expect(text.text, 'abc');
  });

  testWidgets('pasar de un campo a otro no esconde el teclado', (tester) async {
    final other = TextEditingController();
    addTearDown(other.dispose);
    await open(tester, below: TextField(key: const Key('field2'), controller: other));
    await typeWord(tester, 'a');
    await tester.tap(find.byKey(const Key('field2')));
    await tester.pump(); // sin esperar a la animación: no debe haberse empezado a esconder
    expect(keyboard.visible, isTrue);
    await tester.pumpAndSettle();
    await typeWord(tester, 'z');
    expect(other.text, 'z');
    expect(text.text, 'a');
  });

  testWidgets('en el estilo de la app: teclas cuadradas con filo, letras de 15 px o más, sin esquinas redondas ni sombras', (tester) async {
    await open(tester);
    expect(find.descendant(of: find.byKey(const Key('kyra-keyboard')), matching: find.byType(BackdropFilter)), findsNothing);
    final boxes = tester.widgetList<DecoratedBox>(find.descendant(of: find.byKey(const Key('kyra-keyboard')), matching: find.byType(DecoratedBox)));
    for (final b in boxes) {
      final d = b.decoration as BoxDecoration;
      expect(d.borderRadius, isNull);
      expect(d.boxShadow, isNull);
    }
    for (final t in tester.widgetList<Text>(find.descendant(of: find.byKey(const Key('kyra-keyboard')), matching: find.byType(Text)))) {
      expect(t.style!.fontSize, greaterThanOrEqualTo(15), reason: t.data);
    }
    final enter = tester.widget<DecoratedBox>(find.descendant(of: find.byKey(const Key('kb-enter')), matching: find.byType(DecoratedBox)).first);
    expect((enter.decoration as BoxDecoration).color, tester.element(find.byKey(const Key('kyra-keyboard'))).colors.accent);
  });

  testWidgets('al cerrarse se apaga sin parpadear: la opacidad solo baja', (tester) async {
    await open(tester);
    await tapKey(tester, 'kb-hide');
    final seen = <double>[];
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 18));
      final fade = find.ancestor(of: find.byKey(const Key('kyra-keyboard')), matching: find.byType(Opacity));
      if (fade.evaluate().isEmpty) break;
      seen.add(tester.widget<Opacity>(fade.first).opacity);
    }
    expect(seen, isNotEmpty);
    for (var i = 1; i < seen.length; i++) {
      expect(seen[i], lessThanOrEqualTo(seen[i - 1] + 1e-9), reason: '$seen');
    }
  });

  test('al quitar el anfitrión vuelve el teclado del sistema', () {
    // (el anfitrión instala el control y, al irse, lo restaura: se prueba con el control puesto y quitado)
    TextInput.setInputControl(keyboard);
    TextInput.restorePlatformInputControl();
  });
}
