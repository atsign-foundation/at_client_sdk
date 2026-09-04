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
import 'utils/virtualenv_ports.dart';

/// A **legacy** atSign — one whose keyfile names no enrollment — gives itself
/// an enrollment of its own when its app names a post-quantum posture.
///
/// Such a client authenticates with a bare `pkam:`, naming no enrollment id.
/// The atServer answers that with the enrollment it calls `primary`: the
/// credential a legacy onboarding left at `privatekey:at_pkam_publickey` is
/// migrated into a real, approved, unexpiring enrollment holding `*:rw` and
/// `__manage:rw`, and the flat key is deleted. So the connection is not
/// unidentified — it carries `primary` — while the CLIENT still believes it
/// holds no enrollment, because nothing in its keyfile names one.
///
/// An `enroll:request` from that connection is therefore a retrofit of
/// `primary`: the atServer approves it outright, the successor carries
/// `primary`'s grants exactly, and its record names what it replaced in
/// `retrofitPredecessorEnrollmentId`. The client's own self-approval never
/// runs, because it fires only on a `pending` answer.
///
/// **Everything here is asserted against the atServer, over a connection this
/// file opens itself with the flat key.** The client's own `enrollmentId` is
/// its belief; `enroll:list` is what the atServer actually holds.
///
/// ⚠️ **One-shot, destructive server state.** CRAM authentication works once
/// per atSign per virtualenv, and the retrofit arm creates an enrollment that
/// cannot be un-created — an atSign that has run this holds a successor for
/// ever, and a successor may not itself be retrofitted. So `@barbara🛠` and `@jagan🛠` are this file's alone; both
/// were checked to be claimed by nothing else in the repo before they were
/// chosen, and borrowing an atSign another file uses would break that file
/// rather than this one.
void main() {
  AtSignLogger.root_level = 'WARNING';

  final String retrofits = AtUtils.fixAtSign('@barbara🛠');
  final String staysPut = AtUtils.fixAtSign('@jagan🛠');
  const rootDomain = 'vip.ve.atsign.zone';

  /// Leaves [atSign] in the state a legacy onboarding left behind: its
  /// encryption public key published, and one credential — the legacy PKAM
  /// keypair — reachable by a bare `pkam:` and by nothing else.
  ///
  /// The write below installs that credential. On a server in testing mode it
  /// does not land at `privatekey:at_pkam_publickey` at all: the value becomes
  /// `primary`'s, minted here if absent. So the roster holds exactly one
  /// record from this point on, before any client has authenticated.
  ///
  /// ⛔ Deliberately NOT `AtOnboardingServiceImpl.onboard()`, which sends
  /// `enroll:request` on the CRAM connection and so creates a SECOND, ordinary
  /// enrollment whose id the keyfile would carry. The state under test is a
  /// keyfile that names none, and using onboard would make this file assert
  /// the ordinary APKAM retrofit instead.
  Future<void> makeLegacyAtSign(String atSign) async {
    final atLookup = AtLookupImpl(atSign, rootDomain, virtualenvRootPort);
    await atLookup.cramAuthenticate(at_demos.cramKeyMap[atSign]!);
    expect(
        await atLookup.executeCommand(
            'update:privatekey:at_pkam_publickey '
            '${at_demos.pkamPublicKeyMap[atSign]}\n',
            auth: true),
        'data:-1',
        reason: 'without this credential the atSign cannot authenticate at '
            'all, and every assertion below would fail for that reason '
            'instead');
    await atLookup.executeCommand(
        'update:public:publickey$atSign '
        '${at_demos.encryptionPublicKeyMap[atSign]}\n',
        auth: true);
    await atLookup.close();
  }

  /// Every enrollment the atServer holds for [atSign], read over a bare
  /// `pkam:` connection — which the atServer admits as `primary`, and
  /// `primary` holds `__manage:rw`, so the answer is the whole roster rather
  /// than one record.
  ///
  /// Deliberately a connection this file opens rather than the client under
  /// test: the client's `enrollmentId` is its belief, and this is what the
  /// atServer holds.
  Future<Map<String, dynamic>> enrollmentsOf(String atSign) async {
    final atLookup = AtLookupImpl(atSign, rootDomain, virtualenvRootPort);
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
        ..rootPort = virtualenvRootPort
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
    await makeLegacyAtSign(retrofits);
    await makeLegacyAtSign(staysPut);
  });

  tearDownAll(() async {
    final storage = Directory('storage/');
    if (storage.existsSync()) storage.deleteSync(recursive: true);
  });

  test('a pre-enrollment atSign at a post-quantum posture gives itself its '
      'first enrollment', () async {
    // The precondition, established rather than assumed. The virtualenv
    // pre-provisions demo atSigns, so what this atSign's roster holds is a
    // claim that has to be read before anything runs.
    expect(await enrollmentsOf(retrofits), hasLength(1),
        reason: 'this file is about an atSign whose only credential is the '
            'legacy one the atServer keeps as `primary`; a second record here '
            'would mean the retrofit below is the ordinary APKAM path, which '
            'proves nothing new');
    expect((await enrollmentsOf(retrofits)).keys.single, startsWith('primary'),
        reason: 'and that one record is primary itself, not some other '
            'enrollment this fixture did not create');

    evictCachedAtClients();
    final client = await clientFor(retrofits, PqPosture.pqReady);

    expect(client.enrollmentId, isNotNull,
        reason: 'the client came up on an enrollment it created for itself; '
            'a null id here is the state commit 7 removes');

    // What the atServer holds, not what the client believes.
    final roster = await enrollmentsOf(retrofits);
    expect(roster, hasLength(2),
        reason: 'the retrofit ADDS a successor and leaves its predecessor '
            'standing: primary is a root, so nothing caps or removes it, and '
            'a sibling clone of this keyfile must still be able to '
            'authenticate');
    final key = roster.keys.singleWhere(
        (k) => k.startsWith(client.enrollmentId!),
        orElse: () => fail('the roster names no record for '
            '${client.enrollmentId}; it holds ${roster.keys}'));
    final record = roster[key] as Map<String, dynamic>;
    expect(record['approval']['state'], 'approved',
        reason: 'an enroll:request on a legacy connection is a retrofit of '
            'primary, which the atServer approves outright — so the client '
            'never reaches its own self-approval, which fires only on pending');
    expect(record['retrofitPredecessorEnrollmentId'], 'primary',
        reason: 'the successor records what it replaced, which is what lets '
            'tooling find a whole sibling set later');
    expect(record['namespaces'], {'*': 'rw', '__manage': 'rw'},
        reason: 'a retrofit carries its predecessor\'s grants exactly, and '
            'primary holds these two; the atServer refuses any other set');
    expect(record['deviceName'], startsWith('firstDevice-'),
        reason: 'NOT the bare constant: sibling clones of one pre-enrollment '
            'keyfile would then all name the same (app, device) and the '
            'atServer refuses every one after the first');
    expect(roster.keys.where((k) => k.startsWith(client.enrollmentId!)),
        hasLength(1),
        reason: 'the enrollment the client authenticates as is one the '
            'atServer holds, not a second one it left behind');

    // The legacy credential SURVIVES its own retrofit. A retrofit caps its
    // predecessor only when the predecessor is not a root, and primary is one,
    // so nothing expires it. Retiring it stays the owner's explicit act.
    final legacy = AtLookupImpl(retrofits, rootDomain, virtualenvRootPort);
    expect(
        await legacy.authenticate(at_demos.pkamPrivateKeyMap[retrofits]), true,
        reason: 'a retrofit that silently invalidated the legacy credential '
            'would lock out every sibling clone of the keyfile that has not '
            'upgraded, with no CRAM secret left to recover with');
    await legacy.close();
  }, timeout: Timeout(Duration(minutes: 4)));

  /// The control, and it can go red while every assertion above stays green:
  /// the same fixture, the same shape of atSign, only the posture differs.
  test('the same atSign shape at a legacy posture does not', () async {
    expect(await enrollmentsOf(staysPut), hasLength(1));

    evictCachedAtClients();
    final client = await clientFor(staysPut, PqPosture.legacy);

    expect(client.enrollmentId, isNull,
        reason: 'legacy means "do not drive an upgrade", so this client keeps '
            'authenticating with the atSign\'s own keys');
    expect(await enrollmentsOf(staysPut), hasLength(1),
        reason: 'and it leaves nothing behind on the atServer — primary alone '
            'is what this fixture created, so a SECOND record here would mean '
            'the posture gate is not what decides');
  }, timeout: Timeout(Duration(minutes: 4)));
}
