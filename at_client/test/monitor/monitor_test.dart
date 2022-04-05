import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:at_client/src/client/remote_secondary.dart';
import 'package:at_client/src/manager/monitor.dart';
import 'package:at_client/src/preference/at_client_preference.dart';
import 'package:at_client/src/preference/monitor_preference.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:test/test.dart';

import 'package:mocktail/mocktail.dart';

class MockMonitorConnectivityChecker extends Mock implements MonitorConnectivityChecker {}

class MockRemoteSecondary extends Mock implements RemoteSecondary {}

class MockSecureSocket extends Mock implements SecureSocket {}

class MockStreamSubscription<T> extends Mock implements StreamSubscription<T> {}

class MockOutboundConnection extends Mock implements OutboundConnection {}

class MockMonitorOutboundConnectionFactory extends Mock implements MonitorOutboundConnectionFactory {}

/// Note: The test code here prioritizes brevity over isolation, therefore you need to run the tests with --concurrency=1
void main() {
  RemoteSecondary remoteSecondary = MockRemoteSecondary();
  MonitorOutboundConnectionFactory monitorOutboundConnectionFactory = MockMonitorOutboundConnectionFactory();
  MonitorConnectivityChecker monitorConnectivityChecker = MockMonitorConnectivityChecker();
  OutboundConnection outboundConnection = MockOutboundConnection();
  SecureSocket socket = MockSecureSocket();
  late Function(dynamic data) socketOnDataFn;
  // ignore: unused_local_variable
  late Function() socketOnDoneFn;
  // ignore: unused_local_variable
  late Function(Exception e) socketOnErrorFn;

  var atSign = '@monitor_test';
  var fakeSecondaryUrl = "monitor_test:12345";
  var fakePrivateKey = 'MIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQCDVMetuYSlcwNdS1yLgYE1oBEXaCFZjPq0Lk9w7yjKOqKgPCWnuVVly5+GBkYPYN3mPXbi/LHy3SqVM/8s5srxa+C8s5jk2pQI6BgG/RW59XM6vrGuw0pUQoL0bMyQxtR8XAFVgd54iDcgp4ZPLEH6odAgBraAtkIEpfwSwtMaWJCaS/Yn3q6ZoVOxL+O7DHD2dJWmwwjAJyDqEDeeNVuNHWnmj2ZneVXDnsY4fOR3IZdcGArM28FFcFIM6Q0K6XGiLGvJ2pYPywtzwARFChYJTBJYhNNLRgT+MUvx8fbNa6mMnnXQmagh/YvYwmyIUVQK1EhFNZIgezX9xdmIgS+FAgMBAAECggEAEq0z2FjRrFW23MWi25QHNAEXbSS52WpbHNSZJ45bVqcQCYmEMV4B7wAOJ5kszXMRG3USOyWEiO066Q0D9Pa9VafpxewkiicrdjjLcfL76/4j7O7BhgDvyRvMU8ZFMTGVdjn/VpGpeaqlbFdmmkvI9kOcvXE28wb4TIDuYBykuNI6twRqiaVd1LkKg9yoF0DGfSp8OHGWm/wz5wwnNYT6ofTbgV3gSGKOrLf4rC1swHh1VoNXiaYKQQFo2j23vGznC+hVJy8kAkSTMvRy4+SrZ+0MtYrNt0CI9n4hw79BNzwAd0kfJ5WCsYL6MaF8Giyym3Wl77KoiriwRF7cGCEnAQKBgQDWD+l1b6D8QCmrzxI1iZRoehfdlIlNviTxNks4yaDQ/tu6TC/3ySsRhKvwj7BqFYj2A6ULafeh08MfxpG0MfmJ+aJypC+MJixu/z/OXhQsscnR6avQtVLi9BIZV3EweyaD/yN/PB7IVLuhz6E6BV8kfNDb7UFZzrSSlvm1YzIdvQKBgQCdD5KVbcA88xkv/SrBpJcUME31TIR4DZPg8fSB+IDCnogSwXLxofadezH47Igc1CifLSQp4Rb+8sjVOTIoAXZKvW557fSQk3boR3aZ4CkheDznzjq0vY0qot4llkzHdiogaIUdPDwvYBwERzc73CO3We1pHs36bIz70Z3DRF5BaQKBgQC295jUARs4IVu899yXmEYa2yklAz4tDjajWoYHPwhPO1fysAZcJD3E1oLkttzSgB+2MD1VOTkpwEhLE74cqI6jqZV5qe7eOw7FvTT7npxd64UXAEUUurfjNz11HbGo/8pXDrB3o5qoHwzV7RPg9RByrqETKoMuUSk1FwjPSr9efQKBgAdC7w4Fkvu+aY20cMOfLnT6fsA2l3FNf2bJCPrxWFKnLbdgRkYxrMs/JOJTXT+n93DUj3V4OK3036AsEsuStbti4ra0b7g3eSnoE+2tVXl8q6Qz/rbYhKxR919ZgZc/OVdiPbVKUaYHFYSFHmKgHO6fM8DGcdOALUx/NoIOqSTxAoGBALUdiw8iyI98TFgmbSYjUj5id4MrYKXaR7ndS/SQFOBfJWVH09t5bTxXjKxKsK914/bIqEI71aussf5daOHhC03LdZIQx0ZcCdb2gL8vHNTQoqX75bLRN7J+zBKlwWjjrbhZCMLE/GtAJQNbpJ7jOrVeDwMAF8pK+Put9don44Gx';

  AtClientPreference atClientPreference = AtClientPreference();
  atClientPreference.privateKey = fakePrivateKey;

  group('Monitor start tests', () {
    setUp(() {
      when(() => monitorConnectivityChecker.checkConnectivity(remoteSecondary)).thenAnswer((_) async {
        print('mock check connectivity - OK');
      });
      when(() => remoteSecondary.isAvailable()).thenAnswer((_) async => true);
      when(() => remoteSecondary.findSecondaryUrl()).thenAnswer((_) async => fakeSecondaryUrl);
      when(() => outboundConnection.getSocket()).thenAnswer((_) => socket);
      when(() => monitorOutboundConnectionFactory.createConnection(fakeSecondaryUrl)).thenAnswer((_) async => outboundConnection);
      when(() => socket.listen(any(), onError: any(named: "onError"), onDone: any(named: "onDone")))
          .thenAnswer((Invocation invocation) {
        socketOnDataFn = invocation.positionalArguments[0];
        socketOnDoneFn = invocation.namedArguments[#onDone];
        socketOnErrorFn = invocation.namedArguments[#onError];

        return MockStreamSubscription<Uint8List>();
      });

      when(() => outboundConnection.write('from:$atSign\n')).thenAnswer((Invocation invocation) async {
        socketOnDataFn("server challenge\n".codeUnits); // actual challenge is different, of course, but not important for unit tests
      });
      when(() => outboundConnection.write(any(that: startsWith('pkam:')))).thenAnswer((Invocation invocation) async {
        socketOnDataFn("success\n".codeUnits);
      });
      when(() => outboundConnection.write(any(that: startsWith('monitor')))).thenAnswer((Invocation invocation) async {});
    });
    tearDown(() {
      reset(monitorConnectivityChecker);
      reset(remoteSecondary);
      reset(socket);
      reset(outboundConnection);
      reset(monitorOutboundConnectionFactory);
    });

    /// Create a Monitor with our mock connectivity checker, remote secondary and outbound connection factory.
    /// Start the monitor with a NULL last notification time
    /// Check that the monitor has started and has written the correct things to the socket
    test('Monitor start, secondary OK, NULL lastNotificationTime', () async {
      Monitor monitor = Monitor((String json) => print('onResponse: $json'), (e) => print('onError: $e'), atSign, atClientPreference,
          MonitorPreference(), () => print('onRetry called'),
          monitorConnectivityChecker: monitorConnectivityChecker,
          remoteSecondary: remoteSecondary,
          monitorOutboundConnectionFactory: monitorOutboundConnectionFactory);

      Future<void> monitorStartFuture = monitor.start(lastNotificationTime: null);
      await monitorStartFuture;

      // We're going to create a monitor with a null lastNotificationTime - expect the command sent to the server to be simply 'monitor\n'
      final writesToSocket = verify(() => outboundConnection.write(captureAny())).captured;
      expect(writesToSocket.length, 3);
      expect(writesToSocket.last, 'monitor\n');
      expect(monitor.status, MonitorStatus.started);
    });

    /// Create a Monitor with our mock connectivity checker, remote secondary and outbound connection factory.
    /// Start the monitor with a REAL last notification time
    /// Check that the monitor has started and has written the correct things to the socket
    test('Monitor start, secondary OK, with a real lastNotificationTime', () async {
      Monitor monitor = Monitor((String json) => print('onResponse: $json'), (e) => print('onError: $e'), atSign, atClientPreference,
          MonitorPreference(), () => print('onRetry called'),
          monitorConnectivityChecker: monitorConnectivityChecker,
          remoteSecondary: remoteSecondary,
          monitorOutboundConnectionFactory: monitorOutboundConnectionFactory);

      int lastNotificationTime = DateTime.now().subtract(Duration(days: 1)).millisecondsSinceEpoch;
      Future<void> monitorStartFuture = monitor.start(lastNotificationTime: lastNotificationTime);
      await monitorStartFuture;

      // We're going to create a monitor with a real lastNotificationTime - this time we're
      // going to capture what was written to socket and compare it with what's expected
      final writesToSocket = verify(() => outboundConnection.write(captureAny())).captured;
      expect(writesToSocket.length, 3);
      expect(writesToSocket.last, 'monitor:$lastNotificationTime\n');
      expect(monitor.status, MonitorStatus.started);
    });

    test('Monitor start, secondary not reachable', () async {
      when(() => monitorConnectivityChecker.checkConnectivity(remoteSecondary)).thenThrow(Exception('Secondary is not reachable'));

      Monitor monitor = Monitor((String json) => print('onResponse: $json'), (e) => print('onError: $e'), atSign, atClientPreference,
          MonitorPreference(), () => print('onRetry called'),
          monitorConnectivityChecker: monitorConnectivityChecker,
          remoteSecondary: remoteSecondary,
          monitorOutboundConnectionFactory: monitorOutboundConnectionFactory);

      Future<void> monitorStartFuture = monitor.start();
      await monitorStartFuture;

      expect(monitor.status, MonitorStatus.errored);
    });

    test('Monitor start, secondary OK, then socket error', () async {
      when(() => outboundConnection.close()).thenAnswer((_) async {});

      Monitor monitor = Monitor((String json) => print('onResponse: $json'), (e) => print('onError: $e'), atSign, atClientPreference,
          MonitorPreference(), () => print('onRetry called'),
          monitorConnectivityChecker: monitorConnectivityChecker,
          remoteSecondary: remoteSecondary,
          monitorOutboundConnectionFactory: monitorOutboundConnectionFactory);

      int lastNotificationTime = DateTime.now().subtract(Duration(days: 1)).millisecondsSinceEpoch;
      Future<void> monitorStartFuture = monitor.start(lastNotificationTime: lastNotificationTime);
      await monitorStartFuture;

      expect(monitor.status, MonitorStatus.started);

      socketOnErrorFn(Exception('Simulated socket error'));
      expect(monitor.status, MonitorStatus.errored);
    });

    test('Monitor start, secondary OK, then socket closed', () async {
      Monitor monitor = Monitor((String json) => print('onResponse: $json'), (e) => print('onError: $e'), atSign, atClientPreference,
          MonitorPreference(), () => print('onRetry called'),
          monitorConnectivityChecker: monitorConnectivityChecker,
          remoteSecondary: remoteSecondary,
          monitorOutboundConnectionFactory: monitorOutboundConnectionFactory);

      int lastNotificationTime = DateTime.now().subtract(Duration(days: 1)).millisecondsSinceEpoch;
      Future<void> monitorStartFuture = monitor.start(lastNotificationTime: lastNotificationTime);
      await monitorStartFuture;

      expect(monitor.status, MonitorStatus.started);

      socketOnDoneFn();
      expect(monitor.status, MonitorStatus.stopped);
    });
  });
}
