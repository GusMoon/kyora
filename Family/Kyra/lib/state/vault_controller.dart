import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/vault_source.dart';

/// Cómo se ve lo de dentro de la carpeta: en cuadrícula (la carpeta de ahora, con las imágenes en grande) o en árbol (todas las carpetas
/// a la vez, abriéndose en su sitio).
enum VaultView { grid, tree }

/// Una fila del árbol: lo que es y a qué profundidad está.
class VaultRow {
  const VaultRow(this.entry, this.depth, {this.expanded = false, this.loading = false});

  final VaultEntry entry;
  final int depth;
  final bool expanded;
  final bool loading;
}

/// El Vault: una carpeta elegida del almacenamiento, que se recorre entrando en las carpetas (o en árbol) y de la que se ven las imágenes tal
/// cual son. Recuerda la carpeta y el modo.
class VaultController extends ChangeNotifier {
  VaultController(this._source, this._store) : _root = _store.loadFolder(), _view = _store.loadTree() ? VaultView.tree : VaultView.grid;

  final VaultSource _source;
  final VaultStore _store;

  VaultFolder? _root;
  VaultView _view;

  /// Las carpetas por las que se ha entrado desde la raíz (la última es la de ahora).
  final List<VaultEntry> _trail = [];
  List<VaultEntry> _entries = const [];
  bool _loading = false;
  String? _error;
  bool _lost = false;
  bool _disposed = false;
  int _generation = 0;

  // el árbol: lo abierto y lo que tiene cada carpeta
  final Set<String> _open = {};
  final Set<String> _opening = {};
  final Map<String, List<VaultEntry>> _children = {};

  // las imágenes reducidas ya pedidas
  final Map<String, Future<Uint8List>> _thumbs = {};

  /// La carpeta elegida (`null` hasta que se elige una).
  VaultFolder? get root => _root;
  VaultView get view => _view;
  bool get loading => _loading;
  String? get error => _error;

  /// La carpeta se perdió (se borró o Android ya no deja leerla): hay que elegirla otra vez.
  bool get lost => _lost;

  /// Las carpetas por las que se ha entrado.
  List<VaultEntry> get trail => List.unmodifiable(_trail);

  /// ¿Se puede subir de carpeta?
  bool get canGoUp => _trail.isNotEmpty;

  /// Lo que hay en la carpeta de ahora, ordenado.
  List<VaultEntry> get entries => _entries;

  /// Las imágenes de la carpeta de ahora que se pueden enseñar (para pasar de una a otra).
  List<VaultEntry> get images => [for (final e in _entries) if (e.canShow) e];

  /// La carpeta de ahora (la última por la que se entró) o `null` en la raíz.
  String? get currentUri => _trail.isEmpty ? null : _trail.last.uri;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  // ---- elegir la carpeta ----

  /// Abre el selector del sistema; si se elige una carpeta, es la del Vault y se lee. Devuelve `true` si se eligió.
  Future<bool> pick() async {
    try {
      final picked = await _source.pickFolder();
      if (picked == null) return false;
      await _use(picked);
      return true;
    } on VaultException catch (e) {
      _error = e.message;
      _changed();
      return false;
    }
  }

  Future<void> _use(VaultFolder folder) async {
    _root = folder;
    _trail.clear();
    _open.clear();
    _children.clear();
    _thumbs.clear();
    await _store.saveFolder(folder);
    await refresh();
  }

  /// Olvida la carpeta elegida (no toca nada del almacenamiento).
  Future<void> forget() async {
    _generation++;
    _root = null;
    _trail.clear();
    _entries = const [];
    _rootEntries = const [];
    _open.clear();
    _children.clear();
    _thumbs.clear();
    _error = null;
    _lost = false;
    _loading = false;
    await _store.saveFolder(null);
    _changed();
  }

  // ---- recorrer ----

  /// Lee lo que hay en la carpeta de ahora (la raíz, o la última a la que se entró).
  Future<void> refresh() async {
    final root = _root;
    if (root == null) return;
    if (_view == VaultView.tree) return loadTree();
    final generation = ++_generation;
    _loading = true;
    _error = null;
    _lost = false;
    _changed();
    try {
      final read = await _source.list(root.uri, dirUri: currentUri);
      if (generation != _generation) return;
      _entries = read..sort(compareVaultEntries);
    } on VaultException catch (e) {
      if (generation != _generation) return;
      _entries = const [];
      _error = e.message;
      _lost = e.lost;
    }
    _loading = false;
    _changed();
  }

  /// Entra en una carpeta de la lista.
  Future<void> enter(VaultEntry folder) async {
    if (!folder.isDir) return;
    _trail.add(folder);
    await refresh();
  }

  /// Sube una carpeta.
  Future<void> up() async {
    if (_trail.isEmpty) return;
    _trail.removeLast();
    await refresh();
  }

