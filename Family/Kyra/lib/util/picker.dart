import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

import '../state/chat_controller.dart';
import 'format.dart';

/// De dónde se elige lo que se adjunta.
enum PickSource { gallery, camera, file }

/// Abre el selector del teléfono y devuelve lo elegido (vacío si se cancela).
Future<List<OutgoingFile>> pickOutgoing(PickSource source) async {
  switch (source) {
    case PickSource.gallery:
      final images = await ImagePicker().pickMultiImage();
      return [for (final image in images) await _fromXFile(image)];
    case PickSource.camera:
      final photo = await ImagePicker().pickImage(source: ImageSource.camera);
      return photo == null ? const [] : [await _fromXFile(photo)];
    case PickSource.file:
      final picked = await FilePicker.pickFiles();
      return [for (final file in picked) await _fromPlatformFile(file)];
  }
}

/// Elige de la galería la imagen para una canción: su ruta, o `null` si se cancela.
Future<String?> pickCoverImage() async => (await ImagePicker().pickImage(source: ImageSource.gallery))?.path;

Future<OutgoingFile> _fromXFile(XFile file) async =>
    OutgoingFile(path: file.path, name: file.name, size: await file.length(), mime: file.mimeType);

/// Un archivo del selector del sistema. En Android puede llegar como una dirección `content://` sin ruta en el disco: en ese
/// caso se copia a la carpeta temporal de la app para poder subirlo (y reintentar) después.
Future<OutgoingFile> _fromPlatformFile(PlatformFile file) async {
  var path = file.path;
  if (path == null) {
    final folder = await Directory.systemTemp.createTemp('kyora_pick_');
    final target = File('${folder.path}${Platform.pathSeparator}${safeName(file.name)}');
    final sink = target.openWrite();
    await sink.addStream(file.readAsByteStream());
    await sink.close();
    path = target.path;
  }
  final size = (await file.length()) ?? await File(path).length();
  return OutgoingFile(path: path, name: file.name, size: size);
}
