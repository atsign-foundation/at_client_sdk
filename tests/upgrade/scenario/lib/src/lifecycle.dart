import 'dart:async';

import 'package:at_client/at_client.dart' show AtClient, NotificationParams;
import 'package:at_commons/at_commons.dart' show AtKey;

/// Syncs [client] until it reports itself in sync, or [timeout] passes.
Future<bool> syncUntilInSync(AtClient client,
    {Duration timeout = const Duration(seconds: 90)}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    client.syncService.sync();
    await Future<void>.delayed(const Duration(seconds: 2));
    if (!client.syncService.isSyncInProgress &&
        await client.syncService.isInSync()) {
      return true;
    }
  }
  return false;
}

/// Sends [client] a notification from itself and waits for it to arrive,
/// which leaves a notification watermark in its store.
Future<bool> notifySelfAndWait(AtClient client,
    {required String me,
    required String namespace,
    Duration timeout = const Duration(seconds: 60)}) async {
  final arrived = client.notificationService
      .subscribe(regex: 'upgnote\\.$namespace', shouldDecrypt: true)
      .first
      .timeout(timeout)
      .then((_) => true, onError: (_) => false);
  final key = AtKey()
    ..key = 'upgnote'
    ..namespace = namespace
    ..sharedBy = me
    ..sharedWith = me;
  await client.notificationService
      .notify(NotificationParams.forUpdate(key, value: 'upgrade'));
  return arrived;
}
