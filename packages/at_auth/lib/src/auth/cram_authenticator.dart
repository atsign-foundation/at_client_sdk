import 'dart:async';

import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_auth/src/auth/at_authenticator.dart';

/// Logs a lookup's connection in with an atSign's CRAM secret.
class CramAuthenticator {
  CramAuthenticator();

  /// The lookups a CRAM authentication is running on.
  static final Expando<bool> _running = Expando();

  /// Logs [atLookUp]'s connection in with [cramSecret] and returns true once
  /// the atServer accepts it, then puts back the authenticator [atLookUp] had,
  /// unless another was installed meanwhile.
  ///
  /// Nothing else may use [atLookUp] until this returns: a command sent
  /// meanwhile authenticates with the CRAM secret. A second call on the same
  /// lookup meanwhile throws [StateError] and installs nothing.
  ///
  /// The CRAM login serves the commands that need no authentication, such as
  /// a first enrollment request; the next command that needs authentication
  /// logs in afresh with the authenticator then installed.
  Future<bool> authenticate(
    String atSign,
    String cramSecret,
    AtLookUp atLookUp, {
    Duration retryInterval = const Duration(seconds: 2),
    Duration timeout = const Duration(seconds: 30),
    int maxRetries = 10,
  }) async {
    if (_running[atLookUp] ?? false) {
      throw StateError('A CRAM authentication is already running on this '
          'lookup for $atSign');
    }
    _running[atLookUp] = true;
    final previous = atLookUp.authenticator;
    final cram = authenticatorForCramSecret(atSign, cramSecret);
    atLookUp.authenticator = cram;
    try {
      return await atLookUp.pkamAuthenticate();
    } on UnAuthenticatedException catch (e) {
      if (e.message.startsWith('Cram authentication failed')) rethrow;
      throw UnAuthenticatedException(
          'Cram authentication failed for $atSign: ${e.message}');
    } finally {
      if (identical(atLookUp.authenticator, cram)) {
        atLookUp.authenticator = previous;
      }
      _running[atLookUp] = null;
    }
  }
}
