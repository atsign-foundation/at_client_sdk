import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart' show SigningAlgoType;
import 'package:at_client/src/client/at_client_impl.dart';
import 'package:at_client/src/manager/at_client_manager.dart';
import 'package:at_client/src/preference/at_client_preference.dart';
import 'package:at_client/src/secret_sharing/enrollment_key_package.dart'
    show enrollmentKeyPackageBuilder;
import 'package:at_commons/at_commons.dart' show AtClientException;
import 'package:meta/meta.dart' show experimental;

/// Runs the whole PQ self-retrofit and hands back a manager whose current
/// client runs under the NEW enrollment.
///
/// The sequence, each half already proven on its own: submit an
/// [AtSelfEnrollmentRequest] on the legacy [session]'s authenticated
/// connection (auto-approved, no OTP; idempotent — a keyfile that already
/// carries a PQ enrollment reuses it, nothing is minted); re-authenticate
/// under the new enrollment id, which resolves the ML-DSA AtChops and
/// signing algorithm from the keyfile; then build the client for the new id
/// via [AtClientManager.fromAuthSession].
///
/// **The enrollment never changes under a live client.** The switched-to
/// client is a NEW instance under the `(atSign, enrollmentId)` cache key, so
/// every per-client cache (secret sharing, key-package registration) starts
/// fresh for the new identity by construction — nothing is re-keyed in
/// place, and the old client is not mutated. On the default
/// [AtClientManager.getInstance] manager the previous client is stopped by
/// the switch; pass a dedicated [manager] (the `AtClientManager(atSign)`
/// constructor) to keep the legacy client live alongside, e.g. to drain
/// in-flight work before retiring it.
///
/// The legacy enrollment keeps authenticating until the atServer's expiry
/// cap retires it — the retrofit caps it, never deletes it — so a failure
/// anywhere in this sequence leaves the legacy client fully usable.
@experimental
Future<AtClientManager> selfRetrofit({
  required AtAuthSession session,
  required AtClientPreference preference,
  required String appName,
  required String deviceName,
  required Map<String, String> namespaces,
  Duration? apkamKeysExpiryDuration,
  AtClientManager? manager,
}) async {
  final atLookUp = session.atLookUp;
  if (atLookUp == null) {
    throw ArgumentError.value(session, 'session',
        'the self-retrofit submits on the session\'s authenticated AtLookUp');
  }

  final response = await AtEnrollment.create().submit(
      AtSelfEnrollmentRequest(
          session: session,
          appName: appName,
          deviceName: deviceName,
          namespaces: namespaces,
          apkamKeysExpiryDuration: apkamKeysExpiryDuration,
          metadataBuilder: enrollmentKeyPackageBuilder(session.atSign,
              signingAlgo: SigningAlgoType.mldsa65)),
      atLookUp);

  // Authenticate under the new enrollment: the retrofit response's session
  // is the legacy one, and only authenticate() mints a session carrying the
  // new id (with the ML-DSA chops and algorithm resolved from the keyfile).
  final auth = await AtAuth.create().authenticate(
      AtAuthRequest(session.atSign, atKeysIo: session.atKeysIo)
        ..enrollmentId = response.enrollmentId
        ..rootDomain = session.rootDomain);
  if (auth.isSuccessful != true || auth.session == null) {
    throw AtClientException.message(
        'the retrofitted enrollment ${response.enrollmentId} failed to '
        'authenticate; the legacy client is untouched');
  }

  return await (manager ?? AtClientManager.getInstance())
      .fromAuthSession(auth.session!, preference);
}
