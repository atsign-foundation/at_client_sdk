import 'package:at_client/at_client.dart';

import 'at_demo_credentials.dart' as demo_credentials;

class TestUtils {
  static AtClientPreference getPreference(String atsign) {
    var preference = AtClientPreference();
    preference.hiveStoragePath = 'test/hive/client';
    preference.commitLogPath = 'test/hive/client/commit';
    preference.isLocalStoreRequired = true;
    preference.privateKey = demo_credentials.pkamPrivateKeyMap[atsign];
    preference.rootDomain = 'vip.ve.atsign.zone';
    preference.decryptPackets = true;
    preference.pathToCerts = 'test/testData/cert.pem';
    preference.tlsKeysSavePath = 'test/tlsKeysFile';
    return preference;
  }
}
