import 'dart:async';
import 'dart:io';
import 'package:at_client/at_client.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import '../test_util.dart';

void main() async {
  var atsign = '@alice';
  await AtClientManager.getInstance()
      .setCurrentAtSign(atsign, 'me', TestUtil.getPreferenceLocal());
  var commitLog = await (AtCommitLogManagerImpl.getInstance().getCommitLog(
          atsign,
          commitLogPath: TestUtil.getPreferenceLocal().commitLogPath)
      as FutureOr<AtCommitLog>);
  var entry = await (commitLog.getEntry(5) as FutureOr<CommitEntry>);
  await commitLog.update(entry, 5);
  exit(1);
}
