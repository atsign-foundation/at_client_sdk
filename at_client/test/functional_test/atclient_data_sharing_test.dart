import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';
import 'at_demo_credentials.dart' as demo_credentials;
import 'set_encryption_keys.dart';

var maxRetryCount = 5;
var retryCount = 1;

var atClientInstance;
AtClientImpl aliceClient;
AtClientImpl bobClient;

void main() {
  Future<void> setUpClient() async {
    var firstAtsign = '@alice🛠';
    var firstAtsignPreference = getAlicePreference(firstAtsign);
    await AtClientImpl.createClient(firstAtsign, 'me', firstAtsignPreference);
    aliceClient = await AtClientImpl.getClient(firstAtsign);
    aliceClient.getSyncManager().init(firstAtsign, firstAtsignPreference,
        aliceClient.getRemoteSecondary(), aliceClient.getLocalSecondary());
    await aliceClient.getSyncManager().sync();
    // To setup encryption keys
    await setEncryptionKeys(firstAtsign, firstAtsignPreference);

    var secondAtsign = '@bob🛠';
    var secondAtsignPreference = getBobPreference(secondAtsign);
    await AtClientImpl.createClient(secondAtsign, 'me', secondAtsignPreference);
    bobClient = await AtClientImpl.getClient(secondAtsign);
    bobClient.getSyncManager().init(secondAtsign, secondAtsignPreference,
        bobClient.getRemoteSecondary(), bobClient.getLocalSecondary());
    await bobClient.getSyncManager().sync();
    await setEncryptionKeys(secondAtsign, secondAtsignPreference);
  };

  test('@alice🛠 sharing a key with @bob🛠 with ccd as true ', () async {
    // setting up client
    await setUpClient();
    // ttr:864000:ccd:true:@bob🛠:location@alice🛠 USA
    var metadata = Metadata()
      ..ttr = 864000
      ..ccd = true;
    var locationKey = AtKey()
      ..key = 'location'
      ..namespace = '.me'
      ..sharedWith = '@bob🛠'
      ..metadata = metadata;
    var locationvalue = 'USA';
    // @alice🛠 sharing location key with @bob🛠
    var locationResult = await aliceClient.put(locationKey, locationvalue);
    expect(locationResult, true);
    var getMetadata = Metadata()..isCached = true;
    // lookup:@alice🛠
    var getLocationKey = AtKey()
      ..key = 'location'
      ..sharedBy = '@alice🛠'
      ..metadata = getMetadata;
    await bobClient.getSyncManager().sync();
    // @bob🛠 fetching location key which is shared by @alice🛠
    var result = await waitForResult(bobClient, getLocationKey);
    expect(result.value, locationvalue);
    var deleteResult = await aliceClient.delete(locationKey);
    expect(deleteResult, true);
    await bobClient.getSyncManager().sync();
    await Future.delayed(Duration(seconds: 15));
    result = await bobClient.get(getLocationKey);
    expect(result.value, null);
  }, timeout: Timeout(Duration(seconds: 120)));

  test('@alice🛠 sharing a key with @bob🛠 with ttr as -1 ', () async {
    await setUpClient();
    var metadata = Metadata()
      ..ttr = -1
      ..ccd = true;
    var aboutKey = AtKey()
      ..key = 'about'
      ..namespace = '.me'
      ..sharedWith = '@bob🛠'
      ..metadata = metadata;
    var aboutvalue = 'Photographer';
    // @alice🛠 sharing about key with @bob🛠
    var aboutResult = await aliceClient.put(aboutKey, aboutvalue);
    expect(aboutResult, true);
    var getMetadata = Metadata()..isCached = true;
    var getaboutKey = AtKey()
      ..key = 'about'
      ..sharedBy = '@alice🛠'
      ..metadata = getMetadata;
    await bobClient.getSyncManager().sync();
    // @bob🛠 fetching about key which is shared by @alice🛠
    var result = await waitForResult(bobClient, getaboutKey);
    expect(result.value, aboutvalue);
  }, timeout: Timeout(Duration(seconds: 60)));

  test('@alice🛠 sharing a key with @bob🛠 with ccd as false', () async {
    await setUpClient();
    var metadata = Metadata()..ttr = 8640000;
    var emailKey = AtKey()
      ..key = 'email'
      ..sharedWith = '@bob🛠'
      ..metadata = metadata;
    var emailValue = 'alice@yahoo.com';
    // @alice🛠 sharing email key with @bob🛠
    var emailResult = await aliceClient.put(emailKey, emailValue);
    expect(emailResult, true);
    // @bob🛠 fetching the email key shared by @alice🛠
    var getMetadata = Metadata()..isCached = false;
    var getEmailKey = AtKey()
      ..key = 'email'
      ..sharedBy = '@alice🛠'
      ..metadata = getMetadata;
    await bobClient.getSyncManager().sync();
    var result = await waitForResult(bobClient, getEmailKey);
    expect(result.value, emailValue);
    // @alice🛠 deleting the email key shared with @bob🛠
    var emailDeleteResult = await aliceClient.delete(getEmailKey);
    expect(emailDeleteResult, true);
    await bobClient.getSyncManager().sync();
    // @bob🛠 fetching the email key
    result = await waitForResult(bobClient, getEmailKey);
    expect(result.value, emailValue);
  }, timeout: Timeout(Duration(seconds: 60)));

  test('@alice🛠 sharing a key with @bob🛠 and updating the existing key',
      () async {
    await setUpClient();
    var metadata = Metadata()..ttr = 8640000;
    var usernameKey = AtKey()
      ..key = 'username'
      ..sharedWith = '@bob🛠'
      ..metadata = metadata;
    var usernameValue = 'alice123';
    var updatedusername = 'AliceBuffay';
    // @alice🛠 sharing a key with @bob🛠
    var usernameResult = await aliceClient.put(usernameKey, usernameValue);
    expect(usernameResult, true);
    // @bob fetching keys shared by @alice
    var getMetadata = Metadata()..isCached = true;
    var getusernameKey = AtKey()
      ..key = 'username'
      ..sharedBy = '@alice🛠'
      ..metadata = getMetadata;
    // bob🛠 fetching username key shared by @alice🛠
    await bobClient.getSyncManager().sync();
    var result = await waitForResult(bobClient, getusernameKey);
    expect(result.value, usernameValue);
    // @alice updating the username key shared with @bob
    var updateusernameResult =
        await aliceClient.put(usernameKey, updatedusername);
    expect(updateusernameResult, true);
    // @bob fetching updated key shared by @alice
    await bobClient.getSyncManager().sync();
    await Future.delayed(Duration(seconds: 5));
    result = await waitForResult(bobClient, getusernameKey);
    expect(result.value, updatedusername);
  }, timeout: Timeout(Duration(seconds: 60)));

  test('@alice and @bob sharing keys between each other', () async {
    //  @bob🛠 sharing landline key with @alice🛠
    await setUpClient();
    var metadata = Metadata()..ttr = 120000;
    var numberKey = AtKey()
      ..key = 'landlineTest'
      ..namespace = '.me'
      ..sharedWith = '@alice🛠'
      ..metadata = metadata;
    var numberValue = '040-27502292';
    //  @bob🛠 sharing landline key with @alice🛠
    var numberResult = await bobClient.put(numberKey, numberValue);
    expect(numberResult, true);
    var getMetadata = Metadata()..isCached = true;
    var getNumberKey = AtKey()
      ..key = 'landlineTest'
      ..sharedBy = '@bob🛠'
      ..metadata = getMetadata;
    await aliceClient.getSyncManager().sync();
    var getnumberResult = await waitForResult(aliceClient, getNumberKey);
    expect(getnumberResult.value, numberValue);

    var otpKey = AtKey()
      ..key = 'otpTest'
      ..metadata = metadata
      ..sharedWith = '@bob🛠';
    var otpValue = '9900';
    var otpResult = await aliceClient.put(otpKey, otpValue);
    expect(otpResult, true);
    var getOtpKey = AtKey()
      ..key = 'otpTest'
      ..sharedBy = '@alice🛠'
      ..metadata = getMetadata;
    await aliceClient.getSyncManager().sync();
    var getResult = await waitForResult(bobClient, getOtpKey);
    expect(getResult.value, otpValue);
  }, timeout: Timeout(Duration(seconds: 60)));
}

