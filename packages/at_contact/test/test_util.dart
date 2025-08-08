//import 'dart:typed_data';
import 'package:at_client/src/preference/at_client_preference.dart';

class TestUtil {
  static AtClientPreference getPreferenceRemote() {
    var preference = AtClientPreference();
    preference.isLocalStoreRequired = false;
    preference.cramSecret = '<cram_secret>';
    preference.rootDomain = 'test.do-sf2.atsign.zone';
    preference.outboundConnectionTimeout = 60000;
    return preference;
  }

  static AtClientPreference getPreferenceLocal() {
    var preference = AtClientPreference();
    preference.hiveStoragePath = 'hive/client';
    preference.commitLogPath = 'hive/client/commit';
    preference.isLocalStoreRequired = true;
    preference.cramSecret = '<cram_secret>';
    preference.rootDomain = 'vip.ve.atsign.zone';
    return preference;
  }

//  static List<int> _getKeyStoreSecret(String filePath) {
//    var hiveSecretString = File(filePath).readAsStringSync();
//    var secretAsUint8List = Uint8List.fromList(hiveSecretString.codeUnits);
//    return secretAsUint8List;
//  }
}
