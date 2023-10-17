import 'package:at_client/at_client.dart';
import 'package:at_functional_test/src/at_keys_intialializer.dart';
import 'package:test/test.dart';
import 'commit_log_compaction_test.dart';
import 'test_utils.dart';

/// The tests verify the put and get functionality where key is created using AtKey
/// static factory methods
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

  Future<void> switchAtsigns(String atsign) async {
    var preference = TestUtils.getPreference(atsign);
    atClientManager.setCurrentAtSign(atsign, null, preference);
    var list =
        await atClientManager.atClient.getRemoteSecondary()!.atLookUp.scan();
    print(list);
  }

  Future<void> scan() async {
    var list =
        await atClientManager.atClient.getRemoteSecondary()!.atLookUp.scan();
    atClientManager.atClient.encryptionService!.logger.info(list);
  }

  group('A group of tests to verify positive scenarios of put and get', () {
    test('put method - create a key sharing to other atSign', () async {
      // phone.wavi@alice🛠
      var putPhoneKey = (AtKey.shared('phone', namespace: 'wavi')
            ..sharedWith('@bob🛠'))
          .build();
      var value = '+1 100 200 300';
      var putResult = await atClientManager.atClient.put(putPhoneKey, value);
      expect(putResult, true);

      var getPhoneKey = AtKey()
        ..key = 'phone'
        ..sharedWith = '@bob🛠';
      var getResult = await atClientManager.atClient.get(getPhoneKey);
      expect(getResult.value, value);
    });

    test('put method - create a public key', () async {
      // location.wavi@alice🛠
      var putKey = AtKey.public('location', namespace: 'wavi').build();
      var value = 'California';
      var putResult = await atClientManager.atClient.put(putKey, value);
      expect(putResult, true);

      var getKey = AtKey()
        ..key = 'location'
        ..metadata = (Metadata()..isPublic = true);
      var getResult = await atClientManager.atClient.get(getKey);
      expect(getResult.value, value);
    });

    test('put method - create a self key with sharedWith populated', () async {
      // country.wavi@alice🛠
      var putKey = (AtKey.shared('country', namespace: 'wavi')
            ..sharedWith(atSign))
          .build();
      var value = 'US';
      var putResult = await atClientManager.atClient.put(putKey, value);
      expect(putResult, true);

      var getKey = AtKey()
        ..key = 'country'
        ..sharedWith = atSign;
      var getResult = await atClientManager.atClient.get(getKey);
      expect(getResult.value, value);
    });

    test('put method - create a self key with sharedWith not populated',
        () async {
      // mobile.wavi@alice🛠
      var putKey = AtKey.self('mobile', namespace: 'wavi').build();
      var value = '+1 100 200 300';
      var putResult = await atClientManager.atClient.put(putKey, value);
      expect(putResult, true);

      var getKey = AtKey()..key = 'mobile';
      var getResult = await atClientManager.atClient.get(getKey);
      expect(getResult.value, value);
    });
  });

///
  group('A group of tests to verify get of symmetric shared keys', () {
    test('Positive test - self keys ', () async {
      await scan();
      var atKey =
          AtKey.self("shared_key", namespace: "", sharedBy: "@alice🛠").build();

      var result = await atClientManager.atClient.get(atKey);
      expect(result, returnsNormally);
    });

    test('Positive test - shared keys ', () async {
      await switchAtsigns("@bob🛠");
      await scan();
      atClientManager.atClient.encryptionService!.logger
          .info(atClientManager.atClient.getCurrentAtSign());
      var atKey = (AtKey.shared("shared_key", sharedBy: "@alice🛠")
            ..sharedWith("@bob🛠")
            ..cache(1000, true))
          .build();
      var result = await atClientManager.atClient.get(atKey);
      expect(result, returnsNormally);
    });

    test('Negative test - shared keys ', () async {
      await switchAtsigns("@alice🛠");
      var atKey = (AtKey.shared("shared_key", sharedBy: "@alice🛠")
            ..sharedWith("@bob🛠"))
          .build();

      expect(() async {
        await atClientManager.atClient.get(atKey);
      }, throwsException);
    });
  });
}
