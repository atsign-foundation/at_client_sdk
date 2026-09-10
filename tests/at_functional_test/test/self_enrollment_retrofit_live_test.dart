// The substrate is @experimental; exercising it from another package is the
// point of this file.
// ignore_for_file: experimental_member_use

@Tags(['pq'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:at_auth/at_auth.dart';
import 'package:at_auth/at_auth_io.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_client/src/service/notification_service_impl.dart';
import 'package:at_client/src/signing/envelope_signature.dart'
    show EnvelopeType, parseApskValue, verifyEnvelope;
import 'package:at_demo_data/at_demo_data.dart'
    show aesKeyMap, encryptionPrivateKeyMap;
import 'package:at_functional_test/src/config_util.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import 'test_utils.dart';

/// The PQ self-retrofit, live: an APKAM-authenticated client mints an
/// ML-DSA-65 keypair, submits a no-OTP `enroll:request`, is auto-approved by
/// the atServer, and immediately PKAM-authenticates under the new enrollment
/// with the ML-DSA key — record-authoritative, so the pass proves the whole
/// client chain (keyfile → AtChops → pkam dispatch) signed genuine ML-DSA.
///
/// The pre-PQ starting point is built with an ordinary OTP enrollment on
/// firstAtSign, approved by the demo-keys owner client, rather than a CRAM
/// onboard: CRAM secrets are one-shot per recycled virtualenv, and both
/// dedicated CRAM atSigns are consumed elsewhere in the same suite run.
void main() {
  TestUtils.isolateStorage('self_enrollment_retrofit_live_test');
  late String atSign;
  late AtClient atClient;
  const namespace = 'buzz';
  final rootDomain =
      AtRootDomain('vip.ve.atsign.zone', TestUtils.rootServerPort);
  String keysFilePath(String a) => 'test/testData/rf2b-legacy$a.atKeys';

  /// Mints a fresh pre-PQ (RSA APKAM) enrollment and writes its keyfile at
  /// [pathFor] — the retrofit's precondition, carrying no key package so that
  /// it is genuinely legacy. Each arm needs a path of its own: retrofit
  /// idempotence is per keyfile.
  Future<void> mintLegacyKeyfile(String Function(String) pathFor) async {
    final otp = (await atClient.getOTP()).response;
    final response = await AtEnrollment.create().submit(
        AtEnrollmentRequest(
            atSign: atSign,
            appName: 'rf2b-legacy',
            deviceName: 'rf2b-${Uuid().v4().hashCode}',
            namespaces: {namespace: 'rw'},
            otp: otp,
            signingAlgo: SigningAlgoType.rsa2048),
        AtLookupImpl(atSign, 'vip.ve.atsign.zone', TestUtils.rootServerPort));
    final record = (await atClient.enrollmentService!.fetchEnrollmentRequests())
        .firstWhere((e) => e.enrollmentId == response.enrollmentId);
    await atClient.enrollmentService!.approve(
        EnrollmentRequestDecision.approved(
            atSign: atSign,
            enrollmentId: response.enrollmentId,
            apkamSymmetricKey:
                AtBytes.fromString(record.encryptedAPKAMSymmetricKey!)));

    // NOTE: the keyfile's at-rest self-encryption needs the self key present.
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
    final manager = await TestUtils.initAtClient(atSign, namespace,
        posture: PqPosture.legacy);
    atClient = manager.atClient;
    await mintLegacyKeyfile(keysFilePath);
  });

  /// Authenticates from a legacy keyfile — the shared one by default, or an
  /// arm's own.
  ///
  /// An arm that authenticates its successor needs its own file: that first
  /// authentication revokes the predecessor, and a keyfile is retrofitted once,
  /// so the first arm to retrofit it fixes its algorithm. The shared file
  /// serves the one arm that walks the full retrofit.
  Future<AtAuthSession> legacySession(
      [String Function(String)? pathFor]) async {
    final auth = await AtAuth.create().authenticate(AtAuthRequest(atSign,
        atKeysIo: FileAtKeysIo(filePath: pathFor ?? keysFilePath))
      ..rootDomain = rootDomain);
    expect(auth.isSuccessful, true);
    return auth.session!;
  }

  test(
      'the rollout-window retrofit: an rsa2048 self-enrollment auto-approves '
      'and RSA PKAM succeeds under the new id', () async {
    // NOTE: its own keyfile — a keyfile takes one retrofit, so sharing with
    // the mldsa65 arms would let whichever ran first claim it.
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

    final rsaAuth = await AtAuth.create().authenticate(
        AtAuthRequest(atSign, atKeysIo: FileAtKeysIo(filePath: t1Path))
          ..rootDomain = rootDomain);
    expect(rsaAuth.isSuccessful, true,
        reason: 'the retrofit that carries the rollout window must be usable '
            'immediately, exactly as the PQ one is');
    expect(rsaAuth.session!.enrollmentId, newId,
        reason: 'the keyfile alone names the successor: nothing passed an id');
  });

  test(
      'the full retrofit: no-OTP submit auto-approves, the keyfile holds '
      'both enrollments, and ML-DSA PKAM succeeds under the new id', () async {
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

    final keys = await FileAtKeysIo(filePath: keysFilePath).read(atSign);
    expect(keys.enrollmentId, session.enrollmentId,
        reason: 'the flat fields keep the legacy enrollment; the successor '
            'lives in the typed material under its own id');
    expect(keys.signingAlgorithmForEnrollment(newId), SigningAlgoType.mldsa65);

    // NOTE: read over the legacy connection BEFORE the successor
    // authenticates — that first authentication revokes the legacy enrollment
    // and drops its connections, so nothing on `session.atLookUp` runs after
    // it.
    final apskResponse = await session.atLookUp!.executeCommand(
        'llookup:public:_apsk.$newId.a.__e$atSign\n',
        auth: true);
    final published =
        parseApskValue(apskResponse!.replaceFirst('data:', '').trim());
    expect(published.signingAlgo, SigningAlgoType.mldsa65,
        reason: 'a bare value would be parsed as an RSA key by every '
            'verifier, and the ML-DSA enrollment could never verify');

    // Verified against the raw algorithm rather than through verifyEnvelope, so
    // a bug shared by the writer and the reader cannot hide here; the signing
    // input is the RECEIVED base64url strings joined by a dot.
    final envelope = built!['keyPackage'] as Map;
    final entry = (envelope['signatures'] as List).single as Map;
    final ok = await MlDsa65PureDartAlgo().verifyBytes(
        utf8.encode('${entry['protected']}.${envelope['payload']}'),
        signature: base64Decode(base64.normalize(entry['signature'] as String)),
        publicKey: base64Decode(published.publicKey));
    expect(ok, true,
        reason: 'signer and published verify key must be the same keypair on '
            'the real wire, or every advertised-key verification fails');

    // PKAM is record-authoritative: this passes only with a genuine ML-DSA
    // signature, and an RSA one, whatever it claims, is refused.
    final pqAuth = await AtAuth.create().authenticate(
        AtAuthRequest(atSign, atKeysIo: FileAtKeysIo(filePath: keysFilePath))
          ..rootDomain = rootDomain);
    expect(pqAuth.isSuccessful, true,
        reason: 'the retrofitted enrollment must be usable IMMEDIATELY: '
            'keyfile → AtChops → pkam dispatch, all genuinely ML-DSA');
    expect(pqAuth.session!.enrollmentId, newId,
        reason: 'the keyfile alone names the successor: nothing passed an id');
  });

  test(
      'selfRetrofit switches to a working client: verb connection, monitor, '
      'and envelope signing all run under the ML-DSA enrollment',
      timeout: const Timeout(Duration(seconds: 90)), () async {
    String t3Path(String a) => 'test/testData/rf2c$a.atKeys';
    await mintLegacyKeyfile(t3Path);
    final session = await legacySession(t3Path);
    final deviceRF2C = 'rf2c-${Uuid().v4().hashCode}';
    final manager = await selfRetrofit(
        // Explicit: the parameter default is the rollout-window RSA mode.
        signingAlgo: SigningAlgoType.mldsa65,
        session: session,
        preference: TestUtils.getPreference(atSign, posture: PqPosture.legacy),
        appName: 'rf2b-app',
        deviceName: deviceRF2C,
        namespaces: {namespace: 'rw'},
        // Its own manager and store, named by the device: the owner client
        // stays live over the atSign's bundle, so this cold retrofit is a
        // SECOND principal rather than a succession from it.
        manager: AtClientManager(atSign),
        storage: TestUtils.storageForPrincipal(atSign, deviceRF2C));

    final client = manager.atClient;
    expect(client.enrollmentId, isNotNull);
    expect(client.enrollmentId, isNot(session.enrollmentId));
    expect(AtClientImpl.signingAlgoOf(client), SigningAlgoType.mldsa65,
        reason: 'resolved from the keyfile\'s typed material — the '
            'preference still says rsa2048');

    // Record-authoritative: a pass means this connection PKAMed ML-DSA.
    final scanResult =
        await client.getRemoteSecondary()!.executeCommand('scan\n', auth: true);
    expect(scanResult, startsWith('data:'));

    // The monitor opens its OWN socket and re-authenticates on every
    // (re)connect, so anything arriving over it proves ITS ML-DSA auth
    // independently of the verb connection above.
    final notifications = client.notificationService as NotificationServiceImpl;
    final firstNotification = notifications
        .subscribe(shouldDecrypt: false)
        .firstWhere((n) => n.key.contains('rf2cmon'));

    // NOTE: the listener that matters is the SERVER's. `subscribe()` returns
    // before the monitor's own socket has connected, PKAMed and written
    // `monitor:`, and the monitor asks for no backlog, so anything the atServer
    // creates in that window is unrecoverable.
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

    Future<void> ping() async {
      final result = await atClient.notificationService
          .notify(NotificationParams.forUpdate(pingKey, value: 'ping'));
      expect(result.notificationStatusEnum, NotificationStatusEnum.delivered,
          reason: 'atClientException being null does NOT mean delivered — the '
              'status switch has no default arm and the atServer never says '
              '"undelivered", so an errored notification returns silently');
    }

    // Pinged until one lands, rather than once: `listening` means this client
    // has WRITTEN `monitor:` to its socket, not that the atServer has read it,
    // and the atServer answers `monitor:` with an empty string, so there is no
    // acknowledgement to wait for instead. A ping arriving inside that gap is
    // written to no connection at all and nothing replays it. A genuinely deaf
    // monitor — a refused enrollment, a PKAM that did not take — fails every
    // attempt, so the retry does not weaken what this proves.
    await ping();
    late AtNotification received;
    final deadline = DateTime.now().add(const Duration(seconds: 40));
    while (true) {
      try {
        received = await firstNotification.timeout(const Duration(seconds: 5));
        break;
      } on TimeoutException {
        if (!DateTime.now().isBefore(deadline)) rethrow;
        await ping();
      }
    }
    expect(received.key, contains('rf2cmon'),
        reason: 'the retrofitted, SCOPED enrollment receives notifications '
            'for its own namespace over a monitor its ML-DSA key '
            'authenticated — sender is the owner client, receiver is this '
            'one, so this is a genuine cross-client delivery');

    // What this client signs must verify against the _apsk the atServer serves
    // for its enrollment: wrapAndSign signed ML-DSA, or the verify refuses the
    // algorithm mismatch.
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
    // NOTE: a keyfile of its own, so the retrofit MINTS under the posture —
    // reusing an enrollment an earlier arm minted with different settings
    // would satisfy the algorithm assertion and silently void the key-package
    // one.
    String posturePath(String a) => 'test/testData/rf2d-posture$a.atKeys';
    await mintLegacyKeyfile(posturePath);
    final auth = await AtAuth.create().authenticate(
        AtAuthRequest(atSign, atKeysIo: FileAtKeysIo(filePath: posturePath))
          ..rootDomain = rootDomain);
    expect(auth.isSuccessful, true);
    final session = auth.session!;

    // No signingAlgo argument: under the legacy posture this call resolves
    // rsa2048 and mints RSA, and the assertions below are what tell the two
    // apart.
    final deviceRF2D = 'rf2d-${Uuid().v4().hashCode}';
    final manager = await selfRetrofit(
        session: session,
        preference:
            TestUtils.getPreference(atSign, posture: PqPosture.pqActive),
        appName: 'rf2b-app',
        deviceName: deviceRF2D,
        namespaces: {namespace: 'rw'},
        manager: AtClientManager(atSign),
        // Its own store, named by the device: the owner client is live and
        // holds the atSign's bundle, so this cold retrofit is a SECOND
        // principal rather than a succession from it.
        storage: TestUtils.storageForPrincipal(atSign, deviceRF2D));

    final client = manager.atClient;
    expect(client.enrollmentId, isNot(session.enrollmentId));
    expect(AtClientImpl.signingAlgoOf(client), SigningAlgoType.mldsa65,
        reason: 'nothing in this test named an algorithm — the posture is '
            'the only thing that could have chosen ML-DSA');

    // Fetched with the fully privileged owner client: the scoped retrofit
    // cannot run enroll:list.
    final record = (await atClient.enrollmentService!.fetchEnrollmentRequests())
        .firstWhere((e) => e.enrollmentId == client.enrollmentId);
    final pkg = record.metadata!['keyPackage'] as Map;
    final header = jsonDecode(utf8.decode(base64Decode(base64.normalize(
        ((pkg['signatures'] as List).single as Map)['protected']
            as String)))) as Map;
    expect(header['alg'], 'ML-DSA-65',
        reason: 'a peer verifies this package against this enrollment\'s '
            '_apsk, so the package must be signed by the key that record '
            'names — which is the enrollment\'s data SIGNING key, never its '
            'authentication key. A retrofit mints the algorithm the enrollment '
            'will KEEP, and pqActive keeps ML-DSA-65, so at this posture the '
            'record names an ML-DSA signing key and the package is signed by '
            'it. RS256 here would mean the record and the package disagree, '
            'and every peer would refuse to seal a secret to this enrollment. '
            'History, because the spelling has moved twice: ML-DSA-65 until '
            '2026-08-14, when the enrollment gained a signing key of its own '
            'and this became RS256; back to ML-DSA-65 on 2026-08-30, when the '
            'mint stopped hardcoding rsa2048 and took the algorithm from the '
            'posture. At pqReady it is still RS256');

    // NOTE: the posture reaching the enrollment is proven by the
    // AUTHENTICATION key, not by the header above. The two keys are separate
    // axes — at pqReady they are deliberately different algorithms — and only
    // at pqActive do they coincide, so the header witnesses no posture.
    expect(AtClientImpl.signingAlgoOf(client), SigningAlgoType.mldsa65);
  });

  test(
      'an argless retrofit under the default preference stays rsa2048 — the '
      'legacy posture is really consulted, not a constant', () async {
    // Its own keyfile: this arm resolves rsa2048, and the shared file is the
    // mldsa65 arms'.
    String t5Path(String a) => 'test/testData/rf2b-t5$a.atKeys';
    await mintLegacyKeyfile(t5Path);
    final session = await legacySession(t5Path);
    final deviceRF2E = 'rf2e-${Uuid().v4().hashCode}';
    final manager = await selfRetrofit(
        session: session,
        preference: TestUtils.getPreference(atSign, posture: PqPosture.legacy),
        appName: 'rf2b-app',
        deviceName: deviceRF2E,
        namespaces: {namespace: 'rw'},
        manager: AtClientManager(atSign),
        // Its own store, named by the device: the owner client is live and
        // holds the atSign's bundle, so this cold retrofit is a SECOND
        // principal rather than a succession from it.
        storage: TestUtils.storageForPrincipal(atSign, deviceRF2E));

    final client = manager.atClient;
    expect(client.enrollmentId, isNot(session.enrollmentId));
    expect(AtClientImpl.signingAlgoOf(client), SigningAlgoType.rsa2048,
        reason: 'a consult replaced by a mldsa65 constant would land this '
            'argless call in the ML-DSA idempotence pool — this arm is the '
            'migration column\'s red');
  });

  test('mint-once per keyfile: a rerun reuses the PQ enrollment', () async {
    // NOTE: the successor is never authenticated here — that would revoke the
    // legacy enrollment the rerun submits from. The rerun this pins is a retry
    // after a retrofit that minted and filed but never switched, so the legacy
    // client is still the one running.
    String t6Path(String a) => 'test/testData/rf2b-rerun$a.atKeys';
    await mintLegacyKeyfile(t6Path);
    final session = await legacySession(t6Path);

    final first = await AtEnrollment.create().submit(
        AtSelfEnrollmentRequest(
            session: session,
            appName: 'rf2b-app',
            deviceName: 'rf2b-rerun-${Uuid().v4().hashCode}',
            namespaces: {'buzz': 'rw'},
            metadataBuilder: enrollmentKeyPackageBuilder(atSign,
                signingAlgo: SigningAlgoType.mldsa65)),
        session.atLookUp!);
    expect(first.enrollStatus, EnrollmentStatus.approved);

    final again = await AtEnrollment.create().submit(
        AtSelfEnrollmentRequest(
            session: session,
            appName: 'rf2b-app',
            deviceName: 'rf2b-rerun-${Uuid().v4().hashCode}',
            namespaces: {'buzz': 'rw'}),
        session.atLookUp!);

    expect(again.enrollStatus, EnrollmentStatus.approved);
    expect(again.enrollmentId, first.enrollmentId,
        reason: 'the rerun must hand back the enrollment the first submit '
            'minted, not a second one');
    final keys = await FileAtKeysIo(filePath: t6Path).read(atSign);
    // NOTE: privateAuthentication, not privateSigning — a retrofit files its
    // APKAM keypair, and filtering on privateSigning matches nothing, so the
    // assertion would fail for a reason that has nothing to do with reuse.
    final pqMaterials = keys.keys.where((m) =>
        m.algorithm == CryptographicMaterialAlgorithm.mlDsa65 &&
        m.role == CryptographicMaterialRole.privateAuthentication);
    expect(pqMaterials, hasLength(1),
        reason: 'a keyfile that already carries a PQ enrollment must reuse '
            'it, not mint a second — this is UC-A2.2\'s other arm');
    expect(again.enrollmentId, pqMaterials.single.enrollmentId);
  });
}
