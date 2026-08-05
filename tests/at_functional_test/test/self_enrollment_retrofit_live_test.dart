// The substrate is deliberately marked @experimental and will be reshaped as
// the group surface matures. Exercising it from another package is the point
// of this file.
// ignore_for_file: experimental_member_use

import 'dart:convert';
import 'dart:io';

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_client/src/service/notification_service_impl.dart';
import 'package:at_client/src/signing/envelope_signature.dart'
    show verifyEnvelope;
import 'package:at_demo_data/at_demo_data.dart' show aesKeyMap, encryptionPrivateKeyMap;
import 'package:at_functional_test/src/config_util.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import 'test_utils.dart';

/// The PQ self-retrofit (RF-2b), live: an APKAM-authenticated client mints an
/// ML-DSA-65 keypair, submits a no-OTP `enroll:request`, is auto-approved by
/// the atServer, and immediately PKAM-authenticates under the new enrollment
/// with the ML-DSA key — record-authoritative, so the pass proves the whole
/// client chain (keyfile → AtChops → pkam dispatch) signed genuine ML-DSA.
///
/// The pre-PQ starting point is built with an ordinary OTP enrollment on
/// firstAtSign (approved by the demo-keys owner client, keyfile written
/// fresh) — NOT a CRAM onboard: CRAM secrets are one-shot per recycled
/// virtualenv, and enrollment_test.dart already consumes both dedicated
/// CRAM atSigns in the same suite run.
void main() {
  late String atSign;
  late AtClient atClient;
  const namespace = 'buzz';
  final rootDomain = AtRootDomain('vip.ve.atsign.zone', TestUtils.rootServerPort);
  String keysFilePath(String a) => 'test/testData/rf2b-legacy$a.atKeys';

  setUpAll(() async {
    atSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    final manager = await TestUtils.initAtClient(atSign, namespace);
    atClient = manager.atClient;

    // A pre-PQ (RSA APKAM) enrollment with its own fresh keyfile — the
    // retrofit's precondition. Deliberately carries no key package: a
    // genuinely legacy enrollment.
    final otp = (await atClient.getOTP()).response;
    final response = await AtEnrollment.create().submit(
        AtEnrollmentRequest(
            atSign: atSign,
            appName: 'rf2b-legacy',
            deviceName: 'rf2b-${Uuid().v4().hashCode}',
            namespaces: {namespace: 'rw'},
            otp: otp),
        AtLookupImpl(atSign, 'vip.ve.atsign.zone', TestUtils.rootServerPort));
    final record = (await atClient.enrollmentService!.fetchEnrollmentRequests())
        .firstWhere((e) => e.enrollmentId == response.enrollmentId);
    await atClient.enrollmentService!.approve(
        EnrollmentRequestDecision.approved(
            atSign: atSign,
            enrollmentId: response.enrollmentId,
            apkamSymmetricKey:
                AtBytes.fromString(record.encryptedAPKAMSymmetricKey!)));

    // What waitForApproval would fetch-and-decrypt from the atServer; the
    // approver side of this test knows the same values from at_demo_data,
    // and the keyfile's at-rest self-encryption needs the self key present.
    final keys = response.atAuthKeys!
      ..defaultSelfEncryptionKey = AtBytes.fromString(aesKeyMap[atSign]!)
      ..defaultEncryptionPrivateKey =
          AtBytes.fromString(encryptionPrivateKeyMap[atSign]!);

    final existingKeys = File(keysFilePath(atSign));
    if (existingKeys.existsSync()) {
      existingKeys.deleteSync();
    }
    await FileAtKeysIo(filePath: keysFilePath).write(atSign, keys);
  });

  Future<AtAuthSession> legacySession() async {
    final auth = await AtAuth.create().authenticate(
        AtAuthRequest(atSign, atKeysIo: FileAtKeysIo(filePath: keysFilePath))
          ..rootDomain = rootDomain);
    expect(auth.isSuccessful, true);
    return auth.session!;
  }

  test(
      'the full retrofit: no-OTP submit auto-approves, the keyfile holds '
      'both enrollments, and ML-DSA PKAM succeeds under the new id',
      () async {
    final session = await legacySession();

    Map<String, dynamic>? built;
    final build = enrollmentKeyPackageBuilder(atSign,
        signingAlgo: SigningAlgoType.mldsa65);
    final response = await AtEnrollment.create().submit(
        AtSelfEnrollmentRequest(
            session: session,
            appName: 'rf2b-app',
            deviceName: 'rf2b-${Uuid().v4().hashCode}',
            namespaces: {'buzz': 'rw'},
            metadataBuilder: (keysIo) async => built = await build(keysIo)),
        session.atLookUp!);

    expect(response.enrollStatus, EnrollmentStatus.approved,
        reason: 'auto-approved: no OTP and no human step — the authenticated '
            'parent enrollment is the whole authority');
    final newId = response.enrollmentId;
    expect(newId, isNot(session.enrollmentId));

    // The SAME keyfile now carries both enrollments: the legacy one in the
    // flat fields, the PQ one as typed materials under its own id.
    final keys = await FileAtKeysIo(filePath: keysFilePath).read(atSign);
    expect(keys.enrollmentId, session.enrollmentId,
        reason: 'the flat fields keep the legacy enrollment — it must go on '
            'authenticating until the atServer\'s cap retires it');
    expect(keys.signingAlgorithmForEnrollment(newId), SigningAlgoType.mldsa65);

    // The acceptance assertion: authenticate under the new id. PKAM is
    // record-authoritative, so this passes only with a genuine ML-DSA
    // signature — an RSA one, whatever it claims, is refused.
    final pqAuth = await AtAuth.create().authenticate(AtAuthRequest(atSign,
        atKeysIo: FileAtKeysIo(filePath: keysFilePath))
      ..enrollmentId = newId
      ..rootDomain = rootDomain);
    expect(pqAuth.isSuccessful, true,
        reason: 'the retrofitted enrollment must be usable IMMEDIATELY: '
            'keyfile → AtChops → pkam dispatch, all genuinely ML-DSA');

    // The atServer published the tagged, self-describing _apsk for the new
    // enrollment — composed server-side from the record.
    final apskResponse = await session.atLookUp!.executeCommand(
        'llookup:public:_apsk.$newId.a.__e$atSign\n',
        auth: true);
    final tagged = jsonDecode(apskResponse!.replaceFirst('data:', ''))
        as Map<String, dynamic>;
    expect(tagged['signingAlgo'], 'mldsa65',
        reason: 'a bare value would be parsed as an RSA key by every '
            'verifier, and the ML-DSA enrollment could never verify');

    // Close the loop: the key package the client signed with its minted
    // ML-DSA key verifies against the _apsk the atServer serves.
    final envelope = built!['keyPackage'] as Map;
    final ok = await MlDsa65PureDartAlgo().verifyBytes(
        utf8.encode(jsonEncode(envelope['payload'])),
        signature: base64Decode(envelope['signature'] as String),
        publicKey: base64Decode(tagged['publicKey'] as String));
    expect(ok, true,
        reason: 'signer and published verify key must be the same keypair on '
            'the real wire, or every advertised-key verification fails');
  });

  test(
      'selfRetrofit switches to a working client: verb connection, monitor, '
      'and envelope signing all run under the ML-DSA enrollment',
      timeout: const Timeout(Duration(seconds: 90)), () async {
    final session = await legacySession();
    final manager = await selfRetrofit(
        session: session,
        preference: TestUtils.getPreference(atSign),
        appName: 'rf2b-app',
        deviceName: 'rf2c-${Uuid().v4().hashCode}',
        namespaces: {namespace: 'rw'},
        // A dedicated manager keeps the owner client live alongside — the
        // proven ConcurrentClients shape for two enrollments of one atSign.
        manager: AtClientManager(atSign));

    final client = manager.atClient;
    expect(client.enrollmentId, isNotNull);
    expect(client.enrollmentId, isNot(session.enrollmentId));
    expect(client.signingAlgoType, SigningAlgoType.mldsa65,
        reason: 'resolved from the keyfile\'s typed material — the '
            'preference still says rsa2048');

    // Verb connection: an authenticated command under the new enrollment.
    // Record-authoritative, so a pass means the connection PKAMed ML-DSA.
    final scanResult =
        await client.getRemoteSecondary()!.executeCommand('scan\n', auth: true);
    expect(scanResult, startsWith('data:'));

    // Monitor: it opens its OWN socket and re-authenticates on every
    // (re)connect, so anything arriving over it proves ITS ML-DSA auth
    // independently of the verb connection above. The atServer's own
    // statsNotification stream is the trigger-free signal — it arrives
    // every ~15s once the monitor is listening, which is only possible
    // after that socket's PKAM succeeded.
    final notifications = client.notificationService as NotificationServiceImpl;
    final firstNotification = notifications
        .subscribe(shouldDecrypt: false)
        .firstWhere((n) => n.key.contains('rf2cmon'))
        .timeout(const Duration(seconds: 40));

    // Listener first, trigger second, await third — but the listener that
    // matters is the SERVER's. `subscribe()` returns ~50ms before the
    // monitor's own socket has connected, PKAMed and written `monitor:`,
    // and the monitor asks for no backlog (`lastNotificationTime: null`),
    // so anything the atServer creates in that window is unrecoverable.
    // Registering the client-side stream is NOT the same as the atServer
    // knowing this client is listening.
    if (notifications.monitor.currentState !=
        NotificationListenerState.listening) {
      await notifications.monitor.currentStateStream
          .firstWhere((s) => s == NotificationListenerState.listening)
          .timeout(const Duration(seconds: 30));
    }

    final pingKey = AtKey()
      ..key = 'rf2cmon-${Uuid().v4().hashCode}'
      ..namespace = namespace
      ..sharedBy = atSign
      ..sharedWith = atSign;
    final notifyResult = await atClient.notificationService
        .notify(NotificationParams.forUpdate(pingKey, value: 'ping'));
    expect(notifyResult.notificationStatusEnum,
        NotificationStatusEnum.delivered,
        reason: 'atClientException being null does NOT mean delivered — the '
            'status switch has no default arm and the atServer never says '
            '"undelivered", so an errored notification returns silently');

    final received = await firstNotification;
    expect(received.key, contains('rf2cmon'),
        reason: 'the retrofitted, SCOPED enrollment receives notifications '
            'for its own namespace over a monitor its ML-DSA key '
            'authenticated — sender is the owner client, receiver is this '
            'one, so this is a genuine cross-client delivery');

    // Envelope signing: what this client signs verifies against the tagged
    // _apsk the atServer serves for its enrollment — wrapAndSign must have
    // signed ML-DSA, or the verify refuses the algorithm mismatch.
    final sharing = AtClientSecretSharing.forClient(client);
    final envelope = await sharing.wrapAndSign('rf2c-proof');
    final apsk = (await client.getRemoteSecondary()!.executeCommand(
            'llookup:public:_apsk.${client.enrollmentId}.a.__e$atSign\n',
            auth: true))!
        .replaceFirst('data:', '');
    await verifyEnvelope(envelope, signerPublicKey: apsk);
  });

  test('mint-once per keyfile: a rerun reuses the PQ enrollment', () async {
    final session = await legacySession();

    final again = await AtEnrollment.create().submit(
        AtSelfEnrollmentRequest(
            session: session,
            appName: 'rf2b-app',
            deviceName: 'rf2b-rerun-${Uuid().v4().hashCode}',
            namespaces: {'buzz': 'rw'}),
        session.atLookUp!);

    expect(again.enrollStatus, EnrollmentStatus.approved);
    final keys = await FileAtKeysIo(filePath: keysFilePath).read(atSign);
    final signingMaterials = keys.keys.where((m) =>
        m.keyAlgorithmType == KeyAlgorithmType.mlDsa65 &&
        m.keyPartType == CryptographicKeyType.privateSigning);
    expect(signingMaterials, hasLength(1),
        reason: 'a keyfile that already carries a PQ enrollment must reuse '
            'it, not mint a second — this is UC-A2.2\'s other arm');
    expect(again.enrollmentId, signingMaterials.single.enrollmentId);
  });
}
