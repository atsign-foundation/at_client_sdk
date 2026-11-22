import 'package:at_client/at_client.dart';
import 'package:flutter/material.dart';

/// The Cancel a dialog offers while it waits on a pending enrollment, which
/// abandons the request once the user confirms.
mixin CancelsEnrollment<T extends StatefulWidget> on State<T> {
  /// The atSign the enrollment is for.
  String get atSign;

  AtSignLogger get logger;

  /// The enrollment the dialog waits on, while it waits.
  PendingEnrollment? get waitingOn;

  /// Opens a client on the keys whose approval was written before the Cancel
  /// took effect.
  Future<AtClient> openOnApprovedKeys();

  /// Hands back [client], opened on the approved keys, by closing the dialog
  /// with it.
  Future<void> handBack(AtClient client) async =>
      Navigator.of(context).pop(client);

  /// Whether the dialog is there to report to and to close: mounted, with its
  /// route not yet popped, by the dialog or by the user.
  bool get showing => mounted && (ModalRoute.of(context)?.isActive ?? true);

  /// Closes the dialog, unless it has closed already.
  void closeDialog() {
    if (showing) Navigator.of(context).pop();
  }

  /// The enrollment whose Cancel the user confirmed.
  PendingEnrollment? _cancelled;

  /// The enrollment a confirmed Cancel could not abandon, which Cancel
  /// tries again.
  PendingEnrollment? _abandoning;

  /// The Cancel confirmation while it is showing.
  BuildContext? _confirming;

  /// Whether the dialog offers Cancel: while it waits, and after a confirmed
  /// Cancel that could not remove the keys.
  bool get offersCancel => waitingOn != null || _abandoning != null;

  /// What the dialog says after a confirmed Cancel that could not remove the
  /// keys, and null before one.
  String? get abandonFailure {
    final abandoning = _abandoning;
    if (abandoning == null) return null;
    return 'Could not abandon enrollment '
        '${clipForMessage(abandoning.enrollmentId)}: its keys are still in the '
        'key store. Choose Cancel to try again.';
  }

  /// Whether [error], which ended the wait, comes from a Cancel the user
  /// confirmed, which says itself what came of it.
  bool endedByCancel(Object error) =>
      error is AtEnrollmentCancelledException && _cancelled != null;

  /// Closes the Cancel confirmation, when it is showing, as the approval
  /// arrives.
  void closeConfirmation() {
    final confirming = _confirming;
    if (confirming != null && confirming.mounted) {
      Navigator.of(confirming).pop(false);
    }
  }

  /// Asks the user to confirm abandoning the request, then cancels it.
  Future<void> onCancel() async {
    final retrying = _abandoning;
    final pending = retrying ?? waitingOn;
    if (pending == null) return;
    if (retrying == null && !await _confirmAbandon(pending.enrollmentId)) {
      return;
    }
    _cancelled = pending;
    try {
      await pending.cancel();
    } catch (e) {
      logger.warning(
        'Could not remove the pending keys of enrollment '
        '"${clipForMessage(pending.enrollmentId, quote: '"')}" of $atSign: $e',
      );
      if (!mounted) return;
      setState(() => _abandoning = pending);
      return;
    }
    if (!mounted) return;
    if (pending.approved) {
      await _openApproved(pending);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Enrollment ${clipForMessage(pending.enrollmentId)} abandoned. Ask '
          'the manager of '
          '$atSign to deny it.',
        ),
      ),
    );
    closeDialog();
  }

  /// Hands back a client on the keys whose approval was written before the
  /// Cancel took effect, which lets the approval stand.
  Future<void> _openApproved(PendingEnrollment pending) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'The approval of enrollment ${clipForMessage(pending.enrollmentId)} '
          'landed before the Cancel took effect, so it stands.',
        ),
      ),
    );
    final AtClient client;
    try {
      client = await openOnApprovedKeys();
    } catch (e) {
      logger.warning(
        'Could not open $atSign on the approved keys of enrollment '
        '"${clipForMessage(pending.enrollmentId, quote: '"')}": $e',
      );
      if (mounted) Navigator.of(context).pop();
      return;
    }
    if (!showing) {
      // NOTE: nothing receives a client opened after the dismissal, and
      // while it is live the atSign cannot be opened again.
      await client.stop();
      return;
    }
    await handBack(client);
  }

  /// Whether the user confirms abandoning enrollment [enrollmentId].
  Future<bool> _confirmAbandon(String enrollmentId) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) {
          _confirming = context;
          return AlertDialog(
            title: const Text('Abandon this request?'),
            content: Text(
              'This abandons enrollment ${clipForMessage(enrollmentId)} of '
              '$atSign. '
              'Trying again needs a new OTP from another enrollment of '
              '$atSign.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Keep waiting'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Abandon'),
              ),
            ],
          );
        },
      ).whenComplete(() => _confirming = null) ??
      false;
}
