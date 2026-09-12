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
void main() {
  TestUtils.isolateStorage('nskey_self_notify_live_test');
  late AtClient approver;
  late String atSign;
  late InMemoryAtKeysIo approverKeysIo;

  // NOTE: unique per run. The atServer refuses a second enrollment carrying an
  // already-approved `(appName, deviceName)`, and an nskey mint takes a
  // `_nskeylock` whose ttl is a cooldown that also refuses a rotation, so a
  // fixed namespace fails on a second run against the same virtualenv.
  final runId = DateTime.now().microsecondsSinceEpoch;
  final namespace = 'selfntfy$runId';

  setUpAll(() async {
    atSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    // NOTE: the approver needs an `AtKeysIo`. Approval conveys the approver's
    // FILED nskey privates, so without a keyfile nothing is filed, every
    // enrollment approved here starts with nothing and has to pull the private
    // from a peer — asynchronously, long after the notification it could not
    // open was dropped.
    approverKeysIo = InMemoryAtKeysIo();
    await approverKeysIo.write(atSign, AtKeys());
    // NOTE: the approver stays on the DEFAULT (migration) posture. The posture
    // changes what the approver is willing to write and the enrollment
    // handshake depends on those writes, so a postQuantum approver conveys no
    // `apkamSymmetricKey` and `waitForApproval` times out. Only the SENDER
    // needs to write PQ, and posture is per-client.
    final manager = await TestUtils.initAtClient(atSign, namespace,
        atKeysIo: approverKeysIo, posture: legacyPlusPqProviders);
    approver = manager.atClient;
    await AtClientSecretSharing.forClient(approver).register();
  });

  /// An enrollment with its **own** local store.
  ///
  /// `TestUtils.getPreference` keys `hiveStoragePath` on the atSign alone, so
  /// without this every enrollment of one atSign lands in one directory. The
  /// notification replay watermark is a `local:` record in that store, and a
  /// self notification reaches every listening monitor of the atSign, so a
  /// shared store lets the sibling's monitor advance the watermark past a
  /// notification this client has not received.
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
      storage: TestUtils.storage,
    );
  }

  test('a self notification reaches a second enrollment and decrypts',
      timeout: Timeout(Duration(minutes: 3)), () async {
    // NOTE: raised HERE, not in `setUpAll`. `TestUtils.initAtClient` sets
    // `AtSignLogger.root_level` as its first statement, so a level set before
    // it is silently undone. `finest` is what this file needs: the monitor's
    // `RECEIVED notification` frames, which distinguish a receiver that got the
    // treaty and discarded it from one that never saw it, log at `finer`.
    AtSignLogger.root_level = 'finest';
    expect(AtSignLogger.root_level, 'finest',
        reason: 'the level must survive setup, or every conclusion drawn from '
            'the absence of a log line below is a claim about the filter');

    // NOTE: the nskey is minted by the APPROVER, before either enrollment
    // exists. Conveyance at approval can only hand over material the approver
    // already holds, so a later mint leaves the receiver with no private for
    // the generation the sender seals to, and the ring's asynchronous pull
    // answers long after the notification was dropped for failing to decrypt.
    // Filing is what makes the mint durable — a private kept in RAM leaves
    // nothing to convey. The filing is named explicitly rather than left to the
    // client's own `AtKeysIo`, because this row is about what the approver
    // holds.
    final approverRing = PublishedNskeyKeyRing(
      approver,
      privateFiling: NskeyPrivateFiling(keysIo: approverKeysIo, atSign: atSign),
    );
    approver.getPreferences()!.crypto =
        CryptoConfig.nskey(keyRing: approverRing);
    await approverRing.mintAndPublish(namespace);

    final sender = await enrol('self-notify-sender');
    final receiver = await enrol('self-notify-receiver');

    expect(receiver.enrollmentId, isNot(sender.enrollmentId),
        reason: 'the whole claim is that a SECOND enrollment receives it');
    expect(receiver.kpid, isNot(sender.kpid),
        reason: 'different key packages, so the content key has to be '
            'conveyed rather than already held');
    // NOTE: the two above compare fields of the enrollment RESPONSES, which
    // differ whatever the client cache does with them. Only these compare the
    // clients, and one object handed back twice would be the sender talking to
    // itself over its own connection.
    expect(identical(sender.client, receiver.client), isFalse,
        reason: 'two enrollments must be two clients, or this row proves '
            'nothing about delivery to a sibling enrollment');
    expect(receiver.client.enrollmentId, receiver.enrollmentId,
        reason: 'the receiving CLIENT must carry the receiving enrollment id — '
            'that id is what the atServer authorizes the monitor connection '
            'against');
    expect(sender.client.enrollmentId, sender.enrollmentId);

    // NOTE: both clients' PQ startup must have RUN before anything is notified.
    // `AtClientImpl` fires it unawaited and collecting the conveyed keys is one
    // of its steps, so `enrol` hands back a client that does not yet hold the
    // private conveyed to it at approval, and a notification sealed to that
    // generation is dropped rather than retried. The ring's read-miss self-heal
    // answers, but too late — and UC-A3.4 is that a second enrollment opens
    // what was conveyed to it, not that a notification outrunning its key
    // eventually heals. `startupComplete` never completes with an error, so
    // awaiting it cannot turn a failed step into a hang.
    await (sender.client as AtClientImpl).pqBootstrap!.startupComplete;
    await (receiver.client as AtClientImpl).pqBootstrap!.startupComplete;

    // NOTE: deliberately NOT setting `preference.crypto` on either enrollment.
    // Left alone, a client resolves the nskey providers through the era
    // default, which uses the bootstrap's ring — filing, read-miss self-heal
    // and `privatesFiled` events included. Substituting a bare ring over the
    // top loses the events, because a filing is per instance. That is UC-B5.8's
    // claim, and this row depends on it.

    final key = AtKey()
      ..key = 'treaty$runId'
      ..sharedBy = atSign
      ..sharedWith = atSign
      ..namespace = namespace
      ..metadata = (Metadata()..ttr = 60000);
    const value = 'a self notification sealed to the namespace key';

    // NOTE: listener before trigger, and the listener that matters is the
    // atServer's, not this stream. `subscribe()` returns before the monitor's
    // own socket has connected, PKAMed and written `monitor:`, and the monitor
    // asks for no backlog, so a notification the atServer creates in that
    // window is unrecoverable while the notify still reports `delivered`.
    final notifications =
        receiver.client.notificationService as NotificationServiceImpl;
    // No `regex:` — subscribe to everything and filter here. A wrong regex
    // fails identically to a notification that never arrived, so every key the
    // monitor delivers is recorded and named in the failure instead.
    final seen = <String>[];
    final received = Completer<AtNotification>();
    // The one sent while this listener's monitor is closed; declared here
    // because the listener has to be watching before it is sent.
    final queued = Completer<AtNotification>();
    final subscription =
        notifications.subscribe(shouldDecrypt: true).listen((n) {
      seen.add(n.key);
      if (n.key.contains('treaty$runId') && !received.isCompleted) {
        received.complete(n);
      }
      if (n.key.contains('queued$runId') && !queued.isCompleted) {
        queued.complete(n);
      }
    });
    addTearDown(subscription.cancel);

    // NOTE: wait until the monitor is REGISTERED before notifying anything.
    // `MonitorVerbHandler` subscribes to the atServer's inbound stream only
    // when it processes the `monitor:` command, and that stream is a broadcast
    // with no backlog, so a notification enqueued before that instant is never
    // delivered on that connection at all. The only recovery is the
    // `monitor:…:<epochMillis>` form, and a first-ever monitor has no
    // last-received time to send. See [awaitMonitorListening] for why
    // `listening` now answers this and what it still cannot promise.
    await awaitMonitorListening(notifications);

    // The provider is chosen PER CALL, not by posture: a per-call algorithm
    // overrides the posture's value for that one axis, and the migration
    // default already READS nskey, so only the write needs moving.
    final result = await sender.client.notificationService.notify(
        NotificationParams.forUpdate(key,
            value: value, cryptoProviderId: symmetricAesGcmCryptoProviderId));
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

    expect(seen, isNotEmpty,
        reason: 'the monitor must have delivered something — without that '
            'this row cannot distinguish a working self-notification from a '
            'monitor that happens to be fed by something else');

    expect(notification.metadata?.appMetadata?.providerId,
        symmetricAesGcmCryptoProviderId,
        reason: 'providerId must travel ON THE FRAME. A stored key carries its '
            'appMetadata in the record; a notification has to carry it in the '
            'notification, and without it the receiver falls back to the legacy provider '
            'and hunts a shared_key a PQ write never created');

    expect(notification.value, value,
        reason: 'the second enrollment opens the content key with the nskey '
            'private conveyed to it at approval — this is the half a mocked '
            'frame cannot show, because the mock hands the receiver a value it '
            'never had to decrypt');

    // UC-A3.2's other half, on the same pair: a STORED self record rather than
    // a notification. The frame above shows the second enrollment opening a
    // content key it was handed; this shows it opening one it has to fetch from
    // the atServer for itself.
    final stored = AtKey()
      ..key = 'ledger$runId'
      ..sharedBy = atSign
      ..sharedWith = atSign
      ..namespace = namespace
      ..metadata = (Metadata()..ttr = 60000);
    const storedValue = 'self data sealed to the namespace key';

    // Remote-first, and the provider named per call: these enrollments run the
    // migration posture, and a local-first write reaches the atServer only when
    // sync gets round to it.
    expect(
        await sender.client.put(stored, storedValue,
            putRequestOptions: PutRequestOptions()
              ..useRemoteAtServer = true
              ..cryptoProviderId = symmetricAesGcmCryptoProviderId),
        isTrue);

    // NOTE: a legacy self write opens for every enrollment of this atSign —
    // the self encryption key is atSign-wide, not per-enrollment — so the
    // record's provider is read before the value below.
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

    // UC-A3.4's offline clause, and it is the COMPOSITION rather than either
    // half alone: a value sealed to the namespace key while a SIBLING
    // ENROLLMENT was disconnected still opens when that enrollment returns — a
    // laptop that was shut. Last on purpose, so the pair is known good before
    // the connection is taken away and a failure here is the outage rather
    // than the fixture.
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
