import 'dart:async';

import 'package:kyora_chat/ui/widgets/hack_text.dart';
import 'package:kyora_chat/ui/widgets/radial_menu.dart';

/// Para toda la suite: los textos salen enteros (sin el efecto de escritura), así las pruebas leen el texto final. Las pruebas del efecto lo
/// encienden en su propio grupo.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  HackText.enabled = false;
  ReactorSpin.enabled = false; // el reactor gira sin parar: se deja quieto para que `pumpAndSettle` termine
  await testMain();
}
