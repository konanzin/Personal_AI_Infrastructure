import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/machine_store.dart';
import '../screens/machines_screen.dart';

/// Chip showing the active machine name. Tap opens a bottom sheet for switching.
class MachineSelector extends StatelessWidget {
  const MachineSelector({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<MachineStore>();
    final active = store.activeMachine;
    if (active == null) return const SizedBox.shrink();

    return ActionChip(
      avatar: const Icon(Icons.dns, size: 16),
      label: Text(active.name, style: const TextStyle(fontSize: 13)),
      onPressed: () => _showSwitcher(context, store),
    );
  }

  void _showSwitcher(BuildContext context, MachineStore store) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
              child: Row(
                children: [
                  Text('Machines',
                      style: Theme.of(ctx)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const MachinesScreen()));
                    },
                    icon: const Icon(Icons.settings, size: 18),
                    label: const Text('Manage'),
                  ),
                ],
              ),
            ),
            const Divider(),
            ...store.machines.map((m) {
              final isActive = m.id == store.activeMachineId;
              return ListTile(
                leading: Icon(Icons.dns,
                    color: isActive
                        ? Theme.of(ctx).colorScheme.primary
                        : null),
                title: Text(m.name,
                    style: TextStyle(
                        fontWeight:
                            isActive ? FontWeight.w600 : FontWeight.normal)),
                subtitle: Text(m.serverUrl,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: isActive
                    ? Icon(Icons.check_circle,
                        color: Theme.of(ctx).colorScheme.primary, size: 20)
                    : null,
                onTap: () {
                  store.switchMachine(m.id);
                  Navigator.pop(ctx);
                },
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
