import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../incoming.dart';

/// Asks for an invitation link, pre-filled from the clipboard, and makes it
/// the pending invitation. Returns whether one was entered.
Future<bool> enterInvitation(BuildContext context) async {
  final clipboard = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
  if (!context.mounted) return false;
  final controller = TextEditingController(text: clipboard?.trim() ?? '');
  final text = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Open an invitation'),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'The invitation link you were sent',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: const Text('Open'),
        ),
      ],
    ),
  );
  if (text == null) return false;
  final accepted = Incoming.instance.offer(text);
  if (!accepted && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('That is not an invitation link')),
    );
  }
  return accepted;
}
