import 'dart:async';

import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';

class CramAuthenticator {
  CramAuthenticator();

  /// Authenticates [atSign] over [atLookUp] using the CRAM [cramSecret].
  ///
  /// Completes normally on success and throws [UnAuthenticatedException] on
  /// any failure — both when the underlying lookup throws and when it reports
  /// a soft failure (an empty `from` response).
  Future<void> authenticate(
    String atSign,
    String cramSecret,
    AtLookUp atLookUp,
  ) async {
    try {
      final authenticated = await (atLookUp as AtLookupImpl).cramAuthenticate(
        cramSecret,
      );
      if (!authenticated) {
        throw UnAuthenticatedException('cram auth failed for $atSign');
      }
    } on UnAuthenticatedException catch (e, s) {
      Error.throwWithStackTrace(
        UnAuthenticatedException('cram auth failed for $atSign - $e'),
        s,
      );
    }
  }
}
