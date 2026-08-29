// The nskey surface is @experimental; driving it from another package is the
// point of this file.
// ignore_for_file: experimental_member_use
@Tags(['pq'])
library;

import 'dart:async';

import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
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
            posture: PqPosture.legacy);
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
          .forCoLocatedClient(bob, posture: PqPosture.legacy, device: 'bob2-$id'),
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
    final secondSubscription = bobSecond.client.notificationService
        .subscribe(shouldDecrypt: true)
        .listen((n) {
      secondSeen.add(n.key);
      if (!secondMonitorLive.isCompleted) secondMonitorLive.complete();
      if (n.key.contains('nskeynotify$id') && !secondReceived.isCompleted) {
        secondReceived.complete(n);
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
  });
}
