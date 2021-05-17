import 'dart:io';
import 'dart:typed_data';
import 'package:at_client/src/client/at_client_impl.dart';
import 'package:at_commons/at_commons.dart';
import 'set_encryption_keys.dart';
import 'package:test/test.dart';
import 'package:at_client/at_client.dart';
import 'at_demo_credentials.dart' as demo_credentials;

void main() async {
  AtClientImpl aliceClient;
  AtClientImpl bobClient;

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

  test('@alice🛠 creating image for self ', () async {
    await setUpClient();
    //1.1 put image for self
    var imageLocation =
        'test_data/image.jpeg'; //path to your image file
    var imageData = getdata(imageLocation);
    var metadata = Metadata()..isBinary = true;
    var atKey = AtKey()
      ..key = 'image_self'
      ..metadata = metadata;
    var result = await aliceClient.put(atKey, imageData);
    print(result);
    //1.2 get image for self
    var decodedImage = await aliceClient.get(atKey);
    saveToFile(
        'test_data/downloaded.jpeg',
        decodedImage.value); //path to save the retrieved image
  });

  test('@alice🛠 sharing a image for with @bob🛠 ', () async {
    await setUpClient();
    //1.1 put image for self
    var imageLocation =
        'test_data/image.jpeg'; //path to your image file
    var imageData = getdata(imageLocation);
    var metadata = Metadata()
      ..ttr = 864000
      ..isBinary = true;
    var atKey = AtKey()
      ..key = 'image_1'
      ..sharedWith = '@bob🛠'
      ..metadata = metadata;
    var result = await aliceClient.put(atKey, imageData);
    expect(result, true);
    await bobClient.getSyncManager().sync();
    var getImageMetadata = Metadata()
      ..isBinary = true
      ..isCached = true;
    var getAtKey = AtKey()
      ..key = 'image_1'
      ..sharedBy = '@alice🛠'
      ..metadata = getImageMetadata;
    var decodedImage = await bobClient.get(getAtKey);
    saveToFile(
        'test_data/downloaded.jpeg',
        decodedImage.value); //path to save the retrieved image
  });
}

void saveToFile(String filename, Uint8List contents) {
  var pathToFile = '${Directory.current.path}/filename';
  // var pathToFile = join(dirname(Platform.script.toFilePath()), filename);
  File(pathToFile).writeAsBytesSync(contents);
  return;
}

Uint8List getdata(String filename) {
  var contents = File(filename).readAsBytesSync();
  return (contents);
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
