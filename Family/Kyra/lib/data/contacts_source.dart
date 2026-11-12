import 'package:flutter/services.dart';

import '../util/format.dart';

/// Una persona de la agenda del teléfono, con sus números.
class Contact {
  const Contact({required this.id, required this.name, required this.phones});

  final String id;
  final String name;

  /// Sus números, tal como están en la agenda (sin repetir).
  final List<String> phones;

  /// La letra con la que se agrupa («#» si no empieza por una letra).
  String get letter => letterOf(name);

  /// Su primera letra o cifra, para el cuadro de la lista.
  String get initial {
    final trimmed = name.trim();
    return trimmed.isEmpty ? '#' : String.fromCharCode(trimmed.runes.first).toUpperCase();
  }

  factory Contact.fromMap(Map<Object?, Object?> map) => Contact(
    id: '${map['id']}',
    name: (map['name'] as String?) ?? '',
    phones: [for (final p in (map['phones'] as List<Object?>? ?? const [])) '$p'],
  );
}

/// El número listo para marcar: solo cifras (y el «+» del principio, si lo lleva).
String dialNumber(String raw) {
  final plus = raw.trim().startsWith('+');
  final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
  return plus ? '+$digits' : digits;
}

/// El número para el enlace de WhatsApp (`wa.me`): solo cifras y con el prefijo del país, sin «+» ni «00» delante.
String whatsappNumber(String raw) {
  var digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.startsWith('00')) digits = digits.substring(2);
  return digits;
}

/// La agenda del teléfono: pedir el permiso, leer los contactos y las dos cosas que se hacen con un número (llamar y abrir su chat de WhatsApp).
abstract class ContactsSource {
  /// ¿Ya se dio el permiso de leer los contactos?
  Future<bool> hasPermission();

  /// Pide el permiso (el aviso del sistema). `true` si se dio.
  Future<bool> requestPermission();

  /// Todos los contactos con teléfono, por nombre.
  Future<List<Contact>> list();

  /// Abre el marcador con el número escrito. `false` si no se pudo.
  Future<bool> call(String number);

  /// Abre el chat de WhatsApp con ese número. `false` si no se pudo.
  Future<bool> whatsapp(String number);
}

/// El real: la parte de Android está en `MainActivity.kt` (canal `kyora/contacts`).
class AndroidContactsSource implements ContactsSource {
  static const _channel = MethodChannel('kyora/contacts');

  Future<bool> _flag(String method, [Map<String, Object?>? args]) async {
    try {
      return (await _channel.invokeMethod<bool>(method, args)) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<bool> hasPermission() => _flag('hasPermission');

  @override
  Future<bool> requestPermission() => _flag('request');

  @override
  Future<List<Contact>> list() async {
    final raw = await _channel.invokeListMethod<Map<Object?, Object?>>('list') ?? const [];
    return [for (final item in raw) Contact.fromMap(item)];
  }

  @override
  Future<bool> call(String number) => _flag('call', {'number': dialNumber(number)});

  @override
  Future<bool> whatsapp(String number) => _flag('whatsapp', {'number': whatsappNumber(number)});
}

/// Una agenda de mentira, para las pruebas.
class FakeContactsSource implements ContactsSource {
  FakeContactsSource(this.contacts, {this.granted = true, this.grantsOnRequest = true});

  List<Contact> contacts;
  bool granted;

  /// Si al pedir el permiso se concede.
  bool grantsOnRequest;

  /// Si leer los contactos falla.
  bool failing = false;

  final List<String> calls = [];
  final List<String> chats = [];
  int requests = 0;
  int reads = 0;

  @override
  Future<bool> hasPermission() async => granted;

  @override
  Future<bool> requestPermission() async {
    requests++;
    if (grantsOnRequest) granted = true;
    return granted;
  }

  @override
  Future<List<Contact>> list() async {
    reads++;
    if (failing) throw PlatformException(code: 'contacts_failed', message: 'No se pudieron leer los contactos.');
    return contacts;
  }

  @override
  Future<bool> call(String number) async {
    calls.add(dialNumber(number));
    return true;
  }

  @override
  Future<bool> whatsapp(String number) async {
    chats.add(whatsappNumber(number));
    return true;
  }
}
