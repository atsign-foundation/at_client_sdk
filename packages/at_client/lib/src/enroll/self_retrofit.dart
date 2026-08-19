import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart' show RsaKeyPair, SigningAlgoType;
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

/// A fresh RSA-2048 signing keypair for an enrollment being created.
///
/// `RsaKeyPair.generate()` rather than `AtChopsUtil.generateAtPkamKeyPair()`,
/// which returns a type at_chops deprecates.
({SigningAlgoType algorithm, String publicKey, String privateKey})
    _freshRsaSigningKey() {
  final pair = RsaKeyPair.generate();
  return (
    algorithm: SigningAlgoType.rsa2048,
    publicKey: pair.atPublicKey.publicKey,
    privateKey: pair.atPrivateKey.privateKey,
  );
}

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
/// [signingAlgo] is the **authentication** key's algorithm — the APKAM
/// keypair the new enrollment proves possession of on a connection, not the
/// key it signs envelopes with. The name is the wire field's
/// (`EnrollParams.signingAlgo`), which has meant that since before an
/// enrollment had signing keys of its own; renaming it is a multi-repo seam
/// against a released atServer, so the name stays and this says what it does.
///
/// A per-operation parameter rather than a preference. When the caller names
/// none, [AtClientPreference.authenticationKeyAlgorithm] decides: `rsa2048`
/// under [PqPosture.legacy], `mldsa65` under [PqPosture.pqReady] and
/// [PqPosture.pqActive].
///
/// ⚠️ **The preference's value, not the posture's.** An app may set
/// `authenticationKeyAlgorithm` beside a posture, and the preference's value is
/// then what this client mints under.
///
/// A fully privileged `rsa2048` retrofit still files an ML-DSA-65
/// `pq_signing_root`: the root is the **atSign's**, not this enrollment's, and
/// gating it on a per-enrollment algorithm choice would let the first
/// privileged retrofit decide whether the atSign ever gets a root at all.
/// "No ML-DSA anywhere" is true only of the enrollment's own keys.
///
/// The new enrollment's initial KEM is the first of
/// [AtClientPreference.keyEstablishmentAlgorithms] — its key package rides the
/// `enroll:request`, which carries one key. Any further algorithm the list
/// names is minted, filed and advertised by `KeyPackageMinting` at the
/// retrofitted client's first startup, through the `enroll:update` the new
/// enrollment sends for itself.
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
  final newSession = await retrofitIdentity(
    session: session,
    preference: preference,
    appName: appName,
    deviceName: deviceName,
    namespaces: namespaces,
    apkamKeysExpiryDuration: apkamKeysExpiryDuration,
    signingAlgo: signingAlgo,
  );

  final switched = await (manager ?? AtClientManager.getInstance())
      .fromAuthSession(newSession, preference);

  // The signing-root step (in-flow, privileged only): mint if the atSign
  // publishes no root yet. Inside its own guard because the retrofit itself
  // has already succeeded — the client is live and stays returned — and a
  // root minted later heals nothing worse than a delay.
  try {
    final client = switched.atClient;
    final granted = (await EnrollmentServiceImpl(client, AtEnrollment.create())
            .fetchEnrollmentRequests())
        .where((e) => e.enrollmentId == newSession.enrollmentId)
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

/// The identity half of a self-retrofit: submit the enrollment, then
/// authenticate under the new id, and hand back the session that carries it.
/// No client is built and no [AtClientManager] is touched.
///
/// Split out of [selfRetrofit] because a client that retrofits during its own
/// startup cannot use that function: it ends in
/// [AtClientManager.fromAuthSession], which builds *another* client, whose own
/// initialisation would retrofit in turn. A client deciding its own identity
/// needs the id, not a second client holding it.
///
/// The returned session's `enrollmentId` is the new enrollment. Its `atLookUp`
/// is authenticated as that enrollment, and its `atKeysIo` reads a keyfile
/// that now carries the new enrollment's typed key material — which is what
/// lets a caller re-derive its AtChops and connections from the new identity.
///
/// See [selfRetrofit] for what [signingAlgo] means, why the advertised signing
/// key is minted before the request, and why the KEM is decided at this call.
/// The signing-root step is NOT run here: it needs a live client, so it stays
/// with the half that builds one.
@experimental
Future<AtAuthSession> retrofitIdentity({
  required AtAuthSession session,
  required AtClientPreference preference,
  required String appName,
  required String deviceName,
  required Map<String, String> namespaces,
  Duration? apkamKeysExpiryDuration,
  SigningAlgoType? signingAlgo,
}) async {
  final atLookUp = session.atLookUp;
  if (atLookUp == null) {
    throw ArgumentError.value(session, 'session',
        'the self-retrofit submits on the session\'s authenticated AtLookUp');
  }

  // The preference's value, not the posture's. An app may set
  // `authenticationKeyAlgorithm` beside a posture, and then that value is what
  // the client mints under — reading `posture.authenticationKeyAlgorithm` here
  // would retrofit under the posture's algorithm and never say so.
  final algo = signingAlgo ?? preference.authenticationKeyAlgorithm;

  // Minted here, before the request, because the enrollment must own it from
  // its first byte: `_apsk` advertises this key and the key package is signed
  // with it, so a client start that minted it later would leave a window in
  // which the record names the authentication key — which no un-upgraded peer
  // can read once that key is ML-DSA.
  //
  // rsa2048 regardless of [algo]: a verifier's fleet is not the operator's to
  // upgrade, and a single active rsa2048 entry is the one `_apsk` spelling
  // every deployed reader parses. Moving the signing key to ML-DSA is a later
  // stage, which retires this one rather than skipping it.
  final advertisedSigningKey = preference.dataSigningKeyAlgorithms.isNotEmpty
      ? _freshRsaSigningKey()
      : null;

  final response = await AtEnrollment.create().submit(
      AtSelfEnrollmentRequest(
          session: session,
          appName: appName,
          deviceName: deviceName,
          namespaces: namespaces,
          apkamKeysExpiryDuration: apkamKeysExpiryDuration,
          signingAlgo: algo,
          advertisedSigningKey: advertisedSigningKey,
          metadataBuilder: enrollmentKeyPackageBuilder(session.atSign,
              signingAlgo: algo,
              advertisedSigningKey: advertisedSigningKey,
              keyEstablishmentAlgo:
                  preference.keyEstablishmentAlgorithms.first)),
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

  return auth.session!;
}
