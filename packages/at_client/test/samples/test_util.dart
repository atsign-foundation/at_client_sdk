import 'dart:convert';
import 'dart:typed_data';
import 'package:at_client/src/preference/at_client_preference.dart';
import 'dart:io';
import 'package:crypto/crypto.dart';

class TestUtil {
  static AtClientPreference getPreferenceRemote() {
    var preference = AtClientPreference();
    preference.isLocalStoreRequired = false;
    preference.rootDomain = 'vip.ve.atsign.zone';
    preference.outboundConnectionTimeout = 60000;
    return preference;
  }

  static AtClientPreference getPreferenceLocal() {
    var preference = AtClientPreference();
    preference.hiveStoragePath = 'hive/client';
    preference.commitLogPath = 'hive/client/commit';
    preference.isLocalStoreRequired = true;
    preference.rootDomain = 'test.do-sf2.atsign.zone';
    preference.keyStoreSecret =
        _getKeyStoreSecret(''); // path of hive encryption key filefor client
    return preference;
  }

  static AtClientPreference getAlicePreference() {
    var preference = AtClientPreference();
    preference.hiveStoragePath = '/home/murali/work/2020/hive/client';
    preference.commitLogPath = '/home/murali/work/2020/hive/client/commit';
    preference.isLocalStoreRequired = true;
    preference.rootDomain = 'vip.ve.atsign.zone';
    var hashFile = _getShaForAtSign('@alice🛠');
    preference.keyStoreSecret =
        _getKeyStoreSecret('/home/murali/work/2020/hive/client/$hashFile.hash');
    return preference;
  }

  static AtClientPreference getBobPreference() {
    var preference = AtClientPreference();
    preference.hiveStoragePath = '/home/murali/work/2020/hive/client';
    preference.commitLogPath = '/home/murali/work/2020/hive/client/commit';
    preference.isLocalStoreRequired = true;
    preference.rootDomain = 'vip.ve.atsign.zone';
    var hashFile = _getShaForAtSign('@bob🛠');
    preference.keyStoreSecret =
        _getKeyStoreSecret('/home/murali/work/2020/hive/client/$hashFile.hash');
    return preference;
  }

  static List<int> _getKeyStoreSecret(String filePath) {
    var hiveSecretString = File(filePath).readAsStringSync();
    var secretAsUint8List = Uint8List.fromList(hiveSecretString.codeUnits);
    return secretAsUint8List;
  }

  static String _getShaForAtSign(String atsign) {
    var bytes = utf8.encode(atsign);
    return sha256.convert(bytes).toString();
  }
}
