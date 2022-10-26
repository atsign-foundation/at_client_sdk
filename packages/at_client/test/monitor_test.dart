import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/manager/monitor.dart';
import 'package:at_client/src/preference/monitor_preference.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:test/test.dart';

import 'package:mocktail/mocktail.dart';

class MockMonitorConnectivityChecker extends Mock
    implements MonitorConnectivityChecker {}

class MockRemoteSecondary extends Mock implements RemoteSecondary {}

class MockSecureSocket extends Mock implements SecureSocket {}

class MockStreamSubscription<T> extends Mock implements StreamSubscription<T> {}

class MockOutboundConnection extends Mock implements OutboundConnection {}

class MockMonitorOutboundConnectionFactory extends Mock
    implements MonitorOutboundConnectionFactory {}

/// Note: The test code here prioritizes brevity over isolation
/// So while, right now, the tests are all passing despite sharing their mock objects, at some point
/// we will add a test where that assumption doesn't hold any more, and the tests will start failing
void main() {
  RemoteSecondary mockRemoteSecondary = MockRemoteSecondary();
  MonitorOutboundConnectionFactory mockMonitorOutboundConnectionFactory =
      MockMonitorOutboundConnectionFactory();
  MonitorConnectivityChecker mockMonitorConnectivityChecker =
      MockMonitorConnectivityChecker();
  OutboundConnection mockOutboundConnection = MockOutboundConnection();
  SecureSocket mockSocket = MockSecureSocket();
  late Function(dynamic data) socketOnDataFn;
  late Function() socketOnDoneFn;
  late Function(Exception e) socketOnErrorFn;

  var atSign = '@monitor_test';
  var fakeSecondaryUrl = "monitor_test:12345";
  var fakePrivateKey =
      'MIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQCDVMetuYSlcwNdS1yLgYE1oBEXaCFZjPq0Lk9w7yjKOqKgPCWnuVVly5+GBkYPYN3mPXbi/LHy3SqVM/8s5srxa+C8s5jk2pQI6BgG/RW59XM6vrGuw0pUQoL0bMyQxtR8XAFVgd54iDcgp4ZPLEH6odAgBraAtkIEpfwSwtMaWJCaS/Yn3q6ZoVOxL+O7DHD2dJWmwwjAJyDqEDeeNVuNHWnmj2ZneVXDnsY4fOR3IZdcGArM28FFcFIM6Q0K6XGiLGvJ2pYPywtzwARFChYJTBJYhNNLRgT+MUvx8fbNa6mMnnXQmagh/YvYwmyIUVQK1EhFNZIgezX9xdmIgS+FAgMBAAECggEAEq0z2FjRrFW23MWi25QHNAEXbSS52WpbHNSZJ45bVqcQCYmEMV4B7wAOJ5kszXMRG3USOyWEiO066Q0D9Pa9VafpxewkiicrdjjLcfL76/4j7O7BhgDvyRvMU8ZFMTGVdjn/VpGpeaqlbFdmmkvI9kOcvXE28wb4TIDuYBykuNI6twRqiaVd1LkKg9yoF0DGfSp8OHGWm/wz5wwnNYT6ofTbgV3gSGKOrLf4rC1swHh1VoNXiaYKQQFo2j23vGznC+hVJy8kAkSTMvRy4+SrZ+0MtYrNt0CI9n4hw79BNzwAd0kfJ5WCsYL6MaF8Giyym3Wl77KoiriwRF7cGCEnAQKBgQDWD+l1b6D8QCmrzxI1iZRoehfdlIlNviTxNks4yaDQ/tu6TC/3ySsRhKvwj7BqFYj2A6ULafeh08MfxpG0MfmJ+aJypC+MJixu/z/OXhQsscnR6avQtVLi9BIZV3EweyaD/yN/PB7IVLuhz6E6BV8kfNDb7UFZzrSSlvm1YzIdvQKBgQCdD5KVbcA88xkv/SrBpJcUME31TIR4DZPg8fSB+IDCnogSwXLxofadezH47Igc1CifLSQp4Rb+8sjVOTIoAXZKvW557fSQk3boR3aZ4CkheDznzjq0vY0qot4llkzHdiogaIUdPDwvYBwERzc73CO3We1pHs36bIz70Z3DRF5BaQKBgQC295jUARs4IVu899yXmEYa2yklAz4tDjajWoYHPwhPO1fysAZcJD3E1oLkttzSgB+2MD1VOTkpwEhLE74cqI6jqZV5qe7eOw7FvTT7npxd64UXAEUUurfjNz11HbGo/8pXDrB3o5qoHwzV7RPg9RByrqETKoMuUSk1FwjPSr9efQKBgAdC7w4Fkvu+aY20cMOfLnT6fsA2l3FNf2bJCPrxWFKnLbdgRkYxrMs/JOJTXT+n93DUj3V4OK3036AsEsuStbti4ra0b7g3eSnoE+2tVXl8q6Qz/rbYhKxR919ZgZc/OVdiPbVKUaYHFYSFHmKgHO6fM8DGcdOALUx/NoIOqSTxAoGBALUdiw8iyI98TFgmbSYjUj5id4MrYKXaR7ndS/SQFOBfJWVH09t5bTxXjKxKsK914/bIqEI71aussf5daOHhC03LdZIQx0ZcCdb2gL8vHNTQoqX75bLRN7J+zBKlwWjjrbhZCMLE/GtAJQNbpJ7jOrVeDwMAF8pK+Put9don44Gx';
  var fakeCertsLocation = '/home/ubuntu/Desktop/cert.pem';
  var fakeTlsKeysSavePath = '/home/ubuntu/Desktop/cert.pem';
  AtClientPreference atClientPreference = AtClientPreference();
  atClientPreference.privateKey = fakePrivateKey;
  atClientPreference.decryptPackets = true;
  atClientPreference.tlsKeysSavePath = fakeTlsKeysSavePath;
  atClientPreference.pathToCerts = fakeCertsLocation;

  group('Monitor constructor and start tests', () {
    setUp(() {
      reset(mockMonitorConnectivityChecker);
      reset(mockRemoteSecondary);
      reset(mockSocket);
      reset(mockOutboundConnection);
      reset(mockMonitorOutboundConnectionFactory);

      when(() => mockMonitorConnectivityChecker
          .checkConnectivity(mockRemoteSecondary)).thenAnswer((_) async {
        print('mock check connectivity - OK');
      });
      when(() => mockRemoteSecondary.isAvailable())
          .thenAnswer((_) async => true);
      when(() => mockRemoteSecondary.findSecondaryUrl())
          .thenAnswer((_) async => fakeSecondaryUrl);
      when(() => mockOutboundConnection.getSocket())
          .thenAnswer((_) => mockSocket);
      when(() => mockMonitorOutboundConnectionFactory.createConnection(
              fakeSecondaryUrl,
              decryptPackets: true,
              tlsKeysSavePath: fakeTlsKeysSavePath,
              pathToCerts: fakeCertsLocation))
          .thenAnswer((_) async => mockOutboundConnection);
      when(() => mockSocket.listen(any(),
          onError: any(named: "onError"),
          onDone: any(named: "onDone"))).thenAnswer((Invocation invocation) {
        socketOnDataFn = invocation.positionalArguments[0];
        socketOnDoneFn = invocation.namedArguments[#onDone];
        socketOnErrorFn = invocation.namedArguments[#onError];

        return MockStreamSubscription<Uint8List>();
      });

      when(() => mockOutboundConnection.write('from:$atSign\n'))
          .thenAnswer((Invocation invocation) async {
        socketOnDataFn("server challenge\n"
            .codeUnits); // actual challenge is different, of course, but not important for unit tests
      });
      when(() => mockOutboundConnection.write(any(that: startsWith('pkam:'))))
          .thenAnswer((Invocation invocation) async {
        socketOnDataFn("success\n".codeUnits);
      });
      when(() => mockOutboundConnection.write(any(that: startsWith('monitor'))))
          .thenAnswer((Invocation invocation) async {});
    });

    /// create a monitor without passing a heartbeat interval; it should pick it up from
    /// the AtClientPreference that was passed.
    test('Monitor gets heartbeatInterval from AtClientPreference', () {
      Monitor monitor = Monitor(
          (String json) => print('onResponse: $json'),
          (e) => print('onError: $e'),
          atSign,
          atClientPreference,
          MonitorPreference(),
          () => print('onRetry called'),
          monitorConnectivityChecker: mockMonitorConnectivityChecker,
          remoteSecondary: mockRemoteSecondary,
          monitorOutboundConnectionFactory:
              mockMonitorOutboundConnectionFactory);

      expect(monitor.heartbeatInterval,
          atClientPreference.monitorHeartbeatInterval);
      expect(
          monitor.heartbeatInterval ==
              atClientPreference.monitorHeartbeatInterval,
          true);
    });

    /// create a monitor and pass a heartbeat interval to constructor
    test('Monitor gets heartbeatInterval from constructor parameter', () {
      Duration customHeartbeatInterval =
          atClientPreference.monitorHeartbeatInterval + Duration(seconds: 22);

      Monitor monitor = Monitor(
          (String json) => print('onResponse: $json'),
          (e) => print('onError: $e'),
          atSign,
          atClientPreference,
          MonitorPreference(),
          () => print('onRetry called'),
          monitorConnectivityChecker: mockMonitorConnectivityChecker,
          remoteSecondary: mockRemoteSecondary,
          monitorOutboundConnectionFactory:
              mockMonitorOutboundConnectionFactory,
          monitorHeartbeatInterval: customHeartbeatInterval);

      expect(monitor.heartbeatInterval, customHeartbeatInterval);
      expect(
          monitor.heartbeatInterval ==
              atClientPreference.monitorHeartbeatInterval,
          false);
    });

    /// Create a Monitor with our mock connectivity checker, remote secondary and outbound connection factory.
    /// Start the monitor with a NULL last notification time
    /// Check that the monitor has started and has written the correct things to the socket
    test('Monitor start, secondary OK, NULL lastNotificationTime', () async {
      Monitor monitor = Monitor(
          (String json) => print('onResponse: $json'),
          (e) => print('onError: $e'),
          atSign,
          atClientPreference,
          MonitorPreference(),
          () => print('onRetry called'),
          monitorConnectivityChecker: mockMonitorConnectivityChecker,
          remoteSecondary: mockRemoteSecondary,
          monitorOutboundConnectionFactory:
              mockMonitorOutboundConnectionFactory);

      Future<void> monitorStartFuture =
          monitor.start(lastNotificationTime: null);
      await monitorStartFuture;

      final writesToSocket =
          verify(() => mockOutboundConnection.write(captureAny())).captured;
      expect(writesToSocket.length, 3);
      // We've created a monitor with a null lastNotificationTime - expect the command sent to the server to be simply 'monitor\n'
      expect(writesToSocket.last, 'monitor\n');
      expect(monitor.status, MonitorStatus.started);
    });

    /// Create a Monitor with our mock connectivity checker, remote secondary and outbound connection factory.
    /// Start the monitor with a REAL last notification time
    /// Check that the monitor has started and has written the correct things to the socket
    test('Monitor start, secondary OK, with a real lastNotificationTime',
        () async {
      Monitor monitor = Monitor(
          (String json) => print('onResponse: $json'),
          (e) => print('onError: $e'),
          atSign,
          atClientPreference,
          MonitorPreference(),
          () => print('onRetry called'),
          monitorConnectivityChecker: mockMonitorConnectivityChecker,
          remoteSecondary: mockRemoteSecondary,
          monitorOutboundConnectionFactory:
              mockMonitorOutboundConnectionFactory);

      int lastNotificationTime =
          DateTime.now().subtract(Duration(days: 1)).millisecondsSinceEpoch;
      Future<void> monitorStartFuture =
          monitor.start(lastNotificationTime: lastNotificationTime);
      await monitorStartFuture;

      final writesToSocket =
          verify(() => mockOutboundConnection.write(captureAny())).captured;
      expect(writesToSocket.length, 3);
      // We've created a monitor with a real lastNotificationTime
      expect(writesToSocket.last, 'monitor:$lastNotificationTime\n');
      expect(monitor.status, MonitorStatus.started);
    });

    test('Monitor start, secondary not available', () async {
      when(() => mockMonitorConnectivityChecker
          .checkConnectivity(mockRemoteSecondary)).thenAnswer((_) async {
        throw Exception('No No No');
      });

      Monitor monitor = Monitor(
          (String json) => print('onResponse: $json'),
          (e) => print('onError: $e'),
          atSign,
          atClientPreference,
          MonitorPreference(),
          () => print('onRetry called'),
          monitorConnectivityChecker: mockMonitorConnectivityChecker,
          remoteSecondary: mockRemoteSecondary,
          monitorOutboundConnectionFactory:
              mockMonitorOutboundConnectionFactory);

      Future<void> monitorStartFuture = monitor.start();
      await monitorStartFuture;
      expect(monitor.status, MonitorStatus.errored);
    });

    test('Monitor start, secondary OK, socket error', () async {
      Monitor monitor = Monitor(
          (String json) => print('onResponse: $json'),
          (e) => print('onError: $e'),
          atSign,
          atClientPreference,
          MonitorPreference(),
          () => print('onRetry called'),
          monitorConnectivityChecker: mockMonitorConnectivityChecker,
          remoteSecondary: mockRemoteSecondary,
          monitorOutboundConnectionFactory:
              mockMonitorOutboundConnectionFactory);

      Future<void> monitorStartFuture =
          monitor.start(lastNotificationTime: null);
      await monitorStartFuture;
      expect(monitor.status, MonitorStatus.started);

      when(() => mockOutboundConnection.close()).thenAnswer((_) async => {});
      socketOnErrorFn(Exception('Bad stuff has happened.'));
      expect(monitor.status, MonitorStatus.errored);
    });

    test('Monitor start, secondary OK, socket closed', () async {
      Monitor monitor = Monitor(
          (String json) => print('onResponse: $json'),
          (e) => print('onError: $e'),
          atSign,
          atClientPreference,
          MonitorPreference(),
          () => print('onRetry called'),
          monitorConnectivityChecker: mockMonitorConnectivityChecker,
          remoteSecondary: mockRemoteSecondary,
          monitorOutboundConnectionFactory:
              mockMonitorOutboundConnectionFactory);

      Future<void> monitorStartFuture =
          monitor.start(lastNotificationTime: null);
      await monitorStartFuture;
      expect(monitor.status, MonitorStatus.started);

      when(() => mockOutboundConnection.close()).thenAnswer((_) async => {});
      socketOnDoneFn();
      expect(monitor.status, MonitorStatus.stopped);
    });

    test('Monitor heartbeat sending regularly', () async {
      int heartbeatIntervalMillis = 500;
      Monitor monitor = Monitor(
          (String json) => print('onResponse: $json'),
          (e) => print('onError: $e'),
          atSign,
          atClientPreference,
          MonitorPreference(),
          () => print('onRetry called'),
          monitorConnectivityChecker: mockMonitorConnectivityChecker,
          remoteSecondary: mockRemoteSecondary,
          monitorOutboundConnectionFactory:
              mockMonitorOutboundConnectionFactory,
          monitorHeartbeatInterval:
              Duration(milliseconds: heartbeatIntervalMillis));

      int numHeartbeatsSent = 0;
      when(() => mockOutboundConnection.write("noop:0\n"))
          .thenAnswer((Invocation invocation) async {
        numHeartbeatsSent++;
        sleep(Duration(milliseconds: 1));
        socketOnDataFn("@ok\n".codeUnits);
      });

      when(() => mockOutboundConnection.close()).thenAnswer((_) async => {});

      Future<void> monitorStartFuture =
          monitor.start(lastNotificationTime: null);
      await monitorStartFuture;
      expect(monitor.status, MonitorStatus.started);

      // First off, let's verify that no heartbeat has yet been sent
      expect(monitor.lastHeartbeatSentTime, 0);
      // We expect the first heartbeat to be sent heartbeatIntervalMillis from now
      await Future.delayed(Duration(milliseconds: heartbeatIntervalMillis));
      // the lastHeartbeatSentTime should be very recent
      int now = DateTime.now().millisecondsSinceEpoch;

      expect((now - monitor.lastHeartbeatSentTime) < 15, true);
      // and we should only have sent one heartbeat so far
      expect(numHeartbeatsSent, 1);
      // and the monitor status is still 'started'
      expect(monitor.status, MonitorStatus.started);

      // Now let's wait long enough for 5 heartbeats to be sent, check they have all been sent,
      // and check that the monitor status is still 'started'
      int additionalHeartbeatsToSend = 5;
      await Future.delayed(Duration(
          milliseconds: heartbeatIntervalMillis * additionalHeartbeatsToSend +
              (heartbeatIntervalMillis / 3).floor()));
      int expectedHeartbeatCount = 1 + additionalHeartbeatsToSend;
      expect(numHeartbeatsSent, expectedHeartbeatCount);
      expect(monitor.status, MonitorStatus.started);

      // Now let's simulate the socket is calling 'onDone'
      // Since our retryCallback in this test doesn't do anything, the monitor's status should
      // go to 'stopped' and the heartbeats should no longer be scheduled.
      socketOnDoneFn();
      expect(monitor.status, MonitorStatus.stopped);
      await Future.delayed(Duration(milliseconds: heartbeatIntervalMillis * 3));
      expect(numHeartbeatsSent, expectedHeartbeatCount);
    });

    test('Monitor heartbeat response not received in time', () async {
      int heartbeatIntervalMillis = 500;
      Monitor? monitor;
      // Note that in this test, our retryCallback is doing something real - it's restarting the monitor
      bool retryCallbackCalled = false;
      void retryCallback() {
        retryCallbackCalled = true;
        print('retryCallback called - will restart the monitor in a second');
        Future.delayed(Duration(seconds: 1), () {
          print('restarting the monitor');
          monitor!.start(lastNotificationTime: null);
        });
      }

      monitor = Monitor(
          (String json) => print('onResponse: $json'),
          (e) => print('onError: $e'),
          atSign,
          atClientPreference,
          MonitorPreference(),
          () => retryCallback(),
          monitorConnectivityChecker: mockMonitorConnectivityChecker,
          remoteSecondary: mockRemoteSecondary,
          monitorOutboundConnectionFactory:
              mockMonitorOutboundConnectionFactory,
          monitorHeartbeatInterval:
              Duration(milliseconds: heartbeatIntervalMillis));

      int numHeartbeatsSent = 0;
      bool sendHeartbeatResponse = true;
      when(() => mockOutboundConnection.write("noop:0\n"))
          .thenAnswer((Invocation invocation) async {
        numHeartbeatsSent++;
        if (sendHeartbeatResponse) {
          sleep(Duration(milliseconds: 1));
          socketOnDataFn("@ok\n".codeUnits);
        }
      });

      when(() => mockOutboundConnection.close()).thenAnswer((_) async => {});

      Future<void> monitorStartFuture =
          monitor.start(lastNotificationTime: null);
      await monitorStartFuture;
      expect(monitor.status, MonitorStatus.started);

      // Now let's wait long enough for 5 heartbeats to be sent, check they have all been sent,
      // and check that the monitor status is still 'started'
      int additionalHeartbeatsToSend = 5;
      await Future.delayed(Duration(
          milliseconds: heartbeatIntervalMillis * additionalHeartbeatsToSend +
              50)); // 50 == fudge factor
      int expectedHeartbeatCount = additionalHeartbeatsToSend;
      expect(numHeartbeatsSent, expectedHeartbeatCount);
      expect(monitor.status, MonitorStatus.started);

      // Let's NOT send a response to the next heartbeat(s).
      sendHeartbeatResponse = false;

      // Let's wait long enough for the heartbeat to be sent
      await Future.delayed(
          Duration(milliseconds: heartbeatIntervalMillis.floor()));
      // Let's check that at least one more heartbeat has indeed been sent
      expect(numHeartbeatsSent > expectedHeartbeatCount, true);
      // Now let's wait long enough for the heartbeat response monitor to detect that the socket seems dead
      await Future.delayed(Duration(
          milliseconds: (heartbeatIntervalMillis / 3).floor() +
              50)); // 50 == fudge factor
      // The Monitor should have set status to stopped
      expect(monitor.status, MonitorStatus.stopped);
      // let's start sending responses to heartbeats again
      sendHeartbeatResponse = true;

      // And the retryCallback should have been called
      expect(retryCallbackCalled, true);
      // And the retryCallback will restart the monitor after a second, so the monitor state should be 'started' again
      await Future.delayed(Duration(seconds: 1));
      expect(monitor.status, MonitorStatus.started);

      // Finally, let's make sure that heartbeats are happening again, and the monitor is still happy
      int lastHeartbeatCount = numHeartbeatsSent;
      additionalHeartbeatsToSend = 5;
      await Future.delayed(Duration(
          milliseconds: heartbeatIntervalMillis * additionalHeartbeatsToSend +
              50)); // 50 == fudge factor
      expectedHeartbeatCount = lastHeartbeatCount + additionalHeartbeatsToSend;
      expect(numHeartbeatsSent >= expectedHeartbeatCount, true);
      expect(monitor.status, MonitorStatus.started);
    });
  });

  group('A group of tests to validate verb queue', () {
    test('test when verb queue response is not populated', () async {
      Monitor monitor = Monitor(
          (String json) => print('onResponse: $json'),
          (e) => print('onError: $e'),
          atSign,
          atClientPreference,
          MonitorPreference(),
          () => print('onRetry called'),
          monitorConnectivityChecker: mockMonitorConnectivityChecker,
          remoteSecondary: mockRemoteSecondary,
          monitorOutboundConnectionFactory:
              mockMonitorOutboundConnectionFactory);

      expect(() async => await monitor.getQueueResponse(maxWaitTimeInMillis: 10),
          throwsA(predicate((dynamic e) => e is AtTimeoutException)));
    });

    test('test when verb queue response is populated with data: response', () async {
      Monitor monitor = Monitor(
          (String json) => print('onResponse: $json'),
          (e) => print('onError: $e'),
          atSign,
          atClientPreference,
          MonitorPreference(),
          () => print('onRetry called'),
          monitorConnectivityChecker: mockMonitorConnectivityChecker,
          remoteSecondary: mockRemoteSecondary,
          monitorOutboundConnectionFactory:
              mockMonitorOutboundConnectionFactory);
      monitor.addMonitorResponseToQueue('data:success');

      var response = await monitor.getQueueResponse();
      expect(response, 'success');
    });

    test('test when verb queue response is populated with error: response', () async {
      Monitor monitor = Monitor(
              (String json) => print('onResponse: $json'),
              (e) => print('onError: $e'),
          atSign,
          atClientPreference,
          MonitorPreference(),
              () => print('onRetry called'),
          monitorConnectivityChecker: mockMonitorConnectivityChecker,
          remoteSecondary: mockRemoteSecondary,
          monitorOutboundConnectionFactory:
          mockMonitorOutboundConnectionFactory);
      monitor.addMonitorResponseToQueue('error: AT0003 - Invalid syntax exception');

      expect(() async => await monitor.getQueueResponse(maxWaitTimeInMillis: 10),
          throwsA(predicate((dynamic e) => e is AtClientException)));

    });
  });
}
