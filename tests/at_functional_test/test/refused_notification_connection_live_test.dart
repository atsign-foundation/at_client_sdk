library;

import 'dart:async';

import 'package:at_client/at_client.dart';
import 'package:at_functional_test/src/config_util.dart';
import 'package:at_functional_test/src/enrolled_client.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import 'test_utils.dart';

/// A client listening for notifications whose enrollment is revoked and then
/// restored, against a live atServer.
///
/// The test shares its title with
/// `features/at_client/refused_notification_connection.feature`. The revoked
/// enrollment is this file's own, with a run-unique device name in a
/// run-unique namespace, so no other file's client or roster sees the revoke.
void main() {
  TestUtils.isolateStorage('refused_notification_connection_live_test');
  late String atSign;
  late AtClient owner;
  late AtClient listener;
  final runId = DateTime.now().microsecondsSinceEpoch;
  // NOTE: a namespace of its own, because a client start asks every
  // enrollment holding its namespace for the keys it lacks.
  final namespace = 'refused$runId';
  const rootDomain = 'vip.ve.atsign.zone';

  setUpAll(() async {
    atSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    final keysIo = InMemoryAtKeysIo();
    await keysIo.write(atSign, AtKeys());
    owner = (await TestUtils.initAtClient(atSign, namespace,
            atKeysIo: keysIo, posture: legacyPlusPqProviders))
        .atClient;
    listener = (await enrolAndAuthenticate(
      approver: owner,
      atSign: atSign,
      namespace: namespace,
      preference: TestUtils.getPreference(atSign, posture: PqPosture.legacy),
      rootDomain: rootDomain,
      rootPort: TestUtils.rootServerPort,
      deviceName: 'refused-$runId',
      storage: TestUtils.storage,
    ))
        .client;
  });

  tearDownAll(() async {
    await listener.stop();
    await owner.stop();
  });

  /// Waits until [condition] holds, failing with [what] after [within].
  Future<void> until(bool Function() condition, String what,
      {Duration within = const Duration(seconds: 60)}) async {
    final deadline = DateTime.now().add(within);
    while (!condition()) {
      if (DateTime.now().isAfter(deadline)) {
        fail('$what did not happen within $within; the connection reads '
            '${listener.connection.current}');
      }
      await Future.delayed(const Duration(milliseconds: 250));
    }
  }

  bool listening() =>
      listener.notificationService.currentListenerState ==
      NotificationListenerState.listening;

  test('an app keeps its notifications through a refusal that clears',
      () async {
    final id = const Uuid().v4();
    final seen = <String>[];
    final arrived = Completer<void>();
    final subscription = listener.notificationService
        .subscribe(regex: '.*\\.$namespace', shouldDecrypt: false)
        .listen((notification) {
      seen.add(notification.key);
      if (notification.key.contains(id) && !arrived.isCompleted) {
        arrived.complete();
      }
    });
    addTearDown(subscription.cancel);
    await until(listening, 'the listener connecting');
    final enrollmentId = listener.enrollmentId!;

    await owner.enrollments.revoke(enrollmentId);
    await until(() => !listening(),
        "the revoked listener's notification connection dropping");
    await until(() => listener.connection.current.isRefused,
        'the revoked listener reading refused');
    expect(listener.connection.current.cause, AtConnectionCause.revoked,
        reason: 'the atServer refuses a revoked enrollment as revoked');
    expect(listening(), isFalse,
        reason: 'the atServer refuses every reconnect of the revoked '
            'listener, so its notification connection stays down');

    await owner.enrollments.unrevoke(enrollmentId);
    await until(listening, 'the restored listener reconnecting',
        within: const Duration(minutes: 2));

    final key = AtKey()
      ..key = '$id.$namespace'
      ..sharedBy = atSign
      ..sharedWith = atSign;
    final sent = await owner.notificationService
        .notify(NotificationParams.forUpdate(key, value: 'after the refusal'));
    expect(sent.notificationStatusEnum, NotificationStatusEnum.delivered);

    await arrived.future.timeout(const Duration(seconds: 60),
        onTimeout: () => fail('the subscription taken before the revoke '
            'never received the notification sent after the unrevoke; it saw '
            '$seen'));
    expect(listener.connection.current.isOnline, isTrue,
        reason: 'the listener is accepted again, so its connection is online');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
