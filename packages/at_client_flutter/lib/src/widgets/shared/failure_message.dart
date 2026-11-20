import 'dart:async';
import 'dart:io' show SocketException;

import 'package:at_client/at_client.dart';
import 'package:at_lookup/at_lookup.dart' show AtLookUpException;

/// What a dialog shows when its operation on [atSign] failed with [error].
///
/// For an [AtNoCredentialException], it says this device's enrollment ended
/// or never completed, and to enroll the device again. For an
/// [AtEnrollmentPendingException], it says the enrollment is still waiting
/// for approval, and to enroll again from this app, unless several pending
/// enrollments matched, when it says this device asked more than once and
/// to enroll from this app, which waits for this app's own request. For any
/// other [AtKeysUnusableException], it is the first line of that exception's
/// message. For an atServer's refusal, wrapped or as thrown and classified by
/// the client's connection, or an atSign not in the atDirectory, it is the
/// cause in plain words. For a wait that ran out, it is [timedOut].
/// For any other failure to reach a server, as the client's connection
/// classifies one, it is [unreachable], which defaults to saying the atServer
/// for [atSign] could not be reached. For anything else, it says something
/// went wrong, with the first line of the error's message.
///
/// It holds no stack trace and no exception type.
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
  if (error is AtEnrollmentPendingException && error.severalMatched) {
    return 'This device has asked to enroll $atSign more than once, and none '
        "of those requests has been approved yet, so this screen can't tell "
        'which one to wait for. Enroll this device from this app: it picks '
        "up this app's own request and waits for that one.";
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
    _
        when classified != null &&
            (classified.isRefused ||
                classified.cause == AtConnectionCause.noAtServer) =>
      _refusal(atSign, classified.cause),
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
