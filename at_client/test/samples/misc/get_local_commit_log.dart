import 'dart:async';
import 'dart:io';
import 'package:at_client/src/client/at_client_impl.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import '../test_util.dart';

void main() async {
  await AtClientImpl.createClient(
      '@alice🛠', 'me', TestUtil.getAlicePreference());
  var commitLog = await (AtCommitLogManagerImpl.getInstance().getCommitLog(
      '@alice🛠',
      commitLogPath: TestUtil.getAlicePreference().commitLogPath));
  var entries = commitLog!.getChanges(-1, '');
  print(entries);
  var entry = commitLog.lastSyncedEntry();
  print(entry);
  exit(1);
}
