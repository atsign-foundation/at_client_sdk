import 'dart:convert';
import 'dart:io';

import 'package:at_auth/at_auth.dart';
import 'package:at_auth/at_auth_io.dart';
import 'package:at_client/at_client.dart';
import 'package:at_demo_data/at_demo_data.dart' as at_demos;
import 'package:at_lookup/at_lookup.dart';
import 'package:at_onboarding_cli/at_onboarding_cli.dart';
import 'package:at_onboarding_cli/src/cli/auth_cli.dart' as auth_cli;
import 'package:at_server_status/at_server_status.dart';
import 'package:at_utils/at_utils.dart';
import 'package:test/test.dart';

import 'utils/at_client_cache.dart';
import 'utils/test_keys_dir.dart';
import 'utils/virtualenv_ports.dart';

/// Where at_onboarding_cli falls back to when `atKeysFilePath` is null; only
/// ever compared against, never written to.
final String defaultAtKeysDir = '${Platform.environment['HOME']}/.atsign/keys';
Map<String, bool> keysCreatedMap = {};

void main() {
  AtSignLogger.root_level = 'WARNING';

  // These group of tests run on docker container with only cram key available on secondary
  // Perform cram auth and update keys manually.
  Future<void> _createKeys(String atSign) async {
    if (keysCreatedMap.containsKey(atSign)) {
      return;
    }
    var atLookup =
        AtLookupImpl(atSign, 'vip.ve.atsign.zone', virtualenvRootPort);
    await atLookup.cramAuthenticate(at_demos.cramKeyMap[atSign]!);
    var command =
        'update:privatekey:at_pkam_publickey ${at_demos.pkamPublicKeyMap[atSign]}\n';
    var response = await atLookup.executeCommand(command, auth: true);
    expect(response, 'data:-1');
    command =
        'update:public:publickey${atSign} ${at_demos.encryptionPublicKeyMap[atSign]}\n';
    await atLookup.executeCommand(command, auth: true);
    keysCreatedMap[atSign] = true;
    await atLookup.close();
  }

  // NOTE: every test in this group and the next drives a pre-enrollment atSign
  // — `_createKeys` installs the flat `at_pkam_publickey` and nothing else —
  // so each names `PqPosture.legacy`. At a post-quantum posture the client
  // gives such an atSign its first enrollment on its first start, rewriting
  // the keyfile and replacing the PKAM key these tests read back. Name it on
  // every call: one atSign in one process holds one posture, so a client
  // cached at another posture is refused rather than reused.
  group('A group of tests to assert on authenticate functionality', () {
    test('A test to verify authentication is successful with .atKeys file',
        () async {
      String atSign = '@alice🛠';
      await _createKeys(atSign);
      AtOnboardingPreference preference =
          getPreferences(atSign, posture: PqPosture.legacy);
      await generateAtKeysFile(atSign, preference.atKeysFilePath!);
      AtOnboardingService atOnboardingService =
          AtOnboardingServiceImpl(atSign, preference);
      bool status = await atOnboardingService.authenticate();
      expect(true, status);
    });

    test(
        'A test to verify update and llookup verbs with authenticated atLookup instance',
        () async {
      String atSign = '@alice🛠';
      await _createKeys(atSign);
      AtOnboardingPreference preference =
          getPreferences(atSign, posture: PqPosture.legacy);
      await generateAtKeysFile(atSign, preference.atKeysFilePath!);
      AtOnboardingService atOnboardingService =
          AtOnboardingServiceImpl(atSign, preference);
      await atOnboardingService.authenticate();
      AtLookUp? atLookUp =
          atOnboardingService.atClient?.getRemoteSecondary()?.atLookUp;
      AtKey key = AtKey();
      key.key = 'testKey1';
      await atLookUp?.update(key.key, 'value1');
      String? response = await atLookUp?.llookup(key.key);
      expect('data:value1', response);
    });

    test(
        'A test to authenticate and atSign and invoke AtClient put and get methods',
        () async {
      String atSign = '@eve🛠';
      await _createKeys(atSign);
      AtOnboardingPreference preference =
          getPreferences(atSign, posture: PqPosture.legacy);
      await generateAtKeysFile(atSign, preference.atKeysFilePath!);
      AtOnboardingService onboardingService =
          AtOnboardingServiceImpl(atSign, preference);
      await onboardingService.authenticate();
      AtClient? atClient = await onboardingService.atClient;
      AtKey key = AtKey();
      key.key = 'testKey3';
      key.namespace = 'wavi';
      await atClient?.put(key, 'value3');
      AtValue? response = await atClient?.get(key);
      expect('value3', response?.value);
    });

    test('A test to verify atKeysFilePath is set when null is provided',
        () async {
      String atSign = '@eve🛠';
      AtOnboardingPreference preference =
          getPreferences(atSign, posture: PqPosture.legacy);
      preference.atKeysFilePath = null;
      AtOnboardingServiceImpl(atSign, preference);
      expect(
          preference.atKeysFilePath, '$defaultAtKeysDir/${atSign}_key.atKeys');
    });

    tearDown(() async {
      await tearDownFunc();
    });
  });

  group('A group of tests to assert the client answers the keyfile\'s keys',
      () {
    String atSign = '@eve🛠'.trim();
    AtOnboardingPreference atOnboardingPreference =
        getPreferences(atSign, posture: PqPosture.legacy);
    AtOnboardingService atOnboardingService =
        AtOnboardingServiceImpl(atSign, atOnboardingPreference);
    AtClient? atClient;

    test(
        'A test to authenticate atSign and verify the PKAM keys and encryption keys the client answers are the keyfile\'s',
        () async {
      await generateAtKeysFile(atSign, atOnboardingPreference.atKeysFilePath!);
      await _createKeys(atSign);
      bool status = await atOnboardingService.authenticate();
      atClient = await atOnboardingService.atClient;
      expect(true, status);

      expect(at_demos.pkamPrivateKeyMap[atSign],
          await atClient?.getLocalSecondary()?.getPkamPrivateKey());

      expect(at_demos.pkamPublicKeyMap[atSign],
          await atClient?.getLocalSecondary()?.getPkamPublicKey());

      expect(at_demos.encryptionPrivateKeyMap[atSign],
          await atClient?.getLocalSecondary()?.getEncryptionPrivateKey());

      String? encryptionPublicKey =
          await atClient?.getLocalSecondary()?.getEncryptionPublicKey(atSign);
      expect(at_demos.encryptionPublicKeyMap[atSign], encryptionPublicKey);
    });

    tearDown(() async {
      await tearDownFunc();
    });
  });

  group('A group of tests to verify activation', () {
    test('Activate and verify failure modes', () async {
      String atSign = '@egcovidlab🛠';
      AtOnboardingPreference atOnboardingPreference = getPreferences(atSign);
      File atKeysFile = File(atOnboardingPreference.atKeysFilePath!);

      Future<bool> activated() async =>
          (await AtStatusImpl(
                      rootUrl: atOnboardingPreference.rootDomain,
                      rootPort: atOnboardingPreference.rootPort)
                  .get(atSign))
              .status() ==
          AtSignStatus.activated;

      // The protocol half alone: the keys are minted and filed, and the CRAM
      // secret is left on the atServer, so the atDirectory does not yet
      // report the atSign activated.
      await activateAtSign(
          atSign: atSign,
          cramSecret: atOnboardingPreference.cramSecret!,
          keys: FileAtKeysIo(
              filePath: (_) => atOnboardingPreference.atKeysFilePath!),
          signingAlgo: atOnboardingPreference.authenticationKeyAlgorithm,
          rootDomain: AtRootDomain(atOnboardingPreference.rootDomain,
              atOnboardingPreference.rootPort),
          completeActivation: false);
      expect(await activated(), false);
      expect(await atKeysFile.exists(), true);
      await atKeysFile.delete();

      // The whole activation, as `at_activate onboard` runs it.
      await auth_cli.activate(atSign, atOnboardingPreference);
      expect(await activated(), true);
      expect(await atKeysFile.exists(), true);
      await atKeysFile.delete();

      // Again: refused before anything is minted.
      await expectLater(
          auth_cli.activate(atSign, atOnboardingPreference),
          throwsA(predicate((dynamic e) =>
              e is AtActivateException &&
              e.message == 'atsign $atSign is already activated')));

      // With a keyfile in place: refused as an overwrite.
      await atKeysFile.create(recursive: true);
      await expectLater(auth_cli.activate(atSign, atOnboardingPreference),
          throwsA(predicate((dynamic e) => e is AtException)));
    });

    tearDown(() async {
      await tearDownFunc();
    });
  });

  // This test exiting with status 0 is skipping the rest of the functional tests
  // Skipping this test until the issue can be resolved
  group('A group of tests to verify activate_cli', () {
    String atSign = '@murali🛠';
    AtOnboardingPreference onboardingPreference = getPreferences(atSign);
    AtOnboardingService onboardingService =
        AtOnboardingServiceImpl(atSign, onboardingPreference);
    test(
        'A test to verify atSign is activated and .atKeys file is generated using activate_cli',
        () async {
      List<String> args = [
        // The CLI infers no command from the options; it must be named.
        'onboard',
        '-a',
        atSign,
        '-c',
        at_demos.cramKeyMap[atSign]!,
        '-r',
        'vip.ve.atsign.zone',
        // Without -k the CLI writes the generated keyfile to the home
        // directory's real keys dir.
        '-k',
        onboardingPreference.atKeysFilePath!,
      ];
      // perform activation of atSign
      await runCliCommand(args);

      /// ToDo: test should NOT exit with status 0 after activation is complete
      /// Exiting with status 0 is ideal behaviour, but for the sake of the test we need to be
      /// able to run the following assertions.

      // Authenticate atSign with the .atKeys file generated via the activate_cli tool
      expect(await File(onboardingPreference.atKeysFilePath!).exists(), true);
      // NOTE: the activation left a client in the static cache, keyed without
      // the storage path this preference asks for. Without the eviction the
      // authenticate below reuses that client and the preference does nothing.
      await evictCachedAtClients();
      expect(await onboardingService.authenticate(), true);
    });

    tearDownAll(() async {
      await tearDownFunc();
    });
  });
}

