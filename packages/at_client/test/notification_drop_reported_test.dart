import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/manager/monitor.dart';
import 'package:at_client/src/service/notification_service_impl.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';
import 'test_utils/recorded_logs.dart';
import 'test_utils/transport.dart';

const _atSign = '@juliet';

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

String _frame(String key, String providerId) => 'notification: ${jsonEncode({
          'id': 'n-${key.hashCode}',
          'key': key,
          'from': '@india',
          'to': _atSign,
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

/// A notification a client cannot decrypt is dropped with a warning that
/// names it and says why, and [NotificationService.droppedEvents] reports it.
///
/// Catalogue: features/at_client/notification_drop_reported.feature
void main() {
  final logs = RecordedLogs();

  setUpAll(() {
    logs.installOn();
    registerFallbackValue(FakeAtKey());
  });

  setUp(logs.records.clear);

  Future<NotificationService> serviceAt(AtClientPreference preference) async {
    final atClient = MockAtClientImpl();
    when(() => atClient.getCurrentAtSign()).thenReturn(_atSign);
    when(() => atClient.atSign).thenReturn(_atSign.toAtsign());
    when(() => atClient.getPreferences()).thenReturn(preference);
    when(() => atClient.put(any(), any(),
            putRequestOptions: any(named: 'putRequestOptions')))
        .thenAnswer((_) async => true);
    final service = await NotificationServiceImpl.create(atClient,
        monitor: _FakeMonitor(), secondaryAddressFinder: defaultAtDirectory);
    addTearDown(service.stopAllSubscriptions);
    return service;
  }

  test('A notification a client cannot decrypt is reported, not lost silently',
      () async {
    final service = await serviceAt(AtClientPreference()..namespace = 'sensor');
    final dropped = <DroppedNotification>[];
    service.droppedEvents.listen(dropped.add);
    final seen = <AtNotification>[];
    service.subscribe(shouldDecrypt: true).listen(seen.add);
    const key = '@juliet:reading.d1.sensor@india';

    await (service as NotificationServiceImpl).handleNotificationReceipt(
        _frame(key, symmetricAesGcmCryptoProviderId));
    await Future<void>.delayed(Duration.zero);

    expect(seen, isEmpty);
    expect(dropped.map((d) => d.key), [key], reason: 'droppedEvents emits it');
    expect(
        logs.at('WARNING'),
        contains(allOf(
            contains(key), contains('PqPosture.legacy'), contains('restart'))),
        reason: 'the warning names the notification and the posture, and '
            'says what reads it');
  });

  for (final (shape, preference, providerId) in [
    (
      'a legacy client missing a provider an app chose',
      AtClientPreference(),
      'app-own-provider'
    ),
    (
      'a client whose posture reads post-quantum data',
      AtClientPreference(posture: PqPosture.pqReady),
      symmetricAesGcmCryptoProviderId
    ),
  ]) {
    test('$shape is told to register the provider', () async {
      final service = await serviceAt(preference..namespace = 'sensor');
      final dropped = <DroppedNotification>[];
      service.droppedEvents.listen(dropped.add);
      service.subscribe(shouldDecrypt: true).listen((_) {});

      await (service as NotificationServiceImpl).handleNotificationReceipt(
          _frame('@juliet:reading.d1.sensor@india', providerId));
      await Future<void>.delayed(Duration.zero);

      expect(dropped.single.reason,
          contains('Add it to AtClientPreference.crypto.providers'));
      expect(dropped.single.reason, isNot(contains('restart')));
    });
  }
}
