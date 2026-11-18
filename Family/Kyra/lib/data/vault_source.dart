
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../util/format.dart';

/// Lo que se ve de una carpeta o un archivo del Vault.
class VaultEntry {
  const VaultEntry({required this.uri, required this.name, required this.isDir, this.mime = '', this.size = 0, this.modified = 0});

  /// La dirección del documento (la da el selector de carpetas de Android).
  final String uri;
  final String name;
  final bool isDir;
  final String mime;

  /// Bytes y milisegundos desde 1970 (0 si Android no los dice).
  final int size;
  final int modified;

  static const _imageExtensions = {'jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp', 'heic', 'heif'};
  static const _videoExtensions = {'mp4', 'mkv', 'mov', 'avi', 'webm', '3gp', 'm4v'};
  static const _audioExtensions = {'mp3', 'wav', 'flac', 'm4a', 'ogg', 'aac', 'opus', 'wma'};
  static const _textExtensions = {'txt', 'md', 'json', 'csv', 'log', 'xml', 'yaml', 'yml', 'ini', 'conf', 'html', 'htm', 'css', 'js', 'dart', 'py', 'kt', 'java', 'sql', 'srt', 'tsv'};

  /// Lo más que se lee de un texto para enseñarlo aquí (más grande, se abre con otra app).
  static const maxTextBytes = 2 * 1024 * 1024;

  String get extension {
    final dot = name.lastIndexOf('.');
    return dot < 0 || dot == name.length - 1 ? '' : name.substring(dot + 1).toLowerCase();
  }

  /// ¿Es una imagen que se puede enseñar?
  bool get isImage => !isDir && (mime.startsWith('image/') || _imageExtensions.contains(extension));

  /// ¿Es un vídeo?
  bool get isVideo => !isDir && (mime.startsWith('video/') || _videoExtensions.contains(extension));

  /// ¿Es un audio?
  bool get isAudio => !isDir && (mime.startsWith('audio/') || _audioExtensions.contains(extension));

  /// ¿Es un texto plano (notas, registros, datos…) que se puede leer aquí?
  bool get isText => !isDir && size <= maxTextBytes && (mime.startsWith('text/') || mime == 'application/json' || mime == 'application/xml' || _textExtensions.contains(extension));

  /// ¿Se ve dentro de la app? Imágenes, vídeos, audios y textos. Lo demás (PDF, Word…) lo necesita otra app.
  bool get viewable => canShow || isVideo || isAudio || isText;

  /// Imágenes que Flutter no sabe pintar (HEIC): se abren con la app del teléfono.
  bool get canShow => isImage && extension != 'heic' && extension != 'heif' && !mime.contains('heic') && !mime.contains('heif');

  factory VaultEntry.fromMap(Map<Object?, Object?> map) => VaultEntry(
    uri: '${map['uri']}',
    name: (map['name'] as String?) ?? '',
    isDir: map['dir'] == true,
    mime: (map['mime'] as String?) ?? '',
    size: (map['size'] as num?)?.toInt() ?? 0,
    modified: (map['modified'] as num?)?.toInt() ?? 0,
  );
}

/// Lo que pasó al exportar archivos al Vault: cuántos se copiaron, cuántos de ellos también se borraron de su sitio (movidos) y los que
/// fallaron con su motivo.
class VaultImport {
  const VaultImport({this.copied = 0, this.moved = 0, this.failed = const {}});

  final int copied;
  final int moved;
  final Map<String, String> failed;

  /// Copiados pero que no se pudieron borrar del origen (ese almacenamiento no deja).
  int get kept => copied - moved;
}

/// La carpeta elegida para el Vault: su dirección (de Android) y su nombre.
class VaultFolder {
  const VaultFolder({required this.uri, required this.name});

  final String uri;
  final String name;
}

/// Carpetas y archivos de una carpeta elegida con el selector de Android: elegirla, ver lo que hay dentro, leer un archivo y abrirlo.
abstract class VaultSource {
  /// El selector de carpetas del sistema. `null` si se cierra sin elegir.
  Future<VaultFolder?> pickFolder();

  /// Lo que hay directamente en la carpeta `dirUri` (la raíz elegida si es `null`), sin ordenar.
  Future<List<VaultEntry>> list(String treeUri, {String? dirUri});

  /// El archivo entero, tal cual.
  Future<Uint8List> read(String uri);

  /// La imagen reducida a `side` px como mucho (sin efectos), para las cuadrículas.
  Future<Uint8List> thumb(String uri, {int side = 480, String mime = ''});

  /// Abre el archivo con otra app del teléfono. `false` si no hay ninguna que sepa.
  Future<bool> open(String uri, String mime);

