import 'dart:convert';
import 'dart:io';

import 'package:at_auth/at_auth.dart';
import 'package:at_auth/at_auth_io.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart'
    show AtClient, AtClientImpl, PqPosture;
import 'package:at_demo_data/at_demo_data.dart' as at_demos;
import 'package:at_onboarding_cli/at_onboarding_cli.dart';
import 'package:at_utils/at_utils.dart';
import 'package:test/test.dart';

import 'utils/test_keys_dir.dart';

/// ON-1's consumer half: `at_onboarding_cli` can activate an atSign
/// **PQ-native**, so the capability is one an end user can actually reach.
///
/// The three things a PQ-native activation must produce are all-or-nothing,
/// which is why they are asserted together. An ML-DSA APKAM with no key package
/// is not a partial success — `metadata.keyPackage` is written by the
/// `enroll:request` that creates the enrollment record and never again, so an
/// atSign activated that way could never be repaired, only abandoned. This test
/// exists to fail if the CLI ever mints one of the three without the others.
///
/// Both tests here drive their remote commands on a client from a fresh
/// `authenticate()` under a **bare** preference, never on the activation
/// client. That is what `at_activate`'s `otp`, `list` and `spp` do — they build
/// their client through `createAtClient`, which names no posture — and it is
/// the only arrangement in which the preference and the key material can
/// disagree. A test driven on the activation client agrees with itself.
///
/// The two tests are one comparison: the *only* thing varied between them is
/// the posture at activation, so an outcome that differs can only come from
/// the key material each activation minted. Each states its own resolved
/// algorithm, so a run in which they silently converged fails rather than
/// passing while measuring nothing.
///
/// One-shot server state: CRAM activation works once per atSign per virtualenv,
/// so `@denise` and `@egbiometric🛠` are this file's alone — every other atSign
/// in this package is already spent by an `onboard()` or has its PKAM key
/// installed by hand for the authenticate tests, and either makes an
/// activation here fail.
void main() {
  AtSignLogger.root_level = 'WARNING';

  final String atSign = AtUtils.fixAtSign('@denise');
  final String keysDir = testKeysDir;
  final String keysFilePath = testKeysFile(atSign);

  // The posture rides the constructor, which is the whole point: an app
  // becomes post-quantum by naming a stage, not by setting an algorithm on a
  // preference the activation path may or may not read. Setting the old
  // deprecated field here made this test pass whether or not the resolution
  // worked, because the value it asserted was the one it had written.
  AtOnboardingPreference preference() =>
      AtOnboardingPreference(posture: PqPosture.pqReady)
        ..rootDomain = 'vip.ve.atsign.zone'
        ..hiveStoragePath = 'test/storage/hive/$atSign'
        ..commitLogPath = 'test/storage/hive/$atSign/commit'
        ..namespace = 'wavi'
        ..cramSecret = at_demos.cramKeyMap[atSign]
        ..atKeysFilePath = keysFilePath
        ..downloadPath = keysDir
        ..appName = 'wavi'
        ..deviceName = 'pq-cli';

  setUp(() {
    // AtAuth.onboard refuses if a keyfile already exists, so a leftover from an
    // earlier run would make this pass in isolation and fail in the suite.
    for (final path in [keysFilePath, '$keysFilePath.bak']) {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    }
  });

  test('a CLI activation under the pqReady posture is PQ-native', () async {
    final service = AtOnboardingServiceImpl(atSign, preference());
    expect(await service.onboard(), true);

    final keys = await FileAtKeysIo(filePath: (_) => keysFilePath).read(atSign);
    final enrollmentId = keys.enrollmentId;
    expect(enrollmentId, isNotEmpty);

    // --- 1. the APKAM is ML-DSA, and it is what authenticates --------------
    expect(keys.apkamPublicKey, isNull,
        reason: 'a PQ-native keyfile keeps its APKAM in the typed section, so '
            'a reader that cannot handle that fails loudly rather than '
            'signing an ML-DSA key with the RSA routine');
    expect(keys.signingAlgorithmForEnrollment(enrollmentId!),
        SigningAlgoType.mldsa65);

    // A fresh connection authenticating from the keyfile alone. No RSA APKAM
    // exists anywhere, so this can only succeed by ML-DSA.
    //
    // Under a **bare** preference, deliberately: that is what `at_activate`
    // hands `createAtClient` for `otp`, `list` and `spp`, so its posture is
    // `legacy` and its `authenticationKeyAlgorithm` is `rsa2048`. Everything
    // below then runs on this client rather than on the activation client,
    // because the activation client was built under `pqReady` and so cannot
    // tell a working resolution from a posture that happens to agree with it.
    // A client that reads its algorithm off the preference here signs an
    // ML-DSA key with the RSA routine and every command below throws.
    // `at_activate` is its own process, and in one process the activation
    // client is still cached under `(atSign, enrollmentId)` holding the
    // `pqReady` axes — which `AtClientImpl.create` refuses to hand to a caller
    // naming different ones. That refusal is a real guard, so what this does
    // is what process exit does, rather than working around it.
    await service.atClient!.stop();
    AtClientImpl.atClientInstanceMap
        .remove(AtClientImpl.instanceKey(atSign, enrollmentId));

    final reader = AtOnboardingServiceImpl(
        atSign,
        // Named, not inherited, and identically in both arms. The reader's
        // preference is the FALLBACK for how this client authenticates, and
        // this comparison needs that fallback to be rsa2048: in the PQ arm so
        // that mldsa65 proves the keyfile won, and in the legacy arm so that
        // there is anything to contrast with. When it rode the SDK default it
        // did say rsa2048 — until the default moved to pqReady, at which point
        // the legacy arm's rig check went red and this arm quietly stopped
        // discriminating.
        AtOnboardingPreference(posture: PqPosture.legacy)
          ..rootDomain = 'vip.ve.atsign.zone'
          ..hiveStoragePath = 'test/storage/hive/$atSign-reader'
          ..commitLogPath = 'test/storage/hive/$atSign-reader/commit'
          ..namespace = 'wavi'
          ..atKeysFilePath = keysFilePath);
    expect(await reader.authenticate(), true);
    final client = reader.atClient!;
    expect(AtClientImpl.signingAlgoOf(client), SigningAlgoType.mldsa65,
        reason: 'the keyfile is the authority on how this enrollment '
            'authenticates; the preference above names rsa2048, so resolving '
            'mldsa65 can only have come from the key material');

    // --- 2. the key package is on the enrollment record --------------------
    // Never published, so `enroll:listns` is the only route to it — and it can
    // only have been set by the enroll:request that created the record.
    final listns = await client
        .getRemoteSecondary()!
        .executeCommand('enroll:listns:wavi\n', auth: true);
    final roster =
        jsonDecode(listns!.replaceFirst('data:', '').trim()) as List;
    final mine = roster
        .cast<Map<String, dynamic>>()
        .firstWhere((e) => e['enrollmentId'] == enrollmentId);
    expect((mine['metadata'] as Map?)?['keyPackage'], isNotNull,
        reason: 'without this the atSign is unrepairable: metadata.keyPackage '
            'is written once, by the request that created the enrollment');
    expect(
        mine['apkamPubKey'],
        keys
            .getKey(enrollmentId, 'auth:mldsa65:1',
                CryptographicMaterialRole.publicAuthentication)!
            .bytes
            .toString(),
        reason: 'the APKAM the atServer holds is the ML-DSA one, byte for '
            'byte');

    // --- 3. the signing root exists ----------------------------------------
    final root = await client
        .getRemoteSecondary()!
        .executeCommand('plookup:pq_signing_root$atSign\n', auth: true);
    expect(root, contains('mldsa65'),
        reason: 'the CLI mints the atSign-level signing root after activation, '
            'while it still holds the first enrollment — the one the atServer '
            'grants __manage, which is what entitles it to create the root');
    final rootJson =
        jsonDecode(root!.replaceFirst('data:', '').trim())
            as Map<String, dynamic>;
    // Not `.single`: the record is a list of signing keys precisely so a
    // successor can sit beside a retired predecessor, and a reader taking the
    // only element is what would stop that ever being adopted. One entry is
    // what a fresh activation has, and the assertion says so without
    // requiring it forever.
    final entries = rootJson['keys'] as List;
    expect(entries, hasLength(1),
        reason: 'a fresh activation mints exactly one root');
    expect((entries.first as Map)['alg'], 'mldsa65');

    // --- and legacy material is still cut and published, BY DEFAULT --------
    expect(keys.defaultEncryptionPublicKey, isNotNull);
    final publicKey = await client
        .getRemoteSecondary()!
        .executeCommand('plookup:publickey$atSign\n', auth: true);
    // By value: the virtualenv image ships every demo atSign with a
    // public:publickey already installed, so a presence check would pass on
    // provisioning state even if the activation had published nothing.
    expect(publicKey?.replaceFirst('data:', '').trim(),
        keys.defaultEncryptionPublicKey.toString(),
        reason: 'a legacy peer must still be able to reach this atSign, and '
            'the key it finds has to be the one this atSign holds the private '
            'half of');
  }, timeout: Timeout(Duration(minutes: 3)));

  test('a legacy activation is the rsa2048 arm of the same comparison',
      () async {
    // `@egbiometric🛠` is this test's alone. A CRAM activation is one-shot per
    // atSign per virtualenv, and every other demo atSign this package touches
    // is already spent by an `onboard()` or has its PKAM key installed by
    // hand — either makes an activation here fail.
    final legacyAtSign = AtUtils.fixAtSign('@egbiometric🛠');
    final legacyKeysFile = testKeysFile(legacyAtSign);
    for (final path in [legacyKeysFile, '$legacyKeysFile.bak']) {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    }

    // The only thing varied against the test above is the posture at
    // activation. Everything else — the reader's bare preference, the command
    // driven — is held identical, so a difference in outcome can only come
    // from the key material the activation minted.
    final activation = AtOnboardingPreference(posture: PqPosture.legacy)
      ..rootDomain = 'vip.ve.atsign.zone'
      ..hiveStoragePath = 'test/storage/hive/$legacyAtSign'
      ..commitLogPath = 'test/storage/hive/$legacyAtSign/commit'
      ..namespace = 'wavi'
      ..cramSecret = at_demos.cramKeyMap[legacyAtSign]
      ..atKeysFilePath = legacyKeysFile
      ..downloadPath = keysDir
      ..appName = 'wavi'
      ..deviceName = 'legacy-cli';
    expect(await AtOnboardingServiceImpl(legacyAtSign, activation).onboard(),
        true);

    final keys =
        await FileAtKeysIo(filePath: (_) => legacyKeysFile).read(legacyAtSign);
    expect(keys.apkamPublicKey, isNotNull,
        reason: 'a legacy activation keeps its APKAM in the flat fields, '
            'which is what makes it the rsa2048 arm');

    final reader = AtOnboardingServiceImpl(
        legacyAtSign,
        // Named, not inherited, and identically in both arms. The reader's
        // preference is the FALLBACK for how this client authenticates, and
        // this comparison needs that fallback to be rsa2048: in the PQ arm so
        // that mldsa65 proves the keyfile won, and in the legacy arm so that
        // there is anything to contrast with. When it rode the SDK default it
        // did say rsa2048 — until the default moved to pqReady, at which point
        // the legacy arm's rig check went red and this arm quietly stopped
        // discriminating.
        AtOnboardingPreference(posture: PqPosture.legacy)
          ..rootDomain = 'vip.ve.atsign.zone'
          ..hiveStoragePath = 'test/storage/hive/$legacyAtSign-reader'
          ..commitLogPath = 'test/storage/hive/$legacyAtSign-reader/commit'
          ..namespace = 'wavi'
          ..atKeysFilePath = legacyKeysFile);
    expect(await reader.authenticate(), true);
    final AtClient client = reader.atClient!;

    // The rig check the plan asks for: the two arms must actually differ, or
    // the comparison is of a case with itself.
    expect(AtClientImpl.signingAlgoOf(client), SigningAlgoType.rsa2048,
        reason: 'this arm has no typed material, so the preference fallback '
            'stands — and it must not be the mldsa65 the other arm resolves');

    // The same authenticated command as the PQ-native arm, so what is shown
    // is that each client follows its OWN key material under one identical
    // reader preference.
    final listns = await client
        .getRemoteSecondary()!
        .executeCommand('enroll:listns:wavi\n', auth: true);
    expect(listns, startsWith('data:'));
  }, timeout: Timeout(Duration(minutes: 3)));
}
