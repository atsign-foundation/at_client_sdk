// The self-retrofit and enrollment surfaces are @experimental; driving them is
// the point of this file.
// ignore_for_file: experimental_member_use

@Tags(['pq'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:at_auth/at_auth.dart';
import 'package:at_auth/at_auth_io.dart';
import 'package:at_chops/at_chops.dart' show SigningAlgoType;
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_commons/at_commons.dart' show AtBytes;
import 'package:at_demo_data/at_demo_data.dart'
    show aesKeyMap, encryptionPrivateKeyMap;
import 'package:at_end2end_test/config/config_util.dart';
import 'package:at_end2end_test/src/test_initializers.dart';
import 'package:at_end2end_test/src/test_preferences.dart';
import 'package:at_end2end_test/utils/test_constants.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:test/test.dart';

/// UC-B1.1's settlement, read off the atServer's own records.
///
/// A retrofit's successor settles what it replaced at its FIRST authentication
/// on a connection it opened itself: a predecessor that is approved and not
/// fully privileged is revoked as superseded, the successor is stamped
/// `predecessorSettledAt`, and nothing else moves — the predecessor's own
/// expiry above all, since there is no cap any more. `retrofit_e2e_test`
/// B1.2 carries the other half, a ROOT predecessor keeping its life, which is
/// what lets a clone of the first enrollment's keyfile still retrofit.
///
/// Three legacy enrollments are minted with deliberately different lifetimes
/// and only one is retrofitted. The other two are the control: without them,
/// "revoked" and "unchanged" would be equally explained by something that
/// touches every enrollment on the atSign. Every comparison is between two
/// values the atServer produced, never against this process's clock.
///
/// The settlement is **per predecessor**, which is what makes this safe on an
/// atSign other tests share — nothing here revokes a credential it did not
/// mint.
void main() {
  late String atSign;
  late AtClient owner;
  final namespace = TestConstants.namespace;

  /// `(appName, deviceName)` is one-shot server state, so a fixed name passes
  /// once and collides on the next run against the same virtualenv.
  final runId = DateTime.now().microsecondsSinceEpoch;
  String pathFor(String label) => 'test/testData/cap-$label-$runId.atKeys';

  /// The keyfile as it was before [retrofit] touched it — what an un-upgraded
  /// copy holds. The live keyfile names the successor once retrofitted.
  String preRetrofitPathFor(String label) => '${pathFor(label)}.pre-retrofit';
  AtRootDomain rootDomain() => AtRootDomain(
      ConfigUtil.getYaml()['root_server']['url'],
      ConfigUtil.getYaml()['root_server']['port'] ?? 64);

  /// A genuinely pre-PQ (RSA APKAM) enrollment with its own keyfile, whose key
  /// lifetime is [expiry] — or the atServer's own default when null.
  Future<String> mintLegacy(String label, Duration? expiry) async {
    final otp = (await owner.getOTP()).response;
    final response = await AtEnrollment.create().submit(
        AtEnrollmentRequest(
            atSign: atSign,
            appName: 'cap-$label',
            deviceName: 'cap-$label-$runId',
            namespaces: {namespace: 'rw'},
            otp: otp,
            apkamKeysExpiryDuration: expiry,
            signingAlgo: SigningAlgoType.rsa2048),
        AtLookupImpl(atSign, rootDomain().rootDomain, rootDomain().rootPort));
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
    final file = File(pathFor(label));
    if (file.existsSync()) file.deleteSync();
    final snapshot = File(preRetrofitPathFor(label));
    if (snapshot.existsSync()) snapshot.deleteSync();
    file.parent.createSync(recursive: true);
    await FileAtKeysIo(filePath: (_) => pathFor(label)).write(atSign, keys);
    return response.enrollmentId;
  }

  /// What the atServer reports for enrollment [id]: its status, its effective
  /// expiry as `expiresAt`, and the settlement stamp when it carries one.
  ///
  /// ⛔ **Through `enroll:list`, and it cannot go back to reading the record
  /// key directly.** The record lives at `<id>.new.enrollments.__manage@<atSign>`,
  /// and a data verb on that key is refused to every enrollment but its owner —
  /// including the atSign's own legacy client, which authenticates with no id
  /// and is therefore answered as the enrollment named `primary`. The roster
  /// carries every status, a revoked record included.
  Future<Map<String, dynamic>> enrollmentMeta(String id) async {
    final response = await owner
        .getRemoteSecondary()!
        .executeCommand('enroll:list\n', auth: true);
    expect(response, isNotNull);
    final roster = jsonDecode(response!.replaceFirst('data:', '').trim())
        as Map<String, dynamic>;
    final key = roster.keys.singleWhere((k) => k.startsWith(id),
        orElse: () => fail('enroll:list names no record for $id; it holds '
            '${roster.keys}'));
    final record = roster[key] as Map<String, dynamic>;
    expect(record.containsKey('expiresAt'), isTrue,
        reason: 'every enroll:list entry carries expiresAt, null or not — a '
            'missing key means this atServer predates the field, and every '
            'expiry assertion below would read null and pass for the wrong '
            'reason');
    return record;
  }

  DateTime? expiryOf(Map<String, dynamic> meta) =>
      meta['expiresAt'] == null ? null : DateTime.parse(meta['expiresAt']);

  /// Authenticates as the LEGACY enrollment: from the pre-retrofit snapshot
  /// once one exists, which is exactly what an un-upgraded copy of the keyfile
  /// does. The keys name the enrollment, so the live keyfile would resolve the
  /// successor after a retrofit.
  Future<AtAuthResponse> authenticateLegacy(String label) async {
    final snapshot = preRetrofitPathFor(label);
    final path = File(snapshot).existsSync() ? snapshot : pathFor(label);
    return AtAuth.create().authenticate(
        AtAuthRequest(atSign, atKeysIo: FileAtKeysIo(filePath: (_) => path))
          ..namespace = namespace
          ..rootDomain = rootDomain());
  }

  /// Retrofits [label] and gives the successor one authentication of its own,
  /// which is what settles the predecessor. The submission alone does not.
  ///
  /// Returns the SUCCESSOR's enrollment id, because that is the record the
  /// atServer stamps: `predecessorSettledAt` is written on the successor in
  /// the same act that revokes the predecessor, so the successor's stamp is
  /// the witness that the settlement ran over its parent.
  Future<String> retrofit(String label) async {
    File(pathFor(label)).copySync(preRetrofitPathFor(label));
    final session = (await AtAuth.create().authenticate(AtAuthRequest(atSign,
            atKeysIo: FileAtKeysIo(filePath: (_) => pathFor(label)))
          ..namespace = namespace
          ..rootDomain = rootDomain()))
        .session!;
    final manager = await selfRetrofit(
      // Mode B explicitly: this row is about the PQ retrofit, and the
      // parameter default is the rollout-window RSA mode.
      signingAlgo: SigningAlgoType.mldsa65,
      session: session,
      // A store of its own: the owner client holds the atSign's, and a
      // dedicated manager carries nothing across.
      preference: TestPreferences.getInstance().forCoLocatedClient(atSign,
          posture: PqPosture.legacy, device: 'cap-$label-$runId'),
      appName: 'cap-$label',
      deviceName: 'cap-$label-$runId',
      namespaces: {namespace: 'rw'},
      manager: AtClientManager(atSign),
    );
    expect(AtClientImpl.signingAlgoOf(manager.atClient),
        SigningAlgoType.mldsa65,
        reason: 'the retrofit itself must have succeeded, or the settlement '
            'is being attributed to a retrofit that never happened');
    // The settlement is run by the successor's FIRST authentication on a
    // connection it opened itself — never by the submission — so the
    // successor is made to use one.
    expect(
        await manager.atClient
            .getRemoteSecondary()!
            .executeCommand('scan\n', auth: true),
        startsWith('data:'),
        reason: 'the successor must authenticate on its own connection, '
            'because that is what settles the predecessor; a retrofit whose '
            'successor never authenticates settles nothing');
    final successor = manager.atClient.enrollmentId;
    expect(successor, isNotNull,
        reason: 'the retrofitted client must know the enrollment it came up '
            'on, or the stamp below cannot be looked for anywhere');
    return successor!;
  }

  setUpAll(() async {
    atSign = ConfigUtil.getYaml()['atSign']['thirdAtSign'];
    await TestSuiteInitializer.getInstance().testInitializer(
        atSign, namespace, ConfigUtil.getYaml()['authType'],
        posture: PqPosture.legacy);
    owner = AtClientManager.getInstance().atClient;
    await AtClientSecretSharing.forClient(owner).register();
  });

  test(
      'UC-B1.1: the successor settles its predecessor at first authentication '
      '— revoked as superseded, stamped, its expiry untouched',
      timeout: Timeout(Duration(minutes: 6)), () async {
    final shortId = await mintLegacy('short', Duration(hours: 1));
    final longId = await mintLegacy('long', Duration(hours: 2000));
    final noneId = await mintLegacy('none', null);

    final shortBefore = await enrollmentMeta(shortId);
    final longBefore = await enrollmentMeta(longId);
    final noneBefore = await enrollmentMeta(noneId);

    // The fixture is checked rather than assumed: three approved parents with
    // three different lifetimes, so "untouched" below is measurable on each.
    for (final before in [shortBefore, longBefore, noneBefore]) {
      expect(before['status'], 'approved');
      expect(before['predecessorSettledAt'], isNull,
          reason: 'a parent carries no settlement stamp of its own');
    }
    expect(expiryOf(shortBefore), isNotNull,
        reason: 'the short parent must have an expiry to keep');
    expect(expiryOf(longBefore), isNotNull,
        reason: 'the long parent must have an expiry to keep');
    expect(expiryOf(noneBefore), isNull,
        reason: 'the third parent must have NO expiry, or the arm that says '
            'it gains none is about a value that was already there');
    // Both authenticate before anything happens: the "before" of the
    // before/after pair the lockout below turns on.
    expect((await authenticateLegacy('short')).isSuccessful, isTrue);
    expect((await authenticateLegacy('long')).isSuccessful, isTrue);

    final shortSuccessor = await retrofit('short');

    // The successor is the witness: stamped, pointing at its predecessor, and
    // approved in its own right.
    final successorMeta = await enrollmentMeta(shortSuccessor);
    expect(successorMeta['predecessorSettledAt'], isNotNull,
        reason: 'the settlement ran over this parent — otherwise the revoked '
            'status below could be anything that revokes, and the stamp is '
            'written in the same act. It sits on the SUCCESSOR, never on the '
            'parent');
    expect(successorMeta['retrofitPredecessorEnrollmentId'], shortId,
        reason: 'the successor names the enrollment it replaced');
    expect(successorMeta['status'], 'approved',
        reason: 'settling the predecessor must not touch the successor');

    // ARM 1 — the predecessor is revoked, as superseded, and NOTHING else on
    // it moves: the expiry it was minted with is the expiry it keeps. There is
    // no cap; a server that still capped would pull a one-hour lifetime in
    // or push it out, and either shows here.
    final shortAfter = await enrollmentMeta(shortId);
    expect(shortAfter['status'], 'revoked',
        reason: 'a predecessor that is approved and not fully privileged is '
            'revoked at its successor\'s first authentication');
    expect(shortAfter['predecessorSettledAt'], isNull,
        reason: 'the parent carries no stamp of its own; reading it there is '
            'the mistake this assertion guards, and it would make the check '
            'on the successor unfalsifiable');
    expect(expiryOf(shortAfter), expiryOf(shortBefore),
        reason: 'revocation leaves the predecessor\'s own expiry exactly where '
            'it was — the cap this replaced would have moved it');

    // ARM 2 — the control. The settlement lands on the enrollment its own
    // successor came from and nowhere else: the un-retrofitted parents keep
    // their status and their expiry, and the one with none gains none.
    final longAfter = await enrollmentMeta(longId);
    final noneAfter = await enrollmentMeta(noneId);
    expect(longAfter['status'], 'approved',
        reason: 'retrofitting one enrollment must not revoke another');
    expect(expiryOf(longAfter), expiryOf(longBefore));
    expect(noneAfter['status'], 'approved');
    expect(expiryOf(noneAfter), isNull,
        reason: 'a parent with no expiry gains none: nothing caps, nothing '
            'stamps a lifetime onto a credential that had none');

    // ARM 3 — the lockout, immediately: the revoked parent's keyfile no longer
    // authenticates, while an un-retrofitted sibling minted at the same
    // moment still does. Named rather than `throwsA(anything)`: a bare
    // catch-all would pass for a malformed keyfile or an unreachable atServer.
    await expectLater(
        authenticateLegacy('short'),
        throwsA(predicate(
            (e) => '$e'.contains('AT0027') && '$e'.contains('revoked'))),
        reason: 'the superseded parent is refused as revoked the moment its '
            'successor has authenticated — there is no grace in which a copy '
            'of its keyfile goes on working');
    expect((await authenticateLegacy('long')).isSuccessful, isTrue,
        reason: 'a sibling legacy enrollment that never retrofitted is '
            'unaffected, which is what makes the refusal above attributable '
            'to the settlement rather than to the environment');
  });
}
