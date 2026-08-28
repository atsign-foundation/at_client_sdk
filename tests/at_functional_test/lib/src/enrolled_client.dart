// The enrollment key-package surface is @experimental; driving it is the
// point of this helper.
// ignore_for_file: experimental_member_use

import 'package:at_auth/at_auth.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_client/src/signing/envelope_signature.dart'
    show SignedEnvelope;
import 'package:at_commons/at_commons.dart' show AtBytes;
import 'package:at_lookup/at_lookup_io.dart';
import 'package:uuid/uuid.dart';

/// A live, APKAM-authenticated client for one approved enrollment.
///
/// Several claims in the PQ acceptance catalogue are about what one
/// *enrollment* may do to another — the namespace boundary, the signing-root
/// pull, ML-DSA authentication against the enrollment record. None of them can
/// be driven by a client authenticating with the atSign's own keys, which is
/// what the rest of this package uses: the atServer answers `enroll:listns`
/// only for an APKAM-authenticated connection, and both halves of the
/// substrate's pull path go through it — the requester to enumerate holders,
/// the responder to authorize the requester before answering.
///
/// So this exists to hand back a client that genuinely *is* an enrollment,
/// with its own `enrollmentId`, its own APKAM keypair, and its own key
/// package.
///
/// This works because `AtClientImpl` caches clients by
/// `(atSign, enrollmentId)` — the `(owner, id)` rule applied to the client
/// cache — so a second enrollment of one atSign is a genuinely separate
/// client with its own connection carrying its own enrollment id. Use one
/// `AtClientManager` per client (the public constructor), never
/// `getInstance().setCurrentAtSign`, which would stop the other client.
class EnrolledClient {
  /// The enrolled client, authenticated as [enrollmentId].
  final AtClient client;

  /// The id this enrollment was **submitted** as — and not necessarily the one
  /// its [client] authenticates and signs as.
  ///
  /// ⛔ **A self-retrofit supersedes it.** `enrolAndAuthenticate` submits under
  /// [signingAlgo], which defaults to `rsa2048`; a client whose posture wants a
  /// stronger authentication key retrofits itself during `_init` and comes up
  /// on a **new** enrollment id. This field keeps the submitted one. The
  /// atServer caps the old enrollment rather than deleting it, so both ids are
  /// real: this one is what the roster shows and what an approver approved,
  /// while `client.enrollmentId` is what authenticates the connection, what
  /// `_apsk` is published under, and what signs.
  ///
  /// **Both are needed, and the difference is asserted on purpose.**
  /// `pq_retrofitted_scope_test.dart` requires them to DIFFER — "equal ids mean
  /// no retrofit ran" is the precondition for that whole file — and requires
  /// them to MATCH in its cold-keyfile arm, where a retrofit would leave
  /// nothing varying. `nskey_self_notify_live_test.dart` requires them to match
  /// because the receiving client's id is what the atServer authorizes the
  /// monitor connection against. Making this field mirror `client.enrollmentId`
  /// would redden the first pair and turn the rest into tautologies —
  /// preconditions that are green whatever happens.
  ///
  /// ⚠️ **So compare this against another `EnrolledClient`'s id or against the
  /// enrollment roster; never against anything the CLIENT produced.** A
  /// signature's `kid`, an `_apsk` address or a kpid on the wire all carry the
  /// settled id, and comparing them to this passes only when no retrofit ran.
  /// Pass `signingAlgo: mldsa65` for an enrollment that is post-quantum from
  /// birth and therefore never retrofits, if that is what the test wants.
  final String enrollmentId;

  /// The key package id this enrollment advertised, which is the address
  /// anything sealed to it is written under.
  ///
  /// Throws for a **legacy-mode** enrollment, which advertises no key package
  /// at all — that is the point of the mode, not a gap. A throwing getter
  /// rather than a nullable field because every existing reader is a test
  /// about key packages, so `null` would only have been forced away with `!`
  /// at each one; this way the failure names what happened. Use [kpidOrNull]
  /// where either mode is possible.
  String get kpid =>
      _kpid ??
      (throw StateError(
          'enrollment $enrollmentId was submitted in legacy key-exchange mode, '
          'so it advertised no key package and has no kpid. Nothing can be '
          'sealed to it and it takes no part in secret sharing — which is what '
          'PqPosture.legacy asks for. Read kpidOrNull if either mode is '
          'possible here'));

  /// The advertised key package id, or null for a legacy-mode enrollment.
  final String? kpidOrNull;

