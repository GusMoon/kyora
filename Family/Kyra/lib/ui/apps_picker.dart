import 'package:flutter/material.dart';

import '../state/dock_controller.dart';
import '../theme.dart';
import 'widgets/focus_space.dart';

/// Abre la lista de apps instaladas para llenar la ranura [slot] del disco. Elegir una la pone y cierra la hoja.
Future<void> showAppsPicker(BuildContext context, DockController dock, int slot) {
  return showFocusPanel<void>(context, builder: (_) => AppsPicker(dock: dock, slot: slot),
  );
}

/// El contenido de la hoja: un buscador y las apps por nombre. La de la ranura actual sale marcada; si hay una, también se puede vaciar.
class AppsPicker extends StatefulWidget {
  const AppsPicker({super.key, required this.dock, required this.slot});

  final DockController dock;
  final int slot;

  @override
  State<AppsPicker> createState() => _AppsPickerState();
}

class _AppsPickerState extends State<AppsPicker> {
  String _query = '';

  @override
  void initState() {
    super.initState();
    if (!widget.dock.loaded) widget.dock.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return DecoratedBox(
      key: const Key('apps-picker'),
      decoration: const BoxDecoration(),
      child: Material(
        type: MaterialType.transparency,
        child: Padding(
          padding: EdgeInsets.only(bottom: keyboard),
          child: ListenableBuilder(
            listenable: widget.dock,
            builder: (context, _) {
              final current = widget.dock.slots[widget.slot];
              final q = _query.trim().toLowerCase();
              final apps = [for (final a in widget.dock.installed) if (q.isEmpty || a.label.toLowerCase().contains(q)) a];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 10),
                  Center(child: Container(width: 42, height: 4, color: c.pick)),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                    child: Text('App ${widget.slot + 1} del disco', style: display(size: 24, color: c.ink)),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                    child: TextField(
                      key: const Key('apps-picker-search'),
                      onChanged: (value) => setState(() => _query = value),
                      style: const TextStyle(fontSize: 16),
                      decoration: const InputDecoration(hintText: 'Buscar app', isDense: true, prefixIcon: Icon(Icons.search_rounded)),
                    ),
                  ),
                  if (current != null)
                    ListTile(
                      key: const Key('apps-picker-clear'),
                      leading: Icon(Icons.close_rounded, color: c.warn),
                      title: Text('Dejar vacía', style: TextStyle(fontFamily: appFont, color: c.warn, fontSize: 16)),
                      onTap: () async {
                        await widget.dock.clearSlot(widget.slot);
                        if (context.mounted) Navigator.of(context).pop();
                      },
                    ),
                  Expanded(
                    child: !widget.dock.loaded
                        ? Center(child: Text('Buscando apps…', style: lcdStatus(color: c.dim)))
                        : apps.isEmpty
                        ? Center(child: Text('No hay apps con ese nombre.', style: lcdStatus(color: c.dim)))
                        : ListView.builder(
                            padding: const EdgeInsets.only(bottom: 24),
                            itemCount: apps.length,
                            itemBuilder: (context, i) {
                              final app = apps[i];
                              return ListTile(
                                key: Key('apps-picker-${app.package}'),
                                leading: ClipOval(child: Image.memory(app.icon, width: 40, height: 40, gaplessPlayback: true)),
                                title: Text(app.label, style: TextStyle(fontFamily: appFont, color: c.ink, fontSize: 16)),
                                trailing: app.package == current?.package ? Icon(Icons.check_rounded, color: c.accent) : null,
                                onTap: () async {
                                  await widget.dock.setSlot(widget.slot, app.package);
                                  if (context.mounted) Navigator.of(context).pop();
                                },
                              );
                            },
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
}
