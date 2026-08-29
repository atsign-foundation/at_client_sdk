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

/// Plan 14.30 / ruling 106.5, live: a notification whose nskey private has not
/// been filed yet is **parked and re-driven**, not dropped.
///
/// **The window is held open deliberately, and that is the whole design of this
/// file.** It is ~116 ms wide in the wild — between an `unawaited` startup's
/// second step and a notification — and two earlier attempts to catch it by
/// racing both went green having never entered the park (one fell back to
/// `legacy`, one had its own readiness wait close the gap). A race that cannot
/// be reliably lost cannot be reliably tested, so
/// `NskeyPrivateFiling.holdBeforeStore` blocks the filing until this test lets
/// it go.
///
/// **Why a second namespace.** Both clients are brought fully up on `nsA`
/// first, so nothing here is racing a startup. `nsB` is then minted, and its
/// private was therefore never conveyed to anyone — conveyance happens at
/// approval, which is long past. The receiver has to pull it, and that pull is
/// the filing this test holds.
///
/// `parkedTotal` is asserted, not just arrival: a run that somehow delivered
/// without parking would otherwise look identical to a pass.
void main() {
  late AtClient approver;
  late String atSign;
  late InMemoryAtKeysIo approverKeysIo;

  // Unique per run: the atServer refuses a repeated (appName, deviceName), and
  // an nskey mint takes a lock whose ttl also refuses a rotation, so a fixed
  // namespace passes once and collides on the next run against the same VE.
  final runId = DateTime.now().microsecondsSinceEpoch;
  final nsA = 'nskeyparka$runId';
  final nsB = 'nskeyparkb$runId';

  setUpAll(() async {
    atSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    // The approver needs a keyfile or it holds no filed private to convey, and
    // every enrollment starts with nothing — which would make this test pass
    // for a reason that has nothing to do with the park.
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
        preference: TestUtils.getPreference(atSign, posture: legacyPlusPqProviders),
        rootDomain: 'vip.ve.atsign.zone',
        rootPort: TestUtils.rootServerPort,
        deviceName: '$device-$runId',
        namespaces: {'*': 'rw', '__manage': 'rw', nsA: 'rw', nsB: 'rw'},
      );

  test('a notification that outruns its key is parked, then delivered when it lands',
      timeout: Timeout(Duration(minutes: 3)), () async {
    AtSignLogger.root_level = 'finest';

    // nsA warms everything up: minted before the enrollments, so the sender
    // seals PQ and both clients finish their startups against a namespace they
    // genuinely hold.
    final ringA = PublishedNskeyKeyRing(approver,
        privateFiling:
            NskeyPrivateFiling(keysIo: approverKeysIo, atSign: atSign));
    approver.getPreferences()!.crypto = CryptoConfig.nskey(keyRing: ringA);
    await ringA.mintAndPublish(nsA);

    // ⚠️ ORDER IS THE DESIGN HERE. The receiver is enrolled BEFORE nsB exists,
    // so nsB's private is never conveyed to it — conveyance carries what the
    // approver holds AT APPROVAL. The sender is enrolled after, so it holds
    // nsB and can seal to it.
    //
    // The sender must also be able to SEE nsB's advertisement. `currentPublic`
    // is local-first by design (it is on the write path, so a remote read would
    // put a round trip on every put), which is why a namespace minted while a
    // client is already running is invisible to it and the send silently falls
    // back to legacy — measured three times before this ordering was found.
    final receiver = await enrol('park-receiver');
    await (receiver.client as AtClientImpl).pqBootstrap!.startupComplete;

    // ⚠️ The hold goes on BEFORE nsB exists. Installing it later lost the race:
    // enrolling the sender conveys nsB's private, the receiver's sweep filed it
    // before the notification was ever sent, and the re-drive then ran against
    // an empty park. Measured — `PROBE redrive … parkedKeys=[]` arriving before
    // the park.
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

    // Hold the receiver's filing shut. Installed AFTER its startup, so nothing
    // in the warm-up is blocked and the only filing this catches is the pull
    // for nsB below.

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
    final monitorProvenLive = Completer<void>();
    final subscription =
        notifications.subscribe(shouldDecrypt: true).listen((n) {
      seen.add(n.key);
      if (!monitorProvenLive.isCompleted) monitorProvenLive.complete();
      if (n.key.contains('parked$runId') && !received.isCompleted) {
        received.complete(n);
      }
    });
    addTearDown(() async {
      if (!release.isCompleted) release.complete();
      await subscription.cancel();
    });

    // Positive control: the atServer's stats notification proves the monitor is
    // genuinely registered, so a later timeout means the park failed rather
    // than that nothing was ever listening.
    await monitorProvenLive.future.timeout(Duration(seconds: 60),
        onTimeout: () => throw StateError(
            'no notification of any kind reached the listener within 60s, so '
            'nothing below would be a statement about the park'));

    // ⚠️ `cryptoProviderId` is REQUIRED here, and its absence is what made four
    // earlier versions of this test vacuous. The era default is
    // `readsNskeyWritesLegacy` — it reads the nskey path and **writes legacy** —
    // so a notify that does not ask for the PQ provider goes out legacy, the
    // receiver opens it with no nskey private involved, and the park is never
    // entered. Every one of those runs looked like a product result.
    await sender.client.notificationService.notify(
        NotificationParams.forUpdate(key,
            value: value, cryptoProviderId: symmetricAesGcmCryptoProviderId),
        waitForFinalDeliveryStatus: false);

    // The notification must PARK — with the filing held, it cannot be opened,
    // and this is deterministic rather than raced.
    final deadline = DateTime.now().add(Duration(seconds: 60));
    while (notifications.parkedTotal == 0 && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(Duration(milliseconds: 100));
    }
    expect(notifications.parkedTotal, greaterThan(0),
        reason: 'with the filing held the receiver cannot hold the private, so '
            'the notification must be HELD rather than delivered or dropped — '
            'if this fails the run proves nothing about 14.30');
    expect(received.isCompleted, isFalse,
        reason: 'and it must not have been delivered yet: a value handed over '
            'before its key was filed would be ciphertext');

    // Release the hold: the pull's answer can now be stored, and the filing
    // signal is what releases the park.
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
