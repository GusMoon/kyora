import '../data/music_store.dart';
import '../models/track.dart';
import '../state/local_music_controller.dart';
import '../state/player_controller.dart';
import 'album_options.dart' show AlbumDeletion;
import 'move_sheet.dart' show MoveTarget;
import 'album_view.dart' show AlbumEntry;

/// Las preguntas y avisos que necesitan las acciones de música. Cada app las pone a su manera: KyraAdmin con sus paneles sci-fi
/// (`AdminMusicDialogs`) y KyraFamily con los del diseño cyber-brutalista (`NeoMusicDialogs`). La lógica (`MusicActions`) es la misma.
abstract class MusicDialogs {
  /// ¿Sigue a la vista quien pregunta? (si no, las acciones se paran a medias sin tocar nada más).
  bool get alive;

  /// Pide un nombre; `null` si se cancela.
  Future<String?> askName({required String title, required String hint, required String confirm, String initial = ''});

  /// ¿Borrar estas `count` canciones (de «title»)?
  Future<bool> confirmDeleteSongs({required String title, required int count});

  /// ¿Borrar esta canción?
  Future<bool> confirmDeleteSong({required String title});

  /// ¿Borrar este álbum vacío?
  Future<bool> confirmDeleteEmptyAlbum({required String title});

  /// Un álbum con canciones: pasarlas a otro antes o borrarlo todo; `null` si se cancela.
  Future<AlbumDeletion?> askDeleteAlbum({required String title, required int count});

  /// Elige el álbum de destino para mover `count` canciones; `null` si se cancela.
  Future<MoveTarget?> pickMoveTarget(LocalMusicController local, {required int count});

  /// Un aviso corto (lo que pasó o el error).
  void notify(String text);
}

/// Lo que se puede hacer con la música del teléfono: crear, renombrar y borrar álbumes; mover, renombrar y borrar canciones (una o las
/// marcadas). Lo comparten KyraAdmin y KyraFamily. Antes de tocar los archivos de lo que suena (o está en la cola) se para el reproductor,
/// porque sus direcciones dejarían de valer.
class MusicActions {
  MusicActions({required this.local, required this.dialogs, this.player});

  final LocalMusicController local;
  final MusicDialogs dialogs;
  final PlayerController? player;

  /// Para el reproductor si esa canción suena o está en la cola.
  Future<void> stopIfQueued(Track track) async {
    final p = player;
    if (p != null && (p.current?.id == track.id || p.queue.any((t) => t.id == track.id))) await p.stop();
  }

  /// Para el reproductor si lo que suena (o está en la cola) es de ese álbum.
  Future<void> stopIfPlayingFrom(AlbumEntry e) async {
    final p = player;
    if (p != null && p.queue.any((t) => t.isLocal && local.albumIdOf(t) == e.id)) await p.stop();
  }

  /// Pone al controlador dentro de la carpeta del álbum y espera a que la lea (para poder mover sus canciones).
  Future<void> enterAlbum(AlbumEntry e) async {
    final folder = e.folder;
    if (folder == null) return;
    if (local.path.length == 1 && local.currentUri == folder.uri) return;
    if (!local.atRoot) await local.goTo(0);
    await local.open(folder);
  }

  /// «Nuevo álbum»: pide el nombre y crea la carpeta.
  Future<void> newAlbum() async {
    final name = await dialogs.askName(title: 'Nuevo álbum', hint: 'Nombre del álbum', confirm: 'Crear');
    if (name == null || !dialogs.alive) return;
    await _guard(() async {
      final folder = await local.createFolder(name);
      dialogs.notify('Se creó el álbum «${folder.name}».');
    });
  }

  Future<void> renameAlbum(AlbumEntry e) async {
    final folder = e.folder;
    if (folder == null) return;
    final name = await dialogs.askName(title: 'Cambiar nombre', hint: 'Nombre del álbum', confirm: 'Guardar', initial: e.title);
    if (name == null || !dialogs.alive) return;
    await _guard(() async {
      await stopIfPlayingFrom(e);
      final renamed = await local.renameAlbum(folder, name);
      dialogs.notify('El álbum ahora se llama «${renamed.name}».');
    });
  }

