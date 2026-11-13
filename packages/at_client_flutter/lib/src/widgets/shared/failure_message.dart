import 'dart:async';
import 'dart:io' show SocketException;

import 'package:at_client/at_client.dart';

/// What a dialog shows when its operation on [atSign] failed with [error]: a
/// keys problem's own message, an atServer refusal's cause in plain words,
/// [network] for a failure to reach a server, and otherwise that something
/// went wrong, with the error's message.
///
/// It holds no stack trace and no exception type.
String failureMessage(String atSign, Object error, {required String network}) {
  if (error is AtKeysUnusableException) return _firstLine(error.message);
  final refusal = switch (error) {
    AtOpenRefusedException(:final state) => _refusal(atSign, state.cause),
    AtCredentialRefusedException(:final state) => _refusal(atSign, state.cause),
    _ => null,
  };
  if (refusal != null) return refusal;
  if (_isNetworkFailure(error)) return network;
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

bool _isNetworkFailure(Object error) =>
    error is AtTimeoutException ||
    error is SecondaryConnectException ||
    error is RootServerConnectivityException ||
    error is SecondaryServerConnectivityException ||
    error is AtIOException ||
    error is TimeoutException ||
    error is SocketException;

/// [error]'s message, without the type its text starts with.
String _messageOf(Object error) {
  final text = switch (error) {
    AtException(:final message) => message,
    // NOTE: a FormatException's text carries its source; only its message
    // is shown.
    FormatException(:final message) => message,
    _ => '$error'.replaceFirst(RegExp(r'^[A-Za-z_]\w*: '), ''),
  };
  return _firstLine(text);
}

String _firstLine(String text) => text.split('\n').first.trim();
