import 'dart:async';

import 'package:at_auth/at_auth.dart'
    show AtKeysFileOverwriteException, AtKeysIo, WrittenAtKeysIo;
import 'package:at_client/at_client.dart';
import 'package:at_client_flutter/src/lifecycle/atsign_flows.dart';
import 'package:at_client_flutter/src/widgets/shared/enrollment_cancel.dart';
import 'package:at_client_flutter/src/widgets/shared/failure_message.dart';
import 'package:at_client_flutter/src/widgets/shared/loading.dart';
import 'package:flutter/material.dart';

/// A dialog that opens a client on keys the app already holds and hands it
/// back; the app owns it.
///
/// Use `PkamDialog.show` to display the dialog and handle the login.
///
/// Required Parameters:
/// - [atSign]: the atSign to open.
/// - [keys]: the store holding its keys.
/// - [preference]: the client's preference; [rootDomain] is stamped on it
///   when given.
///
/// Optional Parameters:
/// - [storage]: the client's local storage; with none, a Hive store under the
///   preference's `hiveStoragePath`, or the app's support directory.
/// - [backupKeys]: stores the keys are copied into once the client is open,
///   each skipped when it already holds an entry for the atSign.
/// - [title]: A title string for the dialog (default: "Authenticating via pkam").
/// - [description]: A description shown while the login is in progress
///   (default: "Validating your atKeys...").
/// - [onAuthenticationComplete]: invoked with the client once it is open,
///   even after the user has left the dialog; with none, a client opened
///   after the user has left is stopped.
///
/// The client comes back online, offline or refused, and its `connection`
/// says which; only a refusal on a device that has never held the atSign
/// online is a failure here, beside keys `Atsign.open` cannot use. A failure
/// shows a message chosen by what failed, and no stack trace.
///
/// Keys holding only an enrollment awaiting approval, in a store that can be
/// written, are waited on as `ApkamActivationDialog` waits: the client opens
/// once the request is approved, and leaving stops the wait and keeps the
/// request. While it waits it offers Cancel, which, once the user confirms,
/// abandons the request (`PendingEnrollment.cancel`), as
/// `ApkamActivationDialog`'s does.
///
/// Returns:
/// - The `AtClient`, or null if the process fails or is cancelled.
class PkamDialog extends StatefulWidget {
  const PkamDialog({
    super.key,
    required this.atSign,
    required this.keys,
    required this.preference,
    this.rootDomain,
    this.storage,
    this.lookUps,
    this.onAuthenticationComplete,
    this.title,
    this.description,
    this.backupKeys,
    this.flows = const AtsignFlows(),
  });

  final String atSign;
  final AtKeysIo keys;
  final AtClientPreference preference;
  final AtRootDomain? rootDomain;
  final AtClientStorage? storage;

  /// Builds every connection the client opens; see `Atsign.open`.
  final AtLookUpFactory? lookUps;
  final void Function(AtClient client)? onAuthenticationComplete;
  final String? title;
  final String? description;
  final List<WrittenAtKeysIo>? backupKeys;

  /// Injection seam for tests; defaults to the real lifecycle verbs.
  final AtsignFlows flows;

  static Future<AtClient?> show(
    BuildContext context, {
    required String atSign,
    required AtKeysIo keys,
    required AtClientPreference preference,
    AtRootDomain? rootDomain,
    AtClientStorage? storage,
    AtLookUpFactory? lookUps,
    void Function(AtClient client)? onAuthenticationComplete,
    String? title,
    String? description,
    List<WrittenAtKeysIo>? backupKeys,
  }) async {
    return showDialog<AtClient>(
      context: context,
      builder: (context) => PkamDialog(
        atSign: atSign,
        keys: keys,
        preference: preference,
        rootDomain: rootDomain,
        storage: storage,
        lookUps: lookUps,
        onAuthenticationComplete: onAuthenticationComplete,
        title: title,
        description: description,
        backupKeys: backupKeys,
      ),
    );
  }

  @override
  State<PkamDialog> createState() => _PkamDialogState();
}

