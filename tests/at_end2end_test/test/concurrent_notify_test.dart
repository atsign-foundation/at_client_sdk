/// ⚠️ **Without this the file ran at the 30-second default, and the 60-second
/// `onTimeout` below could never fire** — so the diagnostic it carries, which
/// names the two things worth checking, had never once been printed. A test
/// whose own timeout exceeds its budget reports "timed out after 30 seconds"
/// and nothing else, which is what made the 2026-09-09 failure opaque.
///
/// Five minutes is chosen to be uninteresting: the inner timeouts decide, and
/// this only has to be longer than all of them put together.
@Timeout(Duration(minutes: 5))
library;

import 'dart:async';

import 'package:at_client/at_client.dart';
import 'package:at_end2end_test/config/config_util.dart';
import 'package:at_end2end_test/src/concurrent_clients.dart';
import 'package:at_end2end_test/utils/test_constants.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

/// The notification **receive** path, over a live monitor, for the first time.
///
/// Both halves of it have been implemented and unit-covered for a while: the
/// sender stamps `appMetadata.providerId` and the receiver routes by it through
/// `CryptoRuntime.decryptForNotification`. What could never be shown is that a
/// real atServer delivers to a real monitor and the value comes out decrypted,
/// because `AtClientManager` is a singleton whose `setCurrentAtSign` stops the
/// outgoing client and unsets its `notificationService`. The existing
/// `notify_test.dart` works around exactly that: it switches atSigns and polls
/// `notifyList`, which reads the atServer's queue rather than exercising the
/// monitor or the decryption path at all.
///
/// `ConcurrentClients` removes the workaround by giving each atSign its own
/// `AtClientManager`, so both stay live and a subscription taken on one survives
/// the other coming up.
///
/// The same claim over the nskey data path is `test/pq/nskey_notify_test.dart`.
/// It lives apart because it publishes namespace keys, and this suite's CI
/// atSigns are long-lived: nothing that writes post-quantum material may run
/// against them while the design is still being settled.
void main() {
  late String alice;
  late String bob;
  late String authType;
  final namespace = TestConstants.namespace;

  setUpAll(() {
    alice = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    bob = ConfigUtil.getYaml()['atSign']['secondAtSign'];
    authType = ConfigUtil.getYaml()['authType'];
  });

  test('a monitor on bob receives and decrypts what alice sends', () async {
    final clients =
        await ConcurrentClients.open(alice, bob, namespace, authType,
            posture: PqPosture.legacy);
    addTearDown(clients.close);

    // Asserted, not assumed. If the second client coming up had torn the first
    // one down, the notify below would fail somewhere unrelated and the monitor
    // would simply never fire — which reads as a product defect rather than a
    // harness one.
    expect(clients.first.getCurrentAtSign(), alice);
    expect(clients.second.getCurrentAtSign(), bob);
    expect(clients.first.isStopped, isFalse);
    expect(clients.second.isStopped, isFalse);

    final id = Uuid().v4().split('-').first;
    final key = AtKey()
      ..key = 'concurrent$id'
      ..sharedWith = bob
      ..sharedBy = alice
      ..namespace = namespace
      ..metadata = (Metadata()..ttr = 60000);
    const value = 'delivered over a live monitor';

    // Listener before trigger: subscribe returns a broadcast stream and does
    // not replay what it emitted before subscription.
    final received = Completer<AtNotification>();
    final subscription = clients.second.notificationService
        .subscribe(regex: 'concurrent$id', shouldDecrypt: true)
        .listen((n) {
      if (!received.isCompleted) received.complete(n);
    });
    addTearDown(subscription.cancel);

    // ⚠️ **Subscribing is not the listener being ready, and that distinction is
    // the whole of this test.** `subscribe()` returns its stream at once, but
    // the monitor attaches to the atServer asynchronously — measured 2026-09-09,
    // 424ms after the send had already begun. A notification the atServer
    // accepts while no monitor is attached is not delivered to one that
    // attaches later, and this pack does not set `fetchOfflineNotifications`,
    // so nothing goes back for it. The send reports `delivered` either way.
    //
    // This test passed for two months without the wait, on slack it never asked
    // for: the enrollment approval took ten minutes, so these clients had been
    // live for five before the test ran and the monitor was long attached.
    // Making the approval fast removed the slack and the race surfaced at once
    // — it was never the approval's to hide.
    //
    // Polled rather than awaited on `currentListenerStateStream`: that stream
    // does not replay, so a monitor attaching between the flag check and the
    // subscription would be missed. A test about a race should not open one.
    final notifications = clients.second.notificationService;
    final attachDeadline = DateTime.now().add(Duration(seconds: 30));
    while (!notifications.listening) {
      if (DateTime.now().isAfter(attachDeadline)) {
        throw StateError(
            "$bob's monitor did not attach within 30s of subscribing, so the "
            'notification below would race it. This is the harness waiting for '
            'the wire, not a product timeout.');
      }
      await Future.delayed(Duration(milliseconds: 100));
    }

    final result = await clients.first.notificationService
        .notify(NotificationParams.forUpdate(key, value: value));
    expect(result.notificationStatusEnum, NotificationStatusEnum.delivered);

    final notification = await received.future.timeout(
      Duration(seconds: 60),
      onTimeout: () => throw StateError(
          'No notification reached $bob\'s monitor within 60s. The atServer '
          'accepted it (status was delivered), so either the monitor is not '
          'running or this client\'s notificationService was replaced — the '
          'latter is what the singleton used to do.'),
    );

    expect(notification.from, alice);
    expect(notification.to, bob);
    expect(notification.value, value,
        reason: 'the receive path has to decrypt it: the atServer only ever '
            'held ciphertext, so a plaintext match here is the whole of what '
            'this test exists to show');
  });
}
