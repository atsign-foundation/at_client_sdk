// The enrollment key-package surface is @experimental; driving it is the
// point of this helper.
// ignore_for_file: experimental_member_use

import 'package:at_auth/at_auth.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_client/src/signing/envelope_signature.dart'
    show SignedEnvelope;
import 'package:at_commons/at_commons.dart' show AtBytes;
import 'package:at_lookup/at_lookup.dart';
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

  /// The atServer-assigned id for this enrollment.
  final String enrollmentId;

  /// The key package id this enrollment advertised, which is the address
  /// anything sealed to it is written under.
  final String kpid;

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
    required this.kpid,
    required this.keys,
    required this.manager,
  });
}

/// Enrols a new APKAM enrollment on [atSign], approves it from [approver], and
/// returns a client authenticated as it.
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

  Map<String, dynamic>? built;
  final build = enrollmentKeyPackageBuilder(atSign);

  final response = await AtEnrollment.create().submit(
    AtEnrollmentRequest.pq(
      session: session,
      appName: namespace,
      deviceName: deviceName ?? 'enrolled-${Uuid().v4().hashCode}',
      namespaces: namespaces ?? {namespace: 'rw'},
      otp: otp,
      // pq mode, so the approver mints the symmetric key and seals it to the
      // advertised key package. On the legacy path it would RSA-wrap it, which
      // is the thing this branch exists to remove.
      metadataBuilder: (keysIo) async => built = await build(keysIo),
      apkamSymmetricKeyResolver: enrollmentApkamSymmetricKeyResolver(atSign),
    ),
    AtLookupImpl(atSign, rootDomain, rootPort),
  );

  await approver.enrollmentService!
      .approve(EnrollmentRequestDecision.approved(
    atSign: atSign,
    enrollmentId: response.enrollmentId,
    // Empty: pq mode means the approver mints it rather than unwrapping one
    // the enrollee sent.
    apkamSymmetricKey: AtBytes.fromString(''),
  ));

  await AtEnrollment.create().waitForApproval(response);

  // reuse: true asks for the AtLookUp that already authenticated as this
  // enrollment during waitForApproval, instead of opening a fresh unauthenticated
  // one. It is necessary but NOT sufficient, and on its own changes nothing
  // observable — see the class doc: while AtClientImpl hands back a cached
  // client for this atSign, none of these arguments are applied at all.
  final manager = await AtClientManager(atSign).fromAuthSession(
      response.session ?? session, preference,
      reuse: true);

  final payload = SignedEnvelope.fromJson(built!['keyPackage'] as Map).payload as Map;
  return EnrolledClient(
    client: manager.atClient,
    enrollmentId: response.enrollmentId,
    kpid: ((payload['keys'] as List).single as Map)['kid'] as String,
    keys: await (response.session ?? session).atKeysIo.read(atSign),
    manager: manager,
  );
}
