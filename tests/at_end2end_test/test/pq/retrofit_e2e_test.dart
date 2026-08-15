// The retrofit, signing-root and substrate surfaces are @experimental;
// driving them end-to-end is the point of this file.
// ignore_for_file: experimental_member_use

@Tags(['pq'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart' show SigningAlgoType;
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_client/src/crypto/nskey/conveyed_key_collection.dart';
import 'package:at_client/src/crypto/nskey/pq_signing_chain.dart';
import 'package:at_client/src/crypto/nskey/pq_signing_root.dart';
import 'package:at_client/src/service/enrollment_service_impl.dart';
import 'package:at_demo_data/at_demo_data.dart'
    show aesKeyMap, encryptionPrivateKeyMap;
import 'package:at_end2end_test/config/config_util.dart';
import 'package:at_end2end_test/src/test_initializers.dart';
import 'package:at_end2end_test/src/test_preferences.dart';
import 'package:at_end2end_test/utils/test_constants.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:test/test.dart';

/// UC-B1.1 / B1.2 / B1.3 — the retrofit scenarios, end to end, with the
/// signing-root step **in the flow** rather than driven by hand.
///
/// What the functional pack already proves and this deliberately does not
/// re-prove: the no-OTP auto-approve, the dual-enrollment keyfile, ML-DSA
/// PKAM under the new id, the published `_apsk`, and that `selfRetrofit` hands
/// back a working client
/// (`tests/at_functional_test/test/self_enrollment_retrofit_live_test.dart`).
///
/// What is only observable here, because it needs three enrollments of one
/// atSign interacting over a live atServer:
///
/// - **The signing-root step in-flow.** A *privileged* retrofit mints and
///   publishes the root and anchors itself to it; a *second* one finds the
///   root present, mints nothing, and acquires the private by asking a
///   holder; a *scoped* one does neither. Nothing in the client calls
///   `mintIfAbsent` except `selfRetrofit`, so a test that called it itself
///   would prove the mechanism and not the flow.
/// - **Two clones of one pre-PQ keyfile reach DISTINCT enrollment ids** —
///   the 1:1:1 rule, which is a property of two files and a server, and
///   cannot be seen from one.
///
/// **Recycle the virtualenv before believing a run.** The signing root
/// survives a re-run against the same container — nothing deletes it, and the
/// mint stands down the moment it reads one — while the private that matched
/// it died with the last run's process. The precondition below fails loudly rather than skipping, since a
/// silently-skipped root step is exactly what this file exists to catch.
void main() {
  late String atSign;
  late AtClient owner;
  final namespace = TestConstants.namespace;
  final runId = DateTime.now().microsecondsSinceEpoch;

  /// B1.1's retrofitted enrollment, kept for B1.2 to pull from. It has to be
  /// *that* client and not another session on the same keyfile: the enrollment
  /// is the addressable identity here — a request is sealed to the key package
  /// an enrollment advertised, and a client authenticating from the same file
  /// without naming the enrollment id comes up as the LEGACY enrollment, which
  /// advertises no key package and so is addressed by nobody.
  late AtClient privileged;
  late AtKeysIo privilegedKeysIo;

  // Each legacy enrollment gets its own keyfile, and the clone is a byte copy
  // of one taken BEFORE it retrofits — a copy taken after would already carry
  // PQ material and reuse the enrollment instead of minting its own, which is
  // the opposite of what B1.2 is about.
  String pathFor(String label) => 'test/testData/rf-$label-$runId.atKeys';

  /// Mints a genuinely pre-PQ enrollment — RSA APKAM, no key package — and
  /// writes its keyfile. The retrofit's precondition.
  ///
  /// An OTP enrollment approved by the owner-keys client, not a CRAM onboard:
  /// CRAM secrets are one-shot per recycled virtualenv and this pack's atSigns
  /// are PKAM-provisioned anyway.
  Future<String> mintLegacyEnrollment({
    required String label,
    required Map<String, String> namespaces,
  }) async {
    final otp = (await owner.getOTP()).response;
    final response = await AtEnrollment.create().submit(
        AtEnrollmentRequest(
            atSign: atSign,
            appName: 'rf-$label',
            deviceName: 'rf-$label-$runId',
            namespaces: namespaces,
            otp: otp),
        AtLookupImpl(atSign, ConfigUtil.getYaml()['root_server']['url'],
            ConfigUtil.getYaml()['root_server']['port'] ?? 64));
    final record = (await owner.enrollmentService!.fetchEnrollmentRequests())
        .firstWhere((e) => e.enrollmentId == response.enrollmentId);
    await owner.enrollmentService!.approve(EnrollmentRequestDecision.approved(
        atSign: atSign,
        enrollmentId: response.enrollmentId,
        apkamSymmetricKey:
            AtBytes.fromString(record.encryptedAPKAMSymmetricKey!)));

    // What waitForApproval would fetch and decrypt; the approver here knows
    // the same values from at_demo_data, and the keyfile's at-rest
    // self-encryption needs the self key present.
    final keys = response.atAuthKeys!
      ..defaultSelfEncryptionKey = AtBytes.fromString(aesKeyMap[atSign]!)
      ..defaultEncryptionPrivateKey =
          AtBytes.fromString(encryptionPrivateKeyMap[atSign]!);

    final file = File(pathFor(label));
    if (file.existsSync()) file.deleteSync();
    file.parent.createSync(recursive: true);
    await FileAtKeysIo(filePath: (_) => pathFor(label)).write(atSign, keys);
    return response.enrollmentId;
  }

  Future<AtAuthSession> legacySession(String label) async {
    final auth = await AtAuth.create().authenticate(AtAuthRequest(atSign,
        atKeysIo: FileAtKeysIo(filePath: (_) => pathFor(label)))
      ..namespace = namespace
      ..rootDomain = AtRootDomain(
          ConfigUtil.getYaml()['root_server']['url'],
          ConfigUtil.getYaml()['root_server']['port'] ?? 64));
    expect(auth.isSuccessful, true,
        reason: 'the legacy enrollment must authenticate before it can '
            'retrofit — that connection IS the retrofit\'s authority');
    return auth.session!;
  }

  /// The published root's bytes, or null when the atSign has none.
  Future<List<int>?> publishedRoot(AtClient client) async =>
      await PqSigningRoot.publishedPublicKey(client, atSign);

  setUpAll(() async {
    atSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    await TestSuiteInitializer.getInstance()
        .testInitializer(atSign, namespace, ConfigUtil.getYaml()['authType']);
    owner = AtClientManager.getInstance().atClient;
    // The approver seals each enrollee's symmetric key to its own key
    // package, so it needs one registered before it can approve anything.
    await AtClientSecretSharing.forClient(owner).register();
  });

  test(
      'UC-B1.1: a privileged retrofit mints the signing root in-flow and '
      'anchors itself to it', () async {
    expect(await publishedRoot(owner), isNull,
        reason: 'this row is about the root being CREATED by the retrofit. A '
            'root already published means the virtualenv was not recycled — '
            'the record survives a re-run while the private that matched it '
            'did not');

    await mintLegacyEnrollment(
        label: 'e1', namespaces: {'*': 'rw', '__manage': 'rw'});
    final session = await legacySession('e1');

    // The clone B1.2 uses, taken while the keyfile is still pre-PQ.
    File(pathFor('e1')).copySync(pathFor('e1c'));

    final manager = await selfRetrofit(
      // Mode B, explicitly: these rows test the PQ retrofit, and the
      // parameter default is the rollout-window RSA mode.
      signingAlgo: SigningAlgoType.mldsa65,
      session: session,
      preference: TestPreferences.getInstance().getPreference(atSign),
      appName: 'rf-e1',
      deviceName: 'rf-e1-$runId',
      namespaces: {'*': 'rw', '__manage': 'rw'},
      // A dedicated manager keeps the owner client live alongside — through
      // the singleton, switching would stop it.
      manager: AtClientManager(atSign),
    );
    final client = manager.atClient;
    privileged = client;
    privilegedKeysIo = session.atKeysIo;

    expect(client.enrollmentId, isNot(session.enrollmentId));
    expect(AtClientImpl.signingAlgoOf(client), SigningAlgoType.mldsa65);

    // Checked, not assumed: if the atServer trimmed the grant, everything
    // below would be testing the scoped path while reading green.
    final granted = (await client.enrollmentService!.fetchEnrollmentRequests())
        .where((e) => e.enrollmentId == client.enrollmentId)
        .firstOrNull
        ?.namespace;
    expect(EnrollmentServiceImpl.isFullyPrivileged(granted), isTrue,
        reason: 'the retrofit must have carried * and __manage across, or '
            'the root step below is not being exercised at all');

    // The row: the root exists because the retrofit created it. Nothing in
    // this test called mintIfAbsent.
    final root = await publishedRoot(client);
    expect(root, isNotNull,
        reason: 'a privileged retrofit publishes the atSign\'s signing root '
            'in-flow: it is auto-approved by the atServer with no approver '
            'client in the loop, so nothing else would ever convey it one');

    // And it holds the matching private, in the same keyfile the legacy
    // material lives in.
    final held =
        await PqSigningRoot(client, keysIo: session.atKeysIo).privateHalf(atSign);
    expect(held, isNotNull,
        reason: 'the private is filed before the record is published — a '
            'published root whose private did not survive strands every '
            'enrollment on the atSign, and D1 builds no rotation to replace '
            'it with');

    // Anchored, verified against the published record rather than an
    // in-memory copy of it.
    final sharing = AtClientSecretSharing.forClient(client);
    expect(await PqSigningChain(client).readRootLink(client.enrollmentId!),
        isNotNull);
    final verdict =
        await PqSigningChain(client).verifyChain(sharing, client.enrollmentId!);
    expect(verdict.verdict, ChainVerdict.anchored,
        reason: 'the minter anchors itself at mint — waiting for a later '
            'start would leave a freshly published root vouching for nothing. '
            'Reason if not: ${verdict.reason}');
  }, timeout: const Timeout(Duration(minutes: 3)));

  test(
      'UC-B1.2: a clone of the same pre-PQ keyfile gets its OWN enrollment, '
      'mints no second root, and is given the private', () async {
    final rootBefore = await publishedRoot(owner);
    expect(rootBefore, isNotNull,
        reason: 'UC-B1.1 published it; this row is the second privileged '
            'retrofit, which must find one');

    // The clone authenticates as the SAME legacy enrollment as B1.1's
    // original — that is what makes it a clone rather than another device.
    final cloneSession = await legacySession('e1c');
    final manager = await selfRetrofit(
      // Mode B, explicitly: these rows test the PQ retrofit, and the
      // parameter default is the rollout-window RSA mode.
      signingAlgo: SigningAlgoType.mldsa65,
      session: cloneSession,
      preference: TestPreferences.getInstance().getPreference(atSign),
      // Deliberately the same (appName, deviceName) as B1.1: sibling clones
      // of one keyfile legitimately carry one app's identity, and the
      // atServer exempts this branch from the duplicate-enrollment refusal.
      appName: 'rf-e1',
      deviceName: 'rf-e1-$runId',
      namespaces: {'*': 'rw', '__manage': 'rw'},
      manager: AtClientManager(atSign),
    );
    final clone = manager.atClient;

    expect(clone.enrollmentId, isNotNull);
    expect(clone.enrollmentId, isNot(cloneSession.enrollmentId),
        reason: 'the retrofit spawns a FRESH enrollment; it never adds a '
            'second keypair under the existing one');

    // The row's first half: two clones of one keyfile, two distinct
    // enrollments. Read off the atServer's own list rather than inferred.
    final approved = (await clone.enrollmentService!.fetchEnrollmentRequests())
        .where((e) => e.appName == 'rf-e1' && e.deviceName == 'rf-e1-$runId')
        .map((e) => e.enrollmentId)
        .toSet();
    expect(approved.length, greaterThanOrEqualTo(3),
        reason: 'the legacy parent plus one child per clone — each cloned '
            'pre-PQ keyfile becomes its own enrollment, which is what lets '
            'an owner tell one device from another and revoke them apart');

    // The second half: it did NOT mint a second root.
    expect(await publishedRoot(clone), rootBefore,
        reason: 'byte-identical. Two roots would be unrecoverable rather '
            'than untidy — half this atSign\'s enrollments would chain to a '
            'root the other half rejected, and nothing reconciles that');

    // And its own keyfile has no root private of its own to show for it.
    final cloneRoot = PqSigningRoot(clone, keysIo: cloneSession.atKeysIo);
    expect(await cloneRoot.privateHalf(atSign), isNull,
        reason: 'the clone\'s keyfile is a copy taken before B1.1 ran, so it '
            'never held one — this is the precondition for the pull, not an '
            'assertion about it');

    // The pull. The holder is B1.1's retrofitted enrollment; the atServer
    // carries both legs, so nothing needs the two clients up simultaneously
    // beyond this process.
    //
    // Each step is driven rather than waited for. Client start runs the same
    // sequence fire-and-forget, so a test that raced it would be timing its
    // own luck; driving it also pins the ORDER the start path depends on —
    // bind before asking (a request sent under a kpid this client is about to
    // stop using can never be answered), hydrate before sweeping (a sweep
    // consumes the requests it cannot yet answer).
    final cloneSharing = AtClientSecretSharing.forClient(clone);
    await collectConveyedKeyMaterial(clone, cloneSession.atKeysIo);
    final asked = await cloneRoot.requestPrivateIfAbsent(
      isFullyPrivileged: () async => true,
      sharing: cloneSharing,
      namespace: namespace,
    );
    expect(asked, greaterThan(0),
        reason: 'the root carries no namespace and so never rides the '
            'enroll:listns fan-out; asking the namespace\'s key packages is '
            'the only route left to an enrollment that missed the conveyance');

    // The holder is B1.1's retrofitted enrollment — the one that minted the
    // root and advertised the key package this request was sealed to.
    final holder = privileged;
    final holderRoot = PqSigningRoot(holder, keysIo: privilegedKeysIo);
    final holderSharing = AtClientSecretSharing.forClient(holder);

    // Hydrate BEFORE the holder sweeps, which is the order client start uses
    // and the order this has to be driven in. A sweep consumes and deletes
    // the requests it finds and answers them out of this store, so a holder
    // that hydrates afterwards destroys precisely the request it was meant to
    // serve — and the requester, having spent its broadcast, waits for an
    // answer that no longer has anything to arrive from.
    expect(await holderRoot.hydrateStore(holderSharing, namespace), isTrue,
        reason: 'a holder answers out of its in-memory secret store, which a '
            'restart empties — without this re-prime at start the pull above '
            'would broadcast to a world of holders none of which could '
            'answer');
    await collectConveyedKeyMaterial(holder, privilegedKeysIo);

    // A holder waits a jittered moment before answering (so N holders do not
    // all seal the same reply), so give the collect leg a few passes.
    Uint8List? filed;
    for (var attempt = 0; attempt < 10 && filed == null; attempt++) {
      await cloneSharing.sweepOnce(fromRemote: true);
      await cloneRoot.filePendingPrivate(
          atSign, cloneSharing.secretStore.listSecrets());
      filed = await cloneRoot.privateHalf(atSign);
      if (filed == null) {
        await holderSharing.sweepOnce(fromRemote: true);
        await Future.delayed(const Duration(seconds: 1));
      }
    }
    expect(filed, isNotNull,
        reason: 'it must reach the KEYFILE, not just the transit store: that '
            'store is in-memory by design, so a private stopping there would '
            'be gone at the next start — and a root already published is '
            'never re-minted, so the only recovery is another pull');
    expect(filed, await holderRoot.privateHalf(atSign),
        reason: 'byte-for-byte the holder\'s. Filing verifies the arriving '
            'private against the published root before storing it, so this '
            'also proves what arrived is the real key rather than something '
            'a holder happened to send');

    // Now it can anchor itself, under its own distinct enrollment id.
    expect(
        await PqSigningChain(clone).publishOwnRootLink(
            isFullyPrivileged: () async => true,
            keysIo: cloneSession.atKeysIo),
        isTrue);
    final verdict = await PqSigningChain(clone).verifyChain(
        cloneSharing, clone.enrollmentId!);
    expect(verdict.verdict, ChainVerdict.anchored,
        reason: 'Reason if not: ${verdict.reason}');
  }, timeout: const Timeout(Duration(minutes: 4)));

  test(
      'UC-B1.3: a scoped enrollment retrofits without touching the signing '
      'root, and cannot escalate on the way', () async {
    final rootBefore = await publishedRoot(owner);
    expect(rootBefore, isNotNull, reason: 'published by UC-B1.1');

    await mintLegacyEnrollment(label: 'e2', namespaces: {namespace: 'rw'});

    // The escalation arm first: a scoped parent must not be able to hand
    // itself the grants that would let it mint or hold the root.
    await expectLater(
        selfRetrofit(
          // Mode B, explicitly: these rows test the PQ retrofit, and the
          // parameter default is the rollout-window RSA mode.
          signingAlgo: SigningAlgoType.mldsa65,
          session: await legacySession('e2'),
          preference: TestPreferences.getInstance().getPreference(atSign),
          appName: 'rf-e2',
          deviceName: 'rf-e2-esc-$runId',
          namespaces: {'*': 'rw', '__manage': 'rw'},
          manager: AtClientManager(atSign),
        ),
        throwsA(anything),
        reason: 'without this refusal any scoped keyfile could self-spawn a '
            'fully privileged enrollment, and the retrofit would be a '
            'privilege-escalation verb rather than an upgrade');

    // The scoped retrofit itself succeeds.
    final session = await legacySession('e2');
    final manager = await selfRetrofit(
      // Mode B, explicitly: these rows test the PQ retrofit, and the
      // parameter default is the rollout-window RSA mode.
      signingAlgo: SigningAlgoType.mldsa65,
      session: session,
      preference: TestPreferences.getInstance().getPreference(atSign),
      appName: 'rf-e2',
      deviceName: 'rf-e2-$runId',
      namespaces: {namespace: 'rw'},
      manager: AtClientManager(atSign),
    );
    final scoped = manager.atClient;

    expect(scoped.enrollmentId, isNot(session.enrollmentId));
    expect(AtClientImpl.signingAlgoOf(scoped), SigningAlgoType.mldsa65,
        reason: 'a scoped enrollment upgrades its authentication like any '
            'other — what it skips is the root, not the PQ');

    final granted = (await scoped.enrollmentService!.fetchEnrollmentRequests())
        .where((e) => e.enrollmentId == scoped.enrollmentId)
        .firstOrNull
        ?.namespace;
    expect(EnrollmentServiceImpl.isFullyPrivileged(granted), isFalse,
        reason: 'the other arm of B1.1\'s privilege check: if the atServer '
            'granted this one * and __manage too, the two rows would be the '
            'same case tested twice');

    // The row: the root is untouched and this enrollment holds none of it.
    expect(await publishedRoot(scoped), rootBefore);
    final scopedRoot = PqSigningRoot(scoped, keysIo: session.atKeysIo);
    expect(await scopedRoot.privateHalf(atSign), isNull);
    expect(
        await scopedRoot.requestPrivateIfAbsent(
          isFullyPrivileged: () async => false,
          sharing: AtClientSecretSharing.forClient(scoped),
          namespace: namespace,
        ),
        0,
        reason: 'a namespace-scoped enrollment is not entitled to the key '
            'that vouches for every enrollment on the atSign — asking would '
            'be refused, and asking anyway announces to every holder that '
            'something unentitled is looking for it');
    expect(await PqSigningChain(scoped).readRootLink(scoped.enrollmentId!),
        isNull,
        reason: 'it cannot anchor itself: its route to the chain is a link '
            'signed for it by a privileged enrollment');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
