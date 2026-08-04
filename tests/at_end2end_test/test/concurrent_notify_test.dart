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
        await ConcurrentClients.open(alice, bob, namespace, authType);
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

  /// Puts [client] on the nskey data path and publishes its namespace key.
  /// The ring needs the client, and the preference is read live, so the config
  /// is set once both exist.
  Future<void> onNskeyPath(AtClient client) async {
    final ring = PublishedNskeyKeyRing(client);
    client.getPreferences()!.crypto = CryptoConfig.nskey(keyRing: ring);
    await ring.mintAndPublish(namespace);
  }

  test('UC-A4.4: providerId travels on the frame and bob decrypts by it',
      timeout: Timeout(Duration(minutes: 3)), () async {
    final clients =
        await ConcurrentClients.open(alice, bob, namespace, authType);
    addTearDown(clients.close);

    // Bob first: alice's pre-pass discovers his published nskey by plookup, so
    // it has to exist before she writes anything to him.
    await onNskeyPath(clients.second);
    await onNskeyPath(clients.first);

    final id = Uuid().v4().split('-').first;
    final key = AtKey()
      ..key = 'nskeynotify$id'
      ..sharedWith = bob
      ..sharedBy = alice
      ..namespace = namespace
      ..metadata = (Metadata()..ttr = 60000);
    const value = 'sealed to a namespace key, delivered by monitor';

    final received = Completer<AtNotification>();
    final subscription = clients.second.notificationService
        .subscribe(regex: 'nskeynotify$id', shouldDecrypt: true)
        .listen((n) {
      if (!received.isCompleted) received.complete(n);
    });
    addTearDown(subscription.cancel);

    final result = await clients.first.notificationService
        .notify(NotificationParams.forUpdate(key, value: value));
    expect(result.notificationStatusEnum, NotificationStatusEnum.delivered);

    final notification = await received.future.timeout(
      Duration(seconds: 60),
      onTimeout: () => throw StateError(
          'Nothing reached $bob\'s monitor within 60s for the nskey path'),
    );

    // The UC's own wording: providerId travels ON THE NOTIFICATION FRAME, not
    // only on stored keys. Read off the frame bob's monitor delivered, which is
    // the only place that can show it.
    expect(notification.metadata?.appMetadata?.providerId,
        symmetricAesGcmCryptoProviderId,
        reason: 'without this on the frame the receiver has nothing to route '
            'by and falls back to legacy, hunting a shared_key a PQ write '
            'never created');

    expect(notification.value, value,
        reason: 'bob opens the content key with HIS nskey private — the record '
            'is alice-owned, so a reader keying its ring by sharedBy would ask '
            'for a private it will never hold');
  });
}
