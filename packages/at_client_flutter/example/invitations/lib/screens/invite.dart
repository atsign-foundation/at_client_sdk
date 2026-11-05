import 'dart:convert';

import 'package:at_client/at_client_mixins.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import '../session.dart';

/// Where the landing page is hosted. Replace it with the app's own domain,
/// which also serves the page's `.well-known` association files.
const String linkBase = 'https://invite.example.com';

/// Invites someone, who need not have an atSign yet.
class InviteScreen extends StatefulWidget {
  const InviteScreen({super.key});

  @override
  State<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends State<InviteScreen> {
  final _contact = TextEditingController();
  final _from = TextEditingController();
  final _message = TextEditingController();
  final _content = TextEditingController();
  bool _contentSeparately = false;
  bool _busy = false;
  CreatedInvitation? _created;

  Future<void> _invite() async {
    if (_contact.text.trim().isEmpty || _from.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      final content = _content.text.trim();
      final created = await Session.instance.invitations!.invite(
        publicDetails: InviteDetails(
          inviterName: _from.text.trim(),
          message: _message.text.trim(),
        ).toJson(),
        content: content.isEmpty ? null : PrivateContent(content).toJson(),
        contentOutOfBand: content.isNotEmpty && _contentSeparately,
      );
      if (mounted) setState(() => _created = created);
      await (await Session.instance.contacts).create(
        id: created.link.id,
        obj: Contact(name: _contact.text.trim()),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final created = _created;
    return Scaffold(
      appBar: AppBar(title: const Text('Invite someone')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: created == null ? _form() : _result(created),
      ),
    );
  }

  List<Widget> _form() => [
    TextField(
      controller: _contact,
      decoration: const InputDecoration(labelText: 'Who are you inviting?'),
    ),
    TextField(
      controller: _from,
      decoration: const InputDecoration(
        labelText: 'Your name, as they will see it',
      ),
    ),
    TextField(
      controller: _message,
      decoration: const InputDecoration(labelText: 'A message (optional)'),
    ),
    TextField(
      controller: _content,
      minLines: 2,
      maxLines: 5,
      decoration: const InputDecoration(
        labelText: 'Something private for them (optional)',
        helperText: 'Encrypted now; they can read it once you confirm them',
      ),
    ),
    SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('Send the encrypted content separately'),
      subtitle: const Text('e.g. in the body of an email'),
      value: _contentSeparately,
      onChanged: (v) => setState(() => _contentSeparately = v),
    ),
    const SizedBox(height: 16),
    FilledButton(
      onPressed: _busy ? null : _invite,
      child: Text(_busy ? 'Creating…' : 'Create invitation'),
    ),
  ];

  List<Widget> _result(CreatedInvitation created) {
    final link = created.link.toUrl(linkBase);
    final sealed = created.outOfBandContent;
    return [
      const Text('Send these two separately, over channels you trust.'),
      const SizedBox(height: 16),
      _copyable('The link', link),
      _copyable('The code', created.code),
      if (sealed != null)
        _copyable(
          'The encrypted content, to send alongside the link',
          jsonEncode(sealed.toJson()),
        ),
    ];
  }

  Widget _copyable(String label, String value) => Card(
    child: ListTile(
      title: Text(label),
      subtitle: SelectableText(value),
      trailing: IconButton(
        icon: const Icon(Icons.copy),
        onPressed: () => Clipboard.setData(ClipboardData(text: value)),
      ),
    ),
  );
}