class _PkamDialogState extends State<PkamDialog>
    with CancelsEnrollment<PkamDialog> {
  final AtSignLogger _logger = AtSignLogger('PkamDialog');
  PendingEnrollment? _waitingOn;

  @override
  String get atSign => widget.atSign;

  @override
  AtSignLogger get logger => _logger;

  @override
  PendingEnrollment? get waitingOn => _waitingOn;

  @override
  Future<AtClient> openOnApprovedKeys() => widget.flows.open(
    widget.atSign,
    keys: widget.keys,
    preference: under(widget.preference, widget.rootDomain),
    storage: widget.storage,
    lookUps: widget.lookUps,
  );

  @override
  void initState() {
    super.initState();
    // Kick off the login exactly once. Starting it here rather than in
    // build() means a widget rebuild can't spawn a second open() call.
    _authenticate();
  }

  Future<void> _authenticate() async {
    final AtClient? client;
    try {
      client = await _openOrResume();
    } catch (e) {
      if (!endedByCancel(e)) _fail(e);
      return;
    }
    if (client != null) await handBack(client);
  }

  /// Backs up the keys [client] opened on, tells `onAuthenticationComplete`,
  /// and closes the dialog with it. When the dialog has closed already and
  /// there is no `onAuthenticationComplete`, it stops [client] instead.
  @override
  Future<void> handBack(AtClient client) async {
    try {
      await _backUp();
      final onAuthenticated = widget.onAuthenticationComplete;
      if (onAuthenticated != null) {
        onAuthenticated(client);
      } else {
        _logger.info(
          '${widget.atSign} opened; connection is '
          '${client.connection.current}',
        );
      }
      if (showing) {
        Navigator.of(context).pop(client);
      } else if (onAuthenticated == null) {
        // NOTE: nothing receives a client opened after the user left, and
        // while it is live the atSign cannot be opened again.
        await _stopClient(client);
      }
    } catch (e) {
      // NOTE: a client that opened before the failure reaches nobody, and
      // while it is live the atSign cannot be opened again.
      await _stopClient(client);
      _fail(e);
    }
  }

  /// Shows what [error] says failed and closes the dialog with no client.
  void _fail(Object error) {
    _logger.severe('Authentication via PKAM failed: $error');
    if (!mounted) return;
    final message = failureMessage(
      widget.atSign,
      error,
      timedOut:
          'Authentication timed out — the atServer could not be reached. '
          'Please check your connection and try again.',
    );
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
    closeDialog();
  }

  /// The client opened on the keys, or, when they hold only an enrollment
  /// awaiting approval in a store that can be written, the client it opens
  /// once approved; null when the user left first.
  Future<AtClient?> _openOrResume() async {
    final preference = under(widget.preference, widget.rootDomain);
    try {
      return await widget.flows.open(
        widget.atSign,
        keys: widget.keys,
        preference: preference,
        storage: widget.storage,
        lookUps: widget.lookUps,
      );
    } on AtEnrollmentPendingException {
      final keys = widget.keys;
      if (keys is! WrittenAtKeysIo) rethrow;
      final pending = await widget.flows.resumeEnrollment(
        widget.atSign,
        keys: keys,
        preference: preference,
        lookUps: widget.lookUps,
      );
      if (pending == null) rethrow;
      return _awaitApproval(pending, preference);
    }
  }

  Future<AtClient?> _awaitApproval(
    PendingEnrollment pending,
    AtClientPreference preference,
  ) async {
    if (!mounted) {
      await _stop(pending);
      return null;
    }
    setState(() => _waitingOn = pending);
    try {
      return await pending.client(
        preference,
        storage: await storageOrDefault(
          widget.atSign,
          preference,
          widget.storage,
        ),
      );
    } on StoppedException {
      if (!mounted) return null;
      rethrow;
    } finally {
      if (mounted) {
        closeConfirmation();
        setState(() => _waitingOn = null);
      } else {
        _waitingOn = null;
      }
    }
  }

  /// Stops [pending]'s wait and keeps the request. A failure is logged,
  /// since the dialog is gone and there is nobody to tell.
  Future<void> _stop(PendingEnrollment pending) async {
    try {
      await pending.stop();
    } catch (e) {
      _logger.warning(
        'Could not stop the wait for enrollment '
        '"${clipForMessage(pending.enrollmentId, quote: '"')}" of '
        '${widget.atSign}: $e',
      );
    }
  }

  /// Stops [client], which the dialog will not hand back. A failure is
  /// logged, since the open has already failed and that is what is shown.
  Future<void> _stopClient(AtClient client) async {
    try {
      await client.stop();
    } catch (e) {
      _logger.warning('Could not stop the client of ${widget.atSign}: $e');
    }
  }

  @override
  void dispose() {
    final waitingOn = _waitingOn;
    if (waitingOn != null) unawaited(_stop(waitingOn));
    super.dispose();
  }

  /// Copies the keys the client opened on into each backup store that does
  /// not already hold the atSign.
  Future<void> _backUp() async {
    final backups = widget.backupKeys;
    if (backups == null || backups.isEmpty) return;
    final keys = await widget.keys.read(widget.atSign);
    for (final backup in backups) {
      try {
        await backup.write(widget.atSign, keys);
      } on AtKeysFileOverwriteException {
        _logger.finer('${backup.runtimeType} already holds ${widget.atSign}');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final failure = abandonFailure;
    return Dialog(
      child: Container(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (failure != null)
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 240),
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Text(failure),
                ),
              )
            else
              LoadingDialog(
                title: widget.title ?? "Authenticating via pkam",
                description: _waitingOn == null
                    ? widget.description ?? "Validating your atKeys..."
                    : 'Waiting for approval of enrollment '
                          '${clipForMessage(_waitingOn!.enrollmentId)}..',
                themeData: Theme.of(context),
              ),
            if (offersCancel)
              TextButton(onPressed: onCancel, child: const Text('Cancel')),
          ],
        ),
      ),
    );
  }
}
