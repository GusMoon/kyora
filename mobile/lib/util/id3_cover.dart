import 'dart:convert';
import 'dart:typed_data';

/// El .mp3 con otra carátula: la etiqueta ID3 lleva la imagen nueva en lugar de las que tuviera, conserva lo demás (título, artista…) y
/// el audio queda idéntico, byte a byte. Lanza `FormatException` si la etiqueta está tan rota que no se puede saber dónde empieza el audio.
Uint8List withCover(Uint8List mp3, Uint8List image, {String mime = 'image/jpeg'}) {
  final tag = _readTag(mp3);
  final version = tag.version;
  final picture = _pictureFrame(image, mime, version);
  final size = tag.frames.fold(picture.length, (total, frame) => total + frame.length);
  if (size >= 1 << 28) throw const FormatException('La etiqueta quedaría demasiado grande.');
  final out = BytesBuilder(copy: false)
    ..add([0x49, 0x44, 0x33, version, 0, 0]) // «ID3», versión, sin marcas
    ..add(_syncsafe(size))
    ..add(picture);
  for (final frame in tag.frames) {
    out.add(frame);
  }
  out.add(Uint8List.sublistView(mp3, tag.audioStart));
  return out.takeBytes();
}

class _Tag {
  const _Tag(this.version, this.frames, this.audioStart);

  /// La versión de la etiqueta que se escribe: 3 o 4 (ID3v2.3 o ID3v2.4).
  final int version;

  /// Los datos que se conservan, ya listos para copiar.
  final List<Uint8List> frames;
  final int audioStart;
}

_Tag _readTag(Uint8List mp3) {
  final hasTag = mp3.length >= 10 && mp3[0] == 0x49 && mp3[1] == 0x44 && mp3[2] == 0x33;
  if (!hasTag) return const _Tag(3, [], 0);
  final major = mp3[3];
  final flags = mp3[5];
  if (major < 2 || major > 4) throw const FormatException('Versión de ID3 desconocida.');
  if (mp3.sublist(6, 10).any((b) => b >= 0x80)) throw const FormatException('Etiqueta ID3 dañada.');
  final size = _readSyncsafe(mp3, 6);
  final hasFooter = major == 4 && flags & 0x10 != 0;
  final audioStart = 10 + size + (hasFooter ? 10 : 0);
  if (audioStart > mp3.length) throw const FormatException('Etiqueta ID3 más grande que el archivo.');
  var body = Uint8List.sublistView(mp3, 10, 10 + size);
  // en estas versiones la marca «sin sincronización» afecta a toda la etiqueta
  if (major < 4 && flags & 0x80 != 0) body = _removeUnsync(body);
  if (major == 2) {
    if (flags & 0x40 != 0) throw const FormatException('Etiqueta ID3 comprimida.');
    return _Tag(3, _framesV2(body), audioStart);
  }
  var offset = 0;
  if (flags & 0x40 != 0 && body.length >= 4) offset = major == 3 ? _readBig(body, 0, 4) + 4 : _readSyncsafe(body, 0);
  return _Tag(major, _framesV3V4(body, offset, major), audioStart);
}

List<Uint8List> _framesV3V4(Uint8List body, int start, int major) {
  final frames = <Uint8List>[];
  var at = start;
  while (at + 10 <= body.length && _isFrameId(body, at, 4)) {
    // algunos programas escriben en la v2.4 tamaños normales en vez de «syncsafe»: esos llevan bytes que el formato no permite
    final raw = body.sublist(at + 4, at + 8);
    final size = major == 4 && raw.every((b) => b < 0x80) ? _readSyncsafe(body, at + 4) : _readBig(body, at + 4, 4);
    final end = at + 10 + size;
    if (end > body.length) break;
    if (ascii.decode(body.sublist(at, at + 4)) != 'APIC') frames.add(Uint8List.sublistView(body, at, end));
    at = end;
  }
  return frames;
}

/// Los datos de la versión antigua (ID3v2.2, nombres de 3 letras) pasados a la 2.3. Lo que no está en esta lista se pierde.
const _fromV2 = {
  'TT2': 'TIT2',
  'TP1': 'TPE1',
  'TP2': 'TPE2',
  'TAL': 'TALB',
  'TRK': 'TRCK',
  'TPA': 'TPOS',
  'TYE': 'TYER',
  'TCO': 'TCON',
  'TCM': 'TCOM',
  'COM': 'COMM',
  'ULT': 'USLT',
};

List<Uint8List> _framesV2(Uint8List body) {
  final frames = <Uint8List>[];
  var at = 0;
  while (at + 6 <= body.length && _isFrameId(body, at, 3)) {
    final size = _readBig(body, at + 3, 3);
    final end = at + 6 + size;
    if (end > body.length) break;
    final id = _fromV2[ascii.decode(body.sublist(at, at + 3))];
    if (id != null) {
      frames.add((BytesBuilder(copy: false)
            ..add(ascii.encode(id))
            ..add(_big(size))
            ..add([0, 0])
            ..add(Uint8List.sublistView(body, at + 6, end)))
          .takeBytes());
    }
    at = end;
  }
  return frames;
}

Uint8List _pictureFrame(Uint8List image, String mime, int version) {
  final head = [0, ...latin1.encode(mime), 0, 3, 0]; // texto latin-1, tipo de imagen, «3» = portada, sin descripción
  final size = head.length + image.length;
  return (BytesBuilder(copy: false)
        ..add(ascii.encode('APIC'))
        ..add(version == 4 ? _syncsafe(size) : _big(size))
        ..add([0, 0])
        ..add(head)
        ..add(image))
      .takeBytes();
}

bool _isFrameId(Uint8List bytes, int at, int length) {
  for (var i = at; i < at + length; i++) {
    final b = bytes[i];
    if (!(b >= 0x41 && b <= 0x5A) && !(b >= 0x30 && b <= 0x39)) return false;
  }
  return true;
}

Uint8List _removeUnsync(Uint8List bytes) {
  final out = BytesBuilder(copy: false);
  var from = 0;
  for (var i = 0; i + 1 < bytes.length; i++) {
    if (bytes[i] == 0xFF && bytes[i + 1] == 0) {
      out.add(Uint8List.sublistView(bytes, from, i + 1));
      from = i + 2;
      i++;
    }
  }
  out.add(Uint8List.sublistView(bytes, from));
  return out.takeBytes();
}

int _readSyncsafe(Uint8List b, int at) => (b[at] << 21) | (b[at + 1] << 14) | (b[at + 2] << 7) | b[at + 3];

int _readBig(Uint8List b, int at, int length) {
  var value = 0;
  for (var i = at; i < at + length; i++) {
    value = (value << 8) | b[i];
  }
  return value;
}

List<int> _syncsafe(int v) => [(v >> 21) & 0x7F, (v >> 14) & 0x7F, (v >> 7) & 0x7F, v & 0x7F];

List<int> _big(int v) => [(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF];
