// The nskey surface is @experimental; driving it from another package is the
// point of this file.
// ignore_for_file: experimental_member_use
@Tags(['pq'])
library;

import 'dart:async';

import 'package:at_client/at_client.dart';
import 'package:at_end2end_test/config/config_util.dart';
import 'package:at_end2end_test/src/concurrent_clients.dart';
import 'package:at_end2end_test/utils/test_constants.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

/// The notification receive path with the record sealed to a namespace key.
///
/// Split out of `concurrent_notify_test.dart`, which keeps the legacy half of
/// the same claim. This half publishes namespace keys for both atSigns, so it
/// writes post-quantum material into whichever atServers it runs against — the
/// reason it lives under `test/pq/` and never runs against the long-lived CI
/// atSigns.
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
