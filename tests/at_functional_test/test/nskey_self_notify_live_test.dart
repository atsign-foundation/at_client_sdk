// The nskey surface and the substrate are @experimental; driving them is the
// point of this file.
// ignore_for_file: experimental_member_use

import 'dart:async';

import 'package:at_client/at_client.dart';
import 'package:at_utils/at_logger.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_client/src/service/notification_service_impl.dart';
import 'package:at_functional_test/src/config_util.dart';
import 'package:at_functional_test/src/enrolled_client.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

/// UC-A3.4's **self** direction, live: `alice1` notifies `@alice`, and a second
/// enrollment of the same atSign receives and decrypts it.
///
/// Both live notification tests were alice→bob. The self direction was asserted
/// only against a `MockAtClient` with a hand-built frame, which can show that
/// the receive path reads `providerId` off a frame but cannot show that the
/// atServer puts one there for a self notification, or that a *second
/// enrollment* — a different key package, a different connection — can open the
/// content key.
///
/// It was unwritable until `AtClientImpl`'s instance cache was keyed by
/// `(atSign, enrollmentId)`. Before that a second "enrollment" of one atSign
/// was `identical` to the first, so a self notification would have been a
/// client notifying itself over its own connection — green for a reason that
/// has nothing to do with the claim.
void main() {
  late AtClient approver;
  late String atSign;

  // Unique per run, and it does two jobs. The atServer refuses a second
  // enrollment carrying an already-approved `(appName, deviceName)`, and an
  // nskey mint takes a `_nskeylock` whose ttl is a cooldown that also refuses a
  // rotation — so a fixed namespace would pass on a fresh virtualenv and fail
  // on the next run against the same one.
  final runId = DateTime.now().microsecondsSinceEpoch;
  final namespace = 'selfntfy$runId';

  setUpAll(() async {
    atSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    final manager = await TestUtils.initAtClient(atSign, namespace);
    approver = manager.atClient;
    await AtClientSecretSharing.forClient(approver).register();
  });

  Future<EnrolledClient> enrol(String device) => enrolAndAuthenticate(
        approver: approver,
        atSign: atSign,
        namespace: namespace,
        preference: TestUtils.getPreference(atSign),
        rootDomain: 'vip.ve.atsign.zone',
        rootPort: TestUtils.rootServerPort,
        deviceName: '$device-$runId',
        namespaces: {'*': 'rw', '__manage': 'rw', namespace: 'rw'},
      );

  /// Puts [client] on the nskey data path for [namespace].
  Future<PublishedNskeyKeyRing> onNskeyPath(AtClient client) async {
    final ring = PublishedNskeyKeyRing(client);
    client.getPreferences()!.crypto = CryptoConfig.nskey(keyRing: ring);
    return ring;
  }

  test('a self notification reaches a second enrollment and decrypts',
      timeout: Timeout(Duration(minutes: 3)),
      // ⛔ SKIPPED because the product cannot do this yet, not because the test
      // is unfinished. It is the characterisation of decisions 106: the
      // notification reaches the second enrollment and is dropped with
      // `no nskey private held`, 0.6s before the private it needs arrives.
      // Kept in the pack so the defect has an executable description — remove
      // the skip when 14.30 is fixed and this becomes the regression guard.
      //
      // Everything up to the final two assertions passes, so un-skipping is
      // also the cheapest way to re-measure the race.
      skip: 'decisions 106 / plan 14.30 — a content notification can outrun '
          'the nskey private that opens it, and is dropped without retry',
      () async {
    // ⚠️ Raised HERE, not in `setUpAll`. `TestUtils.initAtClient` sets
    // `AtSignLogger.root_level` as its first statement, so a level set before
    // it is silently undone — which is what happened, and produced a 74-line
    // "finest" log containing nothing but `shout`.
    //
    // The pack default is now `info` (raised from `shout` 2026-08-16, after
    // this file's investigation showed a `warning`-level drop was invisible).
    // `finest` is still needed here: the monitor's `RECEIVED notification`
    // frames, which are what prove the receiver got the treaty and discarded
    // it rather than never seeing it, log at `finer`.
    AtSignLogger.root_level = 'finest';
    expect(AtSignLogger.root_level, 'finest',
        reason: 'the level must survive setup, or every conclusion drawn from '
            'the absence of a log line below is a claim about the filter');

    // ⚠️ The nskey is minted by the APPROVER, BEFORE either enrollment
    // exists. Conveyance at approval can only hand over material the approver
    // already holds, so minting after the approvals — which is what this test
    // did for three runs — leaves the receiver with no private for the
    // generation the sender seals to. It then asks for one
    // (`PublishedNskeyKeyRing`: *"Asked the other enrollments for the nskey
    // private … the answer is filed when a holder replies"*) and the answer
    // arrives asynchronously, long after the notification has been dropped
    // for failing to decrypt. That log line sits at `info`, which the pack's
    // `shout` level hides, so the symptom was an unexplained silence.
    //
    // Minting first is also what UC-A3.4 describes: alice1 and alice2 are both
    // already PQ when the notification is sent.
    final approverRing = PublishedNskeyKeyRing(approver);
    approver.getPreferences()!.crypto =
        CryptoConfig.nskey(keyRing: approverRing);
    await approverRing.mintAndPublish(namespace);

    final sender = await enrol('self-notify-sender');
    final receiver = await enrol('self-notify-receiver');

    // Two genuinely distinct enrollments, checked rather than assumed. If the
    // fixture handed back the same one twice this would be a client notifying
    // itself over its own connection, and it would pass for the wrong reason —
    // which is exactly what the singleton cache used to guarantee.
    expect(receiver.enrollmentId, isNot(sender.enrollmentId),
        reason: 'the whole claim is that a SECOND enrollment receives it');
    expect(receiver.kpid, isNot(sender.kpid),
        reason: 'different key packages, so the content key has to be '
            'conveyed rather than already held');

    await onNskeyPath(sender.client);
    await onNskeyPath(receiver.client);

    final key = AtKey()
      ..key = 'treaty$runId'
      ..sharedBy = atSign
      ..sharedWith = atSign
      ..namespace = namespace
      ..metadata = (Metadata()..ttr = 60000);
    const value = 'a self notification sealed to the namespace key';

    // Listener before trigger — and ⚠️ **the listener that matters is the
    // atServer's**, not this stream. `subscribe()` returns before the
    // monitor's own socket has connected, PKAMed and written `monitor:`, and
    // the monitor asks for no backlog, so a notification the atServer creates
    // in that window is unrecoverable. The first version of this test
    // subscribed and notified immediately: the notify reported `delivered`
    // and nothing ever reached the monitor, which reads exactly like a
    // product defect and was mine.
    final notifications =
        receiver.client.notificationService as NotificationServiceImpl;
    // No `regex:` — subscribe to everything and filter here, as the monitor
    // test in this pack does. A regex is a second thing that can be wrong for
    // reasons unrelated to the claim, and a wrong one fails identically to a
    // notification that never arrived.
    //
    // ⚠️ Every key the monitor delivers is recorded, because the first two
    // runs failed with "nothing arrived" and that message cannot tell a
    // monitor which receives nothing from a monitor which receives everything
    // except this. The atServer's own `statsNotification` arrives every ~15s
    // once a monitor is listening, so it is the positive control: seeing it
    // and not the treaty means the monitor works and self-delivery to a
    // sibling enrollment does not.
    final seen = <String>[];
    final received = Completer<AtNotification>();
    final subscription =
        notifications.subscribe(shouldDecrypt: true).listen((n) {
      seen.add(n.key);
      if (n.key.contains('treaty$runId') && !received.isCompleted) {
        received.complete(n);
      }
    });
    addTearDown(subscription.cancel);

    // The SENDER's own monitor, watched too. With the receiver's monitor
    // proven live by statsNotification and the treaty still absent, three
    // explanations remain and this separates them: the atServer delivers self
    // notifications to no monitor at all, or only to the sending enrollment's,
    // or it filters by enrollment. Only the last two put anything on the
    // sender's stream.
    final senderSeen = <String>[];
    final senderNotifications =
        sender.client.notificationService as NotificationServiceImpl;
    final senderSubscription =
        senderNotifications.subscribe(shouldDecrypt: false).listen((n) {
      senderSeen.add(n.key);
    });
    addTearDown(senderSubscription.cancel);
    if (senderNotifications.monitor.currentState !=
        NotificationListenerState.listening) {
      await senderNotifications.monitor.currentStateStream
          .firstWhere((s) => s == NotificationListenerState.listening)
          .timeout(const Duration(seconds: 30), onTimeout: () => throw StateError(
              "the sender's monitor never reached `listening`, so its stream "
              'proves nothing either way'));
    }

    if (notifications.monitor.currentState !=
        NotificationListenerState.listening) {
      await notifications.monitor.currentStateStream
          .firstWhere((s) => s == NotificationListenerState.listening)
          .timeout(const Duration(seconds: 30),
              onTimeout: () => throw StateError(
                  "the receiver's monitor never reached `listening`, so the "
                  'notification below would be created into a window nothing '
                  'is watching'));
    }

    final result = await sender.client.notificationService
        .notify(NotificationParams.forUpdate(key, value: value));
    expect(result.notificationStatusEnum, NotificationStatusEnum.delivered);

    final notification = await received.future.timeout(
      Duration(seconds: 90),
      onTimeout: () => throw StateError(
          'the treaty notification did not reach the second enrollment within '
          '90s, and the notify above reported `delivered`.\n'
          "  receiver's monitor saw ${seen.length}: $seen\n"
          "  sender's monitor saw ${senderSeen.length}: $senderSeen\n"
          '${seen.every((k) => k.startsWith("statsNotification")) && seen.isNotEmpty ? "  The receiver's monitor IS receiving (statsNotification "
              "arrives), so this is not a monitor-readiness problem." : "  The receiver's monitor may not be receiving at all."} '
          '${senderSeen.any((k) => k.contains("treaty")) ? "The SENDER saw it, so delivery is scoped to the "
              "sending enrollment." : "Neither monitor saw it, so the atServer "
              "appears not to deliver a self notification to any monitor."}'),
    );

    // The positive control, asserted rather than assumed: if the monitor never
    // received anything at all, a passing treaty assertion below could not
    // have been about self-delivery in the first place.
    expect(seen, isNotEmpty,
        reason: 'the monitor must have delivered something — without that '
            'this row cannot distinguish a working self-notification from a '
            'monitor that happens to be fed by something else');

    expect(notification.metadata?.appMetadata?.providerId,
        symmetricAesGcmCryptoProviderId,
        reason: 'providerId must travel ON THE FRAME. A stored key carries its '
            'appMetadata in the record; a notification has to carry it in the '
            'notification, and without it the receiver falls back to legacy '
            'and hunts a shared_key a PQ write never created');

    expect(notification.value, value,
        reason: 'the second enrollment opens the content key with the nskey '
            'private conveyed to it at approval — this is the half a mocked '
            'frame cannot show, because the mock hands the receiver a value it '
            'never had to decrypt');
  });
}
