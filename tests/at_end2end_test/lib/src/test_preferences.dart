import 'package:at_client/at_client.dart';
import 'package:at_end2end_test/config/config_util.dart';
import 'package:at_end2end_test/utils/test_constants.dart';
import 'at_credentials.dart';

class TestPreferences {
  final atClientPreferencesMap = <String, AtClientPreference>{};

  static final TestPreferences _singleton = TestPreferences._internal();

  TestPreferences._internal();

  factory TestPreferences.getInstance() {
    return _singleton;
  }

  AtClientPreference getPreference(String atSign) {
    // If the atClientPreferenceMap contains the atSign, return the preferences
    if (atClientPreferencesMap.containsKey(atSign)) {
      return atClientPreferencesMap[atSign]!;
    }
    // Else create new preferences instance and add it to the map
    var atClientPreference = AtClientPreference();
    atClientPreference.hiveStoragePath = 'test/hive/client';
    atClientPreference.commitLogPath = 'test/hive/client/commit';
    atClientPreference.isLocalStoreRequired = true;
    atClientPreference.rootDomain = ConfigUtil.getYaml()['root_server']['url'];
    atClientPreferencesMap.putIfAbsent(atSign, () => atClientPreference);
    return atClientPreference;
  }
}
