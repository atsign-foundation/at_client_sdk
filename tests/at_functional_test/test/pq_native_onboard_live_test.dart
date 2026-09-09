// The substrate is marked @experimental; exercising it from another package is
// the point of this file.
// ignore_for_file: experimental_member_use

@Tags(['pq'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:at_auth/at_auth.dart';
import 'package:at_auth/at_auth_io.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_demo_data/at_demo_data.dart';
import 'package:at_functional_test/src/config_util.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

/// UC-A1.1 — a first-enrollment CRAM onboard is PQ-native.
///
/// CRAM activation is one-shot server state: it works once per atSign per
/// virtualenv, so this test clears its own keyfile, must run against a
/// recycled container, and needs an atSign no other test spends.
void main() {
  TestUtils.isolateStorage('pq_native_onboard_live_test');
  final atSign = ConfigUtil.getYaml()['atSign']['apkamThirdAtSign'] as String;
  final cramSecret = cramKeyMap[atSign]!;
  final rootDomain = AtRootDomain('vip.ve.atsign.zone', TestUtils.rootServerPort);
  final namespace = ConfigUtil.getYaml()['namespace'] as String? ?? 'wavi';

  String keysFilePath(String a) => 'test/testData/$a.atKeys';

  setUp(() {
    // NOTE: AtAuth.onboard refuses if a keyfile already exists, and the runner
    // clears only @srie's.
    final existing = File(keysFilePath(atSign));
    if (existing.existsSync()) existing.deleteSync();
  });

  test('UC-A1.1 · a CRAM activation is PQ-native, and still legacy-reachable',
      () async {
    final keysIo = FileAtKeysIo(filePath: keysFilePath);
    final preference = TestUtils.getPreference(atSign,
        posture: PqPosture.legacy)
      ..rootDomain = rootDomain.rootDomain
      ..rootPort = rootDomain.rootPort
      ..namespace = namespace;

    final manager = await pqNativeOnboard(
      atSign: atSign,
      cramSecret: cramSecret,
      preference: preference,
      atKeysIo: keysIo,
      appName: 'wavi',
      deviceName: 'pq-onboard',
      storage: TestUtils.storageFor(atSign),
    );
    final client = manager.atClient;
    final enrollmentId = client.enrollmentId;
    expect(enrollmentId, isNotNull);

    final keys = await keysIo.read(atSign);
    expect(keys.apkamPublicKey, isNull,
        reason: 'a PQ-native keyfile keeps its APKAM in the typed section; a '
            'reader that cannot handle that must fail loudly rather than sign '
            'an ML-DSA key with the RSA routine');
    expect(keys.signingAlgorithmForEnrollment(enrollmentId!),
        SigningAlgoType.mldsa65);
    expect(
        base64Decode(keys
                .getKey(enrollmentId, 'auth:mldsa65:1',
                    CryptographicMaterialRole.publicAuthentication)!
                .bytes
                .toString())
            .length,
        1952);

    final reauth = await AtAuth.create()
        .authenticate(AtAuthRequest(atSign, atKeysIo: keysIo)
          ..rootDomain = rootDomain);
    expect(reauth.isSuccessful, true,
        reason: 'no RSA APKAM exists anywhere, so this can only have '
            'succeeded by ML-DSA');
    expect(reauth.session!.enrollmentId, enrollmentId,
        reason: 'the keyfile alone names the enrollment: nothing passed an id');

    final rootValue = await client.getRemoteSecondary()!.executeCommand(
        'plookup:pq_signing_root$atSign\n',
        auth: true);
    expect(rootValue, contains('mldsa65'));
    final rootJson = jsonDecode(
            rootValue!.replaceFirst('data:', '').trim())
        as Map<String, dynamic>;
    expect(rootJson['v'], 1);
    expect(rootJson.containsKey('successor'), isFalse,
        reason: 'decisions 101 deleted the field. Asserted as ABSENT rather '
            'than null, which a missing key satisfies for free');
    final entries = rootJson['keys'] as List;
    // NOTE: not `.single` — the record is a list of signing keys so a
    // successor can sit beside a retired predecessor.
    expect(entries, hasLength(1),
        reason: 'a fresh onboard mints exactly one root');
    expect((entries.first as Map)['alg'], 'mldsa65');

    // NOTE: mutability is read off the metadata, never probed by writing — a
    // second write would land and replace this atSign's root.
    final rootMeta = await client.getRemoteSecondary()!.executeCommand(
        'llookup:meta:public:pq_signing_root$atSign\n',
        auth: true);
    expect(
        (jsonDecode(rootMeta!.replaceFirst('data:', '').trim())
            as Map<String, dynamic>)['immutable'],
        isNot(true),
        reason: 'the atServer makes immutability sticky, so a root created '
            'with the flag could never advertise a successor — rotation would '
            'be unimplementable on every atSign onboarded by this build');

    // listns is the only route to a key package: it is never published, which
    // keeps an enrollment's encapsulation target discoverable only to the
    // atSign's own enrollments.
    final listns = await client
        .getRemoteSecondary()!
        .executeCommand('enroll:listns:$namespace\n', auth: true);
    final roster =
        jsonDecode(listns!.replaceFirst('data:', '').trim()) as List;
    final mine = roster
        .cast<Map<String, dynamic>>()
        .firstWhere((e) => e['enrollmentId'] == enrollmentId);
    expect((mine['metadata'] as Map?)?['keyPackage'], isNotNull,
        reason: 'metadata.keyPackage is written by the enroll:request that '
            'creates the record and never again, so if activation did not put '
            'it there nothing ever can');
    expect(mine['apkamPubKey'],
        keys.getKey(enrollmentId, 'auth:mldsa65:1',
                CryptographicMaterialRole.publicAuthentication)!.bytes.toString());

    expect(keys.defaultEncryptionPublicKey, isNotNull);
    expect(keys.defaultSelfEncryptionKey, isNotNull,
        reason: 'the PQ data path never touches it, but decisions 37 keeps it '
            'until the ECOSYSTEM is PQ');
    final publicKey = await client
        .getRemoteSecondary()!
        .executeCommand('plookup:publickey$atSign\n', auth: true);
    // NOTE: by value, not by presence — the virtualenv ships every demo atSign
    // with a `public:publickey`, so a presence check passes on provisioning
    // state even if the activation published nothing.
    expect(publicKey?.replaceFirst('data:', '').trim(),
        keys.defaultEncryptionPublicKey.toString(),
        reason: 'UC-B4.2: a legacy peer must be able to send to a brand-new '
            'atSign out of the box, and the key it finds has to be the one '
            'this atSign holds the private half of');
  }, timeout: Timeout(Duration(minutes: 3)));
}
