import 'dart:async';
import 'dart:io' show SocketException;

import 'package:at_client/at_client.dart';
import 'package:at_lookup/at_lookup.dart' show AtLookUpException;

/// What a dialog shows when its operation on [atSign] failed with [error]: a
/// keys problem's own message, or for keys holding no credential or only an
/// enrollment awaiting approval what to do next, an atServer refusal's cause
/// in plain words,
/// [timedOut] for a wait that ran out, [unreachable] for any other failure to
/// reach a server, as the client's connection classifies one, and otherwise
/// that something went wrong, with the error's message.
///
/// [unreachable] defaults to saying the atServer for [atSign] could not be
/// reached. It holds no stack trace and no exception type.
String failureMessage(
  String atSign,
  Object error, {
  required String timedOut,
  String? unreachable,
}) {
  if (error is AtNoCredentialException) {
    return "This device's enrollment for $atSign was denied, cancelled or "
        'expired, or never completed. Enroll this device again to use '
        '$atSign here.';
  }
  if (error is AtEnrollmentPendingException) {
    return "This device's enrollment for $atSign is still waiting for "
        'approval and cannot be completed here. Enroll this device again '
        'from this app to carry on.';
  }
  if (error is AtKeysUnusableException) return _firstLine(error.message);
  final classified = classifyConnectionFailure(error);
  final refusal = switch (error) {
    AtOpenRefusedException(:final state) => _refusal(atSign, state.cause),
    AtCredentialRefusedException(:final state) => _refusal(atSign, state.cause),
    _ when classified?.cause == AtConnectionCause.noAtServer => _refusal(
      atSign,
      AtConnectionCause.noAtServer,
    ),
    _ => null,
  };
  if (refusal != null) return refusal;
  if (_isTimeout(error)) return timedOut;
  if (error is SocketException ||
      classified?.cause == AtConnectionCause.unreachable) {
    return unreachable ??
        'The atServer for $atSign could not be reached. Please check your '
            'connection and try again.';
  }
  return 'Something went wrong with $atSign: ${_messageOf(error)}';
}

/// [cause], an atServer's refusal of [atSign], in plain words.
String? _refusal(String atSign, AtConnectionCause? cause) => switch (cause) {
  AtConnectionCause.revoked =>
    "This device's access to $atSign has been revoked.",
  AtConnectionCause.enrollmentNotApproved =>
    "This device's enrollment for $atSign has not been approved yet.",
  AtConnectionCause.enrollmentDenied =>
    "This device's enrollment for $atSign was denied.",
  AtConnectionCause.noAtServer => '$atSign is not in the atDirectory.',
  AtConnectionCause.invalidEnrollment =>
    "This device's enrollment for $atSign has expired.",
  AtConnectionCause.unauthenticated =>
    "The atServer for $atSign did not accept this device's keys.",
  AtConnectionCause.otherRefusal =>
    'The atServer for $atSign refused this device.',
  _ => null,
};

/// The code at_lookup gives a wait that ran out.
const _timedOutCode = 'AT0023';

bool _isTimeout(Object error) =>
    error is AtTimeoutException ||
    error is TimeoutException ||
    (error is AtLookUpException && error.errorCode == _timedOutCode);

/// The first line of [error]'s text, without the type it starts with.
///
/// A [FormatException]'s source, and any stack trace, start on a later line.
String _messageOf(Object error) =>
    _firstLine('$error'.replaceFirst(RegExp(r'^[A-Za-z_]\w*: '), ''));

String _firstLine(String text) => text.split('\n').first.trim();
