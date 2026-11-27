import 'dart:async';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/service/notification_service_impl.dart';
import 'package:at_functional_test/src/config_util.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import 'test_utils.dart';

/// With [NotificationReplay.full] the monitor asks the atServer for everything
/// it still holds for the atSign, by sending `monitor:0`. A notification sent
/// while no monitor was connected is retained and delivered to the next one.
void main() {
  TestUtils.isolateStorage('monitor_replay_full_live_test');
  late String currentAtSign;
  final namespace = 'wavi';

  setUpAll(() async {
    currentAtSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
  });

  test(
      'full replays a notification sent before this notification service '
      'existed', () async {
    final runId = Uuid().v4();
    const sendNamespace = 'fullreplay.wavi';

    // NOTE: a send while no monitor is connected is retained by the atServer.
    // The first client never starts one, so the notification is still there
    // for the second client's monitor to replay.
    final first = (await TestUtils.initAtClient(currentAtSign, namespace,
            posture: PqPosture.legacy,
            preference: TestUtils.getPreference(currentAtSign,
                posture: PqPosture.legacy)
              ..monitorAutoStart = false))
        .atClient;
    final key = AtKey()
      ..key = 'replayed-$runId.$sendNamespace'
      ..sharedBy = currentAtSign
      ..sharedWith = currentAtSign;
    final result = await first.notificationService
        .notify(NotificationParams.forUpdate(key, value: 'retained'));
    expect(result.notificationStatusEnum, NotificationStatusEnum.delivered,
        reason: 'the send itself must succeed');
    await (first as AtClientImpl).stop();

    // The second service is created after the notification was sent. Under
    // `full` its monitor sends `monitor:0`, so the atServer replays it; under
    // `connect` or `resume` the start would be this service's creation time,
    // after the send, and nothing would arrive.
    final second = (await TestUtils.initAtClient(currentAtSign, namespace,
            posture: PqPosture.legacy,
            preference: TestUtils.getPreference(currentAtSign,
                posture: PqPosture.legacy)
              ..monitorAutoStart = false
              ..notificationReplay = const NotificationReplay.full()))
        .atClient;
    final service = second.notificationService as NotificationServiceImpl;
    addTearDown(service.stopAllSubscriptions);
    final arrived = Completer<void>();
    final subscription = service
        .subscribe(regex: '.*\\.$sendNamespace', shouldDecrypt: true)
        .listen((event) {
      if (event.key.contains('replayed-$runId') && !arrived.isCompleted) {
        arrived.complete();
      }
    });
    addTearDown(subscription.cancel);

    service.startListening();
    await awaitMonitorListening(service);
    await arrived.future.timeout(const Duration(seconds: 90),
        onTimeout: () => throw StateError(
            'the notification sent before the monitor started was never '
            'replayed: the monitor did not ask the atServer for everything, '
            'or the atServer no longer held it'));
  }, timeout: const Timeout(Duration(minutes: 4)));
}