  String? get _kpid => kpidOrNull;

  /// This enrollment's key material, as `waitForApproval` left it: its APKAM
  /// keypair, its key-package private half, and the encryption keys unwrapped
  /// from the approver's conveyance. Exposed because tests that drive
  /// authentication by hand — signing a PKAM challenge to check what the
  /// atServer verifies against — need the keypair the record names.
  final AtKeys keys;

  /// The manager owning [client]. Its own instance rather than the singleton —
  /// `AtClientManager.getInstance()` is per-process and keyed by atSign, so a
  /// second enrollment of the SAME atSign would otherwise evict the first.
  final AtClientManager manager;

  EnrolledClient({
    required this.client,
    required this.enrollmentId,
    required this.kpidOrNull,
    required this.keys,
    required this.manager,
  });
}

/// Enrols a new APKAM enrollment on [atSign], approves it from [approver], and
/// returns a client authenticated as it.
///
/// [keyExchangeMode] decides how the enrollment's `apkamSymmetricKey` travels,
/// and therefore whether this enrollment advertises a key package at all. It
/// defaults to **pq**, which is what nearly every test here wants and what
/// this helper always did.
///
/// ⚠️ It is a parameter rather than being read from
/// `preference.posture.keyExchangeMode`, even though `PqPosture`'s dartdoc
/// tells *app* authors to derive it from the posture. Deriving it here was
/// tried and reverted: [AtClientPreference]'s posture defaults to
/// `PqPosture.legacy`, so every caller that names no posture — which is most
/// of this pack — would silently switch to legacy-mode enrollment and lose its
/// key package. Measured: seven substrate tests went red at once.
///
/// ⚠️ Legacy mode is **not** a faithful legacy client, and must not be read as
/// one. It submits a legacy request, so nothing is sealed to it at approval
/// time — but the running client still registers a key package of its own at
/// startup (`collectConveyedKeyMaterial` calls `register()` unconditionally),
/// so it remains addressable and can still take part in secret sharing. The
/// faithful un-upgraded peer in this repo is a separate process running a
/// released at_client: `tests/pq_matrix/published` on 3.14.0, spawned by
/// `pq_released_peer_test.dart`.
///
/// [approver] must be a privileged client able to call `otp:get` and approve —
/// in this package, the ordinary `TestUtils.initAtClient` client.
///
/// Runs the **real** flow rather than assembling keys by hand: submit, approve,
/// then `waitForApproval`, which is what unwraps this enrollment's encryption
/// keys with the `apkamSymmetricKey` the approver sealed to its key package and
/// persists the result. Short-cutting that would produce a client whose keys
/// never went through the conveyance under test, which is the one thing these
/// tests are supposed to exercise.
///
/// The approval is issued **before** `waitForApproval` is awaited. Both sides
/// run in this one process, so waiting first would deadlock — nothing else is
/// scheduled to approve.
///
/// [signingAlgo] is the algorithm the enrollment's APKAM **authentication**
/// keypair is minted under, and it is a different axis from the pq key
/// EXCHANGE this helper always uses: how the symmetric key travels and which
/// algorithm authenticates the connection are separate questions.
///
/// It defaults to `rsa2048` because that is what every caller of this helper
/// was handed before the parameter existed, and several of them assert against
/// it — including the advance ladder, whose first rung needs an RSA enrollment
/// to have something to advance FROM. A test wanting an enrollment that is
/// post-quantum from birth, and therefore does NOT retrofit itself on first
/// client construction, passes `mldsa65`.
///
/// [namespaces] overrides the grants requested, which defaults to `rw` on
/// [namespace] alone. Pass `{'*': 'rw', '__manage': 'rw', …}` for a fully
/// privileged enrollment — the class entitled to hold the signing root, and
/// the only one a holder will serve per-enrollment material to.
Future<EnrolledClient> enrolAndAuthenticate({
  required AtClient approver,
  required String atSign,
  required String namespace,
  required AtClientPreference preference,
  required String rootDomain,
  required int rootPort,
  String? deviceName,
  Map<String, String>? namespaces,
  AtKeysIo? atKeysIo,
  SigningAlgoType signingAlgo = SigningAlgoType.rsa2048,
  EnrollmentKeyExchangeMode keyExchangeMode = EnrollmentKeyExchangeMode.pq,
}) async {
  final otp = (await approver.getOTP()).response;

  final session = AtAuthSession(
    atSign: atSign,
    rootDomain: AtRootDomain(rootDomain, rootPort),
    // In memory: these keys exist for the length of one test, and writing them
    // to disk would leave a file the next run's onboarding refuses to overwrite.
    //
    // Pass [atKeysIo] to share one keyfile with the test. That matters
    // whenever the test observes key material the CLIENT's own start-time
    // self-heal also files: with two stores, whichever sweep wins consumes
    // the envelope and files it where the other side is not looking, and the
    // test reads a null that means "somebody else got there first" rather
    // than "it never arrived".
    atKeysIo: atKeysIo ?? InMemoryAtKeysIo(),
  );

  final legacyMode = keyExchangeMode == EnrollmentKeyExchangeMode.legacy;

  Map<String, dynamic>? built;
  // The key package is signed by the APKAM keypair this enrolment is about to
  // submit, so the builder has to be told which algorithm that is. It has
  // always taken one; nothing passed it here because until the request could
  // carry an algorithm, the answer could only ever be rsa2048.
  final build = enrollmentKeyPackageBuilder(atSign, signingAlgo: signingAlgo);

  final atLookUp = AtLookUp.withSecureSocket(
    atSign: atSign,
    rootDomain: AtRootDomain(rootDomain, rootPort),
    transport: secureSocketTransport(SecureSocketConfig()),
    authenticator: null,
  );

  final response = await AtEnrollment.create().submit(
    legacyMode
        // No metadataBuilder and no resolver: a legacy request advertises no
        // key package, and the symmetric key travels RSA-wrapped on the
        // enrollment record instead of being sealed to one.
        ? AtEnrollmentRequest(
            session: session,
            appName: namespace,
            deviceName: deviceName ?? 'enrolled-${Uuid().v4().hashCode}',
            namespaces: namespaces ?? {namespace: 'rw'},
            otp: otp,
            signingAlgo: signingAlgo,
          )
        : AtEnrollmentRequest.pq(
            session: session,
            appName: namespace,
            deviceName: deviceName ?? 'enrolled-${Uuid().v4().hashCode}',
            namespaces: namespaces ?? {namespace: 'rw'},
            otp: otp,
            // pq mode, so the approver mints the symmetric key and seals it to
            // the advertised key package. On the legacy path it would RSA-wrap
            // it, which is the thing this branch exists to remove.
            metadataBuilder: (keysIo) async => built = await build(keysIo),
            apkamSymmetricKeyResolver:
                enrollmentApkamSymmetricKeyResolver(atSign),
            signingAlgo: signingAlgo,
          ),
    atLookUp,
  );

  // The approver's half differs by mode too, and getting it wrong is silent:
  // a legacy request carries its own RSA-wrapped symmetric key on the record
  // and the approver hands that back, where a pq approver mints one.
  final AtBytes apkamSymmetricKey;
  if (legacyMode) {
    final record = (await approver.enrollmentService!.fetchEnrollmentRequests())
        .firstWhere((e) => e.enrollmentId == response.enrollmentId);
    apkamSymmetricKey = AtBytes.fromString(record.encryptedAPKAMSymmetricKey!);
  } else {
    // Empty: pq mode means the approver mints it rather than unwrapping one
    // the enrollee sent.
    apkamSymmetricKey = AtBytes.fromString('');
  }

  await approver.enrollmentService!.approve(EnrollmentRequestDecision.approved(
    atSign: atSign,
    enrollmentId: response.enrollmentId,
    apkamSymmetricKey: apkamSymmetricKey,
  ));

  await AtEnrollment.create().waitForApproval(response);

  // reuse: true asks for the AtLookUp that already authenticated as this
  // enrollment during waitForApproval, instead of opening a fresh unauthenticated
  // one. It is necessary but NOT sufficient, and on its own changes nothing
  // observable — see the class doc: while AtClientImpl hands back a cached
  // client for this atSign, none of these arguments are applied at all.
  final manager = await AtClientManager(atSign)
      .fromAuthSession(response.session ?? session, preference, reuse: true);

  // Null in legacy mode: `built` is only populated by the pq metadataBuilder,
  // and there is no key package to read a kid out of.
  final String? kpid = built == null
      ? null
      : ((SignedEnvelope.fromJson(built!['keyPackage'] as Map).payload
              as Map)['keys'] as List)
          .single['kid'] as String;
  return EnrolledClient(
    client: manager.atClient,
    enrollmentId: response.enrollmentId,
    kpidOrNull: kpid,
    keys: await (response.session ?? session).atKeysIo.read(atSign),
    manager: manager,
  );
}
