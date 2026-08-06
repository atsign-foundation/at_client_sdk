import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';

class PkamAuthenticator {
  PkamAuthenticator();

  /// Authenticates [atsign] over [atLookup] using PKAM.
  ///
  /// The signing key and algorithm are bound into [atLookup] at construction —
  /// see `buildAtLookUp`, which applies the caller's `ApkamSigningScheme` choice — so
  /// nothing is passed here.
  ///
  /// Completes normally on success and throws [UnAuthenticatedException] on any
  /// failure, both when the underlying lookup throws and when it reports a soft
  /// failure (an empty `from` response).
  Future<void> authenticate(Atsign atsign, AtLookUp atLookup,
      {String? enrollmentId}) async {
    final authenticated =
        await atLookup.pkamAuthenticate(enrollmentId: enrollmentId);
    if (!authenticated) {
      throw UnAuthenticatedException('pkam auth failed for $atsign');
    }
  }
}
