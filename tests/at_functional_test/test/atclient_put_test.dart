import 'dart:io';
import 'dart:typed_data';

import 'package:at_client/at_client.dart';
import 'package:at_functional_test/src/at_keys_intialializer.dart';
import 'package:test/test.dart';
import 'test_utils.dart';

/// The tests verify the put and get functionality where key is created using AtKey concrete
/// class
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

  test('put method - create a key sharing to other atSign', () async {
    // phone.me@alice🛠
    var phoneKey = AtKey()
      ..key = 'phone'
      ..sharedWith = '@bob🛠';
    var value = '+1 100 200 300';
    var putResult = await atClientManager.atClient.put(phoneKey, value);
    expect(putResult, true);
    var getResult = await atClientManager.atClient.get(phoneKey);
    expect(getResult.value, value);
  });

  test('put method - create a public key', () async {
    // phone.me@alice🛠
    var phoneKey = AtKey()
      ..key = 'location'
      ..metadata = (Metadata()..isPublic = true);
    var value = 'California';
    var putResult = await atClientManager.atClient.put(phoneKey, value);
    expect(putResult, true);

    var getResult = await atClientManager.atClient.get(phoneKey);
    expect(getResult.value, value);
  });

  test('put method - create a self key with sharedWith populated', () async {
    // phone.me@alice🛠
    var phoneKey = AtKey()
      ..key = 'country'
      ..sharedWith = atSign;
    var value = 'US';
    var putResult = await atClientManager.atClient.put(phoneKey, value);
    expect(putResult, true);

    var getResult = await atClientManager.atClient.get(phoneKey);
    expect(getResult.value, value);
  });

  test('put method - create a self key with sharedWith not populated',
      () async {
    // phone.me@alice🛠
    var phoneKey = AtKey()..key = 'mobile';
    var value = '+1 100 200 300';
    var putResult = await atClientManager.atClient.put(phoneKey, value);
    expect(putResult, true);

    var getResult = await atClientManager.atClient.get(phoneKey);
    expect(getResult.value, value);
  });

  test('put method - create a key with binary data', () async {
    // phone.me@alice🛠
    var phoneKey = AtKey()
      ..key = 'image'
      ..metadata = (Metadata()..isBinary = true);
    var value = _getBinaryData("/test/testData/dev.png");
    var putResult = await atClientManager.atClient.put(phoneKey, value);
    expect(putResult, true);
    var getKey = AtKey()
      ..key = 'image'
      ..metadata = (Metadata()..isBinary = true);

    var getResult = await atClientManager.atClient.get(getKey);
    expect(getResult.value, value);
  });

  test('put method - create a public key with binary data', () async {
    // phone.me@alice🛠
    var phoneKey = AtKey()
      ..key = 'image'
      ..metadata = (Metadata()
        ..isBinary = true
        ..isPublic = true);
    var value = _getBinaryData("/test/testData/dev.png");
    var putResult = await atClientManager.atClient.put(phoneKey, value);
    expect(putResult, true);

    var getKey = AtKey()
      ..key = 'image'
      ..metadata = (Metadata()
        ..isBinary = true
        ..isPublic = true);
    var getResult = await atClientManager.atClient.get(getKey);
    expect(getResult.value, value);
  });

  test('put method - create a public key', () async {
    // phone.me@alice🛠
    var phoneKey = AtKey()
      ..key = 'city'
      ..metadata = (Metadata()..isPublic = true);
    var value = 'copenhagen';
    var putResult = await atClientManager.atClient.put(phoneKey, value);
    expect(putResult, true);

    var getResult = await atClientManager.atClient.get(phoneKey);
    expect(getResult.value, value);
  });
}

Uint8List _getBinaryData(dynamic filePath) {
  var dir = Directory.current.path;
  var pathToFile = '$dir$filePath';
  return File(pathToFile).readAsBytesSync();
}
