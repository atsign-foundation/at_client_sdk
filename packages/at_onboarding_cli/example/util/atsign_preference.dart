import 'package:at_client/at_client.dart';
import 'package:at_client/hive.dart';
import 'package:at_onboarding_cli/src/util/home_directory_util.dart';

class AtSignPreference {
  static AtClientPreference getAlicePreference() {
    var preference = AtClientPreference();
    preference.rootDomain = 'vip.ve.atsign.zone';
    return preference;
  }

  /// The Hive store under the user's home for [atSign] as [enrollmentId],
  /// closed by the client that opens it.
  static AtClientStorage getAliceStorage(String atSign, String enrollmentId) =>
      HiveAtClientStorage(
          atSign: atSign,
          storagePath: HomeDirectoryUtil.getHiveStoragePath(atSign,
              enrollmentId: enrollmentId),
          closedByClient: true);
}
