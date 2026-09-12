// The enrollment key-package surface is @experimental; driving it is the
// point of this helper.
// ignore_for_file: experimental_member_use

import 'package:at_auth/at_auth.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_client/src/signing/envelope_signature.dart'
    show SignedEnvelope;
import 'package:at_functional_test/src/functional_storage.dart';
import 'package:at_lookup/at_lookup_io.dart';
import 'package:uuid/uuid.dart';

/// A live, APKAM-authenticated client for one approved enrollment, with its
/// own `enrollmentId`, APKAM keypair and key package.
///
/// `AtClientImpl` caches clients by `(atSign, enrollmentId)`, so a second
/// enrollment of one atSign is a genuinely separate client with its own
/// connection carrying its own enrollment id; `Atsign.open` builds one beside
/// the owner client, and the caller owns it.
class EnrolledClient {
  final AtClient client;

  /// The id this enrollment was **submitted** as — and not necessarily the one
  /// its [client] authenticates and signs as.
  ///
  /// ⛔ A self-retrofit supersedes it: a client whose posture wants a stronger
  /// authentication key than it was submitted under retrofits itself during
  /// `_init` and comes up on a **new** enrollment id. The atServer caps the old
  /// enrollment rather than deleting it, so both ids are real — this one is
  /// what the roster shows and what an approver approved, while
  /// `client.enrollmentId` is what authenticates the connection, what `_apsk`
  /// is published under, and what signs.
  ///
  /// ⚠️ So compare this against another `EnrolledClient`'s id or against the
  /// enrollment roster, never against anything the CLIENT produced: a
  /// signature's `kid`, an `_apsk` address or a kpid on the wire all carry the
  /// settled id, and comparing them to this passes only when no retrofit ran.
  final String enrollmentId;

  /// The key package id this enrollment advertised, which is the address
  /// anything sealed to it is written under.
  ///
  /// Throws for a **legacy-mode** enrollment, whose creation request carried
  /// no key package; use [kpidOrNull] where either mode is possible.
  ///
  /// ⚠️ "No key package on the request" is not "no key package ever": the
  /// enrollment acquires one at its first client start, whatever the posture,
  /// and is then conveyed secrets like any other.
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
  /// from the approver's conveyance.
  final AtKeys keys;

  /// Wraps an enrollment that is already approved and authenticated;
  /// [enrolAndAuthenticate] is what produces one.
  EnrolledClient({
    required this.client,
    required this.enrollmentId,
    required this.kpidOrNull,
    required this.keys,
  });

  /// Stops [client], for silencing one mid-test; the pack's teardown stops
  /// whatever a test did not.
  Future<void> stop() => client.stop();
}

