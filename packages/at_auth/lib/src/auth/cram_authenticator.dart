import 'dart:async';

import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_auth/src/auth/at_authenticator.dart';

class CramAuthenticator {
  CramAuthenticator();

  Future<bool> authenticate(
    String atSign,
    String cramSecret,
    AtLookUp atLookUp, {
    Duration retryInterval = const Duration(seconds: 2),
    Duration timeout = const Duration(seconds: 30),
    int maxRetries = 10,
  }) async {
    final previous = atLookUp.authenticator;
    atLookUp.authenticator = authenticatorForCramSecret(atSign, cramSecret);
    try {
      return await atLookUp.pkamAuthenticate();
    } on UnAuthenticatedException catch (e) {
      if (e.message.startsWith('Cram authentication failed')) rethrow;
      throw UnAuthenticatedException(
          'Cram authentication failed for $atSign: ${e.message}');
    } finally {
      // NOTE: the CRAM secret authenticates this connection only.
      atLookUp.authenticator = previous;
    }
  }
}