  /// **Borrar álbum.** Vacío: se confirma y se borra. Con canciones se avisa de que deben pasarse a otro álbum o se borrarán junto con él:
  /// «Pasarlas a otro álbum» deja elegir el destino, las mueve y, solo si todas se movieron, borra la carpeta; «Borrar todo» borra la carpeta con
  /// todo lo que lleve dentro.
  Future<void> deleteAlbum(AlbumEntry e) async {
    final folder = e.folder;
    if (folder == null) return;
    final known = local.tracksIn(folder.uri);
    final count = known?.length ?? folder.count;
    await _guard(() async {
      if (count == 0) {
        if (!await dialogs.confirmDeleteEmptyAlbum(title: e.title) || !dialogs.alive) return;
        await stopIfPlayingFrom(e);
        await local.deleteAlbum(folder);
        dialogs.notify('Se borró el álbum «${e.title}».');
        return;
      }
      final choice = await dialogs.askDeleteAlbum(title: e.title, count: count);
      if (choice == null || !dialogs.alive) return;
      await stopIfPlayingFrom(e);
      if (choice == AlbumDeletion.deleteAll) {
        await local.deleteAlbum(folder);
        dialogs.notify('Se borró el álbum «${e.title}» con sus canciones.');
        return;
      }
      await enterAlbum(e);
      if (!dialogs.alive) return;
      final songs = List.of(local.songs);
      final target = await dialogs.pickMoveTarget(local, count: songs.length);
      if (target == null || !dialogs.alive) return; // sin destino no se toca nada: el álbum se queda como estaba
      final result = await local.move(songs, toUri: target.uri);
      if (result.failures.isNotEmpty) {
        dialogs.notify('No se pudieron pasar todas las canciones (${result.failures.values.first}). El álbum «${e.title}» no se borró.');
        return;
      }
      await local.deleteAlbum(folder);
      dialogs.notify('${result.moved == 1 ? 'Se pasó 1 canción' : 'Se pasaron ${result.moved} canciones'} a «${target.name}» y se borró el álbum «${e.title}».');
    });
  }

  /// «Mover» las canciones marcadas: elige el destino y las mueve de verdad.
  Future<void> moveSelected() async {
    final target = await dialogs.pickMoveTarget(local, count: local.selectedCount);
    if (target == null || !dialogs.alive) return;
    await _guard(() async {
      for (final t in local.selectedSongs) {
        await stopIfQueued(t);
      }
      final result = await local.moveSelected(toUri: target.uri);
      final bad = result.failures.length;
      final done = result.moved == 1 ? 'Se movió 1 canción' : 'Se movieron ${result.moved} canciones';
      dialogs.notify(
        result.moved == 0 && bad == 0
            ? 'No había nada que mover.'
            : [
                if (result.moved > 0) '$done a «${target.name}».',
                if (bad > 0) 'No se ${bad == 1 ? 'pudo mover 1' : 'pudieron mover $bad'}: ${result.failures.values.first}',
              ].join(' '),
      );
    });
  }

  /// Borra las canciones marcadas (con confirmación).
  Future<void> deleteSelected({required String albumTitle}) async {
    final doomed = local.selectedSongs;
    if (doomed.isEmpty) return;
    if (!await dialogs.confirmDeleteSongs(title: albumTitle, count: doomed.length) || !dialogs.alive) return;
    await _guard(() async {
      for (final t in doomed) {
        await stopIfQueued(t);
      }
      final result = await local.delete(doomed);
      final bad = result.failures.length;
      dialogs.notify(
        [
          if (result.deleted > 0) (result.deleted == 1 ? 'Se borró 1 canción.' : 'Se borraron ${result.deleted} canciones.'),
          if (bad > 0) 'No se ${bad == 1 ? 'pudo borrar 1' : 'pudieron borrar $bad'}: ${result.failures.values.first}',
        ].join(' '),
      );
    });
  }

  Future<void> moveTrack(Track track) async {
    final target = await dialogs.pickMoveTarget(local, count: 1);
    if (target == null || !dialogs.alive) return;
    await _guard(() async {
      await stopIfQueued(track);
      final result = await local.move([track], toUri: target.uri);
      dialogs.notify(
        result.moved == 1
            ? 'Se movió a «${target.name}».'
            : result.failures.isEmpty
                ? 'No había nada que mover.'
                : 'No se pudo mover: ${result.failures.values.first}',
      );
    });
  }

  Future<void> deleteTrack(Track track, {required String title}) async {
    if (!await dialogs.confirmDeleteSong(title: title) || !dialogs.alive) return;
    await _guard(() async {
      await stopIfQueued(track);
      final result = await local.delete([track]);
      dialogs.notify(result.deleted == 1 ? 'Se borró la canción.' : 'No se pudo borrar: ${result.failures.values.firstOrNull ?? 'no había nada que borrar'}');
    });
  }

  Future<void> renameTrack(Track track) async {
    final name = await dialogs.askName(title: 'Cambiar nombre', hint: 'Nombre de la canción', confirm: 'Guardar', initial: track.title);
    if (name == null || !dialogs.alive) return;
    await _guard(() async {
      await stopIfQueued(track);
      await local.renameTrack(track, name);
    });
  }

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } on TrackSaveException catch (e) {
      dialogs.notify(e.message);
    }
  }
}
