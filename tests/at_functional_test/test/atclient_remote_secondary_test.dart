import 'package:at_client/at_client.dart';
import 'package:at_commons/src/verb/llookup_verb_builder.dart';
import 'package:at_commons/src/verb/update_verb_builder.dart';
import 'package:at_functional_test/src/at_keys_intialializer.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  late AtClientManager atClientManager;
  String atSign = '@alice🛠';

  setUpAll(() async {
    var preference = TestUtils.getPreference(atSign);
    atClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(atSign, 'wavi', preference);
    // To setup encryption keys
    await AtEncryptionKeysLoader.getInstance()
        .setEncryptionKeys(atClientManager.atClient, atSign);
  });

  test('sequence of put and get results', () async {
    var value = '+1 1111';
    final phoneUpdateBuilder = UpdateVerbBuilder()
      ..isPublic = true
      ..atKey = 'phone'
      ..sharedBy = atSign
      ..value = value;
    await atClientManager.atClient
        .getRemoteSecondary()!
        .executeVerb(phoneUpdateBuilder);
    final phoneLookupVerbBuilder = LLookupVerbBuilder()
      ..isPublic = true
      ..atKey = 'phone'
      ..sharedBy = atSign;

    final emailUpdateBuilder = UpdateVerbBuilder()
      ..isPublic = true
      ..atKey = 'email'
      ..sharedBy = atSign
      ..value = 'alice@gmail.com';
    await atClientManager.atClient
        .getRemoteSecondary()!
        .executeVerb(emailUpdateBuilder);
    final emailLookupVerbBuilder = LLookupVerbBuilder()
      ..isPublic = true
      ..atKey = 'email'
      ..sharedBy = atSign;

    final locationUpdateBuilder = UpdateVerbBuilder()
      ..isPublic = true
      ..atKey = 'location'
      ..sharedBy = atSign
      ..value = 'newyork';
    await atClientManager.atClient
        .getRemoteSecondary()!
        .executeVerb(locationUpdateBuilder);
    final locationLookupVerbBuilder = LLookupVerbBuilder()
      ..isPublic = true
      ..atKey = 'location'
      ..sharedBy = atSign;
    final phoneFuture = atClientManager.atClient
        .getRemoteSecondary()!
        .executeVerb(phoneLookupVerbBuilder);
    final emailFuture = atClientManager.atClient
        .getRemoteSecondary()!
        .executeVerb(emailLookupVerbBuilder);
    final locationFuture = atClientManager.atClient
        .getRemoteSecondary()!
        .executeVerb(locationLookupVerbBuilder);
    phoneFuture.then((value) => expect(value, 'data:+1 1111'));
    emailFuture.then((value) => expect(value, 'data:alice@gmail.com'));
    locationFuture.then((value) => expect(value, 'data:newyork'));
  });
}
