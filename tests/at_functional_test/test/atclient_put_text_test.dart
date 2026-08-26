import 'package:at_client/at_client.dart';
import 'package:at_functional_test/src/config_util.dart';
import 'package:test/test.dart';
import 'test_utils.dart';

/// The tests verify the put and get functionality where key is created using AtKey
/// static factory methods
void main() {
  late AtClientManager atClientManager;
  late String atSign;
  final namespace = 'wavi';

  setUpAll(() async {
    atSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    atClientManager = await TestUtils.initAtClient(atSign, namespace,
        posture: PqPosture.legacy);
  });

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
}
