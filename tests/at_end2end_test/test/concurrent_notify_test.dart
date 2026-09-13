/// Longer than every inner timeout here, so those decide and can print their
/// diagnostics: at the 30-second default the 60-second `onTimeout` below could
/// never fire.
@Timeout(Duration(minutes: 5))
library;

import 'dart:async';

import 'package:at_client/at_client.dart';
import 'package:at_end2end_test/config/config_util.dart';
import 'package:at_end2end_test/src/concurrent_clients.dart';
import 'package:at_end2end_test/utils/test_constants.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

/// The notification receive path over a live monitor: the sender stamps
/// `appMetadata.providerId`, a real atServer delivers to a real monitor, and
/// the receiver routes by that id to hand the test back a decrypted value.
///
/// `AtClientManager` is a singleton whose switch stops the outgoing client,
/// so `ConcurrentClients` gives each atSign its own manager and a subscription
/// taken on one survives the other coming up.
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
    final clients = await ConcurrentClients.open(
        alice, bob, namespace, authType,
        posture: PqPosture.legacy);
    addTearDown(clients.close);

    // NOTE: without these, a second client that tore the first one down would
    // show up as a monitor that never fires, reading as a product defect
    // rather than a harness one.
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

    // NOTE: listener before trigger — subscribe returns a broadcast stream and
    // does not replay what it emitted before subscription.
    final received = Completer<AtNotification>();
    final subscription = clients.second.notificationService
        .subscribe(regex: 'concurrent$id', shouldDecrypt: true)
        .listen((n) {
      if (!received.isCompleted) received.complete(n);
    });
    addTearDown(subscription.cancel);

    // NOTE: subscribing is not the listener being ready — the monitor attaches
    // asynchronously, and a notification the atServer accepts before it
    // attaches is reported `delivered` and never handed to it. Polled rather
    // than awaited on `currentListenerStateStream`, which does not replay an
    // attach happening between the check and the subscription.
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
