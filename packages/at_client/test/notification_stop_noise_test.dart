import 'package:at_client/at_client.dart';
import 'package:at_client/src/manager/monitor.dart';
import 'package:at_client/src/service/notification_service_impl.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';
import 'test_utils/recorded_logs.dart';

class _FakeMonitor extends Fake implements Monitor {
  @override
  NotificationListenerState currentState =
      NotificationListenerState.notConnected;

  @override
  NotificationListenerState targetState =
      NotificationListenerState.notConnected;

  @override
  void start() {
    currentState = NotificationListenerState.listening;
    targetState = NotificationListenerState.listening;
  }

  @override
  Future<void> stop() async {
    currentState = NotificationListenerState.notConnected;
    targetState = NotificationListenerState.notConnected;
  }
}

class _FakeNotifyVerbBuilder extends Fake implements NotifyVerbBuilder {}

/// What the notification service does with a failure nobody is waiting for:
/// the status poll a caller declined to await, and the watermark write a
/// stop lands on.
void main() {
  final recorded = RecordedLogs();
  late MockAtClientImpl atClient;
  late MockRemoteSecondary remote;
  late NotificationServiceImpl service;

  setUpAll(() {
    recorded.installOn(level: 'finer');
    registerFallbackValue(AtKey());
    registerFallbackValue(_FakeNotifyVerbBuilder());
    registerFallbackValue(PutRequestOptions());
  });

  setUp(() async {
    recorded.records.clear();
    atClient = MockAtClientImpl();
    remote = MockRemoteSecondary();
    final finder = MockSecondaryAddressFinder();
    when(() => atClient.getCurrentAtSign()).thenReturn('@alice');
    when(() => atClient.atSign).thenReturn(Atsign('@alice'));
    when(() => atClient.enrollmentId).thenReturn(null);
    when(() => atClient.atChops).thenReturn(MockAtChops());
    when(() => atClient.getPreferences()).thenReturn(AtClientPreference()
      ..namespace = 'wavi'
      ..monitorAutoStart = false);
    when(() => atClient.getRemoteSecondary()).thenReturn(remote);
    when(() => remote.executeVerb(any())).thenAnswer((_) async => 'data:n1');
    when(() => finder.findSecondary('@bob'))
        .thenAnswer((_) async => SecondaryAddress('bob.example', 1));
    service = await NotificationServiceImpl.create(atClient,
        monitor: _FakeMonitor(),
        secondaryAddressFinder: finder) as NotificationServiceImpl;
  });

  NotificationParams params() => NotificationParams.forUpdate(
      (AtKey.shared('phone', namespace: 'wavi', sharedBy: '@alice')
            ..sharedWith('@bob'))
          .build());

  group('the status poll nobody awaits', () {
    test('a failure reaches onError and the log, not the zone', () async {
      when(() => atClient.notifyStatus(any())).thenThrow(AtLookUpException(
          'AT0014',
          'The connection was closed by this client before a response '
              'arrived'));
      NotificationResult? errored;

      await service.notify(params(),
          waitForFinalDeliveryStatus: false,
          onError: (NotificationResult r) => errored = r);
      // Past the poll's first delay.
      await Future.delayed(const Duration(milliseconds: 800));

      expect(errored, isNotNull,
          reason: 'the caller asked for the failure through onError; '
              'before this the poll threw into whatever zone sent the '
              'notification, which no caller can catch');
      expect(errored!.atClientException?.message,
          contains('Could not learn the final status'));
      expect(
          recorded.at('WARNING'),
          contains(
              contains('Could not learn the final status of notification')));
    });

    test('stop() ends it, and the result says so', () async {
      when(() => atClient.notifyStatus(any()))
          .thenAnswer((_) async => 'data:queued');
      NotificationResult? errored;

      final pending = service.notify(params(),
          onError: (NotificationResult r) => errored = r);
      await Future.delayed(const Duration(milliseconds: 100));
      await service.stop();

      final result = await pending;
      expect(result.atClientException?.message, contains('Stopped before'),
          reason: 'a stopped service has nobody to hand a final status to, '
              'so the poll ends at its next turn instead of asking a closed '
              'connection every two seconds; the caller stopped its own '
              'client, so the result carries that rather than a throw');
      expect(errored, same(result));
    });
  });

  group('the watermark write a stop lands on', () {
    String notification(String id) =>
        '{"id":"$id","from":"@alice","to":"@alice","key":"$id.wavi@alice",'
        '"value":null,"operation":"update","epochMillis":1,'
        '"messageType":"MessageType.key","isEncrypted":false}';

    test('is logged as the stop it was, not as a failed save', () async {
      when(() => atClient.put(any(), any(),
          putRequestOptions: any(named: 'putRequestOptions'))).thenAnswer((_) {
        service.isStopped = true;
        throw StateError('Cannot add new events after calling close');
      });

      await service
          .handleNotificationReceipt('notification: ${notification('n1')}');

      expect(
          recorded.at('WARNING'),
          isNot(contains(
              contains('Failed to save last received notification ID'))),
          reason: 'the store closed because stop() closed it; that is not a '
              'save that failed');
      expect(recorded.at('FINER'),
          contains(contains('Not saving the last received notification ID')));
    });

    test('the same failure while running is a failed save (control)', () async {
      when(() => atClient.put(any(), any(),
              putRequestOptions: any(named: 'putRequestOptions')))
          .thenThrow(StateError('Cannot add new events after calling close'));

      await service
          .handleNotificationReceipt('notification: ${notification('n1')}');

      expect(recorded.at('WARNING'),
          contains(contains('Failed to save last received notification ID')));
    });
  });
}