/// Enrols a new APKAM enrollment on [atSign], approves it from [approver], and
/// returns a client authenticated as it.
///
/// [approver] must be a privileged client able to issue a passcode and
/// approve.
///
/// [keyExchangeMode] decides how the enrollment's `apkamSymmetricKey` travels,
/// and therefore whether this enrollment advertises a key package at all. It
/// is a parameter rather than being read from the preference's posture, which
/// defaults to legacy and would silently drop the key package for every caller
/// naming no posture.
///
/// ⚠️ Legacy mode is **not** a faithful legacy client, and must not be read as
/// one. It submits a legacy request, so nothing is sealed to it at approval
/// time — but the running client still registers a key package of its own at
/// startup, so it remains addressable and can still take part in secret
/// sharing.
///
/// The approval is issued **before** `waitForApproval` is awaited. Both sides
/// run in this one process, so waiting first would deadlock — nothing else is
/// scheduled to approve.
///
/// [signingAlgo] is the algorithm the enrollment's APKAM **authentication**
/// keypair is minted under, a different axis from the key EXCHANGE above: how
/// the symmetric key travels and which algorithm authenticates the connection
/// are separate questions. Under the default `rsa2048` a client whose posture
/// wants better retrofits itself on first construction and comes up on a new
/// enrollment id; pass `mldsa65` for one that is post-quantum from birth and
/// therefore never retrofits.
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

  /// This test file's storage. The enrolled client gets its OWN bundle from
  /// it, told apart by the device name below: the enrollee and the owner
  /// client that approves for it are two live principals on one atSign, and
  /// one store holds one principal.
  required FunctionalStorage storage,
  String? deviceName,
  Map<String, String>? namespaces,
  AtKeysIo? atKeysIo,
  SigningAlgoType signingAlgo = SigningAlgoType.rsa2048,
  EnrollmentKeyExchangeMode keyExchangeMode = EnrollmentKeyExchangeMode.pq,
}) async {
  final otp = (await approver.enrollments.otp()).value;

  final session = AtAuthSession(
    atSign: atSign,
    rootDomain: AtRootDomain(rootDomain, rootPort),
    // NOTE: in memory by default, because a keyfile left on disk is one the
    // next run's onboarding refuses to overwrite. Pass atKeysIo to share one
    // keyfile with the test: with two stores, the client's start-time
    // self-heal can consume an envelope and file it where the test is not
    // looking, so the test reads a null meaning "somebody got there first"
    // rather than "it never arrived".
    atKeysIo: atKeysIo ?? InMemoryAtKeysIo(),
  );

  final legacyMode = keyExchangeMode == EnrollmentKeyExchangeMode.legacy;

  Map<String, dynamic>? built;
  // NOTE: the key package is signed by the APKAM keypair this enrolment is
  // about to submit, so the builder must be told the same algorithm.
  final build = enrollmentKeyPackageBuilder(atSign, signingAlgo: signingAlgo);

  final atLookUp = AtLookUp.withSecureSocket(
    atSign: atSign,
    rootDomain: AtRootDomain(rootDomain, rootPort),
    transport: secureSocketTransport(SecureSocketConfig()),
    authenticator: null,
  );

  // NOTE: this names the enrollment AND its store, so resolve it once or the
  // two can disagree.
  final resolvedDeviceName = deviceName ?? 'enrolled-${Uuid().v4().hashCode}';

  final AtEnrollmentResponse response;
  try {
    response = await AtEnrollment.create().submit(
      legacyMode
          // No metadataBuilder and no resolver: a legacy request advertises no
          // key package, and the symmetric key travels RSA-wrapped on the
          // enrollment record.
          ? AtEnrollmentRequest(
              session: session,
              appName: namespace,
              deviceName: resolvedDeviceName,
              namespaces: namespaces ?? {namespace: 'rw'},
              otp: otp,
              signingAlgo: signingAlgo,
            )
          : AtEnrollmentRequest.pq(
              session: session,
              appName: namespace,
              deviceName: resolvedDeviceName,
              namespaces: namespaces ?? {namespace: 'rw'},
              otp: otp,
              metadataBuilder: (keysIo) async => built = await build(keysIo),
              apkamSymmetricKeyResolver:
                  enrollmentApkamSymmetricKeyResolver(atSign),
              signingAlgo: signingAlgo,
            ),
      atLookUp,
    );
  } finally {
    await atLookUp.close();
  }

  // The approver reads the mode off the request: a legacy request carries
  // its own RSA-wrapped symmetric key on the record, where a pq approver
  // mints one.
  await approver.enrollments.approve(response.enrollmentId);

  await AtEnrollment.create().waitForApproval(response);
  // The handshake's connection is not the client's: the client opens its own.
  await response.session?.atLookUp?.close();

  final keys = (response.session ?? session).atKeysIo;
  final client = await Atsign(atSign).open(
      keys: keys,
      preference: preference
        ..rootDomain = rootDomain
        ..rootPort = rootPort,
      storage: storage.forPrincipal(atSign, resolvedDeviceName));

  // Null in legacy mode: only the pq metadataBuilder populates `built`, and
  // there is no key package to read a kid out of.
  final String? kpid = built == null
      ? null
      : ((SignedEnvelope.fromJson(built!['keyPackage'] as Map).payload
              as Map)['keys'] as List)
          .single['kid'] as String;
  return EnrolledClient(
    client: client,
    enrollmentId: response.enrollmentId,
    kpidOrNull: kpid,
    keys: await keys.read(atSign),
  );
}
