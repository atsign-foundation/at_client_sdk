// The nskey surface is @experimental; driving it from another package is the
// point of this file.
// ignore_for_file: experimental_member_use
@Tags(['pq'])
library;

import 'dart:async';

import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
// The monitor's socket is what an outage takes away, and nothing public
// reaches it.
// ignore: implementation_imports
import 'package:at_client/src/service/notification_service_impl.dart';
import 'package:at_end2end_test/config/config_util.dart';
import 'package:at_end2end_test/src/concurrent_clients.dart';
import 'package:at_end2end_test/src/enrolled_client.dart';
import 'package:at_end2end_test/src/test_preferences.dart';
import 'package:at_end2end_test/utils/test_constants.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

/// The notification receive path with the record sealed to a namespace key.
///
/// Publishes namespace keys for both atSigns, so it writes post-quantum
/// material into whichever atServers it runs against — the reason it lives
/// under `test/pq/` and never runs against the long-lived CI atSigns.
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
  Future<void> onNskeyPath(AtClient client) async {
    final ring = PublishedNskeyKeyRing(client);
    client.getPreferences()!.crypto = CryptoConfig.nskey(keyRing: ring);
    await ring.mintAndPublish(namespace);
  }

  test(
      'UC-A4.4: providerId travels on the frame and every bob enrollment decrypts by it',
      timeout: Timeout(Duration(minutes: 5)), () async {
    final clients =
        await ConcurrentClients.open(alice, bob, namespace, authType,
            posture: legacyPlusPqProviders);
    addTearDown(clients.close);

    // NOTE: bob first — alice's pre-pass discovers his published nskey by
    // plookup, so it must exist before she writes anything to him.
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

    // A second authorised enrollment of @bob, on a monitor of its own.
    //
    // NOTE: it needs its own storage path — two monitors of one atSign sharing
    // a store share the notification replay watermark, the record that decides
    // what a reconnecting monitor asks the atServer for.
    await AtClientSecretSharing.forClient(clients.second).register();
    final bobPreference = clients.second.getPreferences()!;
    final bobSecond = await enrolAndAuthenticate(
      approver: clients.second,
      atSign: bob,
      namespace: namespace,
      preference: TestPreferences.getInstance()
          .forCoLocatedClient(bob, posture: legacyPlusPqProviders, device: 'bob2-$id'),
      rootDomain: bobPreference.rootDomain,
      rootPort: bobPreference.rootPort,
      deviceName: 'bob2-$id',
    );
    addTearDown(bobSecond.client.stop);
    expect(identical(bobSecond.client, clients.second), isFalse,
        reason: 'the second enrollment must be a genuinely different client, '
            'or this reads one monitor twice');

    // NOTE: this enrollment only reads, so it mints nothing — @bob's
    // generation is published already and a second mint here would rotate it.
    bobSecond.client.getPreferences()!.crypto = CryptoConfig.nskey(
        keyRing: PublishedNskeyKeyRing(bobSecond.client));

    final secondSeen = <String>[];
    final secondReceived = Completer<AtNotification>();
    final secondMonitorLive = Completer<void>();
    // NOTE: declared here because the listener must be watching before the
    // notification it waits for is sent, and that send happens after this
    // monitor's socket has been taken away.
    final queued = Completer<AtNotification>();
    final secondSubscription = bobSecond.client.notificationService
        .subscribe(shouldDecrypt: true)
        .listen((n) {
      secondSeen.add(n.key);
      if (!secondMonitorLive.isCompleted) secondMonitorLive.complete();
      if (n.key.contains('nskeynotify$id') && !secondReceived.isCompleted) {
        secondReceived.complete(n);
      }
      if (n.key.contains('queued$id') && !queued.isCompleted) {
        queued.complete(n);
      }
    });
    addTearDown(secondSubscription.cancel);

    // NOTE: `subscribe()` returns before the monitor's socket has connected,
    // PKAMed and written `monitor:`, and the monitor asks for no backlog, so a
    // notification created in that window never reaches this connection.
    // `currentListenerState == listening` does not close that window either —
    // it is set straight after the command is written. A notification actually
    // arriving does, and the atServer's periodic stats notification supplies
    // one.
    await secondMonitorLive.future.timeout(
      Duration(seconds: 90),
      onTimeout: () => throw StateError(
          'no notification of any kind reached the second enrollment within '
          '90s, so its monitor is not up; notifying now would repeat the race '
          'this gate exists to close'),
    );

    final result = await clients.first.notificationService
        .notify(NotificationParams.forUpdate(key, value: value));
    expect(result.notificationStatusEnum, NotificationStatusEnum.delivered);

    final notification = await received.future.timeout(
      Duration(seconds: 60),
      onTimeout: () => throw StateError(
          'Nothing reached $bob\'s monitor within 60s for the nskey path'),
    );

    expect(notification.metadata?.appMetadata?.providerId,
        symmetricAesGcmCryptoProviderId,
        reason: 'without this on the frame the receiver has nothing to route '
            'by and falls back to legacy, hunting a shared_key a PQ write '
            'never created');

    expect(notification.value, value,
        reason: 'bob opens the content key with HIS nskey private — the record '
            'is alice-owned, so a reader keying its ring by sharedBy would ask '
            'for a private it will never hold');

    // The same notification, on @bob's other enrollment, which holds no nskey
    // private of its own: the fixture gives each enrollment an in-memory
    // AtKeysIo, so opening this value means the namespace private reached it
    // by conveyance.
    final second = await secondReceived.future.timeout(
      Duration(seconds: 90),
      onTimeout: () => throw StateError(
          'the notification reached one of @bob\'s enrollments and not the '
          'other within 90s. That monitor is live — it was gated on a '
          'notification arriving — and it saw: $secondSeen'),
    );

    expect(second.metadata?.appMetadata?.providerId,
        symmetricAesGcmCryptoProviderId,
        reason: 'the frame carries the same routing to every enrollment; a '
            'receiver handed no providerId falls back to legacy and hunts a '
            'shared_key a PQ write never created');
    expect(second.value, value,
        reason: 'and it DECRYPTS on the second enrollment, which is the '
            'clause: the content key is sealed to (owner, namespace), so '
            'every authorised enrollment of @bob opens it and none is left '
            'out. Sealing per device would deliver to both monitors and '
            'decrypt on only one');

    // Offline, then online: a content key sealed to @bob's namespace key while
    // his monitor was down still opens on his return. Deliberately last, so
    // the pair is known good before the connection is taken away.
    final secondNotifications =
        bobSecond.client.notificationService as NotificationServiceImpl;
    expect(secondNotifications.monitor.lookUp.isNotifying, isTrue,
        reason: 'the monitor must be demonstrably up before it is dropped, or '
            '"it reconnected" and "it never connected" are the same green');
    // NOTE: `isNotifying` cannot tell whether the socket went away — it is a
    // session flag, cleared only by `stopNotifications`, so it stays true
    // across the drop staged here. The connection stream is a broadcast with
    // no backlog, so the watch goes on before the close.
    final connectionEvents = <bool>[];
    final wentDown = Completer<void>();
    final connectionWatch = secondNotifications.monitor.lookUp
        .notificationConnectionUp
        .listen((up) {
      connectionEvents.add(up);
      if (!up && !wentDown.isCompleted) wentDown.complete();
    });
    addTearDown(connectionWatch.cancel);

    await secondNotifications.monitor.lookUp.close();

    await wentDown.future.timeout(
      Duration(seconds: 30),
      onTimeout: () => throw StateError(
          'closing the monitor socket emitted no connection-down event, so '
          'there was no outage — and without one the arm below is green '
          'either way: a notification handed to a live monitor and one '
          'replayed to a reconnecting one satisfy the same assertion. '
          'Saw: $connectionEvents'),
    );

    final queuedKey = AtKey()
      ..key = 'queued$id'
      ..sharedWith = bob
      ..sharedBy = alice
      ..namespace = namespace
      ..metadata = (Metadata()..ttr = 60000);
    const queuedValue = 'sealed while bob had no monitor';

    expect(
        (await clients.first.notificationService
                .notify(NotificationParams.forUpdate(queuedKey,
                    value: queuedValue)))
            .notificationStatusEnum,
        NotificationStatusEnum.delivered,
        reason: 'the send must succeed while the receiving enrollment has no '
            'monitor at all — it does not travel that connection');

    final afterOutage = await queued.future.timeout(
      Duration(seconds: 120),
      onTimeout: () => throw StateError(
          'the notification @alice sent while @bob\'s second enrollment was '
          'disconnected never arrived, and the notify reported `delivered`. '
          'Either the monitor did not come back, or it came back with a '
          'watermark asking only for what followed the reconnect.\n'
          '  the monitor saw ${secondSeen.length}: $secondSeen'),
    );

    expect(afterOutage.metadata?.appMetadata?.providerId,
        symmetricAesGcmCryptoProviderId,
        reason: 'it must come back on the nskey data path, or the value below '
            'could decrypt for a reason that has nothing to do with the '
            'namespace key');
    expect(connectionEvents.first, isFalse,
        reason: 'the first thing this watcher saw was the connection going '
            'down, and it was installed immediately before the close');
    expect(connectionEvents.skip(1), contains(true),
        reason: 'and it came back up — so the delivery above is a replay to a '
            'reconnecting monitor, not a live hand-off. Saw: '
            '$connectionEvents');

    expect(afterOutage.value, queuedValue,
        reason: 'offline-then-online @bob still decrypts the queued '
            'notification. The nskey private this enrollment holds opens a '
            'content key @alice sealed while it was disconnected. ⚠️ This is '
            'an outage of the CONNECTION, not of the process — it says '
            'nothing about the private surviving a restart, which is a '
            'separate claim belonging to the filing tests');
  });
}
