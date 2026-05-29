import 'dart:async';

import 'package:at_client_flutter/at_client_flutter.dart';
import 'package:example/snippets/at_invitation.dart';
import 'package:flutter/material.dart';

class InvitationExamplePage extends StatefulWidget {
  const InvitationExamplePage({super.key});

  @override
  State<InvitationExamplePage> createState() => _InvitationExamplePageState();
}

class _InvitationExamplePageState extends State<InvitationExamplePage> {
  final _inviteBaseUrlController = TextEditingController(
    text: 'https://example.com/invite',
  );
  final _messageController = TextEditingController(text: '{"hello":"world"}');
  final _inviteInputController = TextEditingController();
  final _inviteIdController = TextEditingController();
  final _inviterAtSignController = TextEditingController();
  final _receivedMessages = <String>[];

  late final AtInvitationSnippet _invitations;
  AtInvite? _lastInvite;
  bool _isListening = false;

  @override
  void initState() {
    super.initState();
    _invitations = AtInvitationSnippet(
      atClient: AtClientManager.getInstance().atClient,
      inviteBaseUrl: _inviteBaseUrlController.text.trim(),
    );
    unawaited(_startListening());
  }

  @override
  void dispose() {
    unawaited(_invitations.stopListening());
    _inviteBaseUrlController.dispose();
    _messageController.dispose();
    _inviteInputController.dispose();
    _inviteIdController.dispose();
    _inviterAtSignController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = AtClientManager.getInstance().atClient.getCurrentAtSign();

    return Scaffold(
      appBar: AppBar(title: Text('Invitations ($current)')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _inviteBaseUrlController,
            decoration: const InputDecoration(labelText: 'Invite base URL'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _messageController,
            decoration: const InputDecoration(labelText: 'Message'),
            minLines: 2,
            maxLines: 4,
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _shareInvite,
            icon: const Icon(Icons.ios_share_outlined),
            label: const Text('Create invite'),
          ),
          if (_lastInvite != null) ...[
            const SizedBox(height: 16),
            SelectableText('Invite id: ${_lastInvite!.inviteId}'),
            SelectableText('Invite link: ${_lastInvite!.uri}'),
            SelectableText('Passcode: ${_lastInvite!.passcode}'),
          ],
          const Divider(height: 40),
          TextField(
            controller: _inviteInputController,
            decoration: const InputDecoration(labelText: 'Invite link or id'),
            onSubmitted: (_) => _parseInviteInput(),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _parseInviteInput,
            icon: const Icon(Icons.link_outlined),
            label: const Text('Parse invite'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _inviteIdController,
            decoration: const InputDecoration(labelText: 'Invite id'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _inviterAtSignController,
            decoration: const InputDecoration(labelText: 'Inviter atSign'),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _acknowledgeInvite,
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('Acknowledge invite'),
          ),
          const Divider(height: 40),
          Row(
            children: [
              Icon(
                _isListening
                    ? Icons.notifications_active_outlined
                    : Icons.notifications_off_outlined,
              ),
              const SizedBox(width: 8),
              Text(_isListening ? 'Listening' : 'Not listening'),
            ],
          ),
          const SizedBox(height: 12),
          for (final message in _receivedMessages)
            ListTile(
              leading: const Icon(Icons.mail_outline),
              title: Text(message),
            ),
        ],
      ),
    );
  }

  Future<void> _startListening() async {
    await _invitations.startListening(
      onInviteReceived: (message, fromAtSign) {
        if (!mounted) return;
        setState(() {
          _receivedMessages.insert(0, '$fromAtSign: $message');
        });
      },
    );
    if (mounted) setState(() => _isListening = true);
  }

  Future<void> _shareInvite() async {
    try {
      final invitations = AtInvitationSnippet(
        atClient: AtClientManager.getInstance().atClient,
        inviteBaseUrl: _inviteBaseUrlController.text.trim(),
      );
      final invite = await invitations.shareInvite(
        context,
        message: _messageController.text,
      );
      if (!mounted || invite == null) return;
      setState(() => _lastInvite = invite);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Invite error: $e')));
    }
  }

  Future<void> _acknowledgeInvite() async {
    final inviteId = _inviteIdController.text.trim();
    final inviterInput = _inviterAtSignController.text.trim();
    if (inviteId.isEmpty || inviterInput.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invite id and inviter atSign required.')),
      );
      return;
    }
    final inviterAtSign = inviterInput.toAtsign();

    try {
      await _invitations.acknowledgeInvite(
        context,
        inviteId: inviteId,
        inviterAtSign: inviterAtSign,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Acknowledge error: $e')));
    }
  }

  void _parseInviteInput() {
    final input = _inviteInputController.text.trim();
    if (input.isEmpty) return;

    final uri = Uri.tryParse(input);
    final inviteId = uri?.queryParameters['key'];
    final inviter = uri?.queryParameters['atsign'];

    setState(() {
      _inviteIdController.text = inviteId?.isNotEmpty == true
          ? inviteId!
          : input;
      if (inviter?.isNotEmpty == true) {
        _inviterAtSignController.text = inviter!;
      }
    });
  }
}
