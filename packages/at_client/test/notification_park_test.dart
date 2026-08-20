import 'dart:async';
import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/manager/monitor.dart';
import 'package:at_client/src/service/notification_service_impl.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';

const _owner = '@alice';
const _namespace = 'wavi';
const _kid = 'gen-1';

class _FakeMonitor extends Fake implements Monitor {
  @override
  NotificationListenerState currentState =
      NotificationListenerState.notConnected;
  @override
  NotificationListenerState targetState =
      NotificationListenerState.notConnected;
  @override
  Future<void> start({int? lastNotificationTime}) async {}
  @override
  void stop() {}
  @override
  Stream<NotificationListenerState> get currentStateStream =>
      const Stream.empty();
}

/// Refuses to decrypt until [filed] is set — the live shape exactly: the
/// private is conveyed at approval and lands a fraction of a second after the
/// value sealed to it.
class _WaitingProvider extends CryptoProvider {
  @override
  final String id = 'waiting-provider';
  bool filed = false;

  @override
  Future<String> decrypt(
      CryptoContext context, AtKey atKey, String value) async {
    if (!filed) {
      throw NskeyPrivateUnavailableException(
          _owner, _namespace, _kid, 'not yet received that generation');
    }
    return 'opened:$value';
  }

  @override
  Future<String> encrypt(
          CryptoContext context, AtKey atKey, String value) async =>
      value;
}

/// Fails for a reason no filing can fix, so it must be dropped rather than
/// parked — the control that separates "wait" from "give up".
class _HopelessProvider extends CryptoProvider {
  @override
  final String id = 'hopeless-provider';

  @override
  Future<String> decrypt(CryptoContext context, AtKey atKey, String value) =>
      throw AtDecryptionException('the ciphertext is corrupt');

  @override
  Future<String> encrypt(
          CryptoContext context, AtKey atKey, String value) async =>
      value;
}

/// A ring that emits the filing signal on demand.
class _SignallingRing extends InMemoryNskeyKeyRing
    implements SignalsPrivateFiling {
  final _controller = StreamController<FiledNskeyPrivate>.broadcast();

  @override
  Stream<FiledNskeyPrivate> get privatesFiled => _controller.stream;

  void announce(
          {String owner = _owner,
          String namespace = _namespace,
          String nskeyKid = _kid}) =>
      _controller.add((owner: owner, namespace: namespace, nskeyKid: nskeyKid));

  Future<void> dispose() => _controller.close();
}

String _frame(String key, String providerId) => 'notification: ${jsonEncode({
          'id': 'n-${key.hashCode}',
          'key': key,
          'from': _owner,
          'to': _owner,
          'epochMillis': DateTime.now().millisecondsSinceEpoch,
          'value': 'sealed',
          'operation': 'update',
          'messageType': MessageTypeEnum.key.toString(),
          AtConstants.isEncrypted: true,
          'metadata': {
            AtConstants.appMetadata:
                Metadata.encodeAppMetadata(AppMetadata(providerId: providerId)),
          },
        })}\n';

void main() {
  late MockAtClientImpl atClient;
  late _SignallingRing ring;
  late _WaitingProvider waiting;
  late NotificationServiceImpl service;

  setUpAll(() => registerFallbackValue(FakeAtKey()));

  Future<NotificationServiceImpl> build() async {
    ring = _SignallingRing();
    waiting = _WaitingProvider();
    when(() => atClient.getCurrentAtSign()).thenReturn(_owner);
    when(() => atClient.atSign).thenReturn(_owner.toAtsign());
    when(() => atClient.getPreferences()).thenReturn(AtClientPreference()
      ..namespace = _namespace
      ..crypto = CryptoConfig(
        defaultProviderId: waiting.id,
        providers: [waiting, _HopelessProvider()],
        // The ring the service subscribes to for filings.
        keyRing: ring,
      ));
    return await NotificationServiceImpl.create(atClient,
        monitor: _FakeMonitor()) as NotificationServiceImpl;
  }

  setUp(() async {
    atClient = MockAtClientImpl();
    service = await build();
  });

  tearDown(() async {
    service.stopAllSubscriptions();
    await ring.dispose();
  });

  test('a notification whose key has not arrived is parked, not dropped',
      () async {
    final seen = <AtNotification>[];
    service.subscribe(shouldDecrypt: true).listen(seen.add);

    await service.handleNotificationReceipt(
        _frame('@alice:treaty.$_namespace@alice', waiting.id));
    await Future<void>.delayed(Duration.zero);

    expect(seen, isEmpty,
        reason: 'the value cannot be opened yet — delivering it undecrypted '
            'would hand the subscriber ciphertext');
    expect(service.parkedCount, 1,
        reason: 'and it is HELD: dropping it loses a message whose key lands '
            'milliseconds later, with the record still on the atServer');
  });

  test('filing the generation it waits for delivers it', () async {
    final seen = <AtNotification>[];
    service.subscribe(shouldDecrypt: true).listen(seen.add);

    await service.handleNotificationReceipt(
        _frame('@alice:treaty.$_namespace@alice', waiting.id));
    await Future<void>.delayed(Duration.zero);
    expect(seen, isEmpty, reason: 'precondition: it parked');

    waiting.filed = true;
    ring.announce();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(seen.map((n) => n.value), ['opened:sealed'],
        reason: 'the whole point: the message survives the race instead of '
            'being lost to it');
    expect(service.parkedCount, 0);
  });

  test('a filing for a different generation releases nothing', () async {
    final seen = <AtNotification>[];
    service.subscribe(shouldDecrypt: true).listen(seen.add);

    await service.handleNotificationReceipt(
        _frame('@alice:treaty.$_namespace@alice', waiting.id));
    await Future<void>.delayed(Duration.zero);

    waiting.filed = true;
    ring.announce(nskeyKid: 'some-other-generation');
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(seen, isEmpty,
        reason: 'holding A private for the namespace is not holding THE one '
            'this record was sealed to — releasing on any filing would deliver '
            'a value that still cannot be opened');
    expect(service.parkedCount, 1);
  });

  test('a failure no filing can fix is dropped, not parked', () async {
    final seen = <AtNotification>[];
    service.subscribe(shouldDecrypt: true).listen(seen.add);

    await service.handleNotificationReceipt(
        _frame('@alice:corrupt.$_namespace@alice', 'hopeless-provider'));
    await Future<void>.delayed(Duration.zero);

    expect(seen, isEmpty);
    expect(service.parkedCount, 0,
        reason: 'the park is for a key that is coming; a corrupt ciphertext '
            'would sit there until its ttl and be dropped anyway, having '
            'delayed nothing but the report');
  });

  test('the park is bounded, and says what it drops', () async {
    NotificationServiceImpl.maxParked = 2;
    addTearDown(() => NotificationServiceImpl.maxParked = 64);

    service.subscribe(shouldDecrypt: true).listen((_) {});
    for (var i = 0; i < 4; i++) {
      await service.handleNotificationReceipt(
          _frame('@alice:treaty$i.$_namespace@alice', waiting.id));
    }
    await Future<void>.delayed(Duration.zero);

    expect(service.parkedCount, 2,
        reason: 'a park that grows without limit is a leak, and a held '
            'notification nothing re-drives is the same data loss with a '
            'longer fuse');
  });
}
