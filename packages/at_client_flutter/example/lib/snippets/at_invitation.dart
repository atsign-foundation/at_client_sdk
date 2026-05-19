import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:at_client_flutter/at_client_flutter.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher_string.dart';

typedef InviteReceived = void Function(String message, String fromAtSign);

class AtInvite {
  const AtInvite({
    required this.inviteId,
    required this.uri,
    required this.passcode,
  });

  final String inviteId;
  final Uri uri;
  final String passcode;
}

/// Copy/paste invitation flow for Flutter apps using at_client_flutter.
///
/// The inviter stores a pending invite under `invite.<id>`, sends the invite id
/// and passcode out of band, then shares the original message after the invitee
/// writes a matching `invite-ack.<id>` key.
class AtInvitationSnippet {
  AtInvitationSnippet({required this.atClient, required this.inviteBaseUrl});

  static const _inviteKey = 'invite';
  static const _inviteAckKey = 'invite-ack';
  static const _idAlphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';

  final AtClient atClient;
  final String inviteBaseUrl;

  StreamSubscription<AtNotification>? _notificationSubscription;

  Future<void> startListening({InviteReceived? onInviteReceived}) async {
    if (_notificationSubscription != null) return;

    _notificationSubscription = atClient.notificationService
        .subscribe(regex: _inviteKey, shouldDecrypt: true)
        .listen((notification) {
          unawaited(_handleNotification(notification, onInviteReceived));
        });
  }

  Future<void> stopListening() async {
    await _notificationSubscription?.cancel();
    _notificationSubscription = null;
  }

  Future<AtInvite?> shareInvite(
    BuildContext context, {
    required String message,
  }) async {
    final currentAtSign = atClient.getCurrentAtSign();
    if (currentAtSign == null || currentAtSign.isEmpty) {
      throw StateError('Cannot create an invite without a current atSign.');
    }

    final inviteId = _newInviteId();
    final passcode = _newPasscode();
    final payload = _InvitePayload(
      passcode: passcode,
      identifier: inviteId,
      message: message,
    );

    final inviteKey = _selfKey('$_inviteKey.$inviteId');
    final saved = await atClient.put(inviteKey, jsonEncode(payload));
    if (!saved) return null;

    final invite = AtInvite(
      inviteId: inviteId,
      uri: _inviteUri(inviteId, currentAtSign),
      passcode: passcode,
    );
    if (!context.mounted) return invite;

    await showDialog<void>(
      context: context,
      builder: (context) =>
          _InviteShareDialog(inviteUri: invite.uri, passcode: passcode),
    );
    return invite;
  }

  Future<void> acknowledgeInvite(
    BuildContext context, {
    required String inviteId,
    required String inviterAtSign,
  }) async {
    final passcode = await showDialog<String>(
      context: context,
      builder: (context) => const _PasscodeDialog(),
    );
    if (passcode == null || passcode.length != 4) return;

    final ackPayload = _InvitePayload(
      passcode: passcode,
      identifier: inviteId,
      message: 'invite acknowledgement',
    );
    final ackKey = _sharedKey('$_inviteAckKey.$inviteId', inviterAtSign);
    await atClient.put(ackKey, jsonEncode(ackPayload));
  }

  Future<void> _handleNotification(
    AtNotification notification,
    InviteReceived? onInviteReceived,
  ) async {
    final keyName = _notificationKeyName(notification.key);
    if (!keyName.startsWith(_inviteKey)) return;

    final value = notification.value;
    if (value == null || value.isEmpty) return;

    if (keyName.startsWith(_inviteAckKey)) {
      await _processInviteAck(value, notification.from);
      return;
    }

    onInviteReceived?.call(value, notification.from);
  }

  Future<void> _processInviteAck(String ackJson, String fromAtSign) async {
    final ackPayload = _InvitePayload.fromJsonString(ackJson);
    if (ackPayload.identifier.isEmpty) return;

    final inviteKey = _selfKey('$_inviteKey.${ackPayload.identifier}');
    final storedValue = await atClient.get(inviteKey);
    final storedPayload = _InvitePayload.fromJsonString(
      storedValue.value as String,
    );

    if (storedPayload.passcode != ackPayload.passcode) return;

    final sharedInviteKey = _sharedKey(
      '$_inviteKey.${storedPayload.identifier}',
      fromAtSign,
    );
    await atClient.put(sharedInviteKey, storedPayload.message);
  }

  AtKey _selfKey(String key) {
    return AtKey()
      ..key = key
      ..metadata = (Metadata()..ttr = -1);
  }

  AtKey _sharedKey(String key, String sharedWith) {
    return AtKey()
      ..key = key
      ..sharedWith = sharedWith
      ..metadata = (Metadata()..ttr = -1);
  }

  Uri _inviteUri(String inviteId, String currentAtSign) {
    final baseUri = Uri.parse(inviteBaseUrl);
    return baseUri.replace(
      queryParameters: {
        ...baseUri.queryParameters,
        'key': inviteId,
        'atsign': currentAtSign,
      },
    );
  }

