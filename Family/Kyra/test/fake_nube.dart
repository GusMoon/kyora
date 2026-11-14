import 'dart:async';

import 'package:kyora_chat/data/chat_backend.dart';
import 'package:kyora_chat/data/cloud_files.dart';
import 'package:kyora_chat/data/server_stats.dart';

/// Medir el servidor de mentira: da lo que se le ponga, cuenta las veces que se pidió y se puede dejar fallando o esperando.
class FakeServerBackend implements ServerBackend {
  FakeServerBackend(this.stats);

  ServerStats stats;
  ChatException? error;
  Completer<void>? hold;
  int calls = 0;

  @override
  Future<ServerStats> serverStats() async {
    calls++;
    if (hold != null) await hold!.future;
    final e = error;
    if (e != null) throw e;
    return stats;
  }
}

/// Unas estadísticas con `dbMb` MB de base de datos y `filesMb` MB de archivos.
ServerStats statsOf(double dbMb, double filesMb, {List<BucketStat> buckets = const [], List<TableStat> tables = const [], int objects = 3}) => ServerStats(
      dbBytes: (dbMb * mb).round(),
      storageBytes: (filesMb * mb).round(),
      storageObjects: objects,
      buckets: buckets,
      tables: tables,
      at: DateTime.utc(2026, 11, 13, 10, 5),
    );

/// La nube de mentira: una lista de archivos que se puede borrar de verdad, con las direcciones que se piden.
class FakeCloudBackend implements CloudBackend {
  FakeCloudBackend(List<CloudFile> files) : files = List.of(files);

  List<CloudFile> files;
  ChatException? listError;
  ChatException? deleteError;
  int lists = 0;
  final List<String> deleted = [];
  final List<(String, String?)> urls = [];

  @override
  Future<List<CloudFile>> listCloud() async {
    lists++;
    final e = listError;
    if (e != null) throw e;
    return List.of(files);
  }

  @override
  Future<String> cloudUrl(String path, {String? download}) async {
    urls.add((path, download));
    return 'https://nube.test/$path${download == null ? '' : '?download=$download'}';
  }

  @override
  Future<CloudDeleteResult> deleteCloudFile(CloudFile file) async {
    final e = deleteError;
    if (e != null) throw e;
    deleted.add(file.id);
    files.removeWhere((f) => f.path == file.path);
    return const CloudDeleteResult();
  }
}

CloudFile cloudFile(String id, String name, {CloudSource source = CloudSource.chat, String mime = 'application/pdf', int size = 2048, String from = 'PC', DateTime? at, String? thumb}) => CloudFile(
      id: '${source.name}:$id',
      source: source,
      path: 'u/$id/$name',
      name: name,
      mime: mime,
      size: size,
      at: at ?? DateTime.utc(2026, 11, 12, 9),
      from: from,
      kind: kindOf(mime, name),
      messageId: source == CloudSource.chat ? 'm-$id' : null,
      thumbPath: thumb,
    );
