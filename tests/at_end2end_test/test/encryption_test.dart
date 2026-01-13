import 'package:at_client/at_client.dart';
import 'package:at_end2end_test/config/config_util.dart';
import 'package:at_end2end_test/src/test_initializers.dart';
import 'package:at_end2end_test/src/test_preferences.dart';
import 'package:at_end2end_test/utils/test_constants.dart';
import 'package:test/test.dart';

void main() {
  late String atSign_1;
  late String atSign_2;
  final namespace = TestConstants.namespace;

  var clearText = 'Some clear text';

  setUpAll(() async {
    atSign_1 = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    atSign_2 = ConfigUtil.getYaml()['atSign']['secondAtSign'];
    String authType = ConfigUtil.getYaml()['authType'];

    await TestSuiteInitializer.getInstance()
        .testInitializer(atSign_1, namespace, authType);
    await TestSuiteInitializer.getInstance()
        .testInitializer(atSign_2, namespace, authType);
  });

  tearDownAll(() {});

  Future<AtClient> getAtClient(String atSign) async {
    AtClient atClient = (await AtClientManager.getInstance().setCurrentAtSign(
            atSign,
            namespace,
            TestPreferences.getInstance().getPreference(atSign_1)))
        .atClient;

    return atClient;
  }

  final PutRequestOptions remotePRO = PutRequestOptions()
    ..useRemoteAtServer = true;
  final GetRequestOptions remoteGRO = GetRequestOptions()
    ..useRemoteAtServer = true;

  group('Group of tests storing shared encryption key in metadata', () {
    test('Test put shared, then get, with IV', () async {
      AtClient atClient_1 = await getAtClient(atSign_1);

      var atKey = (AtKey.shared('test_share.2_0.to.2_0', sharedBy: atSign_1)
            ..sharedWith(atSign_2)
            ..timeToLive(TestConstants.oneMinuteMillis))
          .build();
      await atClient_1.put(atKey, clearText, putRequestOptions: remotePRO);
      expect(atKey.metadata.ivNonce, isNotNull);

      AtClient atClient_2 = await getAtClient(atSign_2);

      var getResult = await atClient_2.get(atKey, getRequestOptions: remoteGRO);
      expect(getResult.value, clearText);
    });
  });

  group('Group of tests NOT storing shared encryption key in metadata', () {
    PutRequestOptions putOptions = PutRequestOptions()
      ..useRemoteAtServer = true;
    GetRequestOptions getOptions = GetRequestOptions()
      ..bypassCache = true
      ..useRemoteAtServer = true;

    test('Test put shared, then get, with IV', () async {
      AtClient atClient_1 = await getAtClient(atSign_1);

      var atKey = (AtKey.shared('test_share.2_0.to.2_0.no_inlined_key',
              sharedBy: atSign_1)
            ..sharedWith(atSign_2)
            ..timeToLive(TestConstants.oneMinuteMillis))
          .build();
      await atClient_1.put(atKey, clearText, putRequestOptions: putOptions);
      expect(atKey.metadata.ivNonce, isNotNull);
      // sharedKeyEnc and pubKeyCS are now *always* set
      expect(atKey.metadata.sharedKeyEnc, isNotNull);
      expect(atKey.metadata.pubKeyCS, isNotNull);

      AtClient atClient_2 = await getAtClient(atSign_2);

      var getResult =
          await atClient_2.get(atKey, getRequestOptions: getOptions);
      expect(getResult.value, clearText);
    });
  });
}
