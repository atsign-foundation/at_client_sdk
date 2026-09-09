// The enrollment key-package and posture surfaces this file drives are
// @experimental.
// ignore_for_file: experimental_member_use

@Tags(['pq'])
library;

import 'dart:io';

import 'package:at_auth/at_auth_io.dart' show FileAtKeysIo;
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart' show AtClientSecretSharing;
import 'package:at_functional_test/src/config_util.dart';
import 'package:at_functional_test/src/enrolled_client.dart'
    show EnrolledClient, enrolAndAuthenticate;
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import 'test_utils.dart';

/// What a retrofitted, namespace-scoped enrollment can do afterwards.
///
/// UC-B1.4 to UC-B1.7, plus one arm that is not a catalogue row. Under a
/// `pqReady` preference a client whose enrollment authenticates with a weaker
/// key than the posture asks for retrofits itself onto a fresh enrollment
/// before its constructor returns, and every assertion here happens after that.
///
/// Each arm drives a real operation rather than stopping at "it
/// authenticated": at_auth authenticates on its own connection before the
/// client exists, so a client can report success and still be unable to run a
/// verb. Each arm also asserts `runningAs != enrolledAs` first, because
/// `enrolAndAuthenticate` submits an OTP enrollment and that path mints
/// RSA-2048 unconditionally — a run in which the client did not move would
/// satisfy every operational assertion below while measuring an ordinary
/// enrollment.
void main() {
  TestUtils.isolateStorage('pq_retrofitted_scope_test');
  late String atSign;
  late AtClient approver;

  /// The namespace these enrollments are granted, and one they are not: `wavi`
  /// is a real namespace in this virtualenv, so the refusal below is about the
  /// grant rather than about a namespace nothing knows.
  const namespace = 'buzz';
  const ungrantedNamespace = 'wavi';

  final uuid = Uuid();

  setUpAll(() async {
    atSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    // Legacy deliberately: the approver must not retrofit itself.
    final manager = await TestUtils.initAtClient(atSign, namespace,
        posture: legacyPlusPqProviders);
    approver = manager.atClient;
    // The approver seals each enrollee's symmetric key to its own key package,
    // so it needs one registered before it can approve anything.
    await AtClientSecretSharing.forClient(approver).register();
  });

  /// A client running as a retrofitted enrollment scoped to [namespace] alone.
  ///
  /// No `*` and no `__manage`: a fully privileged retrofit also mints the
  /// signing root, which belongs to UC-B1.1 rather than here.
  Future<EnrolledClient> retrofittedScopedClient(String label) async {
    final enrolled = await enrolAndAuthenticate(
      approver: approver,
      atSign: atSign,
      namespace: namespace,
      // pqReady asks for mldsa65 authentication that the OTP path's RSA-2048
      // enrollment does not have, so the client retrofits. This preference is
      // the independent variable of the file.
      preference: TestUtils.getPreference(atSign, posture: PqPosture.pqReady),
      rootDomain: 'vip.ve.atsign.zone',
      rootPort: TestUtils.rootServerPort,
      // NOTE: (appName, deviceName) is one-shot server state — an
      // already-approved pair is refused, so a re-run against a live container
      // needs a fresh one. appName is the namespace here, so deviceName
      // carries the variance.
      deviceName: 'rs-$label-${uuid.v4().hashCode}',
      namespaces: {namespace: 'rw'},
      storage: TestUtils.storage,
    );

    expect(enrolled.client.enrollmentId, isNot(enrolled.enrollmentId),
        reason: 'the precondition for every assertion in this file: the client '
            'must have left the enrollment it was enrolled as. Equal ids mean '
            'no retrofit ran, and the rest of the arm would then be measuring '
            'an ordinary enrollment');
    expect(AtClientImpl.signingAlgoOf(enrolled.client), SigningAlgoType.mldsa65,
        reason: 'resolved from the retrofitted enrollment\'s typed key '
            'material. rsa2048 here means the client is still running as the '
            'enrollment it was enrolled as under a different id');
    return enrolled;
  }

  test('UC-B1.4 · a retrofitted scoped enrollment runs an authenticated verb',
      () async {
    final enrolled = await retrofittedScopedClient('verb');

    // Record-authoritative: the atServer judges the PKAM signature against the
    // algorithm on the enrollment record, so a reply at all means this
    // connection signed genuine ML-DSA under the new id.
    final scan = await enrolled.client
        .getRemoteSecondary()!
        .executeCommand('scan\n', auth: true);
    expect(scan, startsWith('data:'),
        reason: 'the verb connection authenticates lazily, on its own socket, '
            'with whatever signer and algorithm were stamped on it. A client '
            'that reported "authenticated" and cannot reach this line is the '
            'shape of the defect these rows exist to catch');
  }, timeout: Timeout(Duration(minutes: 3)));

  test('UC-B1.5 · it reads and writes inside its authorised namespace',
      () async {
    final enrolled = await retrofittedScopedClient('rw');
    final client = enrolled.client;

    final key = AtKey()
      ..key = 'rs-own-${uuid.v4().hashCode}'
      ..namespace = namespace
      ..sharedBy = atSign;

    expect(await client.put(key, 'written-after-the-retrofit'), true,
        reason: 'a write inside the granted namespace. The client-side gate '
            'reads the enrollment record the atServer holds for the id this '
            'client runs as, so a retrofit that lost its grants fails here');

    final read = await client.get(key);
    expect(read.value, 'written-after-the-retrofit',
        reason: 'and it reads its own write back — the value is encrypted with '
            'the atSign-wide self key, which is not per-enrollment, so a '
            'retrofit does not strand it');
  }, timeout: Timeout(Duration(minutes: 3)));

  test('UC-B1.6 · it is refused outside its authorised namespace', () async {
    final enrolled = await retrofittedScopedClient('refuse');
    final client = enrolled.client;

    final foreign = AtKey()
      ..key = 'rs-foreign-${uuid.v4().hashCode}'
      ..namespace = ungrantedNamespace
      ..sharedBy = atSign;

    // NOTE: `AtClientException`, not `UnAuthorizedException` — the
    // authorisation check throws the latter and `AtClientImpl.putText` wraps
    // it, so the message is what pins the refusal.
    await expectLater(
        client.put(foreign, 'should not land'),
        throwsA(isA<AtClientException>().having((e) => e.toString(), 'message',
            contains('insufficient privilege'))),
        reason: 'the retrofit carries the parent\'s grants over verbatim, so a '
            'scoped enrollment stays scoped. A retrofit that widened them '
            'would let this write through, and nothing else in the tree would '
            'notice — an escalation is silent where a loss is loud');

    // The positive control: the same client, the same operation, one namespace
    // over. Without it, the refusal above could equally mean the client cannot
    // write at all.
    final granted = AtKey()
      ..key = 'rs-control-${uuid.v4().hashCode}'
      ..namespace = namespace
      ..sharedBy = atSign;
    expect(await client.put(granted, 'control'), true,
        reason: 'the control for the refusal above: this client CAN write, in '
            'the namespace it holds');
  }, timeout: Timeout(Duration(minutes: 3)));

  test('UC-B1.7 · its grants are the parent enrollment\'s, verbatim', () async {
    final enrolled = await retrofittedScopedClient('grants');

    // Read off the atServer's own records rather than off the request the
    // client sent: only what the atServer recorded decides anything.
    final all = await approver.enrollmentService!.fetchEnrollmentRequests();
    final parent =
        all.firstWhere((e) => e.enrollmentId == enrolled.enrollmentId);
    final child =
        all.firstWhere((e) => e.enrollmentId == enrolled.client.enrollmentId);

    expect(child.namespace, parent.namespace,
        reason: 'neither escalated nor lost. The atServer refuses any grant '
            'the parent does not hold, so escalation would fail the retrofit '
            'outright; losing one would succeed silently and leave the client '
            'unable to do something it could do yesterday');
    expect(child.namespace, {namespace: 'rw'},
        reason: 'stated as a literal too, so that a retrofit which dropped the '
            'grants on BOTH records — leaving them equal and both empty — '
            'goes red rather than satisfying the comparison above');

    final ownView =
        await enrolled.client.enrollmentService!.fetchEnrollmentRequests();
    expect(ownView.map((e) => e.enrollmentId), [enrolled.client.enrollmentId],
        reason: 'a scoped enrollment holds no __manage, so enroll:list returns '
            'its own record and nothing else. Seeing the parent here would '
            'mean the retrofit had been granted management rights it was never '
            'asked for');
  }, timeout: Timeout(Duration(minutes: 3)));

  /// A retrofitted enrollment has to publish its own namespace advertisement,
  /// or no peer can seal to it: it sends post-quantum and cannot receive.
  ///
  /// Not a catalogue row, and narrow — it covers the in-process retrofit only:
  /// keys held in memory, one process, `pqReady`, and the `fromAuthSession`
  /// route. The cold-start arm below is the durable form.
  test('a retrofitted scoped enrollment publishes its own namespace key',
      () async {
    final enrolled = await retrofittedScopedClient('seed');
    final client = enrolled.client;

    // Seeding is unawaited startup work, so poll until it lands or the
    // deadline passes: a single read the moment the client returns cannot
    // tell "never seeded" from "not yet".
    final ring = PublishedNskeyKeyRing(client);
    NskeyAdvertisement? advertisement;
    final deadline = DateTime.now().add(Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      advertisement = await ring.publishedAdvertisement(atSign, namespace);
      if (advertisement != null) break;
      await Future.delayed(Duration(milliseconds: 500));
    }

    expect(client.getPreferences()!.seedNamespaceKeys, isTrue,
        reason: 'the control for the assertion below: pqReady asks this '
            'client to seed. If the axis is false the arm proves nothing');
    expect(advertisement, isNotNull,
        reason: 'REPORTED DEFECT: a retrofitted enrollment authorised for '
            'this namespace should publish public:__nskey.<ns>, or no peer '
            'can seal anything to it — it sends and cannot receive');
  }, timeout: Timeout(Duration(minutes: 3)));

  /// The cold-start form: a client that retrofits from a keyfile alone, with
  /// no enrolment session and nothing cached in the process.
  ///
  /// Two clients over one keyfile, varying only whether the retrofitting
  /// client was born from the enrolment session. Step 1 enrols scoped under
  /// `legacy`, so the keyfile it writes is genuinely pre-PQ; step 2 drops every
  /// cached client and builds a fresh one from that keyfile under `pqReady`.
  test(
      'a cold client that retrofits from a keyfile publishes its namespace '
      'key', () async {
    final keysFilePath = 'test/testData/rs-cold@$atSign.atKeys';
    final keyfile = File(keysFilePath);
    if (keyfile.existsSync()) keyfile.deleteSync();
    keyfile.parent.createSync(recursive: true);

    final enrolled = await enrolAndAuthenticate(
      approver: approver,
      atSign: atSign,
      namespace: namespace,
      // Legacy: this client must NOT retrofit, so that step 2 is the first and
      // only retrofit and the keyfile it reads is genuinely pre-PQ.
      preference: TestUtils.getPreference(atSign, posture: PqPosture.legacy),
      rootDomain: 'vip.ve.atsign.zone',
      rootPort: TestUtils.rootServerPort,
      deviceName: 'rs-cold-${uuid.v4().hashCode}',
      namespaces: {namespace: 'rw'},
      atKeysIo: FileAtKeysIo(filePath: (_) => keysFilePath),
      storage: TestUtils.storage,
    );

    expect(enrolled.client.enrollmentId, enrolled.enrollmentId,
        reason: 'step 1 must NOT have retrofitted, or the keyfile the cold '
            'client reads is already post-PQ and this arm varies nothing');
    expect(keyfile.existsSync(), isTrue,
        reason: 'the keyfile has to be on disk for the cold read below; an '
            'in-memory store here would make this a copy of the arm above');

    // Drop everything the process holds for this atSign, so the client below
    // is built the way a later run builds one: from the keyfile.
    await enrolled.manager.atClient.getRemoteSecondary()?.atLookUp.close();
    AtClientImpl.atClientInstanceMap.clear();

    final cold = await AtClientManager(atSign).setCurrentAtSign(atSign,
        namespace, TestUtils.getPreference(atSign, posture: PqPosture.pqReady),
        atKeysIo: FileAtKeysIo(filePath: (_) => keysFilePath),
        enrollmentId: enrolled.enrollmentId,
        storage: TestUtils.storageForPrincipal(atSign, enrolled.enrollmentId));
    final client = cold.atClient;

    expect(client.enrollmentId, isNot(enrolled.enrollmentId),
        reason: 'the cold client must retrofit — pqReady asks for mldsa65 and '
            'the keyfile holds rsa2048. Equal ids mean no retrofit ran and '
            'the seeding question below is not being asked');
    expect(client.getPreferences()!.seedNamespaceKeys, isTrue,
        reason: 'the control: pqReady asks this client to seed');

    final ring = PublishedNskeyKeyRing(client);
    NskeyAdvertisement? advertisement;
    final deadline = DateTime.now().add(Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      advertisement = await ring.publishedAdvertisement(atSign, namespace);
      if (advertisement != null) break;
      await Future.delayed(Duration(milliseconds: 500));
    }

    expect(advertisement, isNotNull,
        reason: 'REPORTED DEFECT, cold-start form: a retrofitted enrollment '
            'authorised for this namespace must publish '
            'public:__nskey.<ns>, or no peer can seal anything to it — it '
            'sends and cannot receive');
  }, timeout: Timeout(Duration(minutes: 4)));
}
