import 'package:at_client/at_client.dart';
import 'package:test/test.dart';
import 'package:at_commons/src/verb/update_verb_builder.dart';
import 'package:at_commons/src/verb/llookup_verb_builder.dart';

import 'at_demo_credentials.dart' as demo_credentials;
import 'set_encryption_keys.dart';

void main() {
  test('sequence of put and get results', () async {
    var atsign = '@alice🛠';
    var preference = getAlicePreference(atsign);
    final atClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(atsign, 'wavi', preference);
    var atClient = atClientManager.atClient;
    atClientManager.syncService.sync();
    // To setup encryption keys
    await setEncryptionKeys(atsign, preference);
    var value = '+1 1111';
    final phoneUpdateBuilder = UpdateVerbBuilder()
      ..isPublic = true
      ..atKey = 'phone'
      ..sharedBy = atsign
      ..value = value;
    await atClient.getRemoteSecondary()!.executeVerb(phoneUpdateBuilder);
    final phoneLookupVerbBuilder = LLookupVerbBuilder()
      ..isPublic = true
      ..atKey = 'phone'
      ..sharedBy = atsign;

    final emailUpdateBuilder = UpdateVerbBuilder()
      ..isPublic = true
      ..atKey = 'email'
      ..sharedBy = atsign
      ..value = 'alice@gmail.com';
    await atClient.getRemoteSecondary()!.executeVerb(emailUpdateBuilder);
    final emailLookupVerbBuilder = LLookupVerbBuilder()
      ..isPublic = true
      ..atKey = 'email'
      ..sharedBy = atsign;

    final locationUpdateBuilder = UpdateVerbBuilder()
      ..isPublic = true
      ..atKey = 'location'
      ..sharedBy = atsign
      ..value = 'newyork';
    await atClient.getRemoteSecondary()!.executeVerb(locationUpdateBuilder);
    final locationLookupVerbBuilder = LLookupVerbBuilder()
      ..isPublic = true
      ..atKey = 'location'
      ..sharedBy = atsign;
    final phoneFuture =
        atClient.getRemoteSecondary()!.executeVerb(phoneLookupVerbBuilder);
    final emailFuture =
        atClient.getRemoteSecondary()!.executeVerb(emailLookupVerbBuilder);
    final locationFuture =
        atClient.getRemoteSecondary()!.executeVerb(locationLookupVerbBuilder);
    phoneFuture.then((value) => expect(value, 'data:+1 1111'));
    emailFuture.then((value) => expect(value, 'data:alice@gmail.com'));
    locationFuture.then((value) => expect(value, 'data:newyork'));
  });
}

AtClientPreference getAlicePreference(String atsign) {
  var preference = AtClientPreference();
  preference.hiveStoragePath = 'test/hive/client';
  preference.commitLogPath = 'test/hive/client/commit';
  preference.isLocalStoreRequired = true;
  preference.privateKey = demo_credentials.pkamPrivateKeyMap[atsign];
  preference.rootDomain = 'vip.ve.atsign.zone';
  return preference;
}
