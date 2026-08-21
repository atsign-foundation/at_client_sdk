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

/// What a reconnect does to the notification watermark, against a live
/// atServer.
///
/// The unit tests pin that the muxable asks the caller for its watermark on
/// every connect and puts the answer on the wire. What they cannot show is the
/// consequence, because it is the atServer that acts on it: a notification
/// created while the connection is down is delivered once the connection
/// returns, and it is delivered *because* the re-issued `monitor:` carried a
/// watermark from before it was sent. A watermark that did not advance would
/// ask only for what came after the reconnect, and this notification would be
/// lost with no error anywhere.
///
/// ⚠️ This is the only live coverage of a notification connection being
/// re-established at all — `_openNotificationStream` otherwise runs exactly
/// once per test process — so it also exercises reauthentication on the second
/// connection.
///
/// ⚠️ **What this does NOT discriminate, so nobody over-trusts the green.**
/// It would still pass with a watermark that never advanced. A frozen
/// watermark holds an EARLIER value, and an earlier value makes the atServer
/// replay a superset — so the notification below would arrive anyway. The case
/// that separates them is a client whose watermark is still null, where a
/// frozen null asks for nothing and the notification is lost; that state is
/// not reachable in a full pack, because earlier files have already seeded
/// this atSign's watermark record. The advancing behaviour itself is
/// discriminated by unit tests: `muxable_notifications_test.dart`'s "a
/// reconnect asks the caller for its CURRENT watermark" and at_client's
/// "hands down a LIVE watermark source, not a value read once", both of which
/// go red when the value is frozen. What this test adds is the end-to-end
/// consequence: the connection really comes back, really reauthenticates, and
/// a notification created during the outage really is delivered.
///
/// ⚠️ **One atSign, notifying itself, deliberately.** A two-atSign version
/// cannot work here: `setCurrentAtSign` tears the previous client down, so
/// switching to a sender stops the receiver's notification listener — measured,
/// and the `stopListening()` it logs is immediate. Self-notification keeps one
/// client for the whole test, and sending is unaffected by the monitor
/// connection being down because a notify travels the verb connection, which
/// is a different socket.
void main() {
  late AtClientManager atClientManager;
  late String currentAtSign;
  final namespace = 'wavi';
  late AtSignLogger logger;

  setUpAll(() async {
    currentAtSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    logger = AtSignLogger(' monitor_reconnect_live_test ');
    atClientManager = await TestUtils.initAtClient(currentAtSign, namespace);
    atClientManager.atClient.syncService.sync();
  });

  test('a notification sent while the connection is down arrives after the '
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
    // a watermark to resume from whether or not an earlier file in the pack
    // has already seeded this atSign's record. Belt and braces: in a full pack
    // it is normally seeded already.
    final service = client.notificationService as NotificationServiceImpl;
    await service.getLastNotificationTime();

    // The monitor has to be demonstrably up before the connection is dropped,
    // or "it reconnected" and "it never connected" look the same. The atServer
    // decides when it considers this connection a subscriber and that instant
    // is recorded only on its side, so wait for real traffic rather than a
    // local flag.
    final Monitor monitor = service.monitor;
    for (var i = 0; i < 60 && !monitor.lookUp.isNotifying; i++) {
      await Future.delayed(Duration(milliseconds: 250));
    }
    expect(monitor.lookUp.isNotifying, isTrue,
        reason: 'the monitor never came up, so nothing below would be '
            'measuring a reconnect');
    await Future.delayed(Duration(seconds: 2));

    // Drop the connection out from under the monitor. `close()` destroys the
    // socket, which is what a far end going away looks like from here, and the
    // muxable owns the reconnect that follows.
    logger.info('closing the notification connection');
    await monitor.lookUp.close();

    // Sent while it is down, on the verb connection. This is the whole point:
    // with a watermark that does not advance, the re-issued `monitor:` asks
    // for nothing from before the reconnect and this never arrives.
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
