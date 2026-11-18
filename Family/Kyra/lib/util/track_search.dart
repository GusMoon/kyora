import '../models/track.dart';

/// El texto sin mayúsculas ni acentos, para buscar sin fijarse en ellos.
String foldText(String text) {
  const from = 'áàäâãéèëêíìïîóòöôõúùüûñç';
  const to = 'aaaaaeeeeiiiiooooouuuunc';
  final lower = text.toLowerCase();
  final out = StringBuffer();
  for (final rune in lower.runes) {
    final ch = String.fromCharCode(rune);
    final at = from.indexOf(ch);
    out.write(at >= 0 ? to[at] : ch);
  }
  return out.toString();
}

/// Las canciones que coinciden con `query`: cada palabra escrita tiene que estar en el título (que ya lleva el artista) o en el nombre del
/// archivo, sin importar mayúsculas ni acentos. Sin texto, todas. Se conserva el orden.
List<Track> searchTracks(String query, List<Track> tracks) {
  final words = foldText(query).split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return tracks;
  return [
    for (final t in tracks)
      if (words.every((w) => foldText('${t.title} ${t.fileName}').contains(w))) t,
  ];
}
