import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/data/dock_store.dart';
import 'package:kyora_chat/data/installed_apps.dart';
import 'package:kyora_chat/state/dock_controller.dart';
import 'package:kyora_chat/util/format.dart';

final _png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');

InstalledApp app(String package, String label) => InstalledApp(package: package, label: label, icon: Uint8List.fromList(_png));

void main() {
  group('el orden alfabético', () {
    test('sin mayúsculas ni acentos, y la «ñ» cuenta como «n»', () {
      expect(alphaKey('Álamo'), 'alamo');
      expect(alphaKey('Ñandú'), 'nandu');
      expect(alphaKey('ÓPERA'), 'opera');
      expect(letterOf('Ñandú'), 'N');
      expect(letterOf('álbum'), 'A');
      expect(letterOf('zeta'), 'Z');
    });

    test('lo que no empieza por letra va al final bajo «#» (los símbolos del principio no cuentan)', () {
      expect(letterOf('1Password'), '#');
      expect(letterOf('9GAG'), '#');
      expect(letterOf('(Mi app)'), 'M');
      expect(letterOf(''), '#');
      final names = ['Zeta', '1Password', 'alfa', 'Beta', 'Álamo', 'Ñandú', 'Charlie']..sort(compareAppNames);
      expect(names, ['Álamo', 'alfa', 'Beta', 'Charlie', 'Ñandú', 'Zeta', '1Password']);
    });

    test('dos nombres iguales sin acento se desempatan sin perderse', () {
      final names = ['Cámara', 'Camara', 'cámara']..sort(compareAppNames);
      expect(names, hasLength(3));
    });

    test('DockController.alphabetical ordena todas las instaladas', () async {
      final apps = FakeInstalledApps([app('z', 'Zeta'), app('a', 'alfa'), app('n', 'Ñandú'), app('1', '1Password'), app('b', 'Beta')]);
      final dock = DockController(MemoryDockStore(), apps);
      addTearDown(dock.dispose);
      await dock.refresh();
      expect(dock.alphabetical.map((a) => a.label), ['alfa', 'Beta', 'Ñandú', 'Zeta', '1Password']);
    });
  });
}
