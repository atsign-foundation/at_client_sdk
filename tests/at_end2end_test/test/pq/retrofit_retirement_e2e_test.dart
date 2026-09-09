// The retrofit surface is @experimental; driving it end-to-end is the point
// of this file.
// ignore_for_file: experimental_member_use

@Tags(['pq'])
library;

import 'dart:io';

import 'package:at_auth/at_auth.dart';
import 'package:at_auth/at_auth_io.dart';
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

/// UC-B2.1 / UC-B2.2 — the superseded legacy enrollment, locked out at once.
///
/// The retrofit's successor **revokes** the enrollment it upgraded from, as
/// superseded, at its own first authentication — it does not delete the
/// keypair, and it does not wait: there is no grace. A copy of the keyfile
/// taken before the upgrade therefore stops authenticating the moment the
/// upgraded install first connects. The one predecessor that keeps its life
/// is a fully privileged one, which `retrofit_e2e_test` B1.2 turns on.
///
/// **Runs on `fourthAtSign`** so the revocations it causes land on no other
/// row's parent.
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
            otp: otp,
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
        .testInitializer(atSign, namespace, ConfigUtil.getYaml()['authType'],
            posture: PqPosture.legacy);
    owner = AtClientManager.getInstance().atClient;
    await AtClientSecretSharing.forClient(owner).register();
  });

  test(
      'UC-B2.1/B2.2: the retrofit revokes its parent at first authentication, '
      'which then fails to authenticate while an un-retrofitted sibling still '
      'can', () async {
    // Two legacy enrollments, minted together. L2 is the control: it is never
    // a parent of any retrofit, so nothing should ever revoke it.
    await mintLegacyEnrollment('l1');
    await mintLegacyEnrollment('l2');

    expect((await authenticateLegacy('l1')).isSuccessful, isTrue,
        reason: 'precondition: the legacy enrollment works BEFORE its '
            'retrofit — this is the "before" of a before/after pair');
    expect((await authenticateLegacy('l2')).isSuccessful, isTrue);

    // The un-upgraded copy of UC-B2.1: the same legacy keypair on a second
    // host, taken before the retrofit and never upgraded.
    File(pathFor('l1')).copySync(pathFor('l1b'));

    final session = (await authenticateLegacy('l1')).session!;
    final manager = await selfRetrofit(
      // Explicit: the parameter default is the rollout-window RSA mode.
      signingAlgo: SigningAlgoType.mldsa65,
      session: session,
      // Its own store location: the owner client holds the atSign's, and a
      // dedicated manager carries nothing across.
      preference: TestPreferences.getInstance().forCoLocatedClient(atSign,
          posture: PqPosture.legacy, device: 'rt-l1-$runId'),
      appName: 'rt-l1',
      deviceName: 'rt-l1-$runId',
      namespaces: {namespace: 'rw'},
      manager: AtClientManager(atSign),
    );
    final upgraded = manager.atClient;
    expect(AtClientImpl.signingAlgoOf(upgraded), SigningAlgoType.mldsa65,
        reason: 'the retrofit itself must have succeeded, or the revocation '
            'below is being attributed to a retrofit that never happened');

    // UC-B2.1: the un-upgraded copy is locked out. The keypair in that file is
    // untouched and still perfectly valid; it is refused because the parent
    // enrollment was revoked as superseded, which is checked at every auth.
    //
    // NOTE: named rather than `throwsA(anything)` — a bare catch-all would
    // pass for a malformed keyfile or an unreachable atServer, leaving the row
    // green for the absence of an effect instead of for the revocation.
    await expectLater(
        authenticateLegacy('l1b'),
        throwsA(predicate(
            (e) => '$e'.contains('AT0027') && '$e'.contains('revoked'))),
        reason: 'the successor\'s first authentication revoked the parent as '
            'superseded, and there is no grace — a copy that never upgraded '
            'must stop authenticating at once, or a stolen keyfile outlives '
            'the upgrade that was supposed to retire it');

    // The control arm, re-run in the same session, so the refusal above is
    // attributable to this retrofit rather than to the environment or the
    // clock.
    expect((await authenticateLegacy('l2')).isSuccessful, isTrue,
        reason: 'a second legacy enrollment of the same atSign, minted at the '
            'same moment and never a parent of any retrofit, must be '
            'unaffected — this is what makes the lockout attributable');

    // The remedy, asserted rather than left as advice: a stranded device comes
    // back by an ordinary OTP enrollment.
    await mintLegacyEnrollment('l1c');
    expect((await authenticateLegacy('l1c')).isSuccessful, isTrue,
        reason: 'a fresh enrollment authenticates on the same atSign moments '
            'after the superseded one was refused: the route back is enrolling '
            'again, and nothing about the atSign itself is broken');

    final scan =
        await upgraded.getRemoteSecondary()!.executeCommand('scan\n', auth: true);
    expect(scan, startsWith('data:'),
        reason: 'the PQ enrollment the retrofit created is unaffected by its '
            'parent\'s retirement — otherwise the upgrade would lock the '
            'device out of its own atSign');
  }, timeout: const Timeout(Duration(minutes: 4)));
}
