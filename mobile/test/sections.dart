import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Desliza de lado `times` secciones (a la izquierda: la siguiente; a la derecha: la anterior), como lo haría el dedo.
Future<void> swipeSections(WidgetTester tester, int times) async {
  for (var i = 0; i < times.abs(); i++) {
    await tester.fling(find.byKey(const Key('sections-pager')), Offset(times > 0 ? -300 : 300, 0), 1500);
    await tester.pumpAndSettle();
  }
}
