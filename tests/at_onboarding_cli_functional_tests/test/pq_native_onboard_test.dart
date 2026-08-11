import 'dart:convert';
import 'dart:io';

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart';
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
/// One-shot server state: CRAM activation works once per atSign per virtualenv.
/// `@denise` is this file's alone — every other atSign in this package is
/// already spent by an `onboard()` or has its PKAM key installed by hand for
/// the authenticate tests, and either makes an activation here fail.
void main() {
  AtSignLogger.root_level = 'WARNING';

  final String atSign = AtUtils.fixAtSign('@denise');
  final String keysDir = testKeysDir;
  final String keysFilePath = testKeysFile(atSign);

  AtOnboardingPreference preference() => AtOnboardingPreference()
    ..rootDomain = 'vip.ve.atsign.zone'
    ..hiveStoragePath = 'test/storage/hive/$atSign'
    ..commitLogPath = 'test/storage/hive/$atSign/commit'
    ..namespace = 'wavi'
    ..cramSecret = at_demos.cramKeyMap[atSign]
    ..atKeysFilePath = keysFilePath
    ..downloadPath = keysDir
    ..appName = 'wavi'
    ..deviceName = 'pq-cli'
    // The one line an app adds to become post-quantum.
    ..signingAlgoType = SigningAlgoType.mldsa65;

  setUp(() {
    // AtAuth.onboard refuses if a keyfile already exists, so a leftover from an
    // earlier run would make this pass in isolation and fail in the suite.
    for (final path in [keysFilePath, '$keysFilePath.bak']) {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    }
  });

  test('a CLI activation with signingAlgoType mldsa65 is PQ-native', () async {
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
    expect(await AtOnboardingServiceImpl(atSign, preference()).authenticate(),
        true);

    // --- 2. the key package is on the enrollment record --------------------
    // Never published, so `enroll:listns` is the only route to it — and it can
    // only have been set by the enroll:request that created the record.
    final client = service.atClient!;
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
            .getKey('apkam:$enrollmentId:1',
                CryptographicKeyType.publicAuthentication)!
            .bytes
            .toString(),
        reason: 'the APKAM the atServer holds is the ML-DSA one, byte for '
            'byte');

    // --- 3. the signing root exists ----------------------------------------
    final root = await client
        .getRemoteSecondary()!
        .executeCommand('plookup:pq_signing_root$atSign\n', auth: true);
    expect(root, contains('ml-dsa-65'),
        reason: 'the CLI mints the atSign-level signing root after activation, '
            'while it still holds the first enrollment — the one the atServer '
            'grants __manage, which is what entitles it to create the root');
    final rootJson =
        jsonDecode(root!.replaceFirst('data:', '').trim())
            as Map<String, dynamic>;
    expect((rootJson['keys'] as List).single['alg'], 'ml-dsa-65');

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
}
