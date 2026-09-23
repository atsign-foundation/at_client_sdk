import 'dart:async';

import 'package:at_client/at_client.dart';
import 'package:at_client/hive.dart';
import 'package:at_utils/at_logger.dart';

import '../test_utils/ml_dsa_keyfile.dart';

/// Opens a client on an atServer that accepts connections and never answers,
/// starts the work that then waits on it, and returns from `main`.
///
/// Arguments: the arm (`stop` stops the client first, `leave` does not), the
/// port of the silent atServer, and a storage directory. Prints `IN_FLIGHT`
/// with what was waiting, `AFTER_STOP` with how that ended, and `MAIN_RETURNS`
/// as `main` ends, for the test that spawns it to time the exit against.
Future<void> main(List<String> args) async {
  final [arm, port, storagePath] = args;
  AtSignLogger.root_level = 'warning';
  const atSign = '@processexit';

  final client = await Atsign(atSign).open(
    keys: await typedKeyfile(atSign, enrollmentId: 'primary'),
    preference: AtClientPreference(posture: PqPosture.pqReady)
      ..rootDomain = '127.0.0.1'
      ..rootPort = int.parse(port)
      ..namespace = 'exit',
    storage: HiveAtClientStorage(
        atSign: atSign, storagePath: storagePath, closedByClient: true),
    connectBudget: const Duration(milliseconds: 300),
  );
  await client.put(
      AtKey.self('queued', namespace: 'exit', sharedBy: atSign).build(), 'x');
  client.syncService.sync();
  client.notificationService.subscribe(regex: '.*').listen((_) {});
  var inSync = 'pending';
  unawaited(client.syncService.isInSync().then(
      (answer) => inSync = 'answered $answer',
      onError: (Object e) => inSync = 'failed ${e.runtimeType}'));
  await Future<void>.delayed(const Duration(seconds: 1));
  print('IN_FLIGHT isInSync=$inSync '
      'monitor=${client.notificationService.currentListenerState.name}');

  if (arm == 'stop') {
    await client.stop();
    await Future<void>.delayed(Duration.zero);
    print('AFTER_STOP isInSync=$inSync');
  }
  print('MAIN_RETURNS');
}
