import 'package:shared_preferences/shared_preferences.dart';

class AtOnboardingBackupService {
  static const _isRemindBackup = "is_remind_backup";
  static const _backupOpenedTime = "backup_opened_time";

  AtOnboardingBackupService._();

  static final AtOnboardingBackupService _instance =
      AtOnboardingBackupService._();

  static AtOnboardingBackupService get instance => _instance;

  ///Did show backupKey screen
  Future<bool> isRemindBackup() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_isRemindBackup) ?? false;
  }

  Future<bool> setRemindBackup({required bool remind}) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.setBool(_isRemindBackup, remind);
  }

  ///Last time backupKey opened
  Future<bool> setBackupOpenedTime({required DateTime dateTime}) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.setInt(_backupOpenedTime, dateTime.millisecondsSinceEpoch);
  }

  Future<DateTime?> getBackupOpenedTime() async {
    final prefs = await SharedPreferences.getInstance();
    final millisecondsSinceEpoch = prefs.getInt(_backupOpenedTime);
    if (millisecondsSinceEpoch != null) {
      return DateTime.fromMillisecondsSinceEpoch(millisecondsSinceEpoch);
    } else {
      return null;
    }
  }

  ///Should show backup key screen
  Future<bool> shouldOpenBackup() async {
    final isRemind = await isRemindBackup();
    final openedTime = await getBackupOpenedTime();
    if (!isRemind) {
      return false;
    }
    if (openedTime == null) {
      return true;
    }
    if (openedTime.day != DateTime.now().day) {
      return true;
    }
    return false;
  }
}