  /// «Exportar»: abre el selector de archivos del sistema (almacenamiento interno, tarjeta, otros dispositivos), copia lo elegido en `dirUri`
  /// (la raíz si es `null`) y, con `move`, borra los originales. `null` si se cierra el selector sin elegir.
  Future<VaultImport?> importFiles(String treeUri, {String? dirUri, bool move = true});

  /// Le cambia el nombre a un archivo o carpeta. Devuelve su dirección nueva.
  Future<String> rename(String uri, String name);

  /// Lo manda con el menú de compartir del sistema (mensajes, correo…). `false` si no se pudo abrir.
  Future<bool> share(String uri, String mime, String name);
}

/// Algo falló al leer del Vault (lo dicho por Android, en cristiano).
class VaultException implements Exception {
  const VaultException(this.message, {this.lost = false});

  final String message;

  /// La carpeta ya no está o Android ya no deja leerla: hay que elegirla otra vez.
  final bool lost;

  @override
  String toString() => message;
}

/// El real: la parte de Android está en `MainActivity.kt` (canal `kyora/vault`).
class AndroidVaultSource implements VaultSource {
  static const _channel = MethodChannel('kyora/vault');

  Future<T> _call<T>(Future<T?> Function() run, String fallback) async {
    try {
      final value = await run();
      if (value == null) throw VaultException(fallback);
      return value;
    } on PlatformException catch (e) {
      throw VaultException(e.message ?? fallback, lost: e.code == 'folder_lost');
    } on MissingPluginException {
      throw VaultException(fallback);
    }
  }

  @override
  Future<VaultFolder?> pickFolder() async {
    try {
      final map = await _channel.invokeMapMethod<String, String>('pickFolder');
      return map == null ? null : VaultFolder(uri: map['uri']!, name: map['name'] ?? 'Carpeta elegida');
    } on PlatformException catch (e) {
      throw VaultException(e.message ?? 'No se pudo usar esa carpeta.');
    } on MissingPluginException {
      throw const VaultException('Este teléfono no tiene selector de carpetas.');
    }
  }

  @override
  Future<List<VaultEntry>> list(String treeUri, {String? dirUri}) async {
    final raw = await _call(() => _channel.invokeListMethod<Map<Object?, Object?>>('list', {'treeUri': treeUri, 'dirUri': dirUri ?? ''}), 'No se pudo leer la carpeta.');
    return [for (final item in raw) VaultEntry.fromMap(item)];
  }

  @override
  Future<Uint8List> read(String uri) => _call(() => _channel.invokeMethod<Uint8List>('read', {'uri': uri}), 'No se pudo leer el archivo.');

  @override
  Future<Uint8List> thumb(String uri, {int side = 480, String mime = ''}) =>
      _call(() => _channel.invokeMethod<Uint8List>('thumb', {'uri': uri, 'side': side, 'mime': mime}), 'No se pudo abrir esa imagen.');

