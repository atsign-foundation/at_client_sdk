// The retrofit surface is @experimental; driving it is the point of this file.
// ignore_for_file: experimental_member_use

@Tags(['pq', 'legacy-server'])
library;

import 'dart:io';

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart' show SigningAlgoType;
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_client/src/crypto/nskey/pq_signing_root.dart';
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
/// `legacy-server` tag on top of `pq`.** Every other test in this directory
/// wants the newest image; this one wants an old one, and would go quietly
/// meaningless against a current image — the server would simply auto-approve
/// and there would be no refusal to observe. `atsigncompany/virtualenv:vip-p3.15.0`
/// is the pin: a release tag, so it stays pre-PQ for good, unlike `vip`, which
/// gains post-quantum support and stops being a legacy atServer.
///
/// The row's Then has five clauses and they are asserted separately, because
/// four of them can hold while the fifth does not — which is exactly what the
/// first run of this scenario found. The abort was clean, but it left the
/// enrollment request it had just created sitting `pending` on the server, and
/// a client that retried left one per attempt. That is now denied on the way
/// out (at_auth 3.4.0), and clause 5 is what guards it.
void main() {
  late String atSign;
  late AtClient owner;
  final namespace = TestConstants.namespace;
  final runId = DateTime.now().microsecondsSinceEpoch;

  String keyfileFor(String label) => 'test/testData/b01-$label-$runId.atKeys';

  setUpAll(() async {
    atSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    await TestSuiteInitializer.getInstance()
        .testInitializer(atSign, namespace, ConfigUtil.getYaml()['authType']);
    owner = AtClientManager.getInstance().atClient;
  });

  /// Mints a genuinely pre-PQ enrollment — RSA APKAM, no key package — and
  /// writes its keyfile. The upgrade's starting point.
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

  Future<AtAuthSession> sessionFor(String label) async {
    final auth = await AtAuth.create().authenticate(AtAuthRequest(atSign,
        atKeysIo: FileAtKeysIo(filePath: (_) => keyfileFor(label)))
      ..namespace = namespace
      ..rootDomain = AtRootDomain(ConfigUtil.getYaml()['root_server']['url'],
          ConfigUtil.getYaml()['root_server']['port'] ?? 64));
    expect(auth.isSuccessful, true,
        reason: 'the legacy enrollment must authenticate before it can attempt '
            'the upgrade — that connection IS the upgrade\'s authority');
    return auth.session!;
  }

  Future<int> enrollmentsWithStatus(
      EnrollmentStatus status, String deviceMarker) async {
    final list = await owner.enrollmentService!.fetchEnrollmentRequests(
        enrollmentListParams: EnrollmentListRequestParam()
          ..enrollmentListFilter = [status]);
    return list.where((e) => (e.deviceName ?? '').contains(deviceMarker)).length;
  }

  test(
      'UC-B0.1: the upgrade aborts cleanly, stays legacy, and leaves the '
      'server as it found it', () async {
    // GIVEN a legacy atServer. Asserted, not assumed — the whole row is about
    //       what happens when the PQ surface is missing, so a run against a
    //       PQ-capable image must fail here rather than quietly prove nothing.
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
        // Mode B, explicitly: these rows test the PQ retrofit, and the
        // parameter default is the rollout-window RSA mode.
        signingAlgo: SigningAlgoType.mldsa65,
        session: session,
        preference: TestPreferences.getInstance().getPreference(atSign),
        appName: 'b01-priv',
        deviceName: 'b01-priv-rf-$runId',
        namespaces: {'*': 'rw', '__manage': 'rw'},
        manager: AtClientManager(atSign),
      );
    } catch (e) {
      thrown = e;
    }

    // THEN (1) it aborts, and (2) cleanly — a typed, named refusal that says
    //      what the atServer failed to do, not an arbitrary crash.
    expect(thrown, isA<AtEnrollmentException>(),
        reason: 'the client must refuse the upgrade in its own terms; an '
            'arbitrary exception type means it fell over rather than declined');
    expect(thrown.toString(), contains('auto-approve'),
        reason: 'the message must name the missing server capability — that '
            'is the "logs why" clause, and it is what tells an operator to '
            'upgrade the atServer rather than to debug the client');

    // (3) stays legacy, and (4) mints no PQ keys.
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
    expect(await enrollmentsWithStatus(EnrollmentStatus.pending, 'b01-priv-rf-'),
        0,
        reason: 'the enrollment the abort created must not be left pending: '
            'nobody will ever act on it, and a client that retries leaves one '
            'per attempt');
    expect(
        await enrollmentsWithStatus(EnrollmentStatus.denied, 'b01-priv-rf-'), 1,
        reason: 'it is denied rather than merely abandoned, which is what '
            'makes the abort observably clean');
  }, timeout: Timeout(Duration(minutes: 3)));

  test(
      'UC-B0.1: a scoped parent cannot tidy up, and the refusal says so',
      () async {
    // The limit of the cleanup, stated rather than hidden. Denying needs
    // `__manage`; a scoped enrollment does not have it, so its aborted request
    // survives until it expires. A caller is told that plainly instead of
    // being left to assume the server is clean.
    await mintLegacyEnrollment('scoped', {namespace: 'rw'});
    final session = await sessionFor('scoped');

    Object? thrown;
    try {
      await selfRetrofit(
        // Mode B, explicitly: these rows test the PQ retrofit, and the
        // parameter default is the rollout-window RSA mode.
        signingAlgo: SigningAlgoType.mldsa65,
        session: session,
        preference: TestPreferences.getInstance().getPreference(atSign),
        appName: 'b01-scoped',
        deviceName: 'b01-scoped-rf-$runId',
        namespaces: {'*': 'rw', '__manage': 'rw'},
        manager: AtClientManager(atSign),
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
}
