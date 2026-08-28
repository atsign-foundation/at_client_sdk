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
import 'utils/test_keys_dir.dart';

/// Where at_onboarding_cli falls back to when `atKeysFilePath` is null. Only
/// ever compared against — nothing in this package writes there, see
/// [testKeysDir].
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
      expect(
          preference.atKeysFilePath, '$defaultAtKeysDir/${atSign}_key.atKeys');
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

  group('A group of tests to verify onboard functionality', () {
    test('Onboard and verify failure modes', () async {
      String atSign = '@egcovidlab🛠';
      AtOnboardingPreference atOnboardingPreference = getPreferences(atSign);

      Future<void> onboard({
        bool autoCompleteActivation = true,
        bool cleanup = true,
      }) async {
        AtOnboardingService atOnboardingService = AtOnboardingServiceImpl(
          atSign,
          atOnboardingPreference,
        );
        File atKeysFile = File(atOnboardingPreference.atKeysFilePath!);
        await atOnboardingService.onboard(
          autoCompleteActivation: autoCompleteActivation,
        );
        expect(await atOnboardingService.isOnboarded(), autoCompleteActivation);

        // Assert .atKeys file is generated for the atSign
        expect(await atKeysFile.exists(), true);
        if (cleanup) {
          await quiesceStartupTail(atOnboardingService);
          await atKeysFile.delete();
          expect(await atKeysFile.exists(), false);
        }
      }

      // onboard without removing cram secret
      await onboard(
        autoCompleteActivation: false,
      );

      // do it again, but remove the cram secret (should succeed)
      await onboard();

      // try to do it again (should fail)
      await expectLater(() async {
        try {
          await onboard();
        } catch (e) {
          print('Caught an ${e.runtimeType} as expected ($e)');
          rethrow;
        }
      },
          throwsA(predicate((dynamic e) =>
              e is AtActivateException &&
              e.message == 'atsign $atSign is already activated')));

      // try to onboard with keys in place
      await expectLater(() async {
        try {
          File atKeysFile = File(atOnboardingPreference.atKeysFilePath!);
          if (await atKeysFile.exists()) {
            await atKeysFile.create(recursive: true);
          }
          await onboard();
        } catch (e) {
          print('Caught an ${e.runtimeType} as expected ($e)');
          rethrow;
        }
      }, throwsA(predicate((dynamic e) => e is AtException)));
      ;
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
        'vip.ve.atsign.zone',
        // Without -k the CLI writes the generated keyfile to the home
        // directory's real keys dir.
        '-k',
        onboardingPreference.atKeysFilePath!,
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

/// Waits for the client an onboard brought up to finish its startup tail,
/// before a test deletes the `.atKeys` file that tail is still writing to.
///
/// A post-quantum activation — which is what the default posture asks for,
/// since `PqPosture.pqReady` authenticates with `mldsa65` — creates the
/// atSign's signing root, and that needs an `AtClient`. Building one fires the
/// PQ startup as an unawaited task, and its steps file key material through
/// `AtKeysIo.update`. That call reads the keyfile and then writes it back, and
/// the write recreates the file when it has gone in between: a delete landing
/// mid-update is undone, and the next onboard then refuses at
/// `AtFileUtil.ensureWritable` — the first statement of `onboard` — instead of
/// reaching the activation check the test is asserting on. The tail and the
/// test share one isolate, so every `await` between the two is a point where
/// they can interleave.
///
/// Nothing here needs the tail to have *succeeded*: `startupComplete` answers
/// "has the startup finished", and a step that failed is logged rather than
/// thrown. All this waits for is that nothing is left writing to the keyfile.
///
/// `AtClient.ensureReachable` is the supported wait and is deliberately not
/// used: it waits for one namespace's advertisement to be published, which is
/// a single startup step, while what has to be quiet here is every step that
/// touches the keyfile. Reaching the experimental `pqBootstrap` is the only
/// way to ask the question this needs answered.
Future<void> quiesceStartupTail(AtOnboardingService service) async {
  final client = service.atClient;
  if (client is AtClientImpl) {
    // ignore: experimental_member_use
    await client.pqBootstrap?.startupComplete;
  }
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
