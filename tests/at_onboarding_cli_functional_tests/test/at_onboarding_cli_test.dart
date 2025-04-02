import 'dart:convert';
import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_demo_data/at_demo_data.dart' as at_demos;
import 'package:at_lookup/at_lookup.dart';
import 'package:at_onboarding_cli/at_onboarding_cli.dart';
import 'package:at_onboarding_cli/src/cli/auth_cli.dart' as auth_cli;
import 'package:at_utils/at_utils.dart';
import 'package:test/test.dart';

import 'utils/onboarding_service_impl_override.dart';

final String atKeysFilePath = '${Platform.environment['HOME']}/.atsign/keys';
Map<String, bool> keysCreatedMap = {};

void main() {
  AtSignLogger.root_level = 'WARNING';

  // These group of tests run on docker container with only cram key available on secondary
  // Perform cram auth and update keys manually.
  Future<void> _createKeys(String atSign) async {
    if (keysCreatedMap.containsKey(atSign)) {
      return;
    }
    var atLookup = AtLookupImpl(atSign, 'vip.ve.atsign.zone', 64);
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

  group('A group of tests to assert on authenticate functionality', () {
    test('A test to verify authentication is successful with .atKeys file',
        () async {
      String atSign = '@alice🛠';
      await _createKeys(atSign);
      AtOnboardingPreference preference = getPreferences(atSign);
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
      AtOnboardingPreference preference = getPreferences(atSign);
      await generateAtKeysFile(atSign, preference.atKeysFilePath!);
      AtOnboardingService atOnboardingService =
          AtOnboardingServiceImpl(atSign, preference);
      await atOnboardingService.authenticate();
      AtLookUp? atLookUp = atOnboardingService.atLookUp;
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
      AtOnboardingPreference preference = getPreferences(atSign);
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
      AtOnboardingPreference preference = getPreferences(atSign);
      preference.atKeysFilePath = null;
      AtOnboardingServiceImpl(atSign, preference);
      expect(preference.atKeysFilePath, '$atKeysFilePath/${atSign}_key.atKeys');
    });

    tearDown(() async {
      await tearDownFunc();
    });
  });

  group(
      'A group of tests to assert encryption keys persist into local secondary',
      () {
    String atSign = '@eve🛠'.trim();
    AtOnboardingPreference atOnboardingPreference = getPreferences(atSign);
    AtOnboardingService atOnboardingService =
        AtOnboardingServiceImpl(atSign, atOnboardingPreference);
    AtClient? atClient;

    test(
        'A test to authenticate atSign and verify PKAM keys and encryption keys are updated to local secondary',
        () async {
      await generateAtKeysFile(atSign, atOnboardingPreference.atKeysFilePath!);
      await _createKeys(atSign);
      bool status = await atOnboardingService.authenticate();
      atClient = await atOnboardingService.atClient;
      expect(true, status);

      expect(at_demos.pkamPrivateKeyMap[atSign],
          await atClient?.getLocalSecondary()?.getPrivateKey());

      expect(at_demos.pkamPublicKeyMap[atSign],
          await atClient?.getLocalSecondary()?.getPublicKey());

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

  group('A group of tests to verify onboard functionality', () {
    test('Onboard and verify failure modes', () async {
      String atSign = '@egcovidlab🛠';
      AtOnboardingPreference atOnboardingPreference = getPreferences(atSign);

      Future<void> onboard(bool autoCompleteActivation) async {
        AtOnboardingService atOnboardingService = AtOnboardingServiceImpl(
          atSign,
          atOnboardingPreference,
        );
        bool status = await atOnboardingService.onboard(
          autoCompleteActivation: autoCompleteActivation,
        );
        expect(status, true);
        expect(await atOnboardingService.isOnboarded(), autoCompleteActivation);

        File atKeysFile = File(atOnboardingPreference.atKeysFilePath!);

        /// Assert .atKeys file is generated for the atSign
        expect(await atKeysFile.exists(), true);
      }

      // onboard without removing cram secret
      await onboard(false);

      // do it again, but remove the cram secret (should succeed)
      await onboard(true);

      // try to do it again (should fail)
      await expectLater(() async {
        try {
          await onboard(true);
        } catch (e) {
          print('Caught an ${e.runtimeType} as expected ($e)');
          rethrow;
        }
      },
          throwsA(predicate((dynamic e) =>
              e is AtActivateException &&
              e.message ==
                  'atsign $atSign is already activated')));
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
        OnboardingServiceImplOverride(atSign, onboardingPreference);
    test(
        'A test to verify atSign is activated and .atKeys file is generated using activate_cli',
        () async {
      List<String> args = [
        '-a',
        atSign,
        '-c',
        at_demos.cramKeyMap[atSign]!,
        '-r',
        'vip.ve.atsign.zone'
      ];
      // perform activation of atSign
      await auth_cli.wrappedMain(args);

      /// ToDo: test should NOT exit with status 0 after activation is complete
      /// Exiting with status 0 is ideal behaviour, but for the sake of the test we need to be
      /// able to run the following assertions.

      // Authenticate atSign with the .atKeys file generated via the activate_cli tool
      expect(await File(onboardingPreference.atKeysFilePath!).exists(), true);
      expect(await onboardingService.authenticate(), true);
    });

    tearDownAll(() async {
      await tearDownFunc();
    });
  });
}

AtOnboardingPreference getPreferences(String atSign) {
  atSign = AtUtils.fixAtSign(atSign);
  AtOnboardingPreference atOnboardingPreference = AtOnboardingPreference()
    ..rootDomain = 'vip.ve.atsign.zone'
    ..isLocalStoreRequired = true
    ..hiveStoragePath = 'storage/hive/client'
    ..commitLogPath = 'storage/hive/client/commit'
    ..privateKey = null
    ..cramSecret = at_demos.cramKeyMap[atSign]
    ..atKeysFilePath = '$atKeysFilePath/${atSign}_key.atKeys'
    ..downloadPath = atKeysFilePath
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
