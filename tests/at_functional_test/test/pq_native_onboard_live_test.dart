// The substrate is deliberately marked @experimental and will be reshaped as
// the group surface matures. Exercising it from another package is the point
// of this file.
// ignore_for_file: experimental_member_use

import 'dart:convert';
import 'dart:io';

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_demo_data/at_demo_data.dart';
import 'package:at_functional_test/src/config_util.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

/// UC-A1.1 — a first-enrollment CRAM onboard is PQ-native (project ON-1).
///
/// Drives [pqNativeOnboard] against a live atServer and asserts the four
/// things the catalogue asks for: the APKAM is ML-DSA and actually
/// authenticates, the signing root is created and mutable, the first
/// enrollment's key package is registered on its record, and legacy material
/// is still cut and published by default.
///
/// One-shot server state: CRAM activation works once per atSign per
/// virtualenv, so this test clears its own keyfile and must run against a
/// recycled container.
///
/// It uses `apkamThirdAtSign`, which exists only because this test needs it:
/// `apkamFirstAtSign` and `apkamSecondAtSign` are both already spent by
/// `enrollment_test.dart`, and two tests sharing one CRAM secret means
/// whichever runs second fails — passing alone and failing in the suite.
void main() {
  final atSign = ConfigUtil.getYaml()['atSign']['apkamThirdAtSign'] as String;
  final cramSecret = cramKeyMap[atSign]!;
  final rootDomain = AtRootDomain('vip.ve.atsign.zone', TestUtils.rootServerPort);
  final namespace = ConfigUtil.getYaml()['namespace'] as String? ?? 'wavi';

  String keysFilePath(String a) => 'test/testData/$a.atKeys';

  setUp(() {
    // AtAuth.onboard refuses if a keyfile already exists, and the runner only
    // clears @srie's. Without this the test passes in isolation and fails in
    // the full suite on a leftover file.
    final existing = File(keysFilePath(atSign));
    if (existing.existsSync()) existing.deleteSync();
  });

  test('UC-A1.1 · a CRAM activation is PQ-native, and still legacy-reachable',
      () async {
    final keysIo = FileAtKeysIo(filePath: keysFilePath);
    final preference = TestUtils.getPreference(atSign)
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
    );
    final client = manager.atClient;
    final enrollmentId = client.enrollmentId;
    expect(enrollmentId, isNotNull);

    // --- the APKAM is ML-DSA, and it is what authenticates -----------------
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

    // A fresh connection, authenticating from the keyfile alone. This is the
    // assertion that matters: the atServer verified an ML-DSA PKAM signature
    // against the enrollment record it created at activation.
    final reauth = await AtAuth.create().authenticate(
        AtAuthRequest(atSign, atKeysIo: keysIo)
          ..enrollmentId = enrollmentId
          ..rootDomain = rootDomain);
    expect(reauth.isSuccessful, true,
        reason: 'no RSA APKAM exists anywhere, so this can only have '
            'succeeded by ML-DSA');

    // --- the signing root exists, and is mutable ---------------------------
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
    // Not `.single`: the record is a list of signing keys precisely so a
    // successor can sit beside a retired predecessor, and a reader that takes
    // the only element is what would stop that ever being adopted. One entry
    // is what a freshly onboarded atSign has, and the assertion says so
    // without requiring it forever.
    expect(entries, hasLength(1),
        reason: 'a fresh onboard mints exactly one root');
    expect((entries.first as Map)['alg'], 'mldsa65');

    // Mutable, read off the metadata rather than attempted by writing: a
    // second write would LAND and replace this atSign's root. What stops two
    // privileged enrollments each minting one is `_rootlock@<atSign>`, whose
    // refusal `pq_signing_root_mint_lock_test.dart` watches the atServer
    // issue.
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

    // --- the key package is on the enrollment record, not published --------
    // The first enrollment holds __manage, whose grant carries `*: rw`, so it
    // is listed for any namespace. listns is the only route to a key package:
    // it is never published, which is the property that keeps an enrollment's
    // encapsulation target discoverable only to the atSign's own enrollments.
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
    // The APKAM the atServer holds is the ML-DSA one, byte for byte.
    expect(mine['apkamPubKey'],
        keys.getKey(enrollmentId, 'auth:mldsa65:1',
                CryptographicMaterialRole.publicAuthentication)!.bytes.toString());

    // --- legacy material is cut and published, BY DEFAULT ------------------
    expect(keys.defaultEncryptionPublicKey, isNotNull);
    expect(keys.defaultSelfEncryptionKey, isNotNull,
        reason: 'the PQ data path never touches it, but decisions 37 keeps it '
            'until the ECOSYSTEM is PQ');
    final publicKey = await client
        .getRemoteSecondary()!
        .executeCommand('plookup:publickey$atSign\n', auth: true);
    // By VALUE, not by presence. The virtualenv image ships every demo atSign
    // with a `public:publickey` already installed — an untouched `@denise` has
    // one — so `startsWith('data:')` passes on provisioning state even if the
    // activation published nothing. Only equality with the key just minted
    // shows the activation wrote it.
    expect(publicKey?.replaceFirst('data:', '').trim(),
        keys.defaultEncryptionPublicKey.toString(),
        reason: 'UC-B4.2: a legacy peer must be able to send to a brand-new '
            'atSign out of the box, and the key it finds has to be the one '
            'this atSign holds the private half of');
  }, timeout: Timeout(Duration(minutes: 3)));
}
