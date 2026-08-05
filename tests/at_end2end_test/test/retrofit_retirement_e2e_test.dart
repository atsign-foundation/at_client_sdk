// The retrofit surface is @experimental; driving it end-to-end is the point
// of this file.
// ignore_for_file: experimental_member_use

import 'dart:io';

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart' show SigningAlgoType;
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_demo_data/at_demo_data.dart'
    show aesKeyMap, encryptionPrivateKeyMap;
import 'package:at_end2end_test/config/config_util.dart';
import 'package:at_end2end_test/src/test_initializers.dart';
import 'package:at_end2end_test/src/test_preferences.dart';
import 'package:at_end2end_test/utils/test_constants.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:test/test.dart';

/// UC-B2.1 / UC-B2.2 — the capped legacy enrollment, watched ageing out.
///
/// The retrofit **caps** the enrollment it upgrades from rather than deleting
/// it: sibling clones of one keyfile upgrade on their own schedules and must
/// keep authenticating until they do. That the cap eventually retires the
/// legacy credential is the other half, and until now nothing asserted it
/// anywhere — the whole retirement story rested on a server-side unit test of
/// a ttl value.
///
/// **Runs on `fourthAtSign`, whose atServer is configured with a zero-hour
/// self-enrollment grace by `runLocal.sh`.** At the default 720h this row
/// would take a month; per-secondary rather than container-wide because a
/// zero grace kills a parent within a millisecond of its first retrofit, and
/// the B1 clone rows need a parent that survives its sibling's.
///
/// The differential that makes this evidence rather than a green light: a
/// SECOND legacy enrollment on the same atSign, at the same moment, that
/// never retrofits — and goes on authenticating. Without it, an environment
/// where nothing could authenticate would pass for a working cap.
void main() {
  late String atSign;
  late AtClient owner;
  final namespace = TestConstants.namespace;
  final runId = DateTime.now().microsecondsSinceEpoch;

  String pathFor(String label) => 'test/testData/rt-$label-$runId.atKeys';

  AtRootDomain rootDomain() => AtRootDomain(
      ConfigUtil.getYaml()['root_server']['url'],
      ConfigUtil.getYaml()['root_server']['port'] ?? 64);

  /// A genuinely pre-PQ (RSA APKAM) enrollment with its own keyfile.
  Future<String> mintLegacyEnrollment(String label) async {
    final otp = (await owner.getOTP()).response;
    final response = await AtEnrollment.create().submit(
        AtEnrollmentRequest(
            atSign: atSign,
            appName: 'rt-$label',
            deviceName: 'rt-$label-$runId',
            namespaces: {namespace: 'rw'},
            otp: otp),
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

  /// Authenticates from [label]'s keyfile with no enrollment id named, so the
  /// flat fields decide — i.e. as the LEGACY enrollment, which is exactly what
  /// an un-upgraded copy of the keyfile does.
  Future<AtAuthResponse> authenticateLegacy(String label) async =>
      AtAuth.create().authenticate(AtAuthRequest(atSign,
          atKeysIo: FileAtKeysIo(filePath: (_) => pathFor(label)))
        ..namespace = namespace
        ..rootDomain = rootDomain());

  setUpAll(() async {
    atSign = ConfigUtil.getYaml()['atSign']['fourthAtSign'];
    await TestSuiteInitializer.getInstance()
        .testInitializer(atSign, namespace, ConfigUtil.getYaml()['authType']);
    owner = AtClientManager.getInstance().atClient;
    await AtClientSecretSharing.forClient(owner).register();
  });

  test(
      'UC-B2.1/B2.2: the retrofit caps its parent, which then fails to '
      'authenticate while an un-retrofitted sibling still can', () async {
    // Two legacy enrollments, minted together. L2 is the control: it is never
    // a parent of any retrofit, so nothing should ever cap it.
    await mintLegacyEnrollment('l1');
    await mintLegacyEnrollment('l2');

    // Both authenticate before anything happens. This is the arm that makes
    // the failure below mean something: without it, an atServer that refused
    // everything would look exactly like a working cap.
    expect((await authenticateLegacy('l1')).isSuccessful, isTrue,
        reason: 'precondition: the legacy enrollment works BEFORE its '
            'retrofit — this is the "before" of a before/after pair');
    expect((await authenticateLegacy('l2')).isSuccessful, isTrue);

    // The un-upgraded copy of UC-B2.1: the same legacy keypair on a second
    // host, taken before the retrofit and never upgraded.
    File(pathFor('l1')).copySync(pathFor('l1b'));

    final session = (await authenticateLegacy('l1')).session!;
    final manager = await selfRetrofit(
      session: session,
      preference: TestPreferences.getInstance().getPreference(atSign),
      appName: 'rt-l1',
      deviceName: 'rt-l1-$runId',
      namespaces: {namespace: 'rw'},
      manager: AtClientManager(atSign),
    );
    final upgraded = manager.atClient;
    expect(upgraded.signingAlgoType, SigningAlgoType.mldsa65,
        reason: 'the retrofit itself must have succeeded, or the cap below '
            'is being attributed to a retrofit that never happened');

    // UC-B2.1: the un-upgraded copy is locked out. The lockout is the
    // enrollment's expiry cap elapsing — checked at auth, per attempt — not
    // a per-key delete: the keypair in that file is untouched and still
    // perfectly valid, and it is refused anyway.
    //
    // Named rather than `throwsA(anything)`: a bare catch-all would pass for
    // a malformed keyfile, an unreachable atServer, or any other accident,
    // and the row would be green for the absence of an effect instead of for
    // the cap.
    await expectLater(
        authenticateLegacy('l1b'),
        throwsA(predicate((e) =>
            '$e'.contains('AT0028') && '$e'.contains('expired or invalid'))),
        reason: 'the retrofit capped the parent to min(now + grace, its own '
            'expiry), and this deployment\'s grace is zero — a copy that '
            'never upgraded must stop authenticating, or a stolen keyfile '
            'outlives the upgrade that was supposed to retire it');

    // The control arm, re-run in the same session: the sibling that never
    // retrofitted still authenticates. So the refusal above is the cap
    // this retrofit applied, not the environment, the clock, or the atSign.
    expect((await authenticateLegacy('l2')).isSuccessful, isTrue,
        reason: 'a second legacy enrollment of the same atSign, minted at the '
            'same moment and never a parent of any retrofit, must be '
            'unaffected — this is what makes the lockout attributable');

    // And the upgraded credential itself keeps working: the retrofit retires
    // the old enrollment, not the device.
    final scan =
        await upgraded.getRemoteSecondary()!.executeCommand('scan\n', auth: true);
    expect(scan, startsWith('data:'),
        reason: 'the PQ enrollment the retrofit created is unaffected by its '
            'parent\'s retirement — otherwise the upgrade would lock the '
            'device out of its own atSign');
  }, timeout: const Timeout(Duration(minutes: 4)));
}
