import 'dart:convert';
import 'dart:io';

import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_onboarding_cli/at_onboarding_cli.dart';
import 'package:at_utils/at_logger.dart';
import 'package:test/test.dart';
import 'package:at_demo_data/at_demo_data.dart' as at_demos;
import 'utils/at_chops_secure_element_mock.dart';
import 'package:at_auth/at_auth.dart' as at_auth;
import 'utils/onboarding_service_impl_override.dart';

/// Usage: dart main.dart <cram_secret>
void main() {
  AtSignLogger.root_level = 'WARNING';
  var logger = AtSignLogger('OnboardSecureElementTest');

  final atSign = '@egcreditbureau🛠'.trim();
  test('Test auth functionality using secure element mock', () async {
    AtOnboardingPreference preference = getPreferences(atSign);
    AtOnboardingService onboardingService =
        OnboardingServiceImplOverride(atSign, preference);
    // create empty keys in AtChops. Encryption key pair will be set later on after generation
    final atChopsImpl =
        AtChopsSecureElementMock(AtChopsKeys.create(null, null));
    AtLookUp atLookupInstance =
        AtLookupImpl(atSign, preference.rootDomain, preference.rootPort);
    atLookupInstance.signingAlgoType = preference.signingAlgoType;
    atLookupInstance.hashingAlgoType = preference.hashingAlgoType;
    at_auth.AtAuth atAuthInstance = at_auth.atAuthBase
        .atAuth(atLookUp: atLookupInstance, atChops: atChopsImpl);
    onboardingService.atAuth = atAuthInstance;
    atChopsImpl.init();
    logger.info('Onboarding the atSign: $atSign');
    bool isOnboarded = await onboardingService.onboard();
    expect(isOnboarded, true);
    logger.info('Onboarding completed successfully');

    logger.info('Authenticating the atSign: $atSign');
    bool status = await onboardingService.authenticate();
    expect(status, true);
    logger.info('Authentication completed successfully for atSign: $atSign');

    // update a key
    AtClient? atClient = await onboardingService.atClient;
    await insertSelfEncKey(atClient, atSign,
        selfEncryptionKey:
            await getSelfEncryptionKey(preference.atKeysFilePath!));
    AtKey key = AtKey();
    key.key = 'securedKey';
    key.namespace = 'wavi';
    var putResult = await atClient?.put(key, 'securedvalue');
    stdout.writeln('[Test] Got AtClient.put() Response: $putResult');
    expect(putResult, true);
    AtValue? response = await atClient?.get(key);
    stdout.writeln('[Test] Got Response: $response');
    expect('securedvalue', response?.value);
    var deleteResponse = await atClient?.delete(key);
    stdout.writeln('[Test] Got Delete Response: $deleteResponse');
    expect(deleteResponse, true);
  });

  tearDown(() async {
    bool isExists = await Directory('test/storage/').exists();
    if (isExists) {
      Directory('test/storage/').deleteSync(recursive: true);
    }
  });
}

AtOnboardingPreference getPreferences(String atSign) {
  AtOnboardingPreference atOnboardingPreference = AtOnboardingPreference()
    ..hiveStoragePath = 'test/storage/hive'
    ..namespace = 'wavi'
    ..downloadPath = 'test/storage/files'
    ..isLocalStoreRequired = true
    ..commitLogPath = 'storage/commitLog'
    ..rootDomain = 'vip.ve.atsign.zone'
    ..fetchOfflineNotifications = true
    ..atKeysFilePath = 'test/storage/files/$atSign' + '_key.atKeys'
    ..signingAlgoType = SigningAlgoType.ecc_secp256r1
    ..hashingAlgoType = HashingAlgoType.sha256
    ..authMode = PkamAuthMode.sim
    ..publicKeyId = '3023020'
    ..cramSecret = at_demos.cramKeyMap[atSign]
    ..skipSync = true;

  return atOnboardingPreference;
}

Future<String?> getSelfEncryptionKey(String atKeysFilePath) async {
  String atAuthData = await File(atKeysFilePath).readAsString();
  Map<String, String> jsonData = <String, String>{};
  json.decode(atAuthData).forEach((String key, dynamic value) {
    jsonData[key] = value.toString();
  });
  return jsonData[AtConstants.atEncryptionSelfKey];
}

Future<void> insertSelfEncKey(AtClient? atClient, String atsign,
    {String? selfEncryptionKey}) async {
  await atClient?.getLocalSecondary()?.putValue(AtConstants.atEncryptionSelfKey,
      selfEncryptionKey ?? at_demos.aesKeyMap[atsign]!);
  return;
}
