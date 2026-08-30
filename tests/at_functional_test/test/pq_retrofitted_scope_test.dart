// The enrollment key-package and posture surfaces are @experimental; driving
// them is how this file gets a retrofitted enrollment at all.
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

/// **What a retrofitted, namespace-SCOPED enrollment can do afterwards.**
///
/// UC-B1.4 to UC-B1.7, plus one arm that is not a catalogue row — see its
/// own comment. A legacy atSign upgrades by running a client at a newer
/// posture, so this is the migration path itself: the client comes up, finds
/// its enrollment authenticates with a weaker key than the posture asks for,
/// and retrofits itself onto a fresh enrollment before its constructor
/// returns. Everything asserted here happens after that.
///
/// ⛔ **The gap these rows close is per-ROUTE, and that is the whole lesson.**
/// Two different pieces of code retrofit a client, and until 2026-08-26 only
/// one of them had ever been asked to do anything afterwards:
///
/// | route | who drives it | proven to work afterwards |
/// | --- | --- | --- |
/// | explicit | `selfRetrofit` in at_client | yes — `self_enrollment_retrofit_live_test.dart` runs a verb and receives over a monitor |
/// | startup | `AtClientImpl._settleEnrollmentIdentity` | **no** — every test stopped at "it authenticated" |
///
/// The second route is the one `at_activate` and every SDK consumer takes, and
/// a defect lived in it for as long as it existed: the CLI stamped the
/// retrofitted enrollment's id and algorithm on its lookup and left the
/// *signer* at the one at_auth had resolved before the move, so the connection
/// declared `mldsa65` over an RSA-2048 keypair and at_chops refused it.
/// Authentication reported success throughout, because at_auth authenticates
/// on its own connection before the client exists.
///
/// **So an assertion that a live enrollment authenticates proves nothing about
/// whether it can work**, and that is why each row below drives an actual
/// operation.
///
/// ⚠️ **Every arm asserts the retrofit HAPPENED before asserting anything
/// else.** `enrolAndAuthenticate` submits an OTP enrollment, and that path
/// mints RSA-2048 unconditionally — there is no algorithm on the request for
/// it to carry. Under a `pqReady` preference the client then leaves that
/// enrollment behind during construction. A run in which it did not would
/// satisfy every operational assertion here while measuring an ordinary
/// enrollment, so `runningAs != enrolledAs` is the precondition rather than a
/// nice-to-have.
void main() {
  late String atSign;
  late AtClient approver;

  /// The namespace this file's enrollments are granted, and one they are not.
  ///
  /// `wavi` is a real namespace in this virtualenv rather than an invented
  /// string, so the refusal below is about the GRANT and not about the
  /// namespace being unknown to anything.
  const namespace = 'buzz';
  const ungrantedNamespace = 'wavi';

  final uuid = Uuid();

  setUpAll(() async {
    atSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    // Legacy, deliberately: the approver must not retrofit itself. It holds no
    // enrollment id of its own, so it would not — but naming the posture says
    // that is intended rather than incidental.
    final manager = await TestUtils.initAtClient(atSign, namespace,
        posture: legacyPlusPqProviders);
    approver = manager.atClient;
    // The approver seals each enrollee's symmetric key to its own key package,
    // so it needs one registered before it can approve anything.
    await AtClientSecretSharing.forClient(approver).register();
  });

  /// A client running as a retrofitted enrollment scoped to [namespace] alone.
  ///
  /// Scoped means scoped: no `*`, no `__manage`. That matters for more than
  /// realism — a fully privileged retrofit also mints the signing root, which
  /// is a second thing to go wrong and belongs to [UC-B1.1] rather than here.
  Future<EnrolledClient> retrofittedScopedClient(String label) async {
    final enrolled = await enrolAndAuthenticate(
      approver: approver,
      atSign: atSign,
      namespace: namespace,
      // pqReady asks for mldsa65 authentication, which the RSA-2048 enrollment
      // the OTP path mints does not have — so `retrofitIsDue` is true and the
      // client moves. This preference IS the independent variable of the file.
      preference: TestUtils.getPreference(atSign, posture: PqPosture.pqReady),
      rootDomain: 'vip.ve.atsign.zone',
      rootPort: TestUtils.rootServerPort,
      // (appName, deviceName) is one-shot server state: an already-approved
      // pair is refused, so a re-run against a live container needs a fresh
      // one. appName is the namespace here, so deviceName carries the variance.
      deviceName: 'rs-$label-${uuid.v4().hashCode}',
      namespaces: {namespace: 'rw'},
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
    // algorithm on the enrollment RECORD, so a reply at all means this
    // connection signed genuine ML-DSA under the new id. That is the exact
    // step the CLI defect broke, and it broke it after authentication had
    // already reported success.
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

    // ⚠️ `AtClientException`, not `UnAuthorizedException`: the authorisation
    // check throws the latter and `AtClientImpl.putText` wraps it. Asserting
    // the inner type — which is what reading `LocalSecondary` alone suggests —
    // fails on a refusal that DID happen, so the message is what pins it.
    await expectLater(
        client.put(foreign, 'should not land'),
        throwsA(isA<AtClientException>().having((e) => e.toString(), 'message',
            contains('insufficient privilege'))),
        reason: 'the retrofit carries the parent\'s grants over verbatim, so a '
            'scoped enrollment stays scoped. A retrofit that widened them '
            'would let this write through, and nothing else in the tree would '
            'notice — an escalation is silent where a loss is loud');

    // The positive control, in the same arm rather than in another file: the
    // same client, the same operation, one namespace over. Without it a refusal
    // here could equally mean the client cannot write at all.
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
    // client sent: what the client asked for and what the atServer recorded are
    // different facts, and only the second one decides anything.
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

    // What a scoped enrollment can see of the enrollment list is itself a
    // grant boundary, and it is the one this arm reads through.
    final ownView = await enrolled.client.enrollmentService!
        .fetchEnrollmentRequests();
    expect(ownView.map((e) => e.enrollmentId), [enrolled.client.enrollmentId],
        reason: 'a scoped enrollment holds no __manage, so enroll:list returns '
            'its own record and nothing else. Seeing the parent here would '
            'mean the retrofit had been granted management rights it was never '
            'asked for');
  }, timeout: Timeout(Duration(minutes: 3)));

  /// ⛔ **Not a catalogue row: this arm was written to reproduce a reported
  /// defect and did not reproduce it.** Kept because it guards a real property
  /// and because its GREEN is the finding — it narrows where the reported
  /// fault can live.
  ///
  /// Reported 2026-08-26 from a live ephemeral environment: a retrofitted
  /// atSign never publishes its own namespace advertisement, so it can SEND
  /// post-quantum and cannot RECEIVE. On this path it does publish one, with
  /// the negative control proven — asking for a namespace nothing seeds
  /// returns null here.
  ///
  /// ⚠️ **What this arm does NOT cover, and the reported case has all four.**
  /// Listed so the green is not read as wider than it is:
  ///
  /// | | here | reported |
  /// | --- | --- | --- |
  /// | key source | `InMemoryAtKeysIo` | a real keyfile on disk |
  /// | process | one — enrol and retrofit together | two — onboard, exit, retrofit on a later run |
  /// | posture | `pqReady` | `pqActive` |
  /// | route | `fromAuthSession` | the app's own onboarding |
  ///
  /// The second row is the one to suspect first: a fresh process reading a
  /// keyfile is the durable arm, and nothing about an in-memory retrofit
  /// exercises it.
  test('a retrofitted scoped enrollment publishes its own namespace key',
      () async {
    final enrolled = await retrofittedScopedClient('seed');
    final client = enrolled.client;

    // Seeding is unawaited startup work, so read until it lands or the
    // deadline passes — a single read the moment the client returns cannot
    // distinguish "never seeded" from "not yet".
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

  /// ⛔ **The COLD-START arm: the difference the arm above does not have.**
  ///
  /// The arm above retrofits inside the process that enrolled, holding its
  /// keys in memory. The reported case does neither: an atSign is onboarded
  /// and enrolled, the process exits, and a LATER run reads the keyfile off
  /// disk and retrofits from that alone. Everything that could be decided once
  /// and never re-evaluated lives in that gap, so it is the arm worth having.
  ///
  /// Two clients over one keyfile, varying **only** whether the retrofitting
  /// client was born from the enrolment session:
  ///
  /// 1. enrol scoped under `legacy`, writing a real keyfile. A legacy client
  ///    does not retrofit and does not seed — asserted, because if it seeded
  ///    here the second half would find an advertisement that has nothing to
  ///    do with the retrofit;
  /// 2. drop every cached client, then build a fresh one from the keyfile
  ///    alone under `pqReady` — no session, no injected AtChops, the store
  ///    read cold. That client retrofits, and the question is whether it
  ///    seeds.
  test('a cold client that retrofits from a keyfile publishes its namespace '
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
      // A real keyfile on disk, which is the whole point of this arm.
      atKeysIo: FileAtKeysIo(filePath: (_) => keysFilePath),
    );

    expect(enrolled.client.enrollmentId, enrolled.enrollmentId,
        reason: 'step 1 must NOT have retrofitted, or the keyfile the cold '
            'client reads is already post-PQ and this arm varies nothing');
    expect(keyfile.existsSync(), isTrue,
        reason: 'the keyfile has to be on disk for the cold read below; an '
            'in-memory store here would make this a copy of the arm above');

    // Everything the process is holding for this atSign goes, so the client
    // below is built the way a later run builds one: from the keyfile.
    await enrolled.manager.atClient.getRemoteSecondary()?.atLookUp.close();
    AtClientImpl.atClientInstanceMap.clear();

    final cold = await AtClientManager(atSign).setCurrentAtSign(
      atSign,
      namespace,
      TestUtils.getPreference(atSign, posture: PqPosture.pqReady),
      atKeysIo: FileAtKeysIo(filePath: (_) => keysFilePath),
      enrollmentId: enrolled.enrollmentId,
    );
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
