import 'package:at_client/at_client.dart';
import 'package:at_functional_test/src/config_util.dart';
import 'package:at_utils/at_utils.dart';
import 'test_utils.dart';
import 'package:test/test.dart';

void main() {
  late String atSign_1;
  final namespace = 'functional_encryption_test';

  var clearText = 'Some clear text';

  var logLevelToRestore = AtSignLogger.root_level;

  setUpAll(() async {
    AtSignLogger.root_level = 'SHOUT';
    atSign_1 = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    await TestUtils.initAtClient(atSign_1, namespace);
  });

  tearDownAll(() {
    AtSignLogger.root_level = logLevelToRestore;
  });

  Future<AtClient> getAtClient(String atSign) async {
    return (await AtClientManager.getInstance().setCurrentAtSign(
            atSign, namespace, TestUtils.getPreference(atSign_1)))
        .atClient;
  }

  int ttl = 60000;
  group('Test encryption for self', () {
    test('Test put self, then get, with IV', () async {
      AtClient atClient = await getAtClient(atSign_1);

      var atKey = (AtKey.self('test_put.20_20')..timeToLive(ttl)).build();
      await atClient.put(atKey, clearText);
      expect(atKey.metadata.ivNonce, isNotNull);

      String selfEncryptionKey =
          (await atClient.getLocalSecondary()!.getEncryptionSelfKey())!;
      var atData =
          await (atClient.getLocalSecondary()!.keyStore!.get(atKey.toString()));
      var cipherText = atData!.data!;
      expect(
          EncryptionUtil.decryptValue(cipherText, selfEncryptionKey,
              ivBase64: atKey.metadata.ivNonce),
          clearText);

      var getResult = await atClient.get(atKey);
      expect(getResult.value, clearText);
    });
  });
}