  static String _notificationKeyName(String key) {
    final withoutSharedWith = key.contains(':') ? key.split(':').last : key;
    return withoutSharedWith.split('@').first.trim();
  }

  static String _newPasscode() {
    return Random.secure().nextInt(10000).toString().padLeft(4, '0');
  }

  static String _newInviteId() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => _idAlphabet[random.nextInt(_idAlphabet.length)],
    ).join();
  }
}

class _InvitePayload {
  const _InvitePayload({
    required this.passcode,
    required this.identifier,
    required this.message,
  });

  factory _InvitePayload.fromJsonString(String value) {
    final json = jsonDecode(value) as Map<String, dynamic>;
    return _InvitePayload(
      passcode: json['passcode'] as String? ?? '',
      identifier: json['identifier'] as String? ?? '',
      message: json['message'] as String? ?? '',
    );
  }

  final String passcode;
  final String identifier;
  final String message;

  Map<String, dynamic> toJson() {
    return {'passcode': passcode, 'identifier': identifier, 'message': message};
  }
}

enum _InviteShareMethod { sms, email }

class _InviteShareDialog extends StatefulWidget {
  const _InviteShareDialog({required this.inviteUri, required this.passcode});

  final Uri inviteUri;
  final String passcode;

  @override
  State<_InviteShareDialog> createState() => _InviteShareDialogState();
}

class _InviteShareDialogState extends State<_InviteShareDialog> {
  final _destinationController = TextEditingController();
  _InviteShareMethod _method = _InviteShareMethod.sms;
  String? _errorText;

  @override
  void dispose() {
    _destinationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Share invite'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SegmentedButton<_InviteShareMethod>(
            segments: const [
              ButtonSegment(
                value: _InviteShareMethod.sms,
                label: Text('SMS'),
                icon: Icon(Icons.sms_outlined),
              ),
              ButtonSegment(
                value: _InviteShareMethod.email,
                label: Text('Email'),
                icon: Icon(Icons.mail_outline),
              ),
            ],
            selected: {_method},
            onSelectionChanged: (selection) {
              setState(() {
                _method = selection.single;
                _destinationController.clear();
                _errorText = null;
              });
            },
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _destinationController,
            decoration: InputDecoration(
              labelText: _method == _InviteShareMethod.sms
                  ? 'Phone number'
                  : 'Email address',
              errorText: _errorText,
            ),
            keyboardType: _method == _InviteShareMethod.sms
                ? TextInputType.phone
                : TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            onChanged: (_) {
              if (_errorText != null) setState(() => _errorText = null);
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _share,
          icon: const Icon(Icons.ios_share_outlined),
          label: const Text('Share'),
        ),
      ],
    );
  }

  Future<void> _share() async {
    final destination = _destinationController.text.trim();
    final errorText = _validateDestination(destination);
    if (errorText != null) {
      setState(() => _errorText = errorText);
      return;
    }

    final uri = _shareUri(destination);
    Navigator.pop(context);
    unawaited(_launchShareUri(uri));
  }

  Future<void> _launchShareUri(String uri) async {
    try {
      await launchUrlString(uri);
    } catch (_) {
      // The invite has already been created and shown in the example app.
      // Apps that copy this snippet can surface launch failures however they
      // prefer.
    }
  }

  String? _validateDestination(String destination) {
    if (destination.isEmpty) return 'Enter a destination.';
    if (_method == _InviteShareMethod.sms) {
      if (!RegExp(r'^\+?[0-9 ]{10,}$').hasMatch(destination)) {
        return 'Enter a full phone number.';
      }
      return null;
    }

    final emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!emailPattern.hasMatch(destination)) {
      return 'Enter a valid email address.';
    }
    return null;
  }

  String _shareUri(String destination) {
    final encodedBody = Uri.encodeComponent(
      'You have been invited to join this app.\n'
      'Link: ${widget.inviteUri}\n'
      'Passcode: ${widget.passcode}',
    );

    if (_method == _InviteShareMethod.email) {
      return 'mailto:$destination?subject=Invitation&body=$encodedBody';
    }

    final separator = Platform.isIOS ? '&' : '?';
    return 'sms:$destination${separator}body=$encodedBody';
  }
}

class _PasscodeDialog extends StatefulWidget {
  const _PasscodeDialog();

  @override
  State<_PasscodeDialog> createState() => _PasscodeDialogState();
}

class _PasscodeDialogState extends State<_PasscodeDialog> {
  final _passcodeController = TextEditingController();
  String? _errorText;

  @override
  void dispose() {
    _passcodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Enter invite passcode'),
      content: TextField(
        controller: _passcodeController,
        autofocus: true,
        decoration: InputDecoration(
          labelText: '4-digit passcode',
          errorText: _errorText,
        ),
        keyboardType: TextInputType.number,
        maxLength: 4,
        obscureText: true,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Continue')),
      ],
    );
  }

  void _submit() {
    final passcode = _passcodeController.text.trim();
    if (!RegExp(r'^[0-9]{4}$').hasMatch(passcode)) {
      setState(() => _errorText = 'Enter the 4-digit passcode.');
      return;
    }
    Navigator.pop(context, passcode);
  }
}