/// Builds the onboarding preference these tests share.
///
/// [posture] is a constructor argument because the field is final; omitted,
/// the preference takes the SDK default.
AtOnboardingPreference getPreferences(String atSign, {PqPosture? posture}) {
  atSign = AtUtils.fixAtSign(atSign);
  AtOnboardingPreference atOnboardingPreference = (posture == null
      ? AtOnboardingPreference()
      : AtOnboardingPreference(posture: posture))
    ..rootDomain = 'vip.ve.atsign.zone'
    ..rootPort = virtualenvRootPort
    ..isLocalStoreRequired = true
    ..hiveStoragePath = 'storage/hive/client'
    ..commitLogPath = 'storage/hive/client/commit'
    ..privateKey = null
    ..cramSecret = at_demos.cramKeyMap[atSign]
    ..atKeysFilePath = testKeysFile(atSign)
    ..downloadPath = testKeysDir
    ..appName = 'wavi'
    ..deviceName = 'pixel';

  return atOnboardingPreference;
}

Future<void> generateAtKeysFile(String atSign, String filePath) async {
  atSign = AtUtils.fixAtSign(atSign);
  Map<String, String?> atKeysMap = <String, String?>{
    AuthKeyType.pkamPublicKey: EncryptionUtil.encryptValue(
        at_demos.pkamPublicKeyMap[atSign]!, at_demos.aesKeyMap[atSign]!),
    AuthKeyType.pkamPrivateKey: EncryptionUtil.encryptValue(
        at_demos.pkamPrivateKeyMap[atSign]!, at_demos.aesKeyMap[atSign]!),
    AuthKeyType.encryptionPublicKey: EncryptionUtil.encryptValue(
        at_demos.encryptionPublicKeyMap[atSign]!, at_demos.aesKeyMap[atSign]!),
    AuthKeyType.encryptionPrivateKey: EncryptionUtil.encryptValue(
        at_demos.encryptionPrivateKeyMap[atSign]!, at_demos.aesKeyMap[atSign]!),
    AuthKeyType.selfEncryptionKey: at_demos.aesKeyMap[atSign],
    atSign: at_demos.aesKeyMap[atSign]
  };

  File file = File(filePath);
  if (!(file.existsSync())) {
    file = await file.create(recursive: true);
  }
  var atKeysFile = await file.open(mode: FileMode.write);
  atKeysFile.writeStringSync(jsonEncode(atKeysMap));
  await atKeysFile.close();
}

Future<void> tearDownFunc() async {
  bool isExists = await Directory('storage/').exists();
  if (isExists) {
    Directory('storage/').deleteSync(recursive: true);
  }
}
