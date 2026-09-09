import 'dart:async';
import 'dart:math';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/manager/monitor.dart';
import 'package:at_client/src/service/notification_service_impl.dart';
import 'package:at_functional_test/src/config_util.dart';
import 'package:at_utils/at_logger.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import 'test_utils.dart';

/// A notification created while the notification connection is down is
/// delivered once the connection returns, against a live atServer.
///
/// NOTE: this does not discriminate a watermark that never advances. A frozen
/// watermark holds an EARLIER value, which makes the atServer replay a
/// superset, so the notification arrives anyway; only a still-null watermark
/// loses it, and a full pack has already seeded this atSign's record.
///
/// NOTE: one atSign, notifying itself. `setCurrentAtSign` tears the previous
/// client down, so a second client for the sender would stop this one's
/// notification listener. Sending is unaffected by the monitor connection
/// being down, because a notify travels the verb connection.
void main() {
  TestUtils.isolateStorage('monitor_reconnect_live_test');
  late AtClientManager atClientManager;
  late String currentAtSign;
  final namespace = 'wavi';
  late AtSignLogger logger;

  setUpAll(() async {
    currentAtSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    logger = AtSignLogger(' monitor_reconnect_live_test ');
    atClientManager = await TestUtils.initAtClient(currentAtSign, namespace,
        posture: PqPosture.legacy);
    atClientManager.atClient.syncService.sync();
  });

  test(
      'a notification sent while the connection is down arrives after the '
      'reconnect', () async {
    final id = Uuid().v4();
    const sendNamespace = 'reconnectlive.wavi';
    final sentValue = 'reconnect-live-${Random().nextInt(1000000)}';
    final client = atClientManager.atClient;

    final received = Completer<String>();
    final seen = <String>[];
    final subscription = client.notificationService
        .subscribe(regex: '.*\\.$sendNamespace', shouldDecrypt: true)
        .listen((event) {
      seen.add(event.key);
      if (event.key.contains(id) && !received.isCompleted) {
        received.complete(event.value ?? '');
      }
    });

    // Gets past the first-call-returns-null branch, so the reconnect below has
    // a watermark to resume from.
    final service = client.notificationService as NotificationServiceImpl;
    await service.getLastNotificationTime();

    // NOTE: the monitor has to be demonstrably up before the connection is
    // dropped, or "it reconnected" and "it never connected" look the same.
    final Monitor monitor = service.monitor;
    for (var i = 0; i < 60 && !monitor.lookUp.isNotifying; i++) {
      await Future.delayed(Duration(milliseconds: 250));
    }
    expect(monitor.lookUp.isNotifying, isTrue,
        reason: 'the monitor never came up, so nothing below would be '
            'measuring a reconnect');
    await Future.delayed(Duration(seconds: 2));

    // Destroying the socket is what a far end going away looks like from here,
    // and the muxable owns the reconnect that follows.
    logger.info('closing the notification connection');
    await monitor.lookUp.close();

    // Sent while the notification connection is down.
    final key = AtKey()
      ..key = '$id.$sendNamespace'
      ..sharedBy = currentAtSign
      ..sharedWith = currentAtSign;
    final result = await client.notificationService
        .notify(NotificationParams.forUpdate(key, value: sentValue));
    expect(result.notificationStatusEnum, NotificationStatusEnum.delivered,
        reason: 'the send itself must succeed while the notification '
            'connection is down - it travels the verb connection');
    logger.info('notified while the notification connection was down');

    final value = await received.future.timeout(Duration(seconds: 90),
        onTimeout: () => throw StateError(
            'the notification never arrived, and the notify above reported '
            '`delivered`. Either the connection did not come back, or it came '
            'back with a watermark that skipped what was sent while it was '
            'down.\n  the monitor saw ${seen.length}: $seen'));

    expect(value, sentValue,
        reason: 'a notification created during an outage must survive it: the '
            'reconnect re-issues monitor: with the watermark this client has '
            'reached, and the atServer replays from there');

    await subscription.cancel();
  }, timeout: Timeout(Duration(minutes: 4)));
}