  @override
  Future<bool> open(String uri, String mime) async {
    try {
      return (await _channel.invokeMethod<bool>('open', {'uri': uri, 'mime': mime})) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<VaultImport?> importFiles(String treeUri, {String? dirUri, bool move = true}) async {
    try {
      final map = await _channel.invokeMapMethod<String, Object?>('import', {'treeUri': treeUri, 'dirUri': dirUri ?? '', 'move': move});
      if (map == null) return null;
      final failed = map['failed'];
      return VaultImport(
        copied: (map['copied'] as num?)?.toInt() ?? 0,
        moved: (map['moved'] as num?)?.toInt() ?? 0,
        failed: failed is Map ? {for (final e in failed.entries) '${e.key}': '${e.value}'} : const {},
      );
    } on PlatformException catch (e) {
      throw VaultException(e.message ?? 'No se pudo exportar.', lost: e.code == 'folder_lost');
    } on MissingPluginException {
      throw const VaultException('Este teléfono no tiene selector de archivos.');
    }
  }

  @override
  Future<String> rename(String uri, String name) => _call(() => _channel.invokeMethod<String>('rename', {'uri': uri, 'name': name}), 'No se pudo cambiar el nombre.');

  @override
  Future<bool> share(String uri, String mime, String name) async {
    try {
      return (await _channel.invokeMethod<bool>('share', {'uri': uri, 'mime': mime, 'name': name})) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}

/// Un Vault de mentira, para las pruebas: carpetas (por su dirección) con lo que tienen dentro y los bytes de cada archivo.
class FakeVaultSource implements VaultSource {
  FakeVaultSource({Map<String, List<VaultEntry>>? folders, Map<String, Uint8List>? files}) : folders = folders ?? {}, files = files ?? {};

  /// Lo que hay en cada carpeta; la clave `''` es la raíz.
  final Map<String, List<VaultEntry>> folders;
  final Map<String, Uint8List> files;

  /// Lo que devolverá el selector de carpetas (`null` = se cierra sin elegir).
  VaultFolder? picked = const VaultFolder(uri: 'tree://vault', name: 'Mi Vault');

  /// Si leer falla, y si es porque la carpeta se perdió.
  bool failing = false;
  bool lost = false;

  final List<String> opened = [];
  final List<String> shared = [];
  final List<({String uri, String name})> renames = [];
  final List<({String? dir, bool move})> imports = [];

  /// Lo que devolverá «exportar» (`null` = se cierra el selector sin elegir) y si falla.
  VaultImport? importResult = const VaultImport(copied: 1, moved: 1);
  bool importFails = false;
  final List<String> listed = [];
  final List<String> thumbs = [];
  int picks = 0;

  @override
  Future<VaultFolder?> pickFolder() async {
    picks++;
    return picked;
  }

  @override
  Future<List<VaultEntry>> list(String treeUri, {String? dirUri}) async {
    listed.add(dirUri ?? '');
    if (failing) throw VaultException(lost ? 'La carpeta ya no existe: elige otra.' : 'No se pudo leer la carpeta.', lost: lost);
    return List.of(folders[dirUri ?? ''] ?? const []);
  }

  @override
  Future<Uint8List> read(String uri) async {
    final bytes = files[uri];
    if (bytes == null) throw const VaultException('No se pudo leer el archivo.');
    return bytes;
  }

  @override
  Future<Uint8List> thumb(String uri, {int side = 480, String mime = ''}) async {
    thumbs.add(uri);
    return read(uri);
  }

  @override
  Future<bool> open(String uri, String mime) async {
    opened.add(uri);
    return true;
  }

  @override
  Future<VaultImport?> importFiles(String treeUri, {String? dirUri, bool move = true}) async {
    imports.add((dir: dirUri, move: move));
    if (importFails) throw const VaultException('Android no dejó escribir en la carpeta del Vault.');
    return importResult;
  }

  @override
  Future<String> rename(String uri, String name) async {
    renames.add((uri: uri, name: name));
    final out = <String, List<VaultEntry>>{};
    for (final e in folders.entries) {
      out[e.key] = [
        for (final entry in e.value) entry.uri == uri ? VaultEntry(uri: '$uri#$name', name: name, isDir: entry.isDir, mime: entry.mime, size: entry.size, modified: entry.modified) : entry,
      ];
    }
    folders
      ..clear()
      ..addAll(out);
    return '$uri#$name';
  }

  @override
  Future<bool> share(String uri, String mime, String name) async {
    shared.add(uri);
    return true;
  }
}

/// Dónde se recuerda la carpeta del Vault y cómo se ve (cuadrícula o árbol).
abstract class VaultStore {
  VaultFolder? loadFolder();
  bool loadTree();
  Future<void> saveFolder(VaultFolder? folder);
  Future<void> saveTree(bool tree);
}

class MemoryVaultStore implements VaultStore {
  MemoryVaultStore({this.folder, this.tree = false});

  VaultFolder? folder;
  bool tree;

  @override
  VaultFolder? loadFolder() => folder;

  @override
  bool loadTree() => tree;

  @override
  Future<void> saveFolder(VaultFolder? value) async => folder = value;

  @override
  Future<void> saveTree(bool value) async => tree = value;
}

class PrefsVaultStore implements VaultStore {
  PrefsVaultStore._(this._prefs);

  final SharedPreferences _prefs;

  static Future<PrefsVaultStore> open() async => PrefsVaultStore._(await SharedPreferences.getInstance());

  @override
  VaultFolder? loadFolder() {
    final uri = _prefs.getString('vault.uri');
    if (uri == null || uri.isEmpty) return null;
    return VaultFolder(uri: uri, name: _prefs.getString('vault.name') ?? 'Vault');
  }

  @override
  bool loadTree() => _prefs.getBool('vault.tree') ?? false;

  @override
  Future<void> saveFolder(VaultFolder? folder) async {
    if (folder == null) {
      await _prefs.remove('vault.uri');
      await _prefs.remove('vault.name');
    } else {
      await _prefs.setString('vault.uri', folder.uri);
      await _prefs.setString('vault.name', folder.name);
    }
  }

  @override
  Future<void> saveTree(bool tree) async => _prefs.setBool('vault.tree', tree);
}

/// Primero las carpetas y después los archivos, cada grupo de la A a la Z (sin distinguir mayúsculas ni acentos).
int compareVaultEntries(VaultEntry a, VaultEntry b) {
  if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
  return compareAppNames(a.name, b.name);
}
