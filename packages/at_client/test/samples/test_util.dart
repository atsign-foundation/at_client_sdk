import 'package:at_client/src/preference/at_client_preference.dart';

class TestUtil {
  static AtClientPreference getPreferenceRemote() {
    var preference = AtClientPreference();
    preference.rootDomain = 'vip.ve.atsign.zone';
    return preference;
  }

  static AtClientPreference getPreferenceLocal() {
    var preference = AtClientPreference();
    preference.hiveStoragePath = 'hive/client';
    preference.rootDomain = 'test.do-sf2.atsign.zone';
    return preference;
  }

  static AtClientPreference getAlicePreference() {
    var preference = AtClientPreference();
    preference.hiveStoragePath = '/home/murali/work/2020/hive/client';
    preference.rootDomain = 'vip.ve.atsign.zone';
    return preference;
  }

  static AtClientPreference getBobPreference() {
    var preference = AtClientPreference();
    preference.hiveStoragePath = '/home/murali/work/2020/hive/client';
    preference.rootDomain = 'vip.ve.atsign.zone';
    return preference;
  }
}
