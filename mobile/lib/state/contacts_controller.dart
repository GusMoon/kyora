import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../data/contacts_source.dart';
import '../util/format.dart';

/// En qué punto está la agenda: sin mirar, pidiendo el permiso, sin permiso, leyendo, lista o con un fallo.
enum ContactsStatus { idle, denied, loading, ready, failed }

/// Los contactos del teléfono: pide el permiso la primera vez, los lee, los busca por nombre o número y hace lo que se pide de cada uno
/// (llamar, abrir su chat de WhatsApp).
class ContactsController extends ChangeNotifier {
  ContactsController(this._source);

  final ContactsSource _source;

  ContactsStatus _status = ContactsStatus.idle;
  List<Contact> _all = const [];
  String _query = '';
  String? _error;
  bool _disposed = false;

  ContactsStatus get status => _status;
  String? get error => _error;
  String get query => _query;

  /// Cuántos contactos hay en total (sin filtrar).
  int get total => _all.length;

  /// Los contactos que casan con lo buscado (por nombre o por los números), de la A a la Z.
  List<Contact> get contacts {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _all;
    final digits = q.replaceAll(RegExp(r'[^0-9]'), '');
    return [
      for (final c in _all)
        if (c.name.toLowerCase().contains(q) || (digits.isNotEmpty && c.phones.any((p) => p.replaceAll(RegExp(r'[^0-9]'), '').contains(digits)))) c,
    ];
  }

  void _set(ContactsStatus status, {String? error}) {
    if (_disposed) return;
    _status = status;
    _error = error;
    notifyListeners();
  }

  /// Al abrir la sección: si ya hay permiso, lee los contactos; si no, queda a la espera de que se pida.
  Future<void> start() async {
    if (_status == ContactsStatus.loading) return;
    final granted = await _source.hasPermission();
    if (granted) {
      await refresh();
    } else {
      _set(ContactsStatus.denied);
    }
  }

  /// Pide el permiso (el aviso del sistema) y, si se da, lee los contactos.
  Future<void> grant() async {
    final granted = await _source.requestPermission();
    if (granted) {
      await refresh();
    } else {
      _set(ContactsStatus.denied);
    }
  }

  /// Vuelve a leer la agenda.
  Future<void> refresh() async {
    _set(ContactsStatus.loading);
    try {
      final read = await _source.list();
      read.sort((a, b) => compareAppNames(a.name, b.name));
      _all = read;
      _set(ContactsStatus.ready);
    } on PlatformException catch (e) {
      _set(ContactsStatus.failed, error: e.message ?? 'No se pudieron leer los contactos.');
    } catch (_) {
      _set(ContactsStatus.failed, error: 'No se pudieron leer los contactos.');
    }
  }

  void search(String text) {
    if (text == _query) return;
    _query = text;
    notifyListeners();
  }

  /// Abre el marcador con el número de ese contacto.
  Future<bool> call(String number) => _source.call(number);

  /// Abre el chat de WhatsApp con ese número.
  Future<bool> whatsapp(String number) => _source.whatsapp(number);

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
