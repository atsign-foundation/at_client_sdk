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

/// UC-B1.1's cap, measured as a **value** rather than as an outcome.
///
/// `retrofit_retirement_e2e_test.dart` proves what the cap DOES — a capped
/// legacy enrollment stops authenticating while an un-retrofitted sibling goes
/// on working — and it runs on an atSign configured with a **zero-hour** grace
/// so the effect is observable inside a test. At zero grace
/// `min(now + grace, its own remaining lifetime)` always picks `now`, so that
/// file can never show the expression is a `min` at all: an atServer that
/// unconditionally set the expiry to `now` would satisfy every assertion in it.
///
/// This runs at the deployment's ORDINARY grace and straddles it. Three legacy
/// enrollments are minted with deliberately different lifetimes, each is
/// retrofitted, and each parent's expiry is read off the atServer before and
/// after:
///
/// - a **short** parent (1 hour) keeps its own expiry — the grace is the larger
///   candidate, so the min takes the lifetime;
/// - a **long** parent (2000 hours) is pulled in — the grace is the smaller
///   candidate, so the min takes it;
/// - a parent with **no expiry at all** gains one.
///
/// ⚠️ **Every comparison is between two values the atServer produced**, never
/// against this process's clock. A capped expiry checked against
/// `DateTime.now()` here would be measuring clock agreement between two
/// machines, which fails rarely and gets diagnosed as a flake.
///
/// The cap is **per parent**, not per atSign: retrofitting one of these leaves
/// the other two at record version 1, untouched. That is what makes it safe to
/// run on an atSign other tests share — nothing here caps a credential it did
/// not mint.
void main() {
  late String atSign;
  late AtClient owner;
  final namespace = TestConstants.namespace;

  /// `(appName, deviceName)` is one-shot server state, so a fixed name passes
  /// once and collides on the next run against the same virtualenv.
  final runId = DateTime.now().microsecondsSinceEpoch;

  String pathFor(String label) => 'test/testData/cap-$label-$runId.atKeys';

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
    file.parent.createSync(recursive: true);
    await FileAtKeysIo(filePath: (_) => pathFor(label)).write(atSign, keys);
    return response.enrollmentId;
  }

  /// The enrollment record's metadata, straight off the atServer.
  ///
  /// The record stays at `<id>.new.enrollments.__manage@<atSign>` after
  /// approval — there is no `.approved.` address — so this is where the cap is
  /// visible.
  Future<Map<String, dynamic>> enrollmentMeta(String id) async {
    final response = await owner.getRemoteSecondary()!.executeCommand(
        'llookup:meta:$id.new.enrollments.__manage$atSign\n',
        auth: true);
    expect(response, isNotNull);
    return jsonDecode(response!.replaceFirst('data:', '').trim())
        as Map<String, dynamic>;
  }

  DateTime? expiryOf(Map<String, dynamic> meta) =>
      meta['expiresAt'] == null ? null : DateTime.parse(meta['expiresAt']);

  /// Retrofits [label] and gives the child one authentication of its own,
  /// which is what arms the cap. The submission alone does not.
  Future<void> retrofit(String label) async {
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
      // A store of its own. Three retrofitted clients of one atSign are live
      // in this process at once, and a shared storage path is a shared
      // keystore.
      preference: TestPreferences.getInstance().forCoLocatedClient(atSign,
          posture: PqPosture.legacy, device: 'cap-$label-$runId'),
      appName: 'cap-$label',
      deviceName: 'cap-$label-$runId',
      namespaces: {namespace: 'rw'},
      manager: AtClientManager(atSign),
    );
    expect(AtClientImpl.signingAlgoOf(manager.atClient),
        SigningAlgoType.mldsa65,
        reason: 'the retrofit itself must have succeeded, or the cap is being '
            'attributed to a retrofit that never happened');
    // The cap is armed by the new enrollment's FIRST authentication on a
    // connection it opened itself — never by the submission — so the child is
    // made to use one.
    expect(
        await manager.atClient
            .getRemoteSecondary()!
            .executeCommand('scan\n', auth: true),
        startsWith('data:'),
        reason: 'the child must authenticate on its own connection, because '
            'that is what arms the cap; a retrofit whose child never '
            'authenticates caps nothing');
  }

  setUpAll(() async {
    // NOT the atSign the retirement rows use: that one is configured with a
    // zero-hour grace, where both branches of the min collapse onto `now`.
    atSign = ConfigUtil.getYaml()['atSign']['thirdAtSign'];
    await TestSuiteInitializer.getInstance().testInitializer(
        atSign, namespace, ConfigUtil.getYaml()['authType'],
        posture: PqPosture.legacy);
    owner = AtClientManager.getInstance().atClient;
    await AtClientSecretSharing.forClient(owner).register();
  });

  test(
      'UC-B1.1: the cap is min(now + grace, the enrollment\'s own remaining lifetime)',
      timeout: Timeout(Duration(minutes: 6)), () async {
    final shortId = await mintLegacy('short', Duration(hours: 1));
    final longId = await mintLegacy('long', Duration(hours: 2000));
    final noneId = await mintLegacy('none', null);

    final shortBefore = await enrollmentMeta(shortId);
    final longBefore = await enrollmentMeta(longId);
    final noneBefore = await enrollmentMeta(noneId);

    // The fixture is the differential, so it is checked rather than assumed:
    // the three lifetimes must actually straddle the deployment's grace, or
    // the arms below are three copies of one case.
    expect(expiryOf(shortBefore), isNotNull,
        reason: 'the short parent must have an expiry to keep');
    expect(expiryOf(longBefore), isNotNull,
        reason: 'the long parent must have an expiry to be pulled in from');
    expect(expiryOf(noneBefore), isNull,
        reason: 'the third parent must have NO expiry, or the arm that says '
            'the cap gives it one is about a value that was already there');
    expect(expiryOf(longBefore)!.difference(expiryOf(shortBefore)!),
        greaterThan(Duration(days: 30)),
        reason: 'the two dated parents must be far enough apart to sit either '
            'side of the grace, or both arms take the same branch of the min');

    await retrofit('short');

    // The un-retrofitted parents are untouched: the cap lands on the
    // enrollment its own child came from and nowhere else. This is the
    // control for both arms below — without it, "long's expiry moved" would
    // be equally explained by something that moves every enrollment's.
    expect(expiryOf(await enrollmentMeta(longId)), expiryOf(longBefore),
        reason: 'retrofitting one enrollment must not cap another');
    expect(expiryOf(await enrollmentMeta(noneId)), isNull);

    // ARM 1 — the min takes the enrollment's OWN remaining lifetime, because
    // an hour is less than the grace. The record IS rewritten (the atServer
    // recomputes the ttl against the moment it caps), so this is not "nothing
    // happened": what survives is the absolute expiry.
    final shortAfter = await enrollmentMeta(shortId);
    expect(shortAfter['version'], greaterThan(shortBefore['version'] as int),
        reason: 'the cap did run over this record — otherwise the unchanged '
            'expiry below is an enrollment the retrofit never reached, which '
            'is the same green for the opposite reason');
    expect(
        expiryOf(shortAfter)!.difference(expiryOf(shortBefore)!).abs(),
        lessThan(Duration(seconds: 30)),
        reason: 'a parent expiring in an hour keeps its own expiry: the grace '
            'is the LARGER candidate, so the min takes the lifetime. An '
            'atServer that set the expiry to now + grace unconditionally '
            'would push this one out by weeks, and one that set it to `now` '
            'would pull it in by an hour');

    await retrofit('long');

    // ARM 2 — the min takes now + grace, because 2000 hours is more than it.
    final longAfter = await enrollmentMeta(longId);
    expect(
        expiryOf(longBefore)!.difference(expiryOf(longAfter)!),
        greaterThan(Duration(days: 1)),
        reason: 'a parent expiring in 2000 hours is pulled in hard: the grace '
            'is the SMALLER candidate, so the min takes it. A day of margin, '
            'so the 17ms of drift that arm 1 tolerates cannot satisfy this '
            'one — the two arms have to be answering different questions');
    expect(expiryOf(longAfter)!.isBefore(expiryOf(longBefore)!), isTrue);

    await retrofit('none');

    // ARM 3 — a parent with no expiry at all gains one. `min(now + grace, ∞)`
    // is the grace, and this is the arm that says the cap is not merely
    // shortening an existing lifetime.
    final noneAfter = await enrollmentMeta(noneId);
    expect(expiryOf(noneAfter), isNotNull,
        reason: 'an enrollment that never expired now does. No enrollment is '
            'exempt, and one with an unbounded lifetime is the case where a '
            'cap that only shortened what was already there would do nothing');
  });
}
