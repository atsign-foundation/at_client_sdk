import 'dart:io';
import 'package:at_client/at_client.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import '../test_util.dart';

void main() async {
  var atsign = '@alice';
  await AtClientManager.getInstance()
      .setCurrentAtSign(atsign, 'me', TestUtil.getPreferenceLocal());
  final prefs = TestUtil.getPreferenceLocal();
  final factory = HiveAtPersistenceFactory();
  final bundle = await factory.initialize(
    atsign,
    HivePersistenceConfig(
      storagePath: prefs.hiveStoragePath!,
      commitLogPath: prefs.commitLogPath!,
      accessLogPath: prefs.commitLogPath!,
      notificationStoragePath: prefs.hiveStoragePath!,
    ),
  );
  final commitLog = bundle.commitLog;
  var entries = commitLog.getChanges(-1, '');
  print(entries);
  var entry = commitLog.lastSyncedEntry();
  print(entry);
  exit(1);
}
