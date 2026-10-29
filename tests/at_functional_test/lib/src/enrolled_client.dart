// The enrollment key-package surface is @experimental; driving it is the
// point of this helper.
// ignore_for_file: experimental_member_use

import 'package:at_auth/at_auth.dart';
import 'package:at_client/at_client_io.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_functional_test/src/functional_storage.dart';
import 'package:at_functional_test/src/enrollment_approval.dart';
import 'package:at_lookup/at_lookup.dart' show AtLookUp;
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

/// Enrols a new APKAM enrollment on [atSign] and approves it from [approver],
/// opening no client; [ApprovedEnrollment.open] opens one.
///
/// Approving every enrollment before opening any client lets the first
/// client to mint find all of them on the roster.
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
/// are separate questions, save that at_auth refuses `rsa2048` with the pq
/// exchange. It defaults to `mldsa65` for the pq exchange, post-quantum from
/// birth and never retrofitting, and to `rsa2048` for the legacy exchange,
/// which a client whose posture wants better retrofits on first construction,
/// coming up on a new enrollment id: the production shape of a retrofit.
///
/// [namespaces] overrides the grants requested, which defaults to `rw` on
/// [namespace] alone. Pass `{'*': 'rw', '__manage': 'rw', …}` for a fully
/// privileged enrollment — the class entitled to hold the signing root, and
/// the only one a holder will serve per-enrollment material to.
Future<ApprovedEnrollment> enrolAndApprove({
  required AtClient approver,
  required String atSign,
  required String namespace,
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
  SigningAlgoType? signingAlgo,
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
    // ignore: invalid_use_of_visible_for_testing_member
    atKeysIo: atKeysIo ?? InMemoryAtKeysIo(),
  );

  final legacyMode = keyExchangeMode == EnrollmentKeyExchangeMode.legacy;
  final algo = signingAlgo ??
      (legacyMode ? SigningAlgoType.rsa2048 : SigningAlgoType.mldsa65);

  Map<String, dynamic>? built;
  // NOTE: the key package is signed by the APKAM keypair this enrolment is
  // about to submit, so the builder must be told the same algorithm.
  final build = enrollmentKeyPackageBuilder(atSign, signingAlgo: algo);

  final submission = secureSocketLookUps()(
    atSign: atSign,
    rootDomain: AtRootDomain(rootDomain, rootPort),
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
              signingAlgo: algo,
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
              signingAlgo: algo,
            ),
      submission,
    );
  } finally {
    await submission.close();
  }

  // The approver reads the mode off the request: a legacy request carries
  // its own RSA-wrapped symmetric key on the record, where a pq approver
  // mints one.
  await approver.enrollments.approve(response.enrollmentId);

  await awaitEnrollmentApproval(response,
      atSign: atSign, rootDomain: AtRootDomain(rootDomain, rootPort));

  final keys = (response.session ?? session).atKeysIo;

  // Null in legacy mode: only the pq metadataBuilder populates `built`, and
  // there is no key package to read a kid out of.
  final String? kpid = built == null
      ? null
      : ((SignedEnvelope.fromJson(built!['keyPackage'] as Map).payload
              as Map)['keys'] as List)
          .single['kid'] as String;
  return ApprovedEnrollment._(
    atSign: atSign,
    enrollmentId: response.enrollmentId,
    deviceName: resolvedDeviceName,
    keysIo: keys,
    keys: await keys.read(atSign),
    kpidOrNull: kpid,
    rootDomain: rootDomain,
    rootPort: rootPort,
    storage: storage,
  );
}

/// An enrollment [enrolAndApprove] has approved, with no client open on it.
class ApprovedEnrollment {
  final String atSign;
  final String enrollmentId;
  final String deviceName;
  final AtKeysIo keysIo;
  final AtKeys keys;
  final String? kpidOrNull;
  final String rootDomain;
  final int rootPort;
  final FunctionalStorage storage;

  ApprovedEnrollment._({
    required this.atSign,
    required this.enrollmentId,
    required this.deviceName,
    required this.keysIo,
    required this.keys,
    required this.kpidOrNull,
    required this.rootDomain,
    required this.rootPort,
    required this.storage,
  });

  /// Opens a client authenticated as this enrollment, on [atLookUp] when one
  /// is given.
  Future<EnrolledClient> open(AtClientPreference preference,
      {AtLookUp? atLookUp}) async {
    final client = await Atsign(atSign).open(
        keys: keysIo,
        preference: preference
          ..rootDomain = rootDomain
          ..rootPort = rootPort,
        storage: storage.forPrincipal(atSign, deviceName),
        atLookUp: atLookUp,
        lookUps: secureSocketLookUps(),
        secondaryAddressFinder:
            CacheableSecondaryAddressFinder(rootDomain, rootPort));
    return EnrolledClient(
      client: client,
      enrollmentId: enrollmentId,
      kpidOrNull: kpidOrNull,
      keys: keys,
    );
  }
}

/// Enrols a new APKAM enrollment on [atSign], approves it from [approver], and
/// returns a client authenticated as it; see [enrolAndApprove].
Future<EnrolledClient> enrolAndAuthenticate({
  required AtClient approver,
  required String atSign,
  required String namespace,
  required AtClientPreference preference,
  required String rootDomain,
  required int rootPort,
  required FunctionalStorage storage,
  String? deviceName,
  Map<String, String>? namespaces,
  AtKeysIo? atKeysIo,
  SigningAlgoType? signingAlgo,
  EnrollmentKeyExchangeMode keyExchangeMode = EnrollmentKeyExchangeMode.pq,

  /// The connection the client is opened on, instead of one it builds.
  AtLookUp? atLookUp,
}) async =>
    (await enrolAndApprove(
      approver: approver,
      atSign: atSign,
      namespace: namespace,
      rootDomain: rootDomain,
      rootPort: rootPort,
      storage: storage,
      deviceName: deviceName,
      namespaces: namespaces,
      atKeysIo: atKeysIo,
      signingAlgo: signingAlgo,
      keyExchangeMode: keyExchangeMode,
    ))
        .open(preference, atLookUp: atLookUp);