Future<void> tearDownFunc() async {
  var isExists = await Directory('test/hive').exists();
  if (isExists) {
    Directory('test/hive').deleteSync(recursive: true);
  }
}

Future<AtValue> waitForResult(AtClientImpl atClient, AtKey key) async {
  var result;
  while (true) {
    try {
      await atClient.getSyncManager().sync();
      result = await atClient.get(key);
      if (result.value != null || retryCount > maxRetryCount) {
        break;
      }
      if (result.value == null) {
        print('Waiting for result.. $retryCount');
        await Future.delayed(Duration(seconds: 10));
        retryCount++;
      }
    } on Exception {
      print('Waiting for result in Exception $retryCount');
      await Future.delayed(Duration(seconds: 10));
      retryCount++;
    }
  }
  return result;
}

AtClientPreference getAlicePreference(String atsign) {
  var preference = AtClientPreference();
  preference.hiveStoragePath = 'test/hive/client';
  preference.commitLogPath = 'test/hive/client/commit';
  preference.isLocalStoreRequired = true;
  preference.syncStrategy = SyncStrategy.IMMEDIATE;
  preference.privateKey = demo_credentials.pkamPrivateKeyMap[atsign];
  preference.rootDomain = 'vip.ve.atsign.zone';
  return preference;
}

AtClientPreference getBobPreference(String atsign) {
  var preference = AtClientPreference();
  preference.hiveStoragePath = 'test/hive/client';
  preference.commitLogPath = 'test/hive/client/commit';
  preference.isLocalStoreRequired = true;
  preference.syncStrategy = SyncStrategy.IMMEDIATE;
  preference.privateKey = demo_credentials.pkamPrivateKeyMap[atsign];
  preference.rootDomain = 'vip.ve.atsign.zone';
  return preference;
}
