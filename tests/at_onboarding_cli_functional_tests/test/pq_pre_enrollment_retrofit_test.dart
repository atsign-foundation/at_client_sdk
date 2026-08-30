import 'dart:convert';
import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_demo_data/at_demo_data.dart' as at_demos;
import 'package:at_lookup/at_lookup.dart';
import 'package:at_onboarding_cli/at_onboarding_cli.dart';
import 'package:at_utils/at_utils.dart';
import 'package:test/test.dart';

import 'utils/at_client_cache.dart';
import 'utils/test_keys_dir.dart';

/// A **pre-enrollment** atSign — one onboarded before enrollments existed —
/// gives itself its first enrollment when its app names a post-quantum
/// posture.
///
/// Such an atSign authenticates with the flat `at_pkam_publickey`, so the
/// atServer marks the connection `pkamLegacy` and leaves its enrollment id
/// null. Its self-enrolment auto-approve branch is gated on an
/// APKAM-authenticated connection and is therefore out of reach, and the
/// request lands `pending`. What makes this work anyway is that the atServer
/// grants a connection carrying no enrollment id full access, so the client
/// approves its own request over the same connection.
///
/// **Everything here is asserted against the atServer, over a connection this
/// file opens itself with the flat key.** The client's own `enrollmentId` is
/// its belief; `enroll:list` is what the atServer actually holds.
///
/// ⚠️ **One-shot, destructive server state.** CRAM authentication works once
/// per atSign per virtualenv, and the retrofit arm creates an enrollment that
/// cannot be un-created — an atSign that has run this is no longer
/// pre-enrollment. So `@barbara🛠` and `@jagan🛠` are this file's alone; both
/// were checked to be claimed by nothing else in the repo before they were
/// chosen, and borrowing an atSign another file uses would break that file
/// rather than this one.
void main() {
  AtSignLogger.root_level = 'WARNING';

  final String retrofits = AtUtils.fixAtSign('@barbara🛠');
  final String staysPut = AtUtils.fixAtSign('@jagan🛠');
  const rootDomain = 'vip.ve.atsign.zone';

  /// Leaves [atSign] in the state a legacy onboarding left behind: a flat
  /// `at_pkam_publickey` on the atServer, its encryption public key published,
  /// and **no enrollment at all**.
  ///
  /// ⛔ Deliberately NOT `AtOnboardingServiceImpl.onboard()`, which sends
  /// `enroll:request` on the CRAM connection and so creates a first
  /// enrollment — the very thing whose absence defines the state under test.
  /// Using it would make this file assert the retrofit of an atSign that was
  /// never pre-enrollment.
  Future<void> makePreEnrollment(String atSign) async {
    final atLookup = AtLookupImpl(atSign, rootDomain, 64);
    await atLookup.cramAuthenticate(at_demos.cramKeyMap[atSign]!);
    expect(
        await atLookup.executeCommand(
            'update:privatekey:at_pkam_publickey '
            '${at_demos.pkamPublicKeyMap[atSign]}\n',
            auth: true),
        'data:-1',
        reason: 'without the flat key this atSign cannot authenticate at all, '
            'and every assertion below would fail for that reason instead');
    await atLookup.executeCommand(
        'update:public:publickey$atSign '
        '${at_demos.encryptionPublicKeyMap[atSign]}\n',
        auth: true);
    await atLookup.close();
  }

  /// Every enrollment the atServer holds for [atSign], read over a connection
  /// authenticated with the FLAT key — so it is answerable before any
  /// enrollment exists, which the client under test is not.
  Future<Map<String, dynamic>> enrollmentsOf(String atSign) async {
    final atLookup = AtLookupImpl(atSign, rootDomain, 64);
    expect(await atLookup.authenticate(at_demos.pkamPrivateKeyMap[atSign]),
        true,
        reason: 'the flat credential must authenticate, or this reader is '
            'measuring its own failure rather than the roster');
    final response = await atLookup.executeCommand('enroll:list\n', auth: true);
    await atLookup.close();
    return jsonDecode(response!.replaceFirst('data:', ''))
        as Map<String, dynamic>;
  }

  AtOnboardingPreference preferenceFor(String atSign, PqPosture posture) =>
      AtOnboardingPreference(posture: posture)
        ..rootDomain = rootDomain
        ..isLocalStoreRequired = true
        ..hiveStoragePath = 'storage/hive/$atSign'
        ..commitLogPath = 'storage/hive/$atSign/commit'
        ..atKeysFilePath = testKeysFile(atSign)
        ..downloadPath = testKeysDir
        ..appName = 'wavi'
        ..deviceName = 'pixel';

  /// The `.atKeys` a legacy onboarding would have written: the flat PKAM
  /// keypair, the encryption keypair and the self-encryption key, and no
  /// enrollment id anywhere.
  Future<void> writeLegacyKeyfile(String atSign) async {
    final aes = at_demos.aesKeyMap[atSign]!;
    final map = <String, String?>{
      AuthKeyType.pkamPublicKey:
          EncryptionUtil.encryptValue(at_demos.pkamPublicKeyMap[atSign]!, aes),
      AuthKeyType.pkamPrivateKey:
          EncryptionUtil.encryptValue(at_demos.pkamPrivateKeyMap[atSign]!, aes),
      AuthKeyType.encryptionPublicKey: EncryptionUtil.encryptValue(
          at_demos.encryptionPublicKeyMap[atSign]!, aes),
      AuthKeyType.encryptionPrivateKey: EncryptionUtil.encryptValue(
          at_demos.encryptionPrivateKeyMap[atSign]!, aes),
      AuthKeyType.selfEncryptionKey: aes,
      atSign: aes,
    };
    final file = File(testKeysFile(atSign));
    if (!file.existsSync()) await file.create(recursive: true);
    await file.writeAsString(jsonEncode(map));
  }

  Future<AtClient> clientFor(String atSign, PqPosture posture) async {
    await writeLegacyKeyfile(atSign);
    final service =
        AtOnboardingServiceImpl(atSign, preferenceFor(atSign, posture));
    expect(await service.authenticate(), true,
        reason: 'authentication is with the FLAT key; a failure here is the '
            'fixture, not the behaviour under test');
    final client = await service.atClient;
    return client!;
  }

  setUpAll(() async {
    await makePreEnrollment(retrofits);
    await makePreEnrollment(staysPut);
  });

  tearDownAll(() async {
    final storage = Directory('storage/');
    if (storage.existsSync()) storage.deleteSync(recursive: true);
  });

  test('a pre-enrollment atSign at a post-quantum posture gives itself its '
      'first enrollment', () async {
    // The precondition, established rather than assumed. The virtualenv
    // pre-provisions demo atSigns, so "it has no enrollment" is a claim about
    // this atSign that has to be read before anything runs.
    expect(await enrollmentsOf(retrofits), isEmpty,
        reason: 'this file is about an atSign that holds NO enrollment; with '
            'one already present the retrofit below would be the ordinary '
            'APKAM path and would prove nothing new');

    evictCachedAtClients();
    final client = await clientFor(retrofits, PqPosture.pqReady);

    expect(client.enrollmentId, isNotNull,
        reason: 'the client came up on an enrollment it created for itself; '
            'a null id here is the state commit 7 removes');

    // What the atServer holds, not what the client believes.
    final roster = await enrollmentsOf(retrofits);
    expect(roster, hasLength(1));
    final record = roster.values.single as Map<String, dynamic>;
    expect(record['approval']['state'], 'approved',
        reason: 'the atServer parks such a request PENDING — its auto-approve '
            'branch needs an APKAM connection — so approved means the client '
            'approved its own request over the same connection');
    expect(record['namespaces'], {'*': 'rw', '__manage': 'rw'},
        reason: 'the connection that asked was unscoped, so there was nothing '
            'narrower to bound the first enrollment by');
    expect(record['deviceName'], startsWith('firstDevice-'),
        reason: 'NOT the bare constant: sibling clones of one pre-enrollment '
            'keyfile would then all name the same (app, device) and the '
            'atServer refuses every one after the first');
    expect(roster.keys.single, startsWith(client.enrollmentId!),
        reason: 'the enrollment the client authenticates as is the one the '
            'atServer holds, not a second one it left behind');

    // The legacy root credential SURVIVES its own retrofit. The atServer caps
    // a parent ENROLLMENT on a retrofit and there is no parent here — and it
    // never touches the flat key on any path. Retiring it stays the owner's
    // explicit act.
    final flat = AtLookupImpl(retrofits, rootDomain, 64);
    expect(await flat.authenticate(at_demos.pkamPrivateKeyMap[retrofits]), true,
        reason: 'a retrofit that silently invalidated the flat key would lock '
            'out every sibling clone of the keyfile that has not upgraded, '
            'with no CRAM secret left to recover with');
    await flat.close();
  }, timeout: Timeout(Duration(minutes: 4)));

  /// The control, and it can go red while every assertion above stays green:
  /// the same fixture, the same shape of atSign, only the posture differs.
  test('the same atSign shape at a legacy posture does not', () async {
    expect(await enrollmentsOf(staysPut), isEmpty);

    evictCachedAtClients();
    final client = await clientFor(staysPut, PqPosture.legacy);

    expect(client.enrollmentId, isNull,
        reason: 'legacy means "do not drive an upgrade", so this client keeps '
            'authenticating with the atSign\'s own keys');
    expect(await enrollmentsOf(staysPut), isEmpty,
        reason: 'and it leaves nothing behind on the atServer — an enrollment '
            'here would mean the posture gate is not what decides');
  }, timeout: Timeout(Duration(minutes: 4)));
}
