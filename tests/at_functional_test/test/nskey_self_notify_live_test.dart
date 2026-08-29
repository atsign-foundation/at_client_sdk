// The nskey surface and the substrate are @experimental; driving them is the
// point of this file.
// ignore_for_file: experimental_member_use

@Tags(['pq'])
library;

import 'dart:async';

import 'package:at_auth/at_auth.dart';
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
  late InMemoryAtKeysIo approverKeysIo;

  // Unique per run, and it does two jobs. The atServer refuses a second
  // enrollment carrying an already-approved `(appName, deviceName)`, and an
  // nskey mint takes a `_nskeylock` whose ttl is a cooldown that also refuses a
  // rotation — so a fixed namespace would pass on a fresh virtualenv and fail
  // on the next run against the same one.
  final runId = DateTime.now().microsecondsSinceEpoch;
  final namespace = 'selfntfy$runId';

  setUpAll(() async {
    atSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    // ⚠️ The approver needs an `AtKeysIo`, and this is the whole test.
    //
    // Approval conveys **the approver's FILED nskey privates, read from
    // AtKeys** — `nskey_convey_at_approval_test.dart` pins both arms, the
    // second being "an approver with no atKeysIo approves cleanly and conveys
    // none". Without a keyfile the minted private is never filed, so every
    // enrollment approved here starts with nothing and has to *pull* the
    // private from a peer. That pull is asynchronous, the content notification
    // beats it, and the notification is dropped for want of a key that arrives
    // seconds later.
    //
    // Three runs and a ruling went into that symptom before the cause turned
    // out to be this line. The push paths are built and work; the earlier
    // version of this test disabled them.
    approverKeysIo = InMemoryAtKeysIo();
    await approverKeysIo.write(atSign, AtKeys());
    // ⚠️ The approver stays on the DEFAULT (migration) posture. Building it
    // postQuantum made `waitForApproval` time out with "No conveyed
    // apkamSymmetricKey arrived … the approver is running a client that does
    // not convey" — the posture changes what the approver is willing to write,
    // and the enrollment handshake depends on those writes. Only the SENDER
    // needs to write PQ, and posture is per-client.
    final manager = await TestUtils.initAtClient(atSign, namespace,
        atKeysIo: approverKeysIo, posture: legacyPlusPqProviders);
    approver = manager.atClient;
    await AtClientSecretSharing.forClient(approver).register();
  });

  /// An enrollment with its **own** local store.
  ///
  /// `TestUtils.getPreference` keys `hiveStoragePath` on the atSign alone, so
  /// without this every enrollment of one atSign lands in one directory. That
  /// matters here beyond tidiness: the notification replay watermark is a
  /// `local:` record in that store, so a shared store is a shared watermark —
  /// and a self notification reaches **every** listening monitor of the
  /// atSign, so the sibling's monitor would receive the one below, advance the
  /// shared watermark past it, and the disconnected client's reconnect would
  /// ask the atServer for everything *after* the notification it missed.
  ///
  /// ⚠️ Naming separate paths was not enough until 2026-08-29
  /// ([ruling 125](../../../docs/projects/pq/detail/decisions.md)): a box's
  /// identity was the global Hive registry plus its name, and names derive
  /// from the atSign, so the second client silently attached to the first's
  /// box whatever path it asked for. Only the encryption-secret file landed
  /// where it was told.
  Future<EnrolledClient> enrol(String device) {
    final preference =
        TestUtils.getPreference(atSign, posture: legacyPlusPqProviders);
    preference
      ..hiveStoragePath = 'test/hive/client/$atSign/$device-$runId'
      ..commitLogPath = 'test/hive/client/$atSign/$device-$runId';
    return enrolAndAuthenticate(
      approver: approver,
      atSign: atSign,
      namespace: namespace,
      preference: preference,
      rootDomain: 'vip.ve.atsign.zone',
      rootPort: TestUtils.rootServerPort,
      deviceName: '$device-$runId',
      namespaces: {'*': 'rw', '__manage': 'rw', namespace: 'rw'},
    );
  }

  test('a self notification reaches a second enrollment and decrypts',
      timeout: Timeout(Duration(minutes: 3)),
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
    // ⚠️ A filing is what makes the mint durable, and without one nothing
    // downstream works: approval conveys *the approver's FILED privates*, and
    // a mint that kept its private in RAM leaves none to convey. Two omissions
    // had to be fixed to get here and each looked complete on its own — the
    // approver needed an `AtKeysIo`, AND the ring needed telling to use it.
    //
    // The second is no longer required: a ring derives its filing from the
    // client's own `AtKeysIo` (`decisions.md` 111), and this client was given
    // `approverKeysIo` at construction. Named explicitly all the same, because
    // this row is about what the approver holds and the assertion should not
    // depend on a default to be reading the same keyfile.
    final approverRing = PublishedNskeyKeyRing(
      approver,
      privateFiling:
          NskeyPrivateFiling(keysIo: approverKeysIo, atSign: atSign),
    );
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
    // ⚠️ The two above compare fields of the enrollment RESPONSES, which differ
    // whatever the client cache does with them. Only these compare the clients:
    // if `AtClientImpl`'s cache handed back one object twice, the "second
    // enrollment" would be the sender talking to itself over its own
    // connection, and every assertion below would pass for that reason.
    expect(identical(sender.client, receiver.client), isFalse,
        reason: 'two enrollments must be two clients, or this row proves '
            'nothing about delivery to a sibling enrollment');
    expect(receiver.client.enrollmentId, receiver.enrollmentId,
        reason: 'the receiving CLIENT must carry the receiving enrollment id — '
            'that id is what the atServer authorizes the monitor connection '
            'against');
    expect(sender.client.enrollmentId, sender.enrollmentId);

    // ⚠️ Both clients' PQ startup must have RUN before anything is notified.
    //
    // `AtClientImpl` fires it with `unawaited(_pqBootstrap!.startup())`, and
    // `PqClientBootstrap._collectConveyedKeys` — whose own dartdoc calls itself
    // "the only route by which a conveyed nskey private reaches the keyfile" —
    // is its second step. So `enrol` hands back a client that does not yet hold
    // the private conveyed to it at approval, and anything sealed to that
    // generation in the meantime cannot be opened.
    //
    // Measured, from the run that found it (client clock):
    //   12.609–12.637  receiver's sweep reads and deletes its __ssenv envelopes
    //   12.682         sender notifies
    //   12.684         receiver's monitor receives the treaty
    //   12.703         DROPPED: "no nskey private held … generation 7ee3a…"
    //   12.819         ring's read-miss self-heal: "Asked the other
    //                  enrollments for the nskey private …"
    // The heal is 116 ms too late, because a dropped notification is not
    // retried. That gap is real and it is NOT this row's claim — UC-A3.4 is
    // that a second enrollment can open what was conveyed to it, not that a
    // notification outrunning its key eventually heals. Waiting here is what
    // makes the row test its own claim instead of the heal path's timing.
    //
    // `startupComplete` is the documented handle for exactly this
    // ("Awaitable via [pqBootstrap]'s `startupComplete` for callers that need
    // the tail to have run") and never completes with an error, so this cannot
    // turn a step's failure into a hang.
    await (sender.client as AtClientImpl).pqBootstrap!.startupComplete;
    await (receiver.client as AtClientImpl).pqBootstrap!.startupComplete;

    // ⚠️ Deliberately NOT setting `preference.crypto` on either enrollment.
    //
    // An earlier version installed `CryptoConfig.nskey(keyRing:
    // PublishedNskeyKeyRing(client))` on both — a bare ring, over the top of
    // the one `PqClientBootstrap` had already wired — which removed both the
    // filing and the read path's self-heal.
    //
    // ⚠️ **A bare ring now derives both its filing and its read-miss ask**
    // (`decisions.md` 111), so a substituted ring keeps `decisions.md` 38's
    // self-heal — "a miss on an own generation broadcasts a pull, so a record
    // that arrived before its key stops being permanently unreadable and
    // becomes merely early". What it still loses is the `privatesFiled`
    // events: a filing is per instance, so a private filed by the bootstrap's
    // ring announces to nobody listening on this one.
    //
    // Left alone, a client resolves the nskey providers through the era
    // default, which uses `_pqBootstrap.ring` — filing and self-heal
    // included. That is UC-B5.8's claim, and this row depends on it.

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
    // The one sent while this listener's monitor is closed. Declared up here
    // because the listener has to be watching before it is sent — the
    // atServer's inbound stream is a broadcast with no backlog, which is the
    // same reason the readiness gate below exists.
    final queued = Completer<AtNotification>();
    final monitorProvenLive = Completer<void>();
    final subscription =
        notifications.subscribe(shouldDecrypt: true).listen((n) {
      seen.add(n.key);
      if (!monitorProvenLive.isCompleted) monitorProvenLive.complete();
      if (n.key.contains('treaty$runId') && !received.isCompleted) {
        received.complete(n);
      }
      if (n.key.contains('queued$runId') && !queued.isCompleted) {
        queued.complete(n);
      }
    });
    addTearDown(subscription.cancel);

    // ⚠️ Wait until THIS listener has been handed a notification, before
    // notifying anything. Nothing weaker is sufficient, and this test spent
    // several runs proving it.
    //
    // The atServer's inbound notification stream is a **broadcast** stream and
    // `MonitorVerbHandler` subscribes to it when it processes the `monitor:`
    // command, so a notification enqueued before that instant is never
    // delivered to that connection at all — a broadcast stream has no backlog.
    // The only recovery is the `monitor:…:<epochMillis>` form, which replays
    // from the store; the client sends an epoch only once it has a
    // last-received-notification time, which a first-ever monitor does not.
    //
    // The atServer's own log for the failing run, to the millisecond:
    //   00:20:51.343  enqueue … (@alice🛠:treaty….selfntfy…@alice🛠)
    //   00:20:51.345  RCVD: monitor:selfNotifications      <- 2.9ms too late
    // The notification was then delivered exactly once, 29 seconds later, to a
    // different client whose monitor did carry an epoch.
    //
    // `currentListenerState == listening` is NOT this gate: the Monitor sets it
    // straight after writing the command, which says nothing about the atServer
    // having processed it. A notification actually arriving does.
    //
    // `statsNotification` is what satisfies this in practice — the atServer
    // emits one every ~11s to every listening monitor, and an empty-regex
    // subscription receives it. That makes it a readiness signal *and* the
    // positive control asserted after the wait.
    await monitorProvenLive.future.timeout(
      Duration(seconds: 60),
      onTimeout: () => throw StateError(
          'no notification of any kind reached the listener within 60s, so the '
          'monitor is not up; notifying now would repeat the race this gate '
          'exists to close'),
    );

    // ⚠️ The provider is chosen PER CALL, not by posture. Building the
    // enrollments with `PqPosture.pqActive` did make writes PQ — and
    // ⚠️ **This comment said pqActive "broke the monitor: under it the
    // receiver's monitor received nothing at all, not even
    // `statsNotification`, and the sender's never reached `listening`. The
    // monitor authenticates on its own socket, so a posture that moves the
    // signing algorithm takes that connection with it." That is measured
    // false.** A posture grid running five sender postures against one
    // pqActive listener delivered and decrypted every one, the pqActive
    // senders included, and the listener itself is a pqActive enrollment. An
    // earlier interleaved run had already put the rate at 16 of 18 for
    // pqActive against 18 of 20 for a control, both arms failing alike with
    // `AT0014` — so the failure is real, is monitor-readiness flakiness, and
    // is not posture-dependent. The per-call provider below stays for the
    // reason in the next paragraph, not for that one.
    //
    // `AtClientPreference`'s own doc licenses this: "a per-call algorithm
    // overrides the posture's value for that one axis". The migration default
    // already READS nskey (`CryptoConfig.readsNskeyWritesLegacy`), so only the
    // write needed moving.
    final result = await sender.client.notificationService.notify(
        NotificationParams.forUpdate(key,
            value: value,
            cryptoProviderId: symmetricAesGcmCryptoProviderId));
    expect(result.notificationStatusEnum, NotificationStatusEnum.delivered);

    final notification = await received.future.timeout(
      Duration(seconds: 90),
      onTimeout: () => throw StateError(
          'the treaty notification did not reach the second enrollment within '
          '90s, and the notify above reported `delivered`.\n'
          "  the monitor saw ${seen.length}: $seen\n"
          '${seen.isNotEmpty ? "  It IS receiving, so this is not monitor readiness." : "  It received NOTHING, not even statsNotification, so the "
              "monitor is not up and this says nothing about delivery."}'),
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

    // UC-A3.2's other half, on the same pair and at no extra fixture cost: a
    // STORED self record rather than a notification. The frame above shows
    // the second enrollment can open a content key it was handed; this shows
    // it can open one it has to fetch from the atServer for itself, which is
    // what "alice2 obtains the nskey private and reads" says about self data.
    //
    // Nothing in the tree exercised that pairing before 2026-08-28: the
    // multi-enrollment reads were all cross-atSign, and the self direction
    // was only ever a notification.
    final stored = AtKey()
      ..key = 'ledger$runId'
      ..sharedBy = atSign
      ..sharedWith = atSign
      ..namespace = namespace
      ..metadata = (Metadata()..ttr = 60000);
    const storedValue = 'self data sealed to the namespace key';

    // Written remote-first and with the provider named per call, for the same
    // reasons as the notify above: these enrollments run the migration
    // posture, so the write scheme is a per-call decision, and a local-first
    // write would reach the atServer only when sync got round to it.
    expect(
        await sender.client.put(stored, storedValue,
            putRequestOptions: PutRequestOptions()
              ..useRemoteAtServer = true
              ..cryptoProviderId = symmetricAesGcmCryptoProviderId),
        isTrue);

    // Read off the record before reading the value: without this the assertion
    // below passes for a legacy self write, which every enrollment of this
    // atSign can open because the self encryption key is atSign-wide rather
    // than per-enrollment — true, and not this clause.
    final asWritten = await sender.client.get(stored,
        getRequestOptions: GetRequestOptions()..useRemoteAtServer = true);
    expect(asWritten.metadata?.appMetadata?.providerId,
        symmetricAesGcmCryptoProviderId,
        reason: 'the record must be on the nskey data path for the read below '
            'to say anything about holding the namespace private');

    expect(
        (await receiver.client.get(stored,
                getRequestOptions: GetRequestOptions()
                  ..useRemoteAtServer = true))
            .value,
        storedValue,
        reason: 'the second enrollment fetches the record and opens it with '
            'the nskey private conveyed to it at approval — the advertisement '
            'resolves, the conveyance landed, and the read path finds the '
            'generation the record names');

    // UC-A3.4's offline clause, and it is the COMPOSITION the row states
    // rather than either half alone. `monitor_reconnect_live_test.dart` shows
    // a queued notification surviving an outage, but with one client notifying
    // itself. Everything above shows a second enrollment opening a content
    // key, but with its monitor up throughout. Neither says that a value
    // sealed to the namespace key while a SIBLING ENROLLMENT was disconnected
    // still opens when that enrollment returns — a laptop that was shut.
    //
    // Deliberately last: everything above has passed, so the pair is known
    // good before the connection is taken away and a failure here is the
    // outage rather than the fixture.
    expect(notifications.monitor.lookUp.isNotifying, isTrue,
        reason: 'the monitor must be demonstrably up before it is dropped, or '
            '"it reconnected" and "it never connected" are the same green');

    await notifications.monitor.lookUp.close();

    final queuedKey = AtKey()
      ..key = 'queued$runId'
      ..sharedBy = atSign
      ..sharedWith = atSign
      ..namespace = namespace;
    const queuedValue = 'sealed while the sibling enrollment was offline';

    // Sent on the SENDER's verb connection — a different socket from the
    // receiver's monitor — so `delivered` here means the atServer took it for
    // a listener that is not currently there.
    expect(
        (await sender.client.notificationService.notify(
                NotificationParams.forUpdate(queuedKey,
                    value: queuedValue,
                    cryptoProviderId: symmetricAesGcmCryptoProviderId)))
            .notificationStatusEnum,
        NotificationStatusEnum.delivered,
        reason: 'the send must succeed while the receiving enrollment has no '
            'monitor at all — it does not travel that connection');

    final afterOutage = await queued.future.timeout(
      Duration(seconds: 120),
      onTimeout: () => throw StateError(
          'the notification sent while the second enrollment was disconnected '
          'never arrived, and the notify reported `delivered`. Either the '
          'monitor did not come back, or it came back with a watermark that '
          'asked only for what followed the reconnect — which is what happened '
          'while the two enrollments shared one store, because the SENDER\'s '
          'monitor received this and moved the shared watermark past it.\n'
          '  the monitor saw ${seen.length}: $seen'),
    );

    expect(afterOutage.metadata?.appMetadata?.providerId,
        symmetricAesGcmCryptoProviderId,
        reason: 'it must come back on the nskey data path. Without this the '
            'value below could decrypt for a reason that has nothing to do '
            'with the namespace key — a legacy fallback opens for every '
            'enrollment of this atSign, because the self encryption key is '
            'atSign-wide');

    expect(afterOutage.value, queuedValue,
        reason: 'the queued notification still decrypts on later delivery: the '
            'nskey private this enrollment was conveyed at approval still '
            'opens a content key sealed while it was disconnected. ⚠️ This is '
            'an outage of the CONNECTION, not of the process — it says nothing '
            'about the private surviving a restart, which is a separate claim '
            'belonging to the filing tests');
  });
}
