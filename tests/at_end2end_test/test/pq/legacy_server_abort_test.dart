// The retrofit surface is @experimental; driving it is the point of this file.
// ignore_for_file: experimental_member_use

@Tags(['pq', 'legacy-server'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:at_auth/at_auth.dart';
import 'package:at_auth/at_auth_io.dart';
import 'package:at_chops/at_chops.dart' show SigningAlgoType;
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_client/src/crypto/nskey/pq_signing_root.dart';
import 'package:at_commons/at_builders.dart' show UpdateVerbBuilder;
import 'package:at_commons/at_commons.dart' show AtBytes;
import 'package:at_demo_data/at_demo_data.dart'
    show aesKeyMap, encryptionPrivateKeyMap;
import 'package:at_end2end_test/config/config_util.dart';
import 'package:at_end2end_test/src/test_initializers.dart';
import 'package:at_end2end_test/src/test_preferences.dart';
import 'package:at_end2end_test/utils/test_constants.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:test/test.dart';

/// UC-B0.1 — a PQ-capable client cannot PQ-upgrade against a legacy atServer.
///
/// **This file needs a PINNED pre-PQ atServer, which is why it carries the
/// `legacy-server` tag on top of `pq`.** Against a current image the server
/// auto-approves and there is no refusal to observe.
/// `atsigncompany/virtualenv:vip-p3.15.0` is the pin: a release tag stays
/// pre-PQ, unlike `vip`, which gains post-quantum support.
///
/// The row's Then has five clauses, asserted separately because four of them
/// can hold while the fifth does not.
void main() {
  late String atSign;
  late AtClient owner;
  final namespace = TestConstants.namespace;
  final runId = DateTime.now().microsecondsSinceEpoch;

  String keyfileFor(String label) => 'test/testData/b01-$label-$runId.atKeys';

  setUpAll(() async {
    atSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    await TestSuiteInitializer.getInstance().testInitializer(
        atSign, namespace, ConfigUtil.getYaml()['authType'],
        posture: PqPosture.legacy);
    owner = AtClientManager.getInstance().atClient;
  });

  /// Mints a genuinely pre-PQ enrollment — RSA APKAM, no key package — and
  /// writes its keyfile.
  ///
  /// [namespaces] decides whether the parent holds `__manage`, which is what
  /// decides whether it may deny its own aborted request.
  Future<String> mintLegacyEnrollment(
      String label, Map<String, String> namespaces) async {
    final otp = (await owner.getOTP()).response;
    final response = await AtEnrollment.create().submit(
        AtEnrollmentRequest(
            atSign: atSign,
            appName: 'b01-$label',
            deviceName: 'b01-$label-$runId',
            namespaces: namespaces,
            otp: otp,
            signingAlgo: SigningAlgoType.rsa2048),
        AtLookupImpl(atSign, ConfigUtil.getYaml()['root_server']['url'],
            ConfigUtil.getYaml()['root_server']['port'] ?? 64));
    final record = (await owner.enrollmentService!.fetchEnrollmentRequests())
        .firstWhere((e) => e.enrollmentId == response.enrollmentId);
    await owner.enrollmentService!.approve(EnrollmentRequestDecision.approved(
        atSign: atSign,
        enrollmentId: response.enrollmentId,
        apkamSymmetricKey:
            AtBytes.fromString(record.encryptedAPKAMSymmetricKey!)));

    final keys = response.atAuthKeys!
      ..defaultSelfEncryptionKey = AtBytes.fromString(aesKeyMap[atSign]!)
      ..defaultEncryptionPrivateKey =
          AtBytes.fromString(encryptionPrivateKeyMap[atSign]!);
    final file = File(keyfileFor(label));
    if (file.existsSync()) file.deleteSync();
    file.parent.createSync(recursive: true);
    await FileAtKeysIo(filePath: (_) => keyfileFor(label)).write(atSign, keys);
    return response.enrollmentId;
  }

  /// The legacy enrollment's session, authenticated first: the connection the
  /// upgrade submits on IS the upgrade's authority, so a keyfile that cannot
  /// authenticate has no upgrade to attempt.
  Future<AtAuthSession> sessionFor(String label) async {
    final keysIo = FileAtKeysIo(filePath: (_) => keyfileFor(label));
    final rootDomain = AtRootDomain(ConfigUtil.getYaml()['root_server']['url'],
        ConfigUtil.getYaml()['root_server']['port'] ?? 64);
    final enrollmentId = await Atsign(atSign)
        .authenticatesAs(keys: keysIo, rootDomain: rootDomain);
    return AtAuthSession(
        atSign: atSign,
        rootDomain: rootDomain,
        atKeysIo: keysIo,
        namespace: namespace,
        enrollmentId: enrollmentId);
  }

  Future<int> enrollmentsWithStatus(
      EnrollmentStatus status, String deviceMarker) async {
    final list = await owner.enrollmentService!.fetchEnrollmentRequests(
        enrollmentListParams: EnrollmentListRequestParam()
          ..enrollmentListFilter = [status]);
    return list
        .where((e) => (e.deviceName ?? '').contains(deviceMarker))
        .length;
  }

  test(
      'UC-B0.1: the upgrade aborts cleanly, stays on the legacy provider, and leaves the '
      'server as it found it', () async {
    // GIVEN a legacy atServer, asserted rather than assumed.
    expect(await PqSigningRoot.publishedPublicKey(owner, atSign), isNull,
        reason: 'a signing root means this is not the pre-PQ atServer this '
            'row needs — check VIRTUALENV_IMAGE is the pinned legacy tag');

    final legacyEnrollmentId =
        await mintLegacyEnrollment('priv', {'*': 'rw', '__manage': 'rw'});
    final session = await sessionFor('priv');

    // WHEN alice1 attempts the upgrade sequence.
    Object? thrown;
    try {
      await selfRetrofit(
        // Named explicitly: the parameter default is the rollout-window RSA
        // mode, and these rows test the PQ retrofit.
        signingAlgo: SigningAlgoType.mldsa65,
        session: session,
        preference: TestPreferences.getInstance().forCoLocatedClient(atSign,
            posture: PqPosture.legacy, device: 'b01-priv-rf-$runId'),
        appName: 'b01-priv',
        deviceName: 'b01-priv-rf-$runId',
        namespaces: {'*': 'rw', '__manage': 'rw'},
      );
    } catch (e) {
      thrown = e;
    }

    // THEN (1) it aborts, and (2) cleanly — a typed, named refusal that says
    //      what the atServer failed to do.
    expect(thrown, isA<AtEnrollmentException>(),
        reason: 'the client must refuse the upgrade in its own terms; an '
            'arbitrary exception type means it fell over rather than declined');
    expect(thrown.toString(), contains('auto-approve'),
        reason: 'the message must name the missing server capability — that '
            'is the "logs why" clause, and it is what tells an operator to '
            'upgrade the atServer rather than to debug the client');

    // (3) stays on the legacy provider, and (4) mints no PQ keys.
    final after =
        await FileAtKeysIo(filePath: (_) => keyfileFor('priv')).read(atSign);
    expect(after.keys, isEmpty,
        reason: 'no typed material: an aborted upgrade must not leave PQ keys '
            'in the keyfile, or the next start would act as though it had one');
    expect(after.apkamPublicKey, isNotNull,
        reason: 'the legacy RSA APKAM is untouched — the atSign stays usable '
            'exactly as it was');
    expect(after.enrollmentId, legacyEnrollmentId,
        reason: 'still the legacy enrollment; nothing was switched over');

    // (5) no partial state on the server.
    expect(await PqSigningRoot.publishedPublicKey(owner, atSign), isNull,
        reason: 'a root must not be left behind by a failed upgrade — every '
            'enrollment on the atSign would chain to it, and D1 builds no '
            'rotation able to replace it');
    expect(
        await enrollmentsWithStatus(EnrollmentStatus.pending, 'b01-priv-rf-'),
        0,
        reason: 'the enrollment the abort created must not be left pending: '
            'nobody will ever act on it, and a client that retries leaves one '
            'per attempt');
    expect(
        await enrollmentsWithStatus(EnrollmentStatus.denied, 'b01-priv-rf-'), 1,
        reason: 'it is denied rather than merely abandoned, which is what '
            'makes the abort observably clean');
  }, timeout: Timeout(Duration(minutes: 3)));

  test('UC-B0.1: a scoped parent cannot tidy up, and the refusal says so',
      () async {
    // Denying needs `__manage`; a scoped enrollment does not have it, so its
    // aborted request survives until it expires, and the caller is told so.
    await mintLegacyEnrollment('scoped', {namespace: 'rw'});
    final session = await sessionFor('scoped');

    Object? thrown;
    try {
      await selfRetrofit(
        // Named explicitly: the parameter default is the rollout-window RSA
        // mode, and these rows test the PQ retrofit.
        signingAlgo: SigningAlgoType.mldsa65,
        session: session,
        preference: TestPreferences.getInstance().forCoLocatedClient(atSign,
            posture: PqPosture.legacy, device: 'b01-scoped-rf-$runId'),
        appName: 'b01-scoped',
        deviceName: 'b01-scoped-rf-$runId',
        namespaces: {'*': 'rw', '__manage': 'rw'},
      );
    } catch (e) {
      thrown = e;
    }

    expect(thrown, isA<AtEnrollmentException>());
    expect(thrown.toString(), contains('could NOT be denied'),
        reason: 'the message has to distinguish "cleaned up" from "left '
            'behind" — reporting a leftover it did not leave, or hiding one it '
            'did, are both worse than the leftover itself');
    expect(
        await enrollmentsWithStatus(EnrollmentStatus.pending, 'b01-scoped-rf-'),
        1,
        reason: 'and the leftover is real, which is what makes the message '
            'above worth asserting rather than decorative');
  }, timeout: Timeout(Duration(minutes: 3)));

  test(
      'UC-B0.1: the pre-PQ atServer refuses a second write to an immutable '
      'record', () async {
    // A refused second create is what a mint lock IS — how one signing root
    // and one nskey generation per atSign are kept — so a PQ-capable client
    // meeting an atServer nobody has upgraded needs that enforcement already
    // present. Without it two privileged clients each read no lock, each take
    // one, and each mint; the second overwrites the first with nothing
    // visibly going wrong.
    final record = AtKey()
      ..key = 'b01immutable$runId'
      ..sharedBy = atSign
      ..metadata = (Metadata()..immutable = true);

    Future<void> write(String value) =>
        owner.getRemoteSecondary()!.executeVerb(UpdateVerbBuilder()
          ..atKey = record
          ..value = value);

    Future<String> read(String operation) async {
      final response = await owner
          .getRemoteSecondary()!
          .executeCommand('llookup:$operation$record\n', auth: true);
      return (response ?? '').replaceFirst('data:', '').trim();
    }

    await write('first');

    // The control comes first: a refused second write is otherwise
    // indistinguishable from a record the atServer never stored at all.
    expect(await read(''), 'first',
        reason: 'the create has to be seen to have landed before a refusal of '
            'the write after it means anything');
    expect(
        (jsonDecode(await read('meta:')) as Map<String, dynamic>)['immutable'],
        isTrue,
        reason: 'and it has to have landed AS immutable — an atServer that '
            'parsed the flag and dropped it would refuse nothing below, and '
            'this would go green for an ordinary record nobody wrote twice');

    // Named, not a bare throwsA: a connection that failed for an unrelated
    // reason satisfies any throw, and WHICH refusal fired is the whole point.
    await expectLater(
        write('second'),
        throwsA(predicate((e) =>
            e is IllegalStateException &&
            '$e'.contains('Immutable records may not be updated'))),
        reason: 'the atServer issuing its own refusal, on an image released '
            'before any of the post-quantum work — which is what makes the '
            'interlock a PQ client relies on something it already has against '
            'a server that knows nothing about post-quantum anything');

    expect(await read(''), 'first',
        reason: 'and the refusal kept the record rather than merely reporting '
            'on it: an atServer that stored the second value and answered '
            'with an error afterwards would break every interlock built here');
  }, timeout: Timeout(Duration(minutes: 3)));
}