  /// Vuelve a la carpeta `depth` del camino: cuántas carpetas se mantienen (0 = la raíz).
  Future<void> goTo(int depth) async {
    if (depth < 0 || depth >= _trail.length) return;
    _trail.removeRange(depth, _trail.length);
    await refresh();
  }

  // ---- el modo ----

  Future<void> setView(VaultView view) async {
    if (view == _view) return;
    _view = view;
    await _store.saveTree(view == VaultView.tree);
    _changed();
    if (_root != null) await refresh();
  }

  Future<void> toggleView() => setView(_view == VaultView.grid ? VaultView.tree : VaultView.grid);

  // ---- el árbol ----

  /// Lo que hay en la raíz: el árbol siempre parte de la raíz elegida.
  List<VaultEntry> _rootEntries = const [];

  /// Las filas del árbol, de arriba abajo: la raíz y, dentro de cada carpeta abierta, sus hijos (más a la derecha).
  List<VaultRow> get rows {
    final out = <VaultRow>[];
    void walk(List<VaultEntry> list, int depth) {
      for (final entry in list) {
        final open = entry.isDir && _open.contains(entry.uri);
        out.add(VaultRow(entry, depth, expanded: open, loading: entry.isDir && _opening.contains(entry.uri)));
        if (open) walk(_children[entry.uri] ?? const [], depth + 1);
      }
    }

    walk(_rootEntries, 0);
    return out;
  }

  /// Lee la raíz para el árbol (lo que estaba abierto se cierra).
  Future<void> loadTree() async {
    final root = _root;
    if (root == null) return;
    _open.clear();
    _children.clear();
    _loading = true;
    _error = null;
    _lost = false;
    _changed();
    try {
      _rootEntries = (await _source.list(root.uri))..sort(compareVaultEntries);
    } on VaultException catch (e) {
      _rootEntries = const [];
      _error = e.message;
      _lost = e.lost;
    }
    _loading = false;
    _changed();
  }

  /// Abre o cierra una carpeta del árbol (la primera vez, leyendo lo que tiene).
  Future<void> toggle(VaultEntry folder) async {
    final root = _root;
    if (root == null || !folder.isDir) return;
    if (_open.remove(folder.uri)) {
      _changed();
      return;
    }
    _open.add(folder.uri);
    if (_children.containsKey(folder.uri)) {
      _changed();
      return;
    }
    _opening.add(folder.uri);
    _changed();
    try {
      _children[folder.uri] = (await _source.list(root.uri, dirUri: folder.uri))..sort(compareVaultEntries);
    } on VaultException catch (e) {
      _open.remove(folder.uri);
      _error = e.message;
    }
    _opening.remove(folder.uri);
    _changed();
  }

  // ---- exportar, renombrar, compartir ----

  /// «Exportar»: elige archivos del almacenamiento (o de otro dispositivo) y los **mueve** a la carpeta del Vault donde se está (la raíz si se
  /// ve el árbol). `null` si no hay Vault o se cerró el selector sin elegir; si algo falla, deja el motivo en [error].
  Future<VaultImport?> exportHere({bool move = true}) async {
    final root = _root;
    if (root == null) return null;
    try {
      final result = await _source.importFiles(root.uri, dirUri: _view == VaultView.tree ? null : currentUri, move: move);
      if (result == null) return null;
      await refresh();
      return result;
    } on VaultException catch (e) {
      _error = e.message;
      _lost = e.lost;
      _changed();
      return null;
    }
  }

  /// Le cambia el nombre a un archivo o carpeta del Vault y vuelve a leer. Devuelve el texto del error, o `null` si salió bien.
  Future<String?> rename(VaultEntry entry, String name) async {
    final clean = name.trim();
    if (clean.isEmpty || clean == entry.name) return null;
    try {
      await _source.rename(entry.uri, clean);
    } on VaultException catch (e) {
      return e.message;
    }
    _thumbs.remove(entry.uri);
    await refresh();
    return null;
  }

  /// Lo manda con el menú de compartir del sistema.
  Future<bool> share(VaultEntry entry) => _source.share(entry.uri, entry.mime, entry.name);

  /// Dónde está: el nombre de la carpeta del Vault y las carpetas por las que se ha entrado (para los atributos).
  String get location => [?_root?.name, for (final e in _trail) e.name].join(' / ');

  // ---- archivos ----

  /// La imagen reducida de un archivo (se recuerda: no se pide dos veces).
  Future<Uint8List> thumb(VaultEntry entry) => _thumbs.putIfAbsent(entry.uri, () => _source.thumb(entry.uri, mime: entry.mime));

  /// El archivo entero.
  Future<Uint8List> read(VaultEntry entry) => _source.read(entry.uri);

  /// Abre el archivo con la app del teléfono que sepa verlo.
  Future<bool> open(VaultEntry entry) => _source.open(entry.uri, entry.mime);

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
