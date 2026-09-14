import 'dart:async';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/service/notification_service_impl.dart';
import 'package:at_functional_test/src/at_keys_initializer.dart';
import 'package:at_functional_test/src/config_util.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import 'test_utils.dart';

/// A notification sent to a client after its notification service was created,
/// but before its monitor connected, is still delivered.
///
/// A client with fresh storage has no last-received watermark, and a monitor
/// started with no time is delivered nothing sent before `monitor:` went out.
/// An app that notifies a peer and gets a reply in that window must still
/// receive the reply.
void main() {
  TestUtils.isolateStorage('notification_before_monitor_live_test');
  late String receiverAtSign;
  late String senderAtSign;
  const namespace = 'wavi';

  setUpAll(() {
    senderAtSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    receiverAtSign = ConfigUtil.getYaml()['atSign']['secondAtSign'];
  });

  test(
      'a notification sent before a fresh client\'s monitor connects is '
      'delivered once it does', () async {
    final receiverKeys = InMemoryAtKeysIo.holding(receiverAtSign,
        AtEncryptionKeysLoader.getInstance()
            .createAtKeysFromDemoKeys(receiverAtSign));
    await TestUtils.seedIfCredentialless(receiverAtSign, receiverKeys);
    // NOTE: monitorAutoStart off, so nothing — a startup subscriber included —
    // connects the monitor before this test asks it to. Storage of this file's
    // own, so the store holds no watermark.
    final receiver = await Atsign(receiverAtSign).open(
        keys: receiverKeys,
        preference:
            TestUtils.getPreference(receiverAtSign, posture: PqPosture.legacy)
              ..monitorAutoStart = false,
        namespace: namespace,
        storage: TestUtils.storageFor(receiverAtSign));
    addTearDown(receiver.stop);
    final notifications =
        receiver.notificationService as NotificationServiceImpl;
    expect(notifications.monitor.lookUp.isNotifying, isFalse,
        reason: 'precondition: the monitor must not be up yet, or the '
            'notification below is delivered live and this proves nothing '
            'about the window before it connects');

    final sender = (await TestUtils.initAtClient(senderAtSign, namespace,
            posture: PqPosture.legacy))
        .atClient;
    final id = const Uuid().v4().replaceAll('-', '');
    final result = await sender.notificationService.notify(
        NotificationParams.forUpdate(
            AtKey.fromString(
                '$receiverAtSign:reply$id.$namespace$senderAtSign'),
            value: 'a reply sent before the monitor connected'));
    expect(result.notificationStatusEnum, NotificationStatusEnum.delivered,
        reason: 'the atServer took it for a monitor that is not there yet');

    // NOTE: past the second the atServer stamps it with, so "sent before the
    // monitor connected" is not a matter of the same millisecond.
    await Future<void>.delayed(const Duration(seconds: 2));

    final seen = <String>[];
    final received = Completer<AtNotification>();
    final subscription = notifications.subscribe().listen((n) {
      seen.add(n.key);
      if (n.key.contains('reply$id') && !received.isCompleted) {
        received.complete(n);
      }
    });
    addTearDown(subscription.cancel);
    notifications.startListening();

    final notification = await received.future.timeout(
      const Duration(seconds: 60),
      onTimeout: () => throw StateError(
          'the notification sent before the monitor connected never arrived. '
          'A monitor started with no time is delivered nothing sent before '
          '`monitor:` went out.\n  the monitor saw ${seen.length}: $seen'),
    );
    expect(notification.from, senderAtSign);
  }, timeout: Timeout(Duration(minutes: 3)));
}
