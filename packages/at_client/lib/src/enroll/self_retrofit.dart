import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart' show SigningAlgoType;
import 'package:at_client/src/crypto/nskey/pq_signing_root.dart'
    show PqSigningRoot;
import 'package:at_client/src/manager/at_client_manager.dart';
import 'package:at_client/src/preference/at_client_preference.dart';
import 'package:at_client/src/secret_sharing/enrollment_key_package.dart'
    show enrollmentKeyPackageBuilder;
import 'package:at_client/src/service/enrollment_service_impl.dart'
    show EnrollmentServiceImpl;
import 'package:at_commons/at_commons.dart' show AtClientException;
import 'package:at_utils/at_logger.dart' show AtSignLogger;
import 'package:meta/meta.dart' show experimental;

final _logger = AtSignLogger('selfRetrofit');

/// Runs the whole PQ self-retrofit and hands back a manager whose current
/// client runs under the NEW enrollment.
///
/// The sequence, each half already proven on its own: submit an
/// [AtSelfEnrollmentRequest] on the legacy [session]'s authenticated
/// connection (auto-approved, no OTP; idempotent — a keyfile that already
/// carries an enrollment of the requested algorithm reuses it, nothing is
/// minted); re-authenticate under the new enrollment id, which resolves the
/// AtChops and signing algorithm from the keyfile; then build the client for
/// the new id via [AtClientManager.fromAuthSession].
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
///
/// **A fully privileged retrofit also runs the signing-root step in-flow.**
/// The retrofit is auto-approved by the atServer with no approver client in
/// the loop, so nothing conveys the root to it the way an approve does — its
/// only routes are to mint (no root published yet) or to be given the private
/// by another holder (the every-start pull, already built). The mint half has
/// to happen here: when the atSign publishes no root, the switched-to
/// enrollment mints and publishes it, files both halves in the same keyfile,
/// and anchors itself. Privilege is read off the atServer's enrollment
/// record, never the namespaces this call requested. A scoped retrofit skips
/// the step entirely. A root-step failure does not fail the retrofit — the
/// enrollment is live and usable without it, and re-running [selfRetrofit]
/// (idempotent per keyfile) retries the step.
///
/// [signingAlgo] selects the retrofit mode — one of the rollout axes, a
/// per-operation parameter rather than a preference. When the caller names
/// none, [AtClientPreference.posture] decides: `rsa2048` under the migration
/// posture (the rollout-window mode — a fresh RSA keypair under a new
/// enrollment id, no ML-DSA anywhere), `mldsa65` under
/// `ReleasePosture.postQuantum` (the PQ retrofit).
///
/// The new enrollment's KEM comes from
/// [AtClientPreference.keyEstablishmentAlgo] and is **decided at this call**:
/// the key package rides the `enroll:request`, and changing it afterwards
/// needs an `enroll:update` the new enrollment must send for itself.
@experimental
Future<AtClientManager> selfRetrofit({
  required AtAuthSession session,
  required AtClientPreference preference,
  required String appName,
  required String deviceName,
  required Map<String, String> namespaces,
  Duration? apkamKeysExpiryDuration,
  AtClientManager? manager,
  SigningAlgoType? signingAlgo,
}) async {
  final atLookUp = session.atLookUp;
  if (atLookUp == null) {
    throw ArgumentError.value(session, 'session',
        'the self-retrofit submits on the session\'s authenticated AtLookUp');
  }

  final algo = signingAlgo ?? preference.posture.retrofitSigningAlgo;
  final response = await AtEnrollment.create().submit(
      AtSelfEnrollmentRequest(
          session: session,
          appName: appName,
          deviceName: deviceName,
          namespaces: namespaces,
          apkamKeysExpiryDuration: apkamKeysExpiryDuration,
          signingAlgo: algo,
          metadataBuilder: enrollmentKeyPackageBuilder(session.atSign,
              signingAlgo: algo,
              keyEstablishmentAlgo: preference.keyEstablishmentAlgo)),
      atLookUp);

  // Authenticate under the new enrollment: the retrofit response's session
  // is the legacy one, and only authenticate() mints a session carrying the
  // new id (with the ML-DSA chops and algorithm resolved from the keyfile).
  final auth = await AtAuth.create()
      .authenticate(AtAuthRequest(session.atSign, atKeysIo: session.atKeysIo)
        ..enrollmentId = response.enrollmentId
        // Carried through deliberately: the switched-to client's start-time
        // self-heal — the signing-root pull, the nskey pulls, the store
        // hydration — all key off its namespace, and a client built without
        // one runs none of them while looking perfectly healthy.
        ..namespace = session.namespace ?? preference.namespace
        ..rootDomain = session.rootDomain);
  if (auth.isSuccessful != true || auth.session == null) {
    throw AtClientException.message(
        'the retrofitted enrollment ${response.enrollmentId} failed to '
        'authenticate; the legacy client is untouched');
  }

  final switched = await (manager ?? AtClientManager.getInstance())
      .fromAuthSession(auth.session!, preference);

  // The signing-root step (in-flow, privileged only): mint if the atSign
  // publishes no root yet. Inside its own guard because the retrofit itself
  // has already succeeded — the client is live and stays returned — and a
  // root minted later heals nothing worse than a delay.
  try {
    final client = switched.atClient;
    final granted = (await EnrollmentServiceImpl(client, AtEnrollment.create())
            .fetchEnrollmentRequests())
        .where((e) => e.enrollmentId == response.enrollmentId)
        .firstOrNull
        ?.namespace;
    if (EnrollmentServiceImpl.isFullyPrivileged(granted)) {
      await PqSigningRoot(client, keysIo: session.atKeysIo)
          .mintIfAbsent(isFullyPrivileged: true);
    }
  } catch (e) {
    _logger.warning('The retrofit of ${session.atSign} succeeded but its '
        'signing-root step did not; rerunning selfRetrofit retries it: $e');
  }

  return switched;
}
