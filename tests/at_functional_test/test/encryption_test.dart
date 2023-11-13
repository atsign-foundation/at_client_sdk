import 'package:at_client/at_client.dart';
import 'package:at_functional_test/src/config_util.dart';
import 'package:at_utils/at_utils.dart';
import 'test_utils.dart';
import 'package:test/test.dart';
import 'package:version/version.dart';

void main() {
  late String atSign_1;
  final namespace = 'e2e_encryption_test';


  var clearText = 'Some clear text';

  var logLevelToRestore = AtSignLogger.root_level;
  
  setUpAll(() async {
    AtSignLogger.root_level = 'SHOUT';
    atSign_1 = ConfigUtil.getYaml()['atSign']['firstAtSign'];
  });

  tearDownAll(() {
    AtSignLogger.root_level = logLevelToRestore;
  });

  Future<AtClient> getAtClient(String atSign, Version version) async {
    AtClient atClient = (await AtClientManager.getInstance().setCurrentAtSign(
            atSign,
            namespace,
          TestUtils.getPreference(atSign_1)))
        .atClient;

    atClient.getPreferences()!.atProtocolEmitted = version;

    return atClient;
  }

  int ttl = 60000;
  group('Test encryption for self', () {
    test('Test put self, then get, no IV, 1.5 to 1.5', () async {
      AtClient atClient = await getAtClient(atSign_1, Version(1, 5, 0));

      var atKey = (AtKey.self('test_put.15_15')..timeToLive(ttl)).build();
      await atClient.put(atKey, clearText);
      expect(atKey.metadata?.ivNonce, isNull);

      atClient.getPreferences()!.atProtocolEmitted = Version(1, 5, 0);

      String selfEncryptionKey =
          (await atClient.getLocalSecondary()!.getEncryptionSelfKey())!;
      var atData =
          await (atClient.getLocalSecondary()!.keyStore!.get(atKey.toString()));
      var cipherText = atData.data;
      expect(EncryptionUtil.decryptValue(cipherText, selfEncryptionKey),
          clearText);

      var getResult = await atClient.get(atKey);
      expect(getResult.value, clearText);
    });

    test('Test put self, then get, no IV, 1.5 to 2.0', () async {
      AtClient atClient = await getAtClient(atSign_1, Version(1, 5, 0));

      var atKey = (AtKey.self('test_put.15_20')..timeToLive(ttl)).build();
      await atClient.put(atKey, clearText);
      expect(atKey.metadata?.ivNonce, isNull);

      atClient.getPreferences()!.atProtocolEmitted = Version(2, 0, 0);
      String selfEncryptionKey =
          (await atClient.getLocalSecondary()!.getEncryptionSelfKey())!;
      var atData =
          await (atClient.getLocalSecondary()!.keyStore!.get(atKey.toString()));
      var cipherText = atData.data;
      expect(EncryptionUtil.decryptValue(cipherText, selfEncryptionKey),
          clearText);

      var getResult = await atClient.get(atKey);
      expect(getResult.value, clearText);
    });

    test('Test put self, then get, with IV, 2.0 to 2.0', () async {
      AtClient atClient = await getAtClient(atSign_1, Version(2, 0, 0));

      var atKey = (AtKey.self('test_put.20_20')..timeToLive(ttl)).build();
      await atClient.put(atKey, clearText);
      expect(atKey.metadata?.ivNonce, isNotNull);

      atClient.getPreferences()!.atProtocolEmitted = Version(2, 0, 0);
      String selfEncryptionKey =
          (await atClient.getLocalSecondary()!.getEncryptionSelfKey())!;
      var atData =
          await (atClient.getLocalSecondary()!.keyStore!.get(atKey.toString()));
      var cipherText = atData.data;
      expect(
          EncryptionUtil.decryptValue(cipherText, selfEncryptionKey,
              ivBase64: atKey.metadata?.ivNonce),
          clearText);

      var getResult = await atClient.get(atKey);
      expect(getResult.value, clearText);
    });

    test('Test put self, then get, with IV, 2.0 to 1.5', () async {
      AtClient atClient = await getAtClient(atSign_1, Version(2, 0, 0));

      var atKey = (AtKey.self('test_put.20_15')..timeToLive(ttl)).build();
      await atClient.put(atKey, clearText);
      expect(atKey.metadata?.ivNonce, isNotNull);

      atClient.getPreferences()!.atProtocolEmitted = Version(1, 5, 0);
      String selfEncryptionKey =
          (await atClient.getLocalSecondary()!.getEncryptionSelfKey())!;
      var atData =
          await (atClient.getLocalSecondary()!.keyStore!.get(atKey.toString()));
      var cipherText = atData.data;
      expect(
          EncryptionUtil.decryptValue(cipherText, selfEncryptionKey,
              ivBase64: atKey.metadata?.ivNonce),
          clearText);

      var getResult = await atClient.get(atKey);
      expect(getResult.value, clearText);
    });
  });
}
