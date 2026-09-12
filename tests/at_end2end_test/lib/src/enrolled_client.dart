// The enrollment key-package surface is @experimental; driving it is the
// point of this helper.
// ignore_for_file: experimental_member_use

import 'package:at_auth/at_auth.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_client/src/signing/envelope_signature.dart'
    show SignedEnvelope;
import 'package:at_lookup/at_lookup_io.dart';
import 'package:uuid/uuid.dart';

/// A live, APKAM-authenticated client for one approved enrollment, with its
/// own `enrollmentId`, APKAM keypair and key package.
///
/// A copy of `at_functional_test`'s helper of the same name; the two suites
/// are separate packages with no shared library between them, so keep the two
/// in step if the enrollment flow changes.
///
/// `AtClientImpl` caches clients by `(atSign, enrollmentId)`, so a second
/// enrollment of one atSign is a genuinely separate client with its own
/// connection carrying its own enrollment id; `Atsign.open` builds one beside
/// the owner client, and the caller owns it.
class EnrolledClient {
  /// The enrolled client, authenticated as [enrollmentId].
  final AtClient client;

  /// The id this enrollment was **submitted** as — and not necessarily the one
  /// its [client] authenticates and signs as.
  ///
  /// ⛔ **A self-retrofit supersedes it.** This copy submits every enrollment
  /// under a hard-coded `rsa2048` APKAM keypair, so a client whose posture
  /// wants a stronger authentication key ALWAYS retrofits itself during
  /// `_init` and comes up on a **new** enrollment id, with no way to opt out.
  /// The atServer caps the old enrollment rather than deleting it, so both ids
  /// are real: this one is what the roster shows and what an approver
  /// approved, while `client.enrollmentId` is what authenticates the
  /// connection, what `_apsk` is published under, and what signs.
  ///
  /// ⚠️ **So compare this against another `EnrolledClient`'s id or against the
  /// enrollment roster; never against anything the CLIENT produced.** A
  /// signature's `kid`, an `_apsk` address or a kpid on the wire all carry the
  /// settled id, and comparing them to this passes only when no retrofit ran.
  final String enrollmentId;

  /// The key package id this enrollment advertised, which is the address
  /// anything sealed to it is written under.
  final String kpid;

  /// This enrollment's key material, as `waitForApproval` left it: its APKAM
  /// keypair, its key-package private half, and the encryption keys unwrapped
  /// from the approver's conveyance.
  final AtKeys keys;

  EnrolledClient({
    required this.client,
    required this.enrollmentId,
    required this.kpid,
    required this.keys,
  });
}

/// Enrols a new APKAM enrollment on [atSign], approves it from [approver], and
/// returns a client authenticated as it.
///
/// [approver] must be a privileged client able to issue a passcode and
/// approve — in this package, the client `TestSuiteInitializer` brings up.
///
/// [namespaces] overrides the grants requested, which defaults to `rw` on
/// [namespace] alone. Pass `{'*': 'rw', '__manage': 'rw', …}` for a fully
/// privileged enrollment — the class entitled to hold the signing root, and
/// the only one a holder will serve per-enrollment material to.
///
/// The approval is issued **before** `waitForApproval` is awaited: both sides
/// run in this one process, so waiting first would deadlock — nothing else is
/// scheduled to approve.
Future<EnrolledClient> enrolAndAuthenticate({
  required AtClient approver,
  required String atSign,
  required String namespace,
  required AtClientPreference preference,
  required String rootDomain,
  required int rootPort,
  String? deviceName,
  Map<String, String>? namespaces,
}) async {
  final otp = (await approver.enrollments.otp()).value;

  final session = AtAuthSession(
    atSign: atSign,
    rootDomain: AtRootDomain(rootDomain, rootPort),
    // In memory: these keys exist for the length of one test, and writing them
    // to disk would leave a file the next run's onboarding refuses to overwrite.
    atKeysIo: InMemoryAtKeysIo(),
  );

  Map<String, dynamic>? built;
  final build = enrollmentKeyPackageBuilder(atSign);

  final atLookUp = AtLookUp.withSecureSocket(
    atSign: atSign,
    rootDomain: AtRootDomain(rootDomain, rootPort),
    transport: secureSocketTransport(SecureSocketConfig()),
    authenticator: null,
  );
  final AtEnrollmentResponse response;
  try {
    response = await AtEnrollment.create().submit(
      AtEnrollmentRequest.pq(
        session: session,
        appName: namespace,
        deviceName: deviceName ?? 'enrolled-${Uuid().v4().hashCode}',
        namespaces: namespaces ?? {namespace: 'rw'},
        otp: otp,
        // pq mode, so the approver mints the symmetric key and seals it to the
        // advertised key package rather than RSA-wrapping one the enrollee sent.
        metadataBuilder: (keysIo) async => built = await build(keysIo),
        apkamSymmetricKeyResolver: enrollmentApkamSymmetricKeyResolver(atSign),
        // pq is the key EXCHANGE; the APKAM authentication keypair stays
        // RSA-2048.
        signingAlgo: SigningAlgoType.rsa2048,
      ),
      atLookUp,
    );
  } finally {
    await atLookUp.close();
  }

  // pq mode: the approver mints the symmetric key rather than unwrapping one
  // the enrollee sent, which it reads off the request.
  await approver.enrollments.approve(response.enrollmentId);

  await AtEnrollment.create().waitForApproval(response);

  final keys = (response.session ?? session).atKeysIo;
  final client = await Atsign(atSign).open(
      keys: keys,
      preference: preference
        ..rootDomain = rootDomain
        ..rootPort = rootPort);

  final payload =
      SignedEnvelope.fromJson(built!['keyPackage'] as Map).payload as Map;
  return EnrolledClient(
    client: client,
    enrollmentId: response.enrollmentId,
    kpid: ((payload['keys'] as List).single as Map)['kid'] as String,
    keys: await keys.read(atSign),
  );
}
