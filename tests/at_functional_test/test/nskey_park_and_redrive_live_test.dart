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

/// A notification whose nskey private has not been filed yet is parked and
/// re-driven, not dropped.
///
/// The window between an `unawaited` startup's second step and a notification
/// is far too narrow to lose a race for reliably, so
/// `NskeyPrivateFiling.holdBeforeStore` blocks the filing until this test lets
/// it go.
///
/// Both clients are brought fully up on `nsA`, so nothing here races a startup.
/// `nsB` is minted afterwards, so its private was never conveyed to the
/// receiver — conveyance happens at approval — and the receiver has to pull it.
/// That pull is the filing this test holds.
///
/// `parkedTotal` is asserted rather than arrival alone: a run that delivered
/// without parking would otherwise look identical to a pass.
void main() {
  TestUtils.isolateStorage('nskey_park_and_redrive_live_test');
  late AtClient approver;
  late String atSign;
  late InMemoryAtKeysIo approverKeysIo;

  // NOTE: unique per run. The atServer refuses a repeated (appName,
  // deviceName), and an nskey mint takes a lock whose ttl refuses a rotation,
  // so fixed names pass once and collide on the next run against the same VE.
  final runId = DateTime.now().microsecondsSinceEpoch;
  final nsA = 'nskeyparka$runId';
  final nsB = 'nskeyparkb$runId';

  setUpAll(() async {
    atSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    // NOTE: the approver needs a keyfile or it holds no filed private to
    // convey, and the test passes for a reason unrelated to the park.
    approverKeysIo = InMemoryAtKeysIo();
    await approverKeysIo.write(atSign, AtKeys());
    final manager = await TestUtils.initAtClient(atSign, nsA,
        atKeysIo: approverKeysIo, posture: legacyPlusPqProviders);
    approver = manager.atClient;
    await AtClientSecretSharing.forClient(approver).register();
  });

  Future<EnrolledClient> enrol(String device) => enrolAndAuthenticate(
        approver: approver,
        atSign: atSign,
        namespace: nsA,
        preference:
            TestUtils.getPreference(atSign, posture: legacyPlusPqProviders),
        rootDomain: 'vip.ve.atsign.zone',
        rootPort: TestUtils.rootServerPort,
        deviceName: '$device-$runId',
        namespaces: {'*': 'rw', '__manage': 'rw', nsA: 'rw', nsB: 'rw'},
        storage: TestUtils.storage,
      );

  test(
      'a notification that outruns its key is parked, then delivered when it lands',
      timeout: Timeout(Duration(minutes: 3)), () async {
    AtSignLogger.root_level = 'info';

    // nsA is minted before the enrollments, so the sender seals PQ and both
    // clients finish their startups against a namespace they genuinely hold.
    final ringA = PublishedNskeyKeyRing(approver,
        privateFiling:
            NskeyPrivateFiling(keysIo: approverKeysIo, atSign: atSign));
    approver.getPreferences()!.crypto = CryptoConfig.nskey(keyRing: ringA);
    await ringA.mintAndPublish(nsA);

    // NOTE: the order is the design. The receiver is enrolled BEFORE nsB
    // exists, so nsB's private is never conveyed to it — conveyance carries
    // what the approver holds at approval — and the sender is enrolled after,
    // so it holds nsB and can seal to it. The sender must also be able to SEE
    // nsB's advertisement: `currentPublic` is local-first, so a namespace
    // minted while a client is already running is invisible to it and the send
    // silently falls back to the legacy provider.
    final receiver = await enrol('park-receiver');
    await (receiver.client as AtClientImpl).pqBootstrap!.startupComplete;

    // NOTE: the hold goes on BEFORE nsB exists. Installed later, enrolling the
    // sender conveys nsB's private and the receiver's sweep files it before
    // the notification is sent, leaving the re-drive an empty park.
    final filing = (receiver.client as AtClientImpl).pqBootstrap!.filing;
    expect(filing, isNotNull,
        reason: 'without a filing the receiver could not file a pulled private '
            'at all, and this test would be about the wrong thing');
    final release = Completer<void>();
    filing!.holdBeforeStore = () => release.future;

    await ringA.mintAndPublish(nsB);

    final sender = await enrol('park-sender');
    await (sender.client as AtClientImpl).pqBootstrap!.startupComplete;

    expect(identical(sender.client, receiver.client), isFalse,
        reason: 'two enrollments must be two clients');

    final key = AtKey()
      ..key = 'parked$runId'
      ..sharedBy = atSign
      ..sharedWith = atSign
      ..namespace = nsB
      ..metadata = (Metadata()..ttr = 60000);
    const value = 'a value whose key has not been filed yet';

    final notifications =
        receiver.client.notificationService as NotificationServiceImpl;
    final seen = <String>[];
    final received = Completer<AtNotification>();
    final subscription =
        notifications.subscribe(shouldDecrypt: true).listen((n) {
      seen.add(n.key);
      if (n.key.contains('parked$runId') && !received.isCompleted) {
        received.complete(n);
      }
    });
    addTearDown(() async {
      if (!release.isCompleted) release.complete();
      await subscription.cancel();
    });

    // NOTE: the monitor has to be REGISTERED before the notify below, or the
    // atServer creates the notification while nothing is subscribed to its
    // inbound stream and the park is never entered. See
    // [awaitMonitorListening].
    await awaitMonitorListening(notifications);


    // NOTE: subscribed BEFORE the notify that causes the park.
    // `parkedEvents` is broadcast and does not replay, so attaching
    // afterwards would race the very park it is waiting for.
    final parked = Completer<int>();
    final parkedSubscription = notifications.parkedEvents.listen((total) {
      if (!parked.isCompleted) parked.complete(total);
    });
    addTearDown(parkedSubscription.cancel);

    // NOTE: `cryptoProviderId` is required here. The era default is
    // `readsNskeyWritesLegacy` — it reads the nskey path and writes with the
    // legacy provider — so a notify that does not ask for the PQ provider goes
    // out with the legacy provider, the
    // receiver opens it with no nskey private involved, and the park is never
    // entered.
    await sender.client.notificationService.notify(
        NotificationParams.forUpdate(key,
            value: value, cryptoProviderId: symmetricAesGcmCryptoProviderId),
        waitForFinalDeliveryStatus: false);

    await parked.future.timeout(Duration(seconds: 60),
        onTimeout: () => throw StateError(
            'nothing was parked within 60s, so the notification was either '
            'delivered without parking or dropped'));
    expect(notifications.parkedTotal, greaterThan(0),
        reason: 'with the filing held the receiver cannot hold the private, so '
            'the notification must be HELD rather than delivered or dropped — '
            'if this fails the run proves nothing about 14.30');
    expect(received.isCompleted, isFalse,
        reason: 'and it must not have been delivered yet: a value handed over '
            'before its key was filed would be ciphertext');

    // The pull's answer can now be stored, and the filing signal is what
    // releases the park.
    release.complete();

    final delivered = await received.future.timeout(Duration(seconds: 120),
        onTimeout: () => throw StateError(
            'the parked notification was never re-driven. The chain to watch: '
            'the read miss asks (requestSecretsFromNamespace), the holder is '
            'woken and sweeps remote, _handleRequestPayload replies, the reply '
            'is filed, and the filing signal releases the park. Keys seen were '
            '$seen'));

    expect(delivered.value, value,
        reason: 'and it is DECRYPTED: the re-drive goes through the same '
            'transform the live path would have, or the subscriber is handed '
            'ciphertext');
    expect(notifications.parkedTotal, greaterThan(0),
        reason: 'and it genuinely went through the park rather than being '
            'delivered first time');
  });
}
