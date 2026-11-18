import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../data/chat_backend.dart';
import '../data/improvement_backend.dart';
import '../models/improvement.dart';

/// En qué punto está la lista: cargando, lista o con un error (sin conexión, sin sesión, falta la tabla en Supabase…).
enum ImprovementsState { loading, ready, error }

/// Las **mejoras pendientes** del proyecto, en Supabase (las comparte con Merida). Lo que se anota o se termina se ve al instante; si el servidor
/// no lo acepta, se deshace y se avisa. «Hecho» borra la mejora de verdad.
class ImprovementsController extends ChangeNotifier {
  ImprovementsController(this._backend, {DateTime Function()? now, String Function()? newId})
    : _now = now ?? (() => DateTime.now().toUtc()),
      _newId = newId ?? (() => const Uuid().v4());

  final ImprovementBackend _backend;
  final DateTime Function() _now;
  final String Function() _newId;

  ImprovementsState state = ImprovementsState.loading;

  /// Lo que falló al leer (con `state == error`).
  String? error;

  /// Lo que falló al anotar o terminar una (se enseña como aviso y se quita al siguiente cambio que sale bien).
  String? notice;

  List<Improvement> _items = const [];
  bool _disposed = false;

  /// Las pendientes, de la más nueva a la más antigua.
  List<Improvement> get items => _items;

  void _tell() {
    if (!_disposed) notifyListeners();
  }

  static List<Improvement> _sorted(Iterable<Improvement> list) => list.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  /// Vuelve a leer la lista de Supabase.
  Future<void> refresh() async {
    if (_items.isEmpty) {
      state = ImprovementsState.loading;
      _tell();
    }
    try {
      _items = _sorted(await _backend.list());
      state = ImprovementsState.ready;
      error = null;
    } on ChatException catch (e) {
      state = ImprovementsState.error;
      error = e.message;
    }
    _tell();
  }

  /// Anota una mejora. Devuelve el aviso si lo escrito no vale (`null` si salió bien). Si Supabase no la acepta, se quita y se avisa en [notice].
  Future<String?> add({required String section, String functions = '', String description = ''}) async {
    final problem = Improvement.validate(section: section, functions: functions, description: description);
    if (problem != null) return problem;
    final item = Improvement(id: _newId(), section: section.trim(), functions: functions.trim(), description: description.trim(), createdAt: _now());
    _items = _sorted([..._items, item]);
    state = ImprovementsState.ready;
    _tell();
    try {
      await _backend.add(item);
      notice = null;
    } on ChatException catch (e) {
      _items = [for (final i in _items) if (i.id != item.id) i];
      notice = 'No se guardó la mejora. ${e.message}';
    }
    _tell();
    return null;
  }

  /// «Hecho»: sale de la lista al instante y se borra de la base de datos; si falla, vuelve y se avisa en [notice].
  Future<void> finish(Improvement item) async {
    _items = [for (final i in _items) if (i.id != item.id) i];
    _tell();
    try {
      await _backend.finish(item.id);
      notice = null;
    } on ChatException catch (e) {
      _items = _sorted([..._items, item]);
      notice = 'No se pudo borrar la mejora. ${e.message}';
    }
    _tell();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
