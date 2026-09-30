import 'dart:convert';

import 'package:at_client/at_client_mixins.dart';
import 'package:flutter/material.dart';

import '../models.dart';
import '../session.dart';

/// An invitation someone sent: who from, and whether to accept it, and as
/// which of this device's atSigns.
class ReceivedScreen extends StatefulWidget {
  final InvitationLink link;

  const ReceivedScreen({super.key, required this.link});

  @override
  State<ReceivedScreen> createState() => _ReceivedScreenState();
}

class _ReceivedScreenState extends State<ReceivedScreen> {
  final _code = TextEditingController();
  final _name = TextEditingController();
  final _separateContent = TextEditingController();
  ReceivedInvitation? _preview;
  String? _error;
  bool _busy = false;
  List<String> _atSigns = [];

  String get _me => Session.instance.invitations!.me;

  InviteDetails get _details => InviteDetails.fromJson(_preview!.publicDetails);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _preview = null;
      _error = null;
    });
    try {
      final atSigns = await Session.instance.knownAtSigns();
      final item = await Session.instance.invitations!.preview(widget.link);
      if (!mounted) return;
      setState(() {
        _atSigns = {...atSigns, _me}.toList()..sort();
        _preview = item.obj;
        _error = _unavailable(item.obj);
      });
    } catch (e) {
      if (mounted) {
        setState(
          () => _error =
              'This invitation can no longer be opened. It may have been '
              'accepted, withdrawn, or have expired.\n\n$e',
        );
      }
    }
  }

  String? _unavailable(ReceivedInvitation invitation) {
    final from = InviteDetails.fromJson(invitation.publicDetails).inviterName;
    if (invitation.status == ReceivedInvitationStatus.connected) {
      return 'You are already connected with $from.';
    }
    if (DateTime.now().isAfter(invitation.expiresAt)) {
      return 'This invitation from $from has expired.';
    }
    return null;
  }

  Future<void> _switchTo(String atSign) async {
    if (atSign == _me) return;
    setState(() => _busy = true);
    try {
      final signedIn = await Session.instance.signInFromKeychain(
        context,
        atSign: atSign,
      );
      if (signedIn) await _load();
    } catch (e) {
      _snack('Could not switch to $atSign: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _accept() async {
    final code = _code.text.trim();
    if (code.isEmpty) return;
    SealedInvitationContent? separate;
    final pasted = _separateContent.text.trim();
    if (pasted.isNotEmpty) {
      try {
        separate = SealedInvitationContent.fromJson(jsonDecode(pasted));
      } on FormatException {
        _snack('The encrypted content is not in the expected form');
        return;
      }
    }
    setState(() => _busy = true);
    try {
      await Session.instance.invitations!.accept(
        widget.link,
        code,
        details: AcceptanceDetails(name: _name.text.trim()).toJson(),
        outOfBandContent: separate,
      );
      _snack(
        'Sent. ${_details.inviterName} confirms you if the code is right.',
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      _snack('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _decline() async {
    await Session.instance.invitations!.decline(widget.link.id);
    if (mounted) Navigator.of(context).pop();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    return Scaffold(
      appBar: AppBar(title: Text('From ${widget.link.inviter}')),
      body: _error != null
          ? Padding(padding: const EdgeInsets.all(16), child: Text(_error!))
          : preview == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  '${_details.inviterName} (${preview.inviter}) invited you',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (_details.message.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(_details.message),
                ],
                const SizedBox(height: 8),
                Text(
                  preview.sealedContent == null
                      ? 'No private content came with the invitation.'
                      : 'Private content came with it. You can read it once '
                            '${_details.inviterName} confirms you.',
                ),
                const SizedBox(height: 24),
                if (preview.status == ReceivedInvitationStatus.accepted) ...[
                  Text(
                    'You accepted this. If ${_details.inviterName} has not '
                    'confirmed you, check the code and accept again.',
                  ),
                  const SizedBox(height: 16),
                ],
                if (_atSigns.length > 1)
                  InputDecorator(
                    decoration: const InputDecoration(labelText: 'Accept as'),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _me,
                        isDense: true,
                        isExpanded: true,
                        items: [
                          for (final a in _atSigns)
                            DropdownMenuItem(value: a, child: Text(a)),
                        ],
                        onChanged: _busy
                            ? null
                            : (a) => a == null ? null : _switchTo(a),
                      ),
                    ),
                  )
                else
                  Text('Accepting as $_me'),
                TextField(
                  controller: _code,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'The code ${_details.inviterName} sent you',
                  ),
                ),
                TextField(
                  controller: _name,
                  decoration: InputDecoration(
                    labelText:
                        'Your name, as ${_details.inviterName} will see it',
                  ),
                ),
                if (preview.sealedContent == null)
                  TextField(
                    controller: _separateContent,
                    decoration: const InputDecoration(
                      labelText: 'Encrypted content sent separately (optional)',
                    ),
                  ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _busy ? null : _accept,
                  child: Text(_busy ? 'Accepting…' : 'Accept'),
                ),
                TextButton(
                  onPressed: _busy ? null : _decline,
                  child: const Text('Decline'),
                ),
                Text(
                  'Declining tells ${_details.inviterName} nothing.',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
    );
  }
}
