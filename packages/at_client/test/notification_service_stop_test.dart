import 'package:at_client/at_client.dart';
import 'package:at_client/memory.dart';
import 'package:at_client/src/service/notification_service_impl.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'notification_service_test.dart' show FakeMonitor;
import 'test_utils/fake_at_server.dart';
import 'test_utils/mocks.dart';
import 'test_utils/no_keys.dart';
import 'test_utils/transport.dart';

/// Catalogue: features/at_client/notification_service_stop_is_final.feature
void main() {
  final stopped = throwsA(isA<StoppedException>());

  Future<NotificationServiceImpl> listeningService() async {
    final atClient = MockAtClientImpl();
    when(() => atClient.getCurrentAtSign()).thenReturn('@alice');
    when(() => atClient.atSign).thenReturn(Atsign('@alice'));
    when(() => atClient.enrollmentId).thenReturn(null);
    when(() => atClient.getPreferences()).thenReturn(AtClientPreference()
      ..namespace = 'wavi'
      ..monitorAutoStart = false);
    final service = await NotificationServiceImpl.create(atClient,
        monitor: FakeMonitor(),
        secondaryAddressFinder: defaultAtDirectory) as NotificationServiceImpl;
    service.startListening();
    expect(service.targetListenerState, NotificationListenerState.listening,
        reason: 'the premise');
    expect(service.currentListenerState, NotificationListenerState.listening,
        reason: 'the premise');
    return service;
  }

  Future<AtClient> openClient(String atSign, {FakeAtServer? server}) =>
      buildAtClient(
          atSign: atSign,
          namespace: 'wavi',
          preference: AtClientPreference()
            ..namespace = 'wavi'
            ..monitorAutoStart = false,
          secondaryAddressFinder: defaultAtDirectory,
          atKeysIo: noKeysFor(atSign),
          lookUps: (server ?? FakeAtServer(atSign: atSign)).lookUps,
          storage:
              InMemoryAtClientStorage(atSign: atSign, closedByClient: true));

  test(
      'Stopping a notification service stops its listener even when told to '
      'keep it', () async {
    final service = await listeningService();

    service.stopAllSubscriptions(stopNotificationsListener: false);

    expect(service.targetListenerState, NotificationListenerState.notConnected,
        reason: 'a stopped service delivers nothing, so a listener kept '
            'connected would take in notifications that no subscriber '
            'receives');
    expect(
        service.currentListenerState, NotificationListenerState.notConnected);
  });

  test(
      'A notification service the app stopped refuses a subscription while '
      'its client runs', () async {
    final client = await openClient('@subscriber');
    addTearDown(client.stop);
    final notifications = client.notificationService;

    notifications.stopAllSubscriptions();

    expect(client.isStopped, isFalse, reason: 'the client still runs');
    expect(client.notificationService, same(notifications),
        reason: 'the client still hands out the service it stopped');
    expect(() => client.notificationService.subscribe(regex: 'wavi'), stopped);
    expect(
        () => client.notificationService.subscribeFiltered(namespace: 'wavi'),
        stopped);
  });

  test(
      'A notification service stopped with stopNotificationsListener false '
      'refuses to start listening', () async {
    final server = FakeAtServer(atSign: '@listener');
    final client = await openClient('@listener', server: server);
    addTearDown(client.stop);
    final notifications = client.notificationService;
    notifications.startListening();
    await server.waitUntil(
        () =>
            notifications.currentListenerState ==
            NotificationListenerState.listening,
        what: 'the premise: the monitor connecting');
    expect(
        notifications.targetListenerState, NotificationListenerState.listening,
        reason: 'the premise');

    notifications.stopAllSubscriptions(stopNotificationsListener: false);

    expect(notifications.targetListenerState,
        NotificationListenerState.notConnected,
        reason: 'false is ignored on a running client too: the listener '
            'stops with the service');
    await server.waitUntil(
        () =>
            notifications.currentListenerState ==
            NotificationListenerState.notConnected,
        what: 'the monitor disconnecting after the stop');
    expect(() => client.notificationService.startListening(), stopped);
  });

  group('Given a notification service the app has stopped', () {
    test(
        'when stopAllSubscriptions is called again, then it returns and the '
        'listener stays stopped', () async {
      final service = await listeningService();
      service.stopAllSubscriptions();
      expect(
          service.targetListenerState, NotificationListenerState.notConnected,
          reason: 'the premise');

      expect(service.stopAllSubscriptions, returnsNormally);

      expect(service.isStopped, isTrue);
      expect(
          service.targetListenerState, NotificationListenerState.notConnected);
      expect(
          service.currentListenerState, NotificationListenerState.notConnected);
    });
  });
}
