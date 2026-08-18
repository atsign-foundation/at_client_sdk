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
    show EnvelopeType, parseApskValue, verifyEnvelope;
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

  /// Mints a fresh pre-PQ (RSA APKAM) enrollment and writes its keyfile at
  /// [pathFor] — the retrofit's precondition. Deliberately carries no key
  /// package: a genuinely legacy enrollment. Reusable wherever an arm needs
  /// a keyfile no earlier arm has already retrofitted, since retrofit
  /// idempotence is per keyfile.
  Future<void> mintLegacyKeyfile(String Function(String) pathFor) async {
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

    final existingKeys = File(pathFor(atSign));
    if (existingKeys.existsSync()) {
      existingKeys.deleteSync();
    }
    await FileAtKeysIo(filePath: pathFor).write(atSign, keys);
  }

  setUpAll(() async {
    atSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    final manager = await TestUtils.initAtClient(atSign, namespace);
    atClient = manager.atClient;
    await mintLegacyKeyfile(keysFilePath);
  });

  /// Authenticates from a legacy keyfile — the shared one by default, or an
  /// arm's own.
  ///
  /// An arm that retrofits **rsa2048** needs its own, because a keyfile is
  /// retrofitted once: the first arm to retrofit the shared file fixes its
  /// algorithm, and every later arm asking for a different one is refused.
  /// The mldsa65 arms share it deliberately — the last of them asserts that a
  /// rerun reuses rather than re-mints.
  Future<AtAuthSession> legacySession([String Function(String)? pathFor]) async {
    final auth = await AtAuth.create().authenticate(
        AtAuthRequest(atSign,
            atKeysIo: FileAtKeysIo(filePath: pathFor ?? keysFilePath))
          ..rootDomain = rootDomain);
    expect(auth.isSuccessful, true);
    return auth.session!;
  }

  test(
      'the rollout-window retrofit: an rsa2048 self-enrollment auto-approves '
      'and RSA PKAM succeeds under the new id', () async {
    // Its own keyfile: this arm retrofits rsa2048, and a keyfile takes one
    // retrofit. Sharing the file with the mldsa65 arms would let whichever
    // ran first claim it and refuse the rest.
    String t1Path(String a) => 'test/testData/rf2b-t1$a.atKeys';
    await mintLegacyKeyfile(t1Path);
    final session = await legacySession(t1Path);

    final response = await AtEnrollment.create().submit(
        AtSelfEnrollmentRequest(
            session: session,
            appName: 'rf2b-t1-app',
            deviceName: 'rf2b-t1-${Uuid().v4().hashCode}',
            namespaces: {'buzz': 'rw'},
            signingAlgo: SigningAlgoType.rsa2048,
            metadataBuilder: enrollmentKeyPackageBuilder(atSign,
                signingAlgo: SigningAlgoType.rsa2048)),
        session.atLookUp!);

    expect(response.enrollStatus, EnrollmentStatus.approved);
    final newId = response.enrollmentId;
    expect(newId, isNot(session.enrollmentId));

    final keys = await FileAtKeysIo(filePath: t1Path).read(atSign);
    expect(keys.signingAlgorithmForEnrollment(newId), SigningAlgoType.rsa2048,
        reason: 'the rollout-window mode mints a FRESH RSA keypair — the '
            'same algorithm as legacy, a new key object, its own enrollment '
            'id — and needs no ML-DSA anywhere');

    final rsaAuth = await AtAuth.create().authenticate(AtAuthRequest(atSign,
        atKeysIo: FileAtKeysIo(filePath: t1Path))
      ..enrollmentId = newId
      ..rootDomain = rootDomain);
    expect(rsaAuth.isSuccessful, true,
        reason: 'the retrofit that carries the rollout window must be usable '
            'immediately, exactly as the PQ one is');
  });

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

    // The _apsk this enrollment composed on its own enroll:request, published
    // verbatim by the atServer at approval — the server composes none.
    final apskResponse = await session.atLookUp!.executeCommand(
        'llookup:public:_apsk.$newId.a.__e$atSign\n',
        auth: true);
    final published = parseApskValue(
        apskResponse!.replaceFirst('data:', '').trim());
    expect(published.signingAlgo, SigningAlgoType.mldsa65,
        reason: 'a bare value would be parsed as an RSA key by every '
            'verifier, and the ML-DSA enrollment could never verify');

    // Close the loop: the key package the client signed with its minted
    // ML-DSA key verifies against the _apsk the atServer serves.
    // Verified against the raw algorithm rather than through verifyEnvelope,
    // so a bug shared by our writer and our reader cannot hide here. The
    // signing input is the RECEIVED base64url strings joined by a dot.
    final envelope = built!['keyPackage'] as Map;
    final entry = (envelope['signatures'] as List).single as Map;
    final ok = await MlDsa65PureDartAlgo().verifyBytes(
        utf8.encode('${entry['protected']}.${envelope['payload']}'),
        signature:
            base64Decode(base64.normalize(entry['signature'] as String)),
        publicKey: base64Decode(published.publicKey));
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
        // Mode B, explicitly: this row tests the PQ retrofit, and the
        // parameter default is the rollout-window RSA mode.
        signingAlgo: SigningAlgoType.mldsa65,
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
    expect(AtClientImpl.signingAlgoOf(client), SigningAlgoType.mldsa65,
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

    // Envelope signing: what this client signs verifies against the _apsk the
    // atServer serves for its enrollment — wrapAndSign must have signed
    // ML-DSA, or the verify refuses the algorithm mismatch.
    final sharing = AtClientSecretSharing.forClient(client);
    final envelope = await sharing.wrapAndSign('rf2c-proof');
    final apsk = (await client.getRemoteSecondary()!.executeCommand(
            'llookup:public:_apsk.${client.enrollmentId}.a.__e$atSign\n',
            auth: true))!
        .replaceFirst('data:', '');
    await verifyEnvelope(envelope,
        signerPublicKey: apsk, expecting: EnvelopeType.app);
  });

  test(
      'the pqActive posture decides an argless retrofit: no signingAlgo '
      'anywhere, the enrollment is ML-DSA, and so is its key package',
      () async {
    // A keyfile of its own, so the retrofit MINTS under the posture rather
    // than reusing an enrollment an earlier arm minted with different
    // settings — the reuse would satisfy the algorithm assertion and
    // silently void the key-package one.
    String posturePath(String a) => 'test/testData/rf2d-posture$a.atKeys';
    await mintLegacyKeyfile(posturePath);
    final auth = await AtAuth.create().authenticate(
        AtAuthRequest(atSign, atKeysIo: FileAtKeysIo(filePath: posturePath))
          ..rootDomain = rootDomain);
    expect(auth.isSuccessful, true);
    final session = auth.session!;

    // No signingAlgo argument. Under the legacy posture (or the old parameter
    // default) this call resolves rsa2048 and mints RSA — the assertions below
    // are what tell the two apart.
    final manager = await selfRetrofit(
        session: session,
        preference:
            TestUtils.getPreference(atSign, posture: PqPosture.pqActive),
        appName: 'rf2b-app',
        deviceName: 'rf2d-${Uuid().v4().hashCode}',
        namespaces: {namespace: 'rw'},
        manager: AtClientManager(atSign));

    final client = manager.atClient;
    expect(client.enrollmentId, isNot(session.enrollmentId));
    expect(AtClientImpl.signingAlgoOf(client), SigningAlgoType.mldsa65,
        reason: 'nothing in this test named an algorithm — the posture is '
            'the only thing that could have chosen ML-DSA');

    // The key package frozen on the enrollment record is signed by the
    // enrollment's SIGNING key, which is rsa2048 — fetched with the fully
    // privileged owner client, since the scoped retrofit cannot run
    // enroll:list.
    final record = (await atClient.enrollmentService!.fetchEnrollmentRequests())
        .firstWhere((e) => e.enrollmentId == client.enrollmentId);
    final pkg = record.metadata!['keyPackage'] as Map;
    final header = jsonDecode(utf8.decode(base64Decode(base64.normalize(
        ((pkg['signatures'] as List).single as Map)['protected']
            as String)))) as Map;
    expect(header['alg'], 'RS256',
        reason: 'a peer verifies this package against this enrollment\'s '
            '_apsk, and _apsk names its rsa2048 SIGNING key — so the package '
            'must be signed by that key and not by the ML-DSA authentication '
            'key. ML-DSA-65 here would mean the record and the package '
            'disagree, and every peer would refuse to seal a secret to this '
            'enrollment. This assertion read ML-DSA-65 until 2026-08-14, when '
            'the enrollment gained a signing key of its own');

    // ⚠️ The posture reaching the enrollment is proven by the AUTHENTICATION
    // key above, not by this header. Until the enrollment owned a signing key
    // the header was a second witness for it; now the two keys are
    // deliberately different algorithms, which is the whole point of the
    // split, and only the auth key tracks the posture.
    expect(AtClientImpl.signingAlgoOf(client), SigningAlgoType.mldsa65);
  });

  test(
      'an argless retrofit under the default preference stays rsa2048 — the '
      'legacy posture is really consulted, not a constant', () async {
    // Its own keyfile, for the same reason as the first arm: this one
    // resolves rsa2048, and the shared file is the mldsa65 arms'.
    String t5Path(String a) => 'test/testData/rf2b-t5$a.atKeys';
    await mintLegacyKeyfile(t5Path);
    final session = await legacySession(t5Path);
    final manager = await selfRetrofit(
        session: session,
        preference: TestUtils.getPreference(atSign),
        appName: 'rf2b-app',
        deviceName: 'rf2e-${Uuid().v4().hashCode}',
        namespaces: {namespace: 'rw'},
        manager: AtClientManager(atSign));

    final client = manager.atClient;
    expect(client.enrollmentId, isNot(session.enrollmentId));
    expect(AtClientImpl.signingAlgoOf(client), SigningAlgoType.rsa2048,
        reason: 'a consult replaced by a mldsa65 constant would land this '
            'argless call in the ML-DSA idempotence pool — this arm is the '
            'migration column\'s red');
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
    // privateAuthentication, not privateSigning: a retrofit files its APKAM
    // keypair (`fileApkamMaterial`), and nothing in production calls
    // `fileSigningMaterial` at all — per-algorithm signing material has no
    // writer yet. Filtering on privateSigning matches nothing, so this
    // assertion would fail for a reason that has nothing to do with reuse.
    final pqMaterials = keys.keys.where((m) =>
        m.keyAlgorithmType == KeyAlgorithmType.mlDsa65 &&
        m.keyPartType == CryptographicKeyType.privateAuthentication);
    expect(pqMaterials, hasLength(1),
        reason: 'a keyfile that already carries a PQ enrollment must reuse '
            'it, not mint a second — this is UC-A2.2\'s other arm');
    expect(again.enrollmentId, pqMaterials.single.enrollmentId);
  });
}
