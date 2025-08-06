import 'package:at_client/src/preference/at_client_preference.dart';
import 'package:at_onboarding_cli/src/util/home_directory_util.dart';

class AtSignPreference {
  static AtClientPreference getAlicePreference(
      String atSign, String enrollmentId) {
    var preference = AtClientPreference();
    preference.hiveStoragePath = HomeDirectoryUtil.getHiveStoragePath(atSign,
        enrollmentId: enrollmentId);
    preference.commitLogPath =
        HomeDirectoryUtil.getCommitLogPath(atSign, enrollmentId: enrollmentId);
    preference.isLocalStoreRequired = true;
    preference.rootDomain = 'vip.ve.atsign.zone';
    return preference;
  }
}
