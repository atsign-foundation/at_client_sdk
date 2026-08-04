import 'dart:async';

import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';

class CramAuthenticator {
  CramAuthenticator();

  /// Authenticates [atsign] over [atLookUp] using the CRAM [cramSecret].
  ///
  /// Completes normally on success and throws [UnAuthenticatedException] on
  /// any failure — both when the underlying lookup throws and when it reports
  /// a soft failure (an empty `from` response).
  Future<void> authenticate(
    Atsign atsign,
    String cramSecret,
    AtLookUp atLookUp,
  ) async {
    final authenticated = await atLookUp.cramAuthenticate(cramSecret);
    if (!authenticated) {
      throw UnAuthenticatedException('cram auth failed for $atsign');
    }
  }
}
