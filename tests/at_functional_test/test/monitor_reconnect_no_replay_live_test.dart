import 'dart:async';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/manager/monitor.dart';
import 'package:at_client/src/service/notification_service_impl.dart';
import 'package:at_functional_test/src/config_util.dart';
import 'package:at_utils/at_logger.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import 'test_utils.dart';

/// With [AtClientPreference.fetchOfflineNotifications] false, a notification
/// delivered before the notification connection drops is not delivered again
/// after the reconnect, against a live atServer.
///
/// NOTE: one atSign, notifying itself. `TestUtils.initAtClient` stops the
/// client that was current, so a second client for the sender would stop this
/// one's notification listener.
void main() {
  TestUtils.isolateStorage('monitor_reconnect_no_replay_live_test');
  late AtClientManager atClientManager;
  late String currentAtSign;
  final namespace = 'wavi';
  late AtSignLogger logger;

  setUpAll(() async {
    currentAtSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    logger = AtSignLogger(' monitor_reconnect_no_replay_live_test ');
    atClientManager = await TestUtils.initAtClient(currentAtSign, namespace,
        posture: PqPosture.legacy,
        preference:
            TestUtils.getPreference(currentAtSign, posture: PqPosture.legacy)
              ..fetchOfflineNotifications = false);
    atClientManager.atClient.syncService.sync();
  });

  test(
      'a notification delivered before the connection drops is not delivered '
      'again after the reconnect', () async {
    final runId = Uuid().v4();
    const sendNamespace = 'reconnectnoreplay.wavi';
    final client = atClientManager.atClient;

    final seen = <String>[];
    final arrivals = {'first': Completer<void>(), 'second': Completer<void>()};
    final subscription = client.notificationService
        .subscribe(regex: '.*\\.$sendNamespace', shouldDecrypt: true)
        .listen((event) {
      seen.add(event.key);
      for (final arrival in arrivals.entries) {
        if (event.key.contains('${arrival.key}-$runId') &&
            !arrival.value.isCompleted) {
          arrival.value.complete();
        }
      }
    });

    Future<void> notifyAndAwait(String label) async {
      final key = AtKey()
        ..key = '$label-$runId.$sendNamespace'
        ..sharedBy = currentAtSign
        ..sharedWith = currentAtSign;
      final result = await client.notificationService
          .notify(NotificationParams.forUpdate(key, value: label));
      expect(result.notificationStatusEnum, NotificationStatusEnum.delivered,
          reason: 'the $label send itself must succeed');
      await arrivals[label]!.future.timeout(Duration(seconds: 90),
          onTimeout: () =>
              throw StateError('the $label notification never arrived.\n'
                  '  the monitor saw ${seen.length}: $seen'));
    }

    // NOTE: the monitor has to be demonstrably up before the connection is
    // dropped, or "it reconnected" and "it never connected" look the same.
    final service = client.notificationService as NotificationServiceImpl;
    final Monitor monitor = service.monitor;
    for (var i = 0; i < 60 && !monitor.lookUp.isNotifying; i++) {
      await Future.delayed(Duration(milliseconds: 250));
    }
    expect(monitor.lookUp.isNotifying, isTrue,
        reason: 'the monitor never came up, so nothing below would be '
            'measuring a reconnect');
    await Future.delayed(Duration(seconds: 2));

    await notifyAndAwait('first');

    logger.info('closing the notification connection');
    await monitor.lookUp.close();

    // Arrives only once the connection has come back.
    await notifyAndAwait('second');

    // Leaves time for the reconnect's replay to deliver anything again.
    await Future.delayed(Duration(seconds: 3));

    expect(seen.where((k) => k.contains('first-$runId')), hasLength(1),
        reason: 'the reconnect re-issues monitor: from the latest notification '
            'this client received, so the atServer replays none of what it '
            'already delivered.\n  the monitor saw ${seen.length}: $seen');

    await subscription.cancel();
  }, timeout: Timeout(Duration(minutes: 4)));
}
