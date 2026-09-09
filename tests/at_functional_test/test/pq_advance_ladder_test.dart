// The enrollment key-package surface is @experimental; an advance drives it.
// ignore_for_file: experimental_member_use

@Timeout(Duration(minutes: 20))
@Tags(['pq'])
library;

import 'dart:io';

import 'package:at_auth/at_auth.dart'
    show AtAuth, AtAuthRequest, AtKeys, InMemoryAtKeysIo;
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart' show AtClientSecretSharing;
import 'package:at_functional_test/src/at_keys_initializer.dart'
    show AtEncryptionKeysLoader;
import 'package:at_functional_test/src/config_util.dart';
import 'package:at_functional_test/src/enrolled_client.dart'
    show enrolAndAuthenticate;
import 'package:test/test.dart';

import 'test_utils.dart';

/// The advance ladder: one enrollment walked legacy → pqReady → pqActive,
/// asserting what changes at each rung and that nothing written before a rung
/// stops being readable after it.
///
/// **Neither rung is a call, and they are different mechanisms.**
///
/// - **legacy → pqReady happens by itself.** A client whose posture wants a
///   stronger authentication algorithm than its key material holds is
///   retrofitted by `AtClientImpl._settleEnrollmentIdentity` during
///   construction, and comes up on a NEW enrollment id. Nothing here asks for
///   that; building the client is the whole of it.
/// - **pqReady → pqActive keeps the enrollment.** Both authenticate with
///   ML-DSA-65, so no retrofit is due. What moves is the data signing key,
///   through `SigningKeyMinting.reconcileSigningKeys`, which reads a FINAL
///   preference field — so it needs a second client object for the same
///   `(atSign, enrollmentId)`, which `AtClientImpl.refuseChangedRolloutAxes`
///   refuses. The rung evicts the client cache first, as a process restart
///   would.
///
/// One test rather than three: a rung in its own `test()` would depend on the
/// previous one having run, so the file would pass or fail on declaration
/// order, which is not a property of the code.
void main() {
  TestUtils.isolateStorage('pq_advance_ladder_test');
  final atSign = ConfigUtil.getYaml()['atSign']['firstAtSign'] as String;

  /// Run-unique. A namespace key is minted once and thereafter ADOPTED, and
  /// adopting conveys no private half — so against a virtualenv that outlives
  /// a run, a fixed namespace makes this run's client adopt a generation whose
  /// private belongs to a previous run's and read nothing.
  final runId = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final namespace = 'pqlad$runId';

  late InMemoryAtKeysIo keysIo;
  late String legacyEnrollmentId;
  late AtClientManager ladderManager;
  late AtClientStorage ladderStorage;

  setUpAll(() async {
    final approverKeys = InMemoryAtKeysIo();
    await approverKeys.write(atSign, AtKeys());
    final loader = AtEncryptionKeysLoader.getInstance();
    final approverManager = await AtClientManager(atSign).setCurrentAtSign(
        atSign, namespace, TestUtils.getPreference(atSign,
            posture: legacyPlusPqProviders),
        atKeysIo: approverKeys,
        atChops: loader.createAtChopsFromDemoKeys(atSign),
        storage: TestUtils.storageFor(atSign));
    await loader.setEncryptionKeys(approverManager.atClient, atSign);
    await AtClientSecretSharing.forClient(approverManager.atClient).register();

    // The rung-0 enrollment: `enrolAndAuthenticate` submits over OTP, and that
    // path mints RSA-2048 unconditionally — the starting state rung 1 advances
    // FROM. An enrollment born ML-DSA would make rung 1 a no-op.
    keysIo = InMemoryAtKeysIo();
    await keysIo.write(atSign, AtKeys());
    final deviceName = 'ladder-$runId';
    final enrolled = await enrolAndAuthenticate(
      approver: approverManager.atClient,
      atSign: atSign,
      namespace: namespace,
      preference: TestUtils.getPreference(atSign, posture: PqPosture.legacy),
      rootDomain: 'vip.ve.atsign.zone',
      rootPort: TestUtils.rootServerPort,
      namespaces: {namespace: 'rw'},
      deviceName: deviceName,
      atKeysIo: keysIo,
      storage: TestUtils.storage,
    );
    legacyEnrollmentId = enrolled.client.enrollmentId!;
    // The install's one store: the enrolment built it under the device name,
    // and every rung below is a restart of the same install over it.
    ladderManager = enrolled.manager;
    ladderStorage = TestUtils.storageForPrincipal(atSign, deviceName);
    expect(ladderStorage.isHeldBy(enrolled.client), isTrue,
        reason: 'the ladder must walk the store the enrolment built, or the '
            'durability assertions compare two stores');
    stdout.writeln('##LADDER## rung 0 (legacy) is $legacyEnrollmentId');
  });

  /// Builds a client from the keyfile the ladder has been walking, under
  /// [posture] — the restart path an app walks when it ships a new stage, which
  /// is what an advance IS.
  Future<AtClient> clientAt(PqPosture posture, String enrollmentId) async {
    // The keyfile names the enrollment: once a rung has retrofitted, the
    // successor's typed material is the one active authentication key, so
    // at_auth resolves it; the flat id — the OTP enrollment — is what it
    // falls back to only before any retrofit.
    final auth = AtAuth.create();
    final response = await auth.authenticate(AtAuthRequest(
      atSign,
      rootDomain: AtRootDomain('vip.ve.atsign.zone', TestUtils.rootServerPort),
      atKeysIo: keysIo,
    ));
    expect(response.isSuccessful, isTrue,
        reason: 'could not authenticate from the ladder keyfile');
    expect(response.session!.enrollmentId, enrollmentId,
        reason: 'the ladder keyfile must resolve to the rung being asked for');

    // NOTE: ONE store for the whole ladder. An install does not move its
    // storage on every upgrade, and the durability assertions below only mean
    // something if the later rung reads the SAME store the earlier one wrote
    // to. A rung is a restart of the one install: the manager stops the
    // previous rung's client, which unfiles it and releases the store, and the
    // next client attaches to it as the principal that last held it. A fresh
    // manager per rung leaves the previous client holding the store, and the
    // next is refused as a second holder.
    final manager = await ladderManager.setCurrentAtSign(
        atSign, namespace, TestUtils.getPreference(atSign, posture: posture),
        atChops: auth.atChops,
        atKeysIo: keysIo,
        enrollmentId: enrollmentId,
        storage: ladderStorage);
    return manager.atClient;
  }

  /// Waits until the keyfile holds a signing key for every algorithm [posture]
  /// names, and returns what it holds.
  ///
  /// `SigningKeyMinting.reconcileSigningKeys` runs from the client's startup
  /// and is fire-and-forget, so the keyfile is not guaranteed to have caught
  /// up the instant `setCurrentAtSign` returns. Reading it immediately reports
  /// the PREVIOUS rung's key material and fails as though the stage moved
  /// nothing.
  ///
  /// Bounded and loud: a mint that never settles is a finding, not a wait.
  Future<Set<SigningAlgoType>> settledSigningKeys(
      String enrollmentId, PqPosture posture) async {
    final wanted = posture.dataSigningKeyAlgorithms;
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    while (true) {
      final held = (await keysIo.read(atSign))
          .signingKeysFor(enrollmentId)
          .map((k) => k.algorithm)
          .toSet();
      if (held.containsAll(wanted)) return held;
      if (DateTime.now().isAfter(deadline)) {
        throw StateError(
            'the mint never settled for $enrollmentId: the stage names '
            '$wanted and the keyfile holds $held after 60s. Signing now would '
            'fall back to the authentication key and measure a race rather '
            'than the stage');
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }

  Future<AtKey> writeAt(AtClient client, String rung) async {
    final key = AtKey()
      ..key = 'ladder$runId$rung'
      ..namespace = namespace
      ..sharedBy = atSign;
    expect(await client.put(key, 'written-at-$rung'), isTrue,
        reason: 'rung $rung could not write the record its successors must '
            'still be able to read');
    return key;
  }

  test('one enrollment walks legacy to pqReady to pqActive, and nothing '
      'written before a rung stops being readable after it', () async {
    // ---- rung 0: legacy ------------------------------------------------
    final atLegacy = await clientAt(PqPosture.legacy, legacyEnrollmentId);
    expect(atLegacy.enrollmentId, legacyEnrollmentId,
        reason: 'a legacy posture wants exactly the rsa2048 key the OTP '
            'enrollment already minted, so no retrofit is due and this client '
            'must still be running as the enrolled id');

    final keysAtLegacy = await keysIo.read(atSign);
    expect(keysAtLegacy.authenticationAlgorithmFor(legacyEnrollmentId),
        anyOf(isNull, SigningAlgoType.rsa2048),
        reason: 'the OTP path mints RSA-2048 and nothing has moved it yet');
    expect(keysAtLegacy.signingKeysFor(legacyEnrollmentId), isEmpty,
        reason: 'PqPosture.legacy names no data signing algorithms, so the '
            'enrollment holds no signing key of its own and its APKAM '
            'authentication key signs');

    final wroteAtLegacy = await writeAt(atLegacy, 'legacy');
    stdout.writeln('##LADDER## rung 0 keyfile: auth='
        '${keysAtLegacy.authenticationAlgorithmFor(legacyEnrollmentId)} '
        'signing=${keysAtLegacy.signingKeysFor(legacyEnrollmentId).map((k) => k.algorithm).toList()}');

    // ---- rung 1: legacy -> pqReady, which fires by itself ---------------
    final atPqReady = await clientAt(PqPosture.pqReady, legacyEnrollmentId);
    final pqReadyId = atPqReady.enrollmentId!;

    expect(pqReadyId, isNot(legacyEnrollmentId),
        reason: 'pqReady wants ML-DSA-65 while the enrollment holds RSA-2048, '
            'so the client must have retrofitted itself during construction '
            'and come up on a NEW enrollment id. Still running as '
            '$legacyEnrollmentId means the retrofit never fired and this is a '
            'legacy client wearing a pqReady preference');

    final signingAtPqReady =
        await settledSigningKeys(pqReadyId, PqPosture.pqReady);
    final keysAtPqReady = await keysIo.read(atSign);
    expect(keysAtPqReady.authenticationAlgorithmFor(pqReadyId),
        SigningAlgoType.mldsa65,
        reason: 'the retrofit mints the new enrollment an ML-DSA-65 APKAM '
            'authentication key - that is the whole of what rollout stage 1 '
            'moves');
    expect(signingAtPqReady, {SigningAlgoType.rsa2048},
        reason: 'pqReady names rsa2048 as its data signing algorithm, so the '
            'enrollment must now hold a signing key of its OWN - and it must '
            'still be RSA, because what peers verify is not asked to move at '
            'this stage. An ML-DSA signing key here would make the stage '
            'visible to every deployed peer');
    stdout.writeln('##LADDER## rung 1 (pqReady) is $pqReadyId, auth='
        '${keysAtPqReady.authenticationAlgorithmFor(pqReadyId)} '
        'signing=${keysAtPqReady.signingKeysFor(pqReadyId).map((k) => k.algorithm).toList()}');

    // Durability across the advance.
    expect((await atPqReady.get(wroteAtLegacy)).value, 'written-at-legacy',
        reason: 'a record written before the advance is unreadable after it. '
            'That is the guarantee the whole staged rollout rests on: nothing '
            'an install wrote may become unreadable when it upgrades');

    final wroteAtPqReady = await writeAt(atPqReady, 'pqready');

    // ---- rung 2: pqReady -> pqActive, same enrollment --------------------
    final atPqActive = await clientAt(PqPosture.pqActive, pqReadyId);
    expect(atPqActive.enrollmentId, pqReadyId,
        reason: 'pqReady and pqActive both authenticate with ML-DSA-65, so no '
            'retrofit is due and this rung must keep the SAME enrollment. A '
            'new id here would mean the ladder minted a second enrollment for '
            'a stage that changes no authentication key');

    final signingAtPqActive =
        await settledSigningKeys(pqReadyId, PqPosture.pqActive);
    expect(signingAtPqActive, contains(SigningAlgoType.mldsa65),
        reason: 'pqActive names mldsa65 as its data signing algorithm, so '
            'reconcileSigningKeys must have minted one. Without it the stage '
            'moved nothing and a pqActive client is signing RSA');
    stdout.writeln('##LADDER## rung 2 (pqActive) is ${atPqActive.enrollmentId}'
        ', signing=$signingAtPqActive');

    // Durability across BOTH advances, for both earlier rungs.
    expect((await atPqActive.get(wroteAtLegacy)).value, 'written-at-legacy',
        reason: 'the record written at legacy is unreadable two rungs later. '
            'Upgrading only ever ADDS read-capability, and a ladder that '
            'loses its own earliest write means an upgrading install loses '
            'data');
    expect((await atPqActive.get(wroteAtPqReady)).value, 'written-at-pqready',
        reason: 'the record written at pqReady is unreadable after the move '
            'to pqActive');
  });
}
