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

/// Arm 3 — the advance ladder: one enrollment walked legacy → pqReady →
/// pqActive, asserting what changes at each rung and that nothing written
/// before a rung stops being readable after it.
///
/// **Why this is separate from the posture grid.** Re-running a static grid
/// after an advance adds no posture pair the grid does not already have —
/// advancing the legacy row to pqReady leaves four distinct pairs, all of them
/// already cells. What a ladder buys is what a re-run cannot: the shape of the
/// keyfile at each rung, and durability across the change.
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
///   refuses. The rung evicts the client cache first, which is what a process
///   restart would do for free.
///
/// One test rather than three: a rung in its own `test()` would depend on the
/// previous one having run, so the file would pass or fail on declaration
/// order, which is not a property of the code.
void main() {
  final atSign = ConfigUtil.getYaml()['atSign']['firstAtSign'] as String;

  /// Run-unique. A namespace key is minted once and thereafter ADOPTED, and
  /// adopting conveys no private half — so against a virtualenv that outlives
  /// a run, a fixed namespace makes this run's client adopt a generation whose
  /// private belongs to a previous run's and read nothing.
  final runId = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final namespace = 'pqlad$runId';

  late InMemoryAtKeysIo keysIo;
  late String legacyEnrollmentId;

  setUpAll(() async {
    final approverKeys = InMemoryAtKeysIo();
    await approverKeys.write(atSign, AtKeys());
    final loader = AtEncryptionKeysLoader.getInstance();
    final approverManager = await AtClientManager(atSign).setCurrentAtSign(
        atSign, namespace, TestUtils.getPreference(atSign,
            posture: legacyPlusPqProviders),
        atKeysIo: approverKeys,
        atChops: loader.createAtChopsFromDemoKeys(atSign));
    await loader.setEncryptionKeys(approverManager.atClient, atSign);
    await AtClientSecretSharing.forClient(approverManager.atClient).register();

    // The rung-0 enrollment. `enrolAndAuthenticate` submits over OTP, and that
    // path mints RSA-2048 unconditionally — which is exactly the starting
    // state this ladder needs, and is why rung 1 has something to advance
    // FROM. An enrollment born ML-DSA would make rung 1 a no-op.
    keysIo = InMemoryAtKeysIo();
    await keysIo.write(atSign, AtKeys());
    final enrolled = await enrolAndAuthenticate(
      approver: approverManager.atClient,
      atSign: atSign,
      namespace: namespace,
      preference: TestUtils.getPreference(atSign, posture: PqPosture.legacy),
      rootDomain: 'vip.ve.atsign.zone',
      rootPort: TestUtils.rootServerPort,
      namespaces: {namespace: 'rw'},
      deviceName: 'ladder-$runId',
      atKeysIo: keysIo,
    );
    legacyEnrollmentId = enrolled.client.enrollmentId!;
    stdout.writeln('##LADDER## rung 0 (legacy) is $legacyEnrollmentId');
  });

  /// Builds a client from the keyfile the ladder has been walking, under
  /// [posture] — which is what an advance IS. The same restart path a
  /// production app walks when it ships a new stage.
  Future<AtClient> clientAt(PqPosture posture, String enrollmentId) async {
    // Evict first, on EVERY rung. `AtClientImpl.create` checks the cache under
    // the id it is ASKED with, and refuses a hit whose rollout axes differ —
    // those axes are final at construction, so adopting them would leave the
    // caller writing under a stage it thinks it has left.
    //
    // ⚠️ That applies to the legacy → pqReady rung too, which is easy to get
    // wrong: the enrollment id does change on that rung, but it changes as a
    // RESULT of the retrofit, which runs inside `create` — after the cache
    // check. So the id being different afterwards buys nothing here.
    //
    // Evicting is what a process restart does for free, and a restart is what
    // an app shipping a new stage actually performs.
    AtClientImpl.atClientInstanceMap
        .remove(AtClientImpl.instanceKey(atSign, enrollmentId));

    // ⚠️ **Name the enrollment.** Left unset, `AtAuthRequest.enrollmentId`
    // defaults to the keyfile's FLAT id — the original OTP enrollment — and
    // the algorithm and the chops are then resolved from that one. By rung 2
    // this keyfile holds two enrollments, so the client would authenticate
    // with the legacy RSA keypair while the preference told at_chops the
    // algorithm was ML-DSA-65, and PKAM would fail deep inside a startup step
    // with "ML-DSA-65 secret key must be 4032 bytes: 1216" — the RSA key's
    // length, signed as though it were the other algorithm.
    //
    // `AtKeys.resolveAuthenticatingEnrollment` exists for callers with no id
    // and REFUSES to choose between several, on purpose. This ladder always
    // knows which rung it is on, so it says so.
    final auth = AtAuth.create();
    final response = await auth.authenticate(AtAuthRequest(
      atSign,
      rootDomain: AtRootDomain('vip.ve.atsign.zone', TestUtils.rootServerPort),
      atKeysIo: keysIo,
    )..enrollmentId = enrollmentId);
    expect(response.isSuccessful, isTrue,
        reason: 'could not authenticate from the ladder keyfile as '
            '$enrollmentId');

    // ⚠️ ONE directory for the whole ladder, and that is the point of the row.
    // This used to be per-posture (`$runId-${posture.hashCode}`), which is what
    // an install moving its storage on every upgrade would do — and no install
    // does. The durability assertion below only means something if the later
    // rung reads the SAME store the earlier one wrote to.
    //
    // It passed anyway until 2026-08-28, because `hiveStoragePath` was ignored
    // for the second client of an atSign in one process: every rung silently
    // shared one Hive box whatever path it named, so "readable after the
    // advance" was true because the rungs were one store rather than because
    // anything survived. Honouring the path is what exposed it.
    final storage = 'test/hive/ladder/$runId';
    final preference = TestUtils.getPreference(atSign, posture: posture)
      ..hiveStoragePath = storage
      ..commitLogPath = storage;

    final manager = await AtClientManager(atSign).setCurrentAtSign(
        atSign, namespace, preference,
        atChops: auth.atChops,
        atKeysIo: keysIo,
        enrollmentId: enrollmentId);
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
