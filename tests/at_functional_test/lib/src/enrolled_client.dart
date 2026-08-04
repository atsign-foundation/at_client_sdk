// The enrollment key-package surface is @experimental; driving it is the
// point of this helper.
// ignore_for_file: experimental_member_use

import 'package:at_auth/at_auth.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
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
class EnrolledClient {
  /// The enrolled client, authenticated as [enrollmentId].
  final AtClient client;

  /// The atServer-assigned id for this enrollment.
  final String enrollmentId;

  /// The key package id this enrollment advertised, which is the address
  /// anything sealed to it is written under.
  final String kpid;

  /// The manager owning [client]. Its own instance rather than the singleton —
  /// `AtClientManager.getInstance()` is per-process and keyed by atSign, so a
  /// second enrollment of the SAME atSign would otherwise evict the first.
  final AtClientManager manager;

  EnrolledClient({
    required this.client,
    required this.enrollmentId,
    required this.kpid,
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
Future<EnrolledClient> enrolAndAuthenticate({
  required AtClient approver,
  required String atSign,
  required String namespace,
  required AtClientPreference preference,
  required String rootDomain,
  required int rootPort,
  String? deviceName,
}) async {
  final otp = (await approver.getOTP()).response;

  final session = AtAuthSession(
    atSign: atSign,
    rootDomain: AtRootDomain(rootDomain, rootPort),
    // In memory: these keys exist for the length of one test, and writing them
    // to disk would leave a file the next run's onboarding refuses to overwrite.
    atKeysIo: InMemoryAtKeysIo(),
  );

  Map<String, dynamic>? built;
  final build = enrollmentKeyPackageBuilder(atSign);

  final response = await AtEnrollment.create().submit(
    AtEnrollmentRequest(
      session: session,
      appName: namespace,
      deviceName: deviceName ?? 'enrolled-${Uuid().v4().hashCode}',
      namespaces: {namespace: 'rw'},
      otp: otp,
      // pq mode, so the approver mints the symmetric key and seals it to the
      // advertised key package. On the legacy path it would RSA-wrap it, which
      // is the thing this branch exists to remove.
      keyExchangeMode: EnrollmentKeyExchangeMode.pq,
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

  final manager = await AtClientManager(atSign)
      .fromAuthSession(response.session ?? session, preference);

  final payload = (built!['keyPackage'] as Map)['payload'] as Map;
  return EnrolledClient(
    client: manager.atClient,
    enrollmentId: response.enrollmentId,
    kpid: ((payload['keys'] as List).single as Map)['kid'] as String,
    manager: manager,
  );
}
