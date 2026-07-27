import 'package:at_auth/src/auth/pkam_signers.dart';
import 'package:at_auth/src/exception/at_auth_exceptions.dart';
import 'package:at_auth/src/keys/at_keys.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';

class PkamAuthenticator {
  PkamAuthenticator();

  /// Authenticates [atSign] over [atLookup] using PKAM, signing the challenge
  /// with the RSA PKAM strategy built from [atKeys].
  ///
  /// Completes normally on success and throws [UnAuthenticatedException] on
  /// any failure — both when the underlying lookup throws and when it reports
  /// a soft failure (an empty `from` response). Throws
  /// [AtAuthenticationException] up front if [atKeys] has no apkam private key
  /// to sign with.
  Future<void> authenticate(String atSign, AtLookUp atLookup, AtKeys atKeys,
      {String? enrollmentId}) async {
    _setPkamSigner(atLookup, atKeys, enrollmentId);
    try {
      final authenticated =
          await atLookup.pkamAuthenticate(enrollmentId: enrollmentId);
      if (!authenticated) {
        throw UnAuthenticatedException('pkam auth failed for $atSign');
      }
    } catch (e, s) {
      Error.throwWithStackTrace(
        UnAuthenticatedException('pkam auth failed for $atSign - $e'),
        s,
      );
    }
  }

  /// Gives [atLookUp] the RSA PKAM signing strategy built from [atKeys] (plus
  /// the [enrollmentId] used for any auto-reauth). at_lookup drives the
  /// handshake but doesn't own the keys. ML-DSA signing ([MlDsaPkamSigner]) is
  /// experimental and not selected here yet.
  void _setPkamSigner(AtLookUp atLookUp, AtKeys atKeys, String? enrollmentId) {
    // ignore: deprecated_member_use_from_same_package
    final apkamPrivateKey = atKeys.apkamPrivateKey;
    if (apkamPrivateKey == null) {
      throw AtAuthenticationException(
          'No apkam private key available to sign PKAM');
    }
    atLookUp
      ..pkamSigner = RsaPkamSigner(apkamPrivateKey.toString())
      ..enrollmentId = enrollmentId;
  }
}
