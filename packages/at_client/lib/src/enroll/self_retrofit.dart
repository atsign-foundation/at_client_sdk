import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart' show SigningAlgoType;
import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_client/src/crypto/nskey/pq_signing_root.dart'
    show PqSigningRoot;
import 'package:at_client/src/enroll/signing_key_mint.dart'
    show mintAdvertisedSigningKey;
import 'package:at_client/src/lifecycle/at_connection.dart';
import 'package:at_client/src/lifecycle/atsign_lifecycle.dart';
import 'package:at_client/src/lifecycle/authenticated_lookup.dart';
import 'package:at_client/src/preference/at_client_preference.dart';
import 'package:at_client/src/secret_sharing/enrollment_key_package.dart'
    show enrollmentKeyPackageBuilder;
import 'package:at_client/src/service/enrollment_service_impl.dart'
    show EnrollmentServiceImpl;
import 'package:at_client/src/storage/at_client_storage.dart';
import 'package:at_commons/at_commons.dart' show AtClientException, Atsign;
import 'package:at_lookup/at_lookup.dart' show AtLookUp;
import 'package:at_utils/at_logger.dart' show AtSignLogger;
import 'package:meta/meta.dart' show experimental;

final _logger = AtSignLogger('selfRetrofit');

/// Runs the whole PQ self-retrofit and hands back a client running under the
/// NEW enrollment, which the caller owns.
///
/// The sequence: submit an [AtSelfEnrollmentRequest] authenticated as the
/// legacy [session] (auto-approved, no OTP; idempotent — a keyfile that
/// already carries an enrollment of the requested algorithm reuses it,
/// nothing is minted); check the keyfile now authenticates as the new
/// enrollment id; then open the client for the new id, whose own connection
/// is the first to authenticate as it.
///
/// **The enrollment never changes under a live client _on this path_.** The
/// switched-to client is a NEW instance under the `(atSign, enrollmentId)`
/// cache key, so every per-client cache (secret sharing, key-package
/// registration) starts fresh for the new identity and a legacy client is
/// not mutated. ⚠️ That is not an invariant of the SDK: `AtClientImpl`
/// retrofits itself at start-up through [retrofitIdentity] and DOES mutate in
/// place, which is safe only there, inside `_init`, before the client has
/// been filed in the instance map or handed to any caller.
///
/// A legacy client that is live is left running: it keeps authenticating
/// until the new enrollment first does, which is when the atServer revokes
/// it as superseded (a fully privileged predecessor keeps its life). So a
/// failure before that point leaves the legacy client fully usable, and
/// nothing after it does. The new client opens on [storage], or on a Hive
/// store under the preference's path with none; a retrofit over the legacy
/// client's own store is that client's to arrange, by stopping with the
/// store handed over and its principal forgotten before this is called.
///
/// [atLookUp] serves the submission and the client, for a caller that holds
/// a connection; with none the submission authenticates a connection of its
/// own from the session's keys and closes it. See `Atsign.open` for
/// [connectBudget].
///
/// **A fully privileged retrofit also runs the signing-root step in-flow.**
/// The retrofit is auto-approved by the atServer with no approver client in
/// the loop, so nothing conveys the root to it the way an approve does — its
/// only routes are to mint one, when the atSign publishes none, or to be given
/// the private by another holder on the every-start pull. The mint half has to
/// happen here: the switched-to enrollment mints and publishes the root, files
/// both halves in the same keyfile, and anchors itself. Privilege is read off
/// the atServer's enrollment record, never the namespaces this call requested,
/// and a scoped retrofit skips the step entirely. A root-step failure does not
/// fail the retrofit — the enrollment is live and usable without it, and
/// re-running [selfRetrofit] (idempotent per keyfile) retries the step.
///
/// [signingAlgo] is the **authentication** key's algorithm — the APKAM
/// keypair the new enrollment proves possession of on a connection, not the
/// key it signs envelopes with. The name is the wire field's
/// (`EnrollParams.signingAlgo`); renaming it is a multi-repo seam against a
/// released atServer, so the name stays and this says what it does.
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
Future<AtClient> selfRetrofit({
  required AtAuthSession session,
  required AtClientPreference preference,
  required String appName,
  required String deviceName,
  required Map<String, String> namespaces,
  Duration? apkamKeysExpiryDuration,
  SigningAlgoType? signingAlgo,
  AtClientStorage? storage,
  AtLookUp? atLookUp,
  Duration connectBudget = AtConnection.defaultBudget,
}) async {
  final newSession = await retrofitIdentity(
    session: session,
    preference: preference,
    appName: appName,
    deviceName: deviceName,
    namespaces: namespaces,
    apkamKeysExpiryDuration: apkamKeysExpiryDuration,
    signingAlgo: signingAlgo,
    atLookUp: atLookUp,
  );

  preference
    ..rootDomain = session.rootDomain.rootDomain
    ..rootPort = session.rootDomain.rootPort;
  final client = await Atsign(session.atSign).open(
      keys: session.atKeysIo,
      preference: preference,
      namespace: newSession.namespace,
      storage: storage,
      atLookUp: atLookUp,
      connectBudget: connectBudget);

  try {
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

  return client;
}

/// The identity half of a self-retrofit: submit the enrollment, check the
/// keyfile names the new id, and hand back the session that carries it. No
/// client is built, nothing authenticates, and no [AtClientManager] is
/// touched.
///
/// Split out of [selfRetrofit] because a client that retrofits during its own
/// startup cannot use that function: it ends in `Atsign.open`, which builds
/// *another* client, whose own initialisation would retrofit in turn.
///
/// The returned session's `enrollmentId` is the new enrollment, and its
/// `atKeysIo` reads a keyfile carrying the new enrollment's typed key
/// material, which is what lets a caller re-derive its AtChops and
/// connections from the new identity. It carries no connection: the caller's
/// next connection authenticates as the new enrollment, and reports into the
/// client's connection state if the atServer refuses it.
///
/// See [selfRetrofit] for what [signingAlgo] means, why the advertised signing
/// key is minted before the request, and why the KEM is decided at this call.
/// The signing-root step is NOT run here: it needs a live client, so it stays
/// with the half that builds one.
///
/// The request is submitted on [atLookUp], a connection authenticated as the
/// legacy enrollment, which a client retrofitting itself passes from its own
/// remote secondary; with none, one is authenticated from the session's keys
/// for the submission and closed after it.
@experimental
Future<AtAuthSession> retrofitIdentity({
  required AtAuthSession session,
  required AtClientPreference preference,
  required String appName,
  required String deviceName,
  required Map<String, String> namespaces,
  Duration? apkamKeysExpiryDuration,
  SigningAlgoType? signingAlgo,
  AtLookUp? atLookUp,
}) async {
  // ignore: deprecated_member_use
  final given = atLookUp ?? session.atLookUp;
  final connection = given ??
      await authenticatedLookUp(
          session.atSign, session.atKeysIo, session.rootDomain,
          enrollmentId: session.enrollmentId);

  // NOTE: the preference's value, not the posture's — an app may set
  // `authenticationKeyAlgorithm` beside a posture, and reading
  // `posture.authenticationKeyAlgorithm` here would retrofit under the
  // posture's algorithm and never say so.
  final algo = signingAlgo ?? preference.authenticationKeyAlgorithm;

  // NOTE: minted before the request because the enrollment must own it from
  // its first byte — `_apsk` advertises this key and the key package is signed
  // with it, so minting it at a later client start would leave a window in
  // which the record names the authentication key, which no un-upgraded peer
  // can read once that key is ML-DSA. It takes the algorithm the in-use set
  // names, not a constant: anything else leaves the new enrollment's first
  // start finding the in-use algorithm missing, minting a second keypair and
  // republishing the record this request just created.
  final advertisedSigningKey =
      await mintAdvertisedSigningKey(preference.dataSigningKeyAlgorithms);

  final AtEnrollmentResponse response;
  try {
    response = await AtEnrollment.create().submit(
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
        connection);
  } finally {
    if (given == null) await connection.close();
  }

  // NOTE: the retrofit response's session is the legacy one. The keyfile the
  // successor's material was just filed in names the enrollment it now
  // authenticates as, and that is checked here; the PKAM that proves it runs
  // on the client's own connection, which reports a refusal into
  // `client.connection` rather than failing the retrofit after the fact.
  final AtKeys retrofitted;
  try {
    retrofitted = await session.atKeysIo.read(session.atSign);
  } on Exception catch (e) {
    throw AtClientException.message(
        'the retrofit of ${session.atSign} filed enrollment '
        '${response.enrollmentId} but its keyfile could not be read back: $e; '
        'the legacy client is untouched');
  }
  final authenticatesAs = retrofitted.enrollmentToAuthenticateAs();
  if (authenticatesAs != response.enrollmentId) {
    throw AtClientException.message(
        'the keyfile authenticates as $authenticatesAs after retrofitting to '
        '${response.enrollmentId}; the legacy client is untouched');
  }

  return AtAuthSession(
      atSign: session.atSign,
      rootDomain: session.rootDomain,
      atKeysIo: session.atKeysIo,
      // NOTE: the switched-to client's start-time self-heal — the signing-root
      // pull, the nskey pulls, the store hydration — all key off its
      // namespace, and a client built without one runs none of them while
      // looking perfectly healthy.
      namespace: session.namespace ?? preference.namespace,
      enrollmentId: response.enrollmentId);
}
