import 'dart:io';
import 'dart:typed_data';

import 'package:at_client/at_client.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';
import 'package:version/version.dart';

import 'set_encryption_keys.dart';
import 'test_utils.dart';

/// The tests verify the delete key functionality of at_client
void main() {
  test('delete method - public key', () async {
    var atsign = '@alice🛠';
    var preference = TestUtils.getPreference(atsign);
    final atClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(atsign, 'wavi', preference);
    var atClient = atClientManager.atClient;
    atClientManager.syncService.sync();
    // To setup encryption keys
    await setEncryptionKeys(atsign, preference);
    // public:phone.wavi@alice🛠
    var phoneKey = AtKey()
      ..key = 'location'
      ..metadata = (Metadata()..isPublic = true)
      ..sharedBy = atsign;
    var value = 'California';
    var putResult = await atClient.put(phoneKey, value);
    expect(putResult, true);
    var deleteResult = await atClient.delete(phoneKey);
    expect(deleteResult, true);
  });
  test('delete method - delete non existent key', () async {
    var atsign = '@alice🛠';
    final atSignPort = 25000;
    var host = 'vip.ve.atsign.zone';
    var preference = TestUtils.getPreference(atsign);
    final atClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(atsign, 'wavi', preference);
    var atClient = atClientManager.atClient;
    atClientManager.syncService.sync();
    // To setup encryption keys
    await setEncryptionKeys(atsign, preference);
    // phone.me@alice🛠
    var phoneKey = AtKey()
      ..key = 'location'
      ..metadata = (Metadata()..isPublic = true)
      ..sharedBy = atsign;
    var value = 'California';
    var putResult = await atClient.put(phoneKey, value);
    expect(putResult, true);
    var deleteResult = await atClient.delete(phoneKey);
    expect(deleteResult, true);
    deleteResult = await atClient.delete(phoneKey);
    final socketHandler =
        await getUnAuthSocketHandler(host, atSignPort, atsign);
    final serverVersion = await socketHandler.getVersion();
    var version;
    if (serverVersion != null) {
      version = Version.parse(serverVersion);
    }
    print('***version $version');
    if (version > Version(3, 0, 25)) {
      expect(deleteResult, false);
    } else {
      expect(deleteResult, true);
    }
  });
  tearDown(() async => await tearDownFunc());
}

Future<void> tearDownFunc() async {
  var isExists = await Directory('test/hive').exists();
  if (isExists) {
    Directory('test/hive').deleteSync(recursive: true);
  }
}

Uint8List _getBinaryData(dynamic filePath) {
  var dir = Directory.current.path;
  var pathToFile = '$dir$filePath';
  return File(pathToFile).readAsBytesSync();
}
