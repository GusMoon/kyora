import 'dart:async';

import 'package:flutter/material.dart';

import '../data/contacts_source.dart';
import '../state/contacts_controller.dart';
import '../theme.dart';
import 'widgets/cyber_panel.dart';
import 'widgets/hack_text.dart';
import 'widgets/section_motion.dart';

/// **Contactos**: los de la agenda del teléfono, de la A a la Z y con buscador. Tocar uno lo abre y enseña sus números; de cada número se puede
/// **llamar** (abre el marcador con el número escrito) o abrir su **chat de WhatsApp**. La primera vez pide el permiso de contactos.
class ContactsPage extends StatefulWidget {
  const ContactsPage({super.key, required this.controller});

  final ContactsController controller;

  @override
  State<ContactsPage> createState() => _ContactsPageState();
}

class _ContactsPageState extends State<ContactsPage> {
  final _search = TextEditingController();

  /// El contacto abierto (con sus números a la vista).
  String? _open;

  @override
  void initState() {
    super.initState();
    // se lee después de construir: `start` avisa a quien escucha
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(widget.controller.start());
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _do(Future<bool> action, String failure) async {
    final ok = await action;
    if (!ok && mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failure)));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: ListenableBuilder(
            listenable: widget.controller,
            builder: (context, _) {
              final ctrl = widget.controller;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FlyIn(
                    edge: MotionEdge.top,
                    order: 0,
                    child: CyberPanel(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                        child: Row(
                          children: [
                            Expanded(child: HackText('CONTACTOS', maxLines: 1, style: TextStyle(fontFamily: monoFont, fontSize: 17, letterSpacing: 1.6, fontWeight: FontWeight.w600, color: c.accent))),
                            if (ctrl.status == ContactsStatus.ready) Text('${ctrl.contacts.length}/${ctrl.total}', key: const Key('contacts-count'), style: TextStyle(fontFamily: monoFont, fontSize: 15, color: c.dim)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (ctrl.status == ContactsStatus.ready || ctrl.query.isNotEmpty)
                    FlyIn(
                      edge: MotionEdge.left,
                      order: 1,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.5), border: Border.all(color: c.edge)),
                        child: Row(
                          children: [
                            Text('>', style: TextStyle(fontFamily: monoFont, fontSize: 17, color: c.accent)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                key: const Key('contacts-search'),
                                controller: _search,
                                onChanged: ctrl.search,
                                style: TextStyle(fontFamily: monoFont, fontSize: 16, color: c.ink),
                                cursorColor: c.accent,
                                decoration: InputDecoration(hintText: 'buscar nombre o número', hintStyle: TextStyle(fontFamily: monoFont, fontSize: 16, color: c.dim), border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none, filled: false),
                              ),
                            ),
                            if (ctrl.query.isNotEmpty)
                              GestureDetector(
                                key: const Key('contacts-clear'),
                                behavior: HitTestBehavior.opaque,
                                onTap: () {
                                  _search.clear();
                                  ctrl.search('');
                                },
                                child: Padding(padding: const EdgeInsets.all(8), child: Icon(Icons.close_rounded, size: 20, color: c.dim)),
                              ),
                          ],
                        ),
                      ),
                    ),
                  Expanded(
                    child: FlyIn(
                      edge: MotionEdge.bottom,
                      order: 2,
                      child: CyberPanel(child: _body(context, ctrl)),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, ContactsController ctrl) {
    final c = context.colors;
    Widget message(String text, {String? button, Key? buttonKey, VoidCallback? onPressed, Color? color}) => Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.contacts_outlined, size: 40, color: c.accent),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center, style: TextStyle(fontFamily: monoFont, fontSize: 15, color: color ?? c.dim)),
            if (button != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(key: buttonKey, onPressed: onPressed, child: Text(button)),
            ],
          ],
        ),
      ),
    );

    switch (ctrl.status) {
      case ContactsStatus.idle:
      case ContactsStatus.loading:
        return const Center(child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(key: Key('contacts-loading'), strokeWidth: 2.4)));
      case ContactsStatus.denied:
        return message('> falta el permiso para leer tus contactos', button: 'PERMITIR CONTACTOS', buttonKey: const Key('contacts-grant'), onPressed: () => unawaited(ctrl.grant()));
      case ContactsStatus.failed:
        return message('> ${ctrl.error ?? 'no se pudieron leer los contactos'}', button: 'REINTENTAR', buttonKey: const Key('contacts-retry'), onPressed: () => unawaited(ctrl.refresh()), color: c.warn);
      case ContactsStatus.ready:
        final list = ctrl.contacts;
        if (list.isEmpty) return message(ctrl.query.isEmpty ? '> la agenda está vacía' : '> sin coincidencias');
        // las cabeceras de letra van intercaladas
        final items = <Object>[];
        String? last;
        for (final contact in list) {
          final letter = contact.letter;
          if (letter != last) {
            items.add(letter);
            last = letter;
          }
          items.add(contact);
        }
        return ListView.builder(
          key: const Key('contacts-list'),
          padding: const EdgeInsets.symmetric(vertical: 6),
          itemCount: items.length,
          itemBuilder: (context, i) {
            final item = items[i];
            if (item is String) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 2),
                child: Text('// $item', style: TextStyle(fontFamily: monoFont, fontSize: 15, letterSpacing: 1.2, color: c.accent)),
              );
            }
            final contact = item as Contact;
            return _ContactRow(
              contact: contact,
              open: _open == contact.id,
              onTap: () => setState(() => _open = _open == contact.id ? null : contact.id),
              onCall: (number) => _do(ctrl.call(number), 'No se pudo abrir el marcador.'),
              onWhatsapp: (number) => _do(ctrl.whatsapp(number), 'No se pudo abrir WhatsApp.'),
            );
          },
        );
    }
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({required this.contact, required this.open, required this.onTap, required this.onCall, required this.onWhatsapp});

  final Contact contact;
  final bool open;
  final VoidCallback onTap;
  final ValueChanged<String> onCall;
  final ValueChanged<String> onWhatsapp;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          key: Key('contact-${contact.id}'),
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: open ? c.accent : null, border: Border.all(color: open ? c.accent : c.edge)),
                  child: Text(contact.initial, style: TextStyle(fontFamily: monoFont, fontSize: 17, fontWeight: FontWeight.w600, color: open ? c.onAccent : c.accent)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(contact.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: appFont, fontSize: 17, color: c.ink)),
                      if (!open && contact.phones.isNotEmpty)
                        Text(contact.phones.first, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: monoFont, fontSize: 15, color: c.dim)),
                    ],
                  ),
                ),
                Icon(open ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, size: 22, color: c.dim),
              ],
            ),
          ),
        ),
        if (open)
          Container(
            key: Key('contact-${contact.id}-numbers'),
            margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.35), border: Border(left: BorderSide(color: c.accent, width: 2))),
            child: Column(
              children: [
                for (var i = 0; i < contact.phones.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(contact.phones[i], maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: monoFont, fontSize: 16, color: c.ink)),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(child: _Action(key: Key('call-${contact.id}-$i'), icon: Icons.call_rounded, label: 'LLAMAR', onTap: () => onCall(contact.phones[i]))),
                            const SizedBox(width: 8),
                            Expanded(child: _Action(key: Key('wa-${contact.id}-$i'), icon: Icons.chat_rounded, label: 'WHATSAPP', onTap: () => onWhatsapp(contact.phones[i]))),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Un botón cuadrado con icono y nombre.
class _Action extends StatelessWidget {
  const _Action({super.key, required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(border: Border.all(color: c.accent.withValues(alpha: 0.7))),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: c.accent),
                const SizedBox(width: 4),
                Text(label, style: TextStyle(fontFamily: monoFont, fontSize: 15, color: c.accent)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
