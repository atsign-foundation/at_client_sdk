import 'dart:io';
import 'package:at_client/src/client/at_client_impl.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import '../test_util.dart';

void main() async {
  await AtClientImpl.createClient('@jagan','me', TestUtil.getPreferenceLocal());
  var commitLog = AtCommitLog.getInstance();
  var entry = await commitLog.getEntry(5);
  await commitLog.update(entry, 5);
  exit(1);
}
