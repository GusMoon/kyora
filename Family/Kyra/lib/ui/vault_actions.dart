import 'dart:async';

import 'package:flutter/material.dart';

import '../data/vault_source.dart';
import '../state/cloud_controller.dart';
import '../state/vault_controller.dart';
import '../theme.dart';
import '../util/format.dart';
import 'move_sheet.dart' show askName;
import 'widgets/focus_space.dart';
import 'widgets/pixel_glyph.dart';

/// Lo más grande que cabe en la nube (el límite de un archivo del plan gratuito de Supabase).
const maxCloudUpload = 50 * 1024 * 1024;

/// Qué es una entrada del Vault, en palabras.
String vaultTypeLabel(VaultEntry e) {
  if (e.isDir) return 'Carpeta';
  if (e.isImage) return 'Imagen';
  if (e.isVideo) return 'Vídeo';
  if (e.isAudio) return 'Audio';
  if (e.extension == 'pdf') return 'PDF';
  if (e.isText) return 'Texto';
  return e.extension.isEmpty ? 'Archivo' : 'Archivo ${e.extension.toUpperCase()}';
}

/// La fecha de un archivo (milisegundos desde 1970) como `16/11/2026 09:05`; sin dato, un guion.
String vaultDate(int millis) {
  if (millis <= 0) return '—';
  final t = DateTime.fromMillisecondsSinceEpoch(millis);
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(t.day)}/${two(t.month)}/${t.year} ${two(t.hour)}:${two(t.minute)}';
}

/// Lo que dice el aviso al terminar de exportar: cuántos se movieron, cuántos solo se copiaron y los que fallaron.
String exportSummary(VaultImport r) {
  if (r.copied == 0 && r.failed.isEmpty) return 'No se eligió nada.';
  if (r.copied == 0) return 'No se pudo exportar: ${r.failed.values.first}';
  String files(int n) => n == 1 ? '1 archivo' : '$n archivos';
  final parts = <String>[
    if (r.moved > 0) 'Se ${r.moved == 1 ? 'movió' : 'movieron'} ${files(r.moved)} al Vault.',
    if (r.kept > 0) '${files(r.kept)} se ${r.kept == 1 ? 'copió' : 'copiaron'} al Vault, pero ese almacenamiento no deja borrar el original.',
    if (r.failed.isNotEmpty) '${files(r.failed.length)} no se pudo${r.failed.length == 1 ? '' : 'eron'} exportar: ${r.failed.values.first}',
  ];
  return parts.join(' ');
}

/// Las acciones de un archivo o carpeta del Vault (mantenerlo presionado o el botón de los visores): abrir, enviar a alguien, subir a tu nube,
/// cambiar el nombre y ver sus atributos.
Future<void> showVaultActions(
  BuildContext context, {
  required VaultController vault,
  required VaultEntry entry,
  CloudController? cloud,
  required Future<void> Function() onOpen,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final choice = await showFocusPanel<String>(
    context,
    title: entry.name,
    builder: (context) => _Actions(entry: entry, canUpload: cloud != null && !entry.isDir),
  );
  if (choice == null || !context.mounted) return;
  switch (choice) {
    case 'open':
      await onOpen();
    case 'send':
      final ok = await vault.share(entry);
      if (!ok) messenger?.showSnackBar(const SnackBar(content: Text('No se pudo abrir el menú de compartir.')));
    case 'cloud':
      if (entry.size > maxCloudUpload) {
        messenger?.showSnackBar(SnackBar(content: Text('«${entry.name}» pesa más de ${humanSize(maxCloudUpload)}: no cabe en la nube.')));
        return;
      }
      messenger?.showSnackBar(SnackBar(content: Text('Subiendo «${entry.name}» a tu nube…')));
      try {
        final bytes = await vault.read(entry);
        final error = await cloud!.upload(name: entry.name, mime: entry.mime.isEmpty ? 'application/octet-stream' : entry.mime, bytes: bytes);
        messenger?.hideCurrentSnackBar();
        messenger?.showSnackBar(SnackBar(content: Text(error ?? '«${entry.name}» ya está en tu nube.')));
      } on VaultException catch (e) {
        messenger?.hideCurrentSnackBar();
        messenger?.showSnackBar(SnackBar(content: Text(e.message)));
      }
    case 'rename':
      final name = await askName(context, title: 'Cambiar nombre', hint: 'Nombre nuevo', confirm: 'Guardar', initial: entry.name);
      if (name == null) return;
      final error = await vault.rename(entry, name);
      if (error != null) messenger?.showSnackBar(SnackBar(content: Text(error)));
    case 'info':
      await showVaultAttributes(context, vault: vault, entry: entry);
  }
}

class _Actions extends StatelessWidget {
  const _Actions({required this.entry, required this.canUpload});

  final VaultEntry entry;
  final bool canUpload;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget tile(String id, IconData icon, String title, {String? subtitle}) => ListTile(
      key: Key('vault-act-$id'),
      leading: LcdIcon(icon, color: c.accent),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle, style: TextStyle(color: c.dim)),
      onTap: () => Navigator.of(context).pop(id),
    );
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          tile('open', entry.isDir ? Icons.folder_open_rounded : Icons.open_in_new_rounded, entry.isDir ? 'Abrir carpeta' : 'Abrir'),
          if (!entry.isDir) tile('send', Icons.send_rounded, 'Enviar a alguien', subtitle: 'Mensajes, correo, WhatsApp…'),
          if (canUpload) tile('cloud', Icons.cloud_upload_outlined, 'Subir a mi nube', subtitle: 'Queda en tu servidor'),
          tile('rename', Icons.edit_outlined, 'Cambiar nombre'),
          tile('info', Icons.info_outline_rounded, 'Atributos'),
        ],
      ),
    );
  }
}

/// Los atributos de un archivo o carpeta: nombre, tipo, tamaño, fecha y dónde está.
Future<void> showVaultAttributes(BuildContext context, {required VaultController vault, required VaultEntry entry}) => showFocusPanel<void>(
  context,
  title: 'Atributos',
  builder: (context) {
    final c = context.colors;
    Widget row(String id, String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: TextStyle(fontFamily: monoFont, fontSize: 15, letterSpacing: 1.2, color: c.dim)),
          Text(value, key: Key('vault-attr-$id'), style: TextStyle(fontFamily: monoFont, fontSize: 15, color: c.ink)),
        ],
      ),
    );
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          row('name', 'Nombre', entry.name),
          row('type', 'Tipo', vaultTypeLabel(entry)),
          if (!entry.isDir) row('size', 'Tamaño', entry.size > 0 ? '${humanSize(entry.size)} (${entry.size} bytes)' : '—'),
          if (entry.mime.isNotEmpty && !entry.isDir) row('mime', 'Formato', entry.mime),
          row('modified', 'Modificado', vaultDate(entry.modified)),
          row('where', 'Ubicación', vault.location),
        ],
      ),
    );
  },
);

/// Un botón de los visores que abre las acciones del archivo que se ve.
class VaultActionsButton extends StatelessWidget {
  const VaultActionsButton({super.key, required this.vault, required this.entry, required this.cloud});

  final VaultController vault;
  final VaultEntry entry;
  final CloudController? cloud;

  @override
  Widget build(BuildContext context) => IconButton(
    key: const Key('viewer-actions'),
    tooltip: 'Compartir y más',
    icon: LcdIcon(Icons.share_outlined, color: context.colors.ink),
    onPressed: () => unawaited(showVaultActions(context, vault: vault, entry: entry, cloud: cloud, onOpen: () async {})),
  );
}
