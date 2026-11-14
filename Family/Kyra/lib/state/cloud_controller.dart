import 'package:flutter/foundation.dart';

import '../data/chat_backend.dart';
import '../data/cloud_files.dart';

/// Los archivos que hay en el servidor (ver [CloudBackend]): se leen, se filtran por tipo, se abren y se borran de verdad.
class CloudController extends ChangeNotifier {
  CloudController(this._backend);

  final CloudBackend _backend;

  List<CloudFile> files = const [];
  bool loading = false;
  bool loaded = false;
  String? error;

  /// El tipo que se ve (`null` = todos).
  CloudKind? filter;
  bool _disposed = false;

  List<CloudFile> get visible => filter == null ? files : [for (final f in files) if (f.kind == filter) f];

  CloudTotals get totals => cloudTotals(files);

  void setFilter(CloudKind? kind) {
    filter = kind;
    _tell();
  }

  /// Vuelve a leer el servidor.
  Future<void> load() async {
    if (loading || _disposed) return;
    loading = true;
    _tell();
    try {
      files = await _backend.listCloud();
      error = null;
      loaded = true;
    } on ChatException catch (e) {
      error = e.message;
    } finally {
      loading = false;
      _tell();
    }
  }

  /// Una dirección temporal para abrir el archivo (o bajarlo con su nombre). `null` si no se pudo.
  Future<String?> url(CloudFile file, {bool download = false}) async {
    try {
      return await _backend.cloudUrl(file.path, download: download ? file.name : null);
    } on ChatException {
      return null;
    }
  }

  /// La dirección de la miniatura (o del archivo, si es una foto sin miniatura). `null` si no se pudo.
  Future<String?> thumbUrl(CloudFile file) async {
    try {
      return await _backend.cloudUrl(file.thumbPath ?? file.path);
    } on ChatException {
      return null;
    }
  }

  /// Borra el archivo del servidor. Devuelve el texto del error si no se pudo, o `null` si salió bien.
  Future<String?> delete(CloudFile file) async {
    try {
      await _backend.deleteCloudFile(file);
    } on ChatException catch (e) {
      return e.message;
    }
    files = [for (final f in files) if (f.id != file.id && f.path != file.path) f];
    _tell();
    return null;
  }

  void _tell() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
