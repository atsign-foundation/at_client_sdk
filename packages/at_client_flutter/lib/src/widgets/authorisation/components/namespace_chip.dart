import 'package:at_auth/at_auth.dart';
import 'package:flutter/material.dart';

class NamespaceChip extends StatelessWidget {
  const NamespaceChip({required this.permission, super.key});

  final NamespacePermission permission;

  @override
  Widget build(BuildContext context) {
    final buffer = StringBuffer();
    if (permission.read) {
      buffer.write('Read');
    }
    if (permission.write) {
      if (buffer.isNotEmpty) {
        buffer.write('/');
      }
      buffer.write('Write');
    }
    return Chip(
      side: const BorderSide(color: Colors.transparent),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SelectableText(
            permission.namespace,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(width: 4),
          Text(
            buffer.toString(),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
          ),
        ],
      ),
    );
  }
}
