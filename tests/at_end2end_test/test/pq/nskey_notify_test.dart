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

  test(
      'UC-A4.4: providerId travels on the frame and every bob enrollment decrypts by it',
      timeout: Timeout(Duration(minutes: 5)), () async {
    final clients =
        await ConcurrentClients.open(alice, bob, namespace, authType,
            posture: legacyPlusPqProviders);
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

    // A second authorised enrollment of @bob, on a monitor of its own. The
    // clause says the value decrypts on EVERY authorised bob enrollment, and
    // one client cannot show that: a design sealing per device would deliver
    // to both monitors and decrypt on only one, which is exactly the failure
    // a single-client test cannot see.
    //
    // Its own storage path, because two monitors of one atSign sharing a store
    // share the notification replay watermark — the record that decides what a
    // reconnecting monitor asks the atServer for.
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

    // Reading is all this enrollment does, so it mints nothing: @bob's
    // generation is already published and a second mint here would rotate it.
    bobSecond.client.getPreferences()!.crypto = CryptoConfig.nskey(
        keyRing: PublishedNskeyKeyRing(bobSecond.client));

    // No `regex:` on this one, deliberately — a regex is a second thing that
    // can be wrong, and a wrong one fails identically to a notification that
    // never arrived. Everything delivered is recorded, so "nothing arrived"
    // can be told apart from "everything except this arrived".
    final secondSeen = <String>[];
    final secondReceived = Completer<AtNotification>();
    final secondMonitorLive = Completer<void>();
    // Declared here because the listener has to be watching before the
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

    // ⚠️ Listener before trigger, and the listener that matters is the
    // atServer's. `subscribe()` returns before the monitor's socket has
    // connected, PKAMed and written `monitor:`, and the monitor asks for no
    // backlog — so a notification the atServer creates in that window reaches
    // this connection never, which reads exactly like a product defect.
    // `currentListenerState == listening` is not this gate either: it is set
    // straight after writing the command. A notification actually arriving is.
    // The atServer's own `statsNotification` satisfies it every ~11s, which
    // makes it the readiness signal and the positive control at once.
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

    // The same notification, on @bob's other enrollment. It holds no nskey
    // private of its own — the fixture gives each enrollment an in-memory
    // AtKeysIo — so opening this value means the namespace private reached it
    // by conveyance, which is what makes the count of bob's devices the
    // sender's business and not hers.
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

    // ── Offline, then online ─────────────────────────────────────────────
    //
    // The clause's other half: a value sealed while @bob was disconnected
    // still opens when he comes back. `monitor_reconnect_live_test.dart`
    // shows a queued notification surviving an outage, with one atSign
    // notifying itself and no namespace key in it; everything above shows a
    // cross-atSign nskey notification opening, with the monitor up
    // throughout. Neither says that a CK sealed to @bob's namespace key while
    // his monitor was down still opens on his return.
    //
    // Deliberately last: everything above has passed, so the pair is known
    // good before the connection is taken away and a failure here is the
    // outage rather than the fixture.
    final secondNotifications =
        bobSecond.client.notificationService as NotificationServiceImpl;
    expect(secondNotifications.monitor.lookUp.isNotifying, isTrue,
        reason: 'the monitor must be demonstrably up before it is dropped, or '
            '"it reconnected" and "it never connected" are the same green');
    // The socket really going away is what makes the arm below an outage,
    // and it has to be watched for before it is taken away — the stream is a
    // broadcast with no backlog.
    //
    // ⚠️ `isNotifying` cannot answer this and reads as though it can. It is a
    // SESSION flag, cleared only by `stopNotifications`, and the reconnect
    // loop reads it to decide whether to keep trying — so it stays true
    // across exactly the drop being staged here. Asserting it false after a
    // close fails against a monitor that did go down.
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

    // @alice sends this on her own client's connection, which is a different
    // socket on a different atServer from the one just closed — so
    // `delivered` means @bob's atServer took it for a listener that is not
    // currently there.
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
