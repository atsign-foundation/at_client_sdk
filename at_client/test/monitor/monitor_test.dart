import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:at_client/src/client/remote_secondary.dart';
import 'package:at_client/src/manager/monitor.dart';
import 'package:at_client/src/preference/at_client_preference.dart';
import 'package:at_client/src/preference/monitor_preference.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:test/test.dart';

import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'monitor_test.mocks.dart';

@GenerateMocks([
  MonitorConnectivityChecker,
  MonitorOutboundConnectionFactory,
  OutboundConnection,
  SecureSocket,
  StreamSubscription,
  RemoteSecondary
])
void main() {

  group('Monitor tests', () {

    test('Monitor constructor', () async {
      void notifCallback(String notifJson) {
        print('notifCallback: ' + notifJson);
      }
      void errorCallback(Exception e) {
        print('errorCallback' + e.toString());
      }
      void retryCallback() {
        print ('retryCallback');
      }

      var fakeSecondaryUrl = "monitor_test:12345";

      MonitorConnectivityChecker monitorConnectivityChecker = MockMonitorConnectivityChecker();
      when(monitorConnectivityChecker.checkConnectivity(any)).thenAnswer((_) async {print('mock check connectivity - OK');});

      RemoteSecondary remoteSecondary = MockRemoteSecondary();
      when(remoteSecondary.isAvailable()).thenAnswer((_) async => true);
      when(remoteSecondary.findSecondaryUrl()).thenAnswer((_) async => fakeSecondaryUrl);

      SecureSocket mockSocket = MockSecureSocket();
      var onData;
      var onDone;
      var onError;
      when(mockSocket.listen(any, onError: anyNamed("onError"), onDone: anyNamed("onDone"))).thenAnswer((Invocation invocation) {
        onData = invocation.positionalArguments[0];
        onDone = invocation.namedArguments[#onDone];
        onError = invocation.namedArguments[#onError];

        return MockStreamSubscription();
      });

      OutboundConnection outboundConnection = MockOutboundConnection();
      when(outboundConnection.getSocket()).thenAnswer((_) => mockSocket);

      MonitorOutboundConnectionFactory monitorOutboundConnectionFactory = MockMonitorOutboundConnectionFactory();
      when(monitorOutboundConnectionFactory.createConnection(fakeSecondaryUrl)).thenAnswer((_) async => outboundConnection);

      AtClientPreference atClientPreference = AtClientPreference();
      atClientPreference.privateKey = 'MIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQCDVMetuYSlcwNdS1yLgYE1oBEXaCFZjPq0Lk9w7yjKOqKgPCWnuVVly5+GBkYPYN3mPXbi/LHy3SqVM/8s5srxa+C8s5jk2pQI6BgG/RW59XM6vrGuw0pUQoL0bMyQxtR8XAFVgd54iDcgp4ZPLEH6odAgBraAtkIEpfwSwtMaWJCaS/Yn3q6ZoVOxL+O7DHD2dJWmwwjAJyDqEDeeNVuNHWnmj2ZneVXDnsY4fOR3IZdcGArM28FFcFIM6Q0K6XGiLGvJ2pYPywtzwARFChYJTBJYhNNLRgT+MUvx8fbNa6mMnnXQmagh/YvYwmyIUVQK1EhFNZIgezX9xdmIgS+FAgMBAAECggEAEq0z2FjRrFW23MWi25QHNAEXbSS52WpbHNSZJ45bVqcQCYmEMV4B7wAOJ5kszXMRG3USOyWEiO066Q0D9Pa9VafpxewkiicrdjjLcfL76/4j7O7BhgDvyRvMU8ZFMTGVdjn/VpGpeaqlbFdmmkvI9kOcvXE28wb4TIDuYBykuNI6twRqiaVd1LkKg9yoF0DGfSp8OHGWm/wz5wwnNYT6ofTbgV3gSGKOrLf4rC1swHh1VoNXiaYKQQFo2j23vGznC+hVJy8kAkSTMvRy4+SrZ+0MtYrNt0CI9n4hw79BNzwAd0kfJ5WCsYL6MaF8Giyym3Wl77KoiriwRF7cGCEnAQKBgQDWD+l1b6D8QCmrzxI1iZRoehfdlIlNviTxNks4yaDQ/tu6TC/3ySsRhKvwj7BqFYj2A6ULafeh08MfxpG0MfmJ+aJypC+MJixu/z/OXhQsscnR6avQtVLi9BIZV3EweyaD/yN/PB7IVLuhz6E6BV8kfNDb7UFZzrSSlvm1YzIdvQKBgQCdD5KVbcA88xkv/SrBpJcUME31TIR4DZPg8fSB+IDCnogSwXLxofadezH47Igc1CifLSQp4Rb+8sjVOTIoAXZKvW557fSQk3boR3aZ4CkheDznzjq0vY0qot4llkzHdiogaIUdPDwvYBwERzc73CO3We1pHs36bIz70Z3DRF5BaQKBgQC295jUARs4IVu899yXmEYa2yklAz4tDjajWoYHPwhPO1fysAZcJD3E1oLkttzSgB+2MD1VOTkpwEhLE74cqI6jqZV5qe7eOw7FvTT7npxd64UXAEUUurfjNz11HbGo/8pXDrB3o5qoHwzV7RPg9RByrqETKoMuUSk1FwjPSr9efQKBgAdC7w4Fkvu+aY20cMOfLnT6fsA2l3FNf2bJCPrxWFKnLbdgRkYxrMs/JOJTXT+n93DUj3V4OK3036AsEsuStbti4ra0b7g3eSnoE+2tVXl8q6Qz/rbYhKxR919ZgZc/OVdiPbVKUaYHFYSFHmKgHO6fM8DGcdOALUx/NoIOqSTxAoGBALUdiw8iyI98TFgmbSYjUj5id4MrYKXaR7ndS/SQFOBfJWVH09t5bTxXjKxKsK914/bIqEI71aussf5daOHhC03LdZIQx0ZcCdb2gL8vHNTQoqX75bLRN7J+zBKlwWjjrbhZCMLE/GtAJQNbpJ7jOrVeDwMAF8pK+Put9don44Gx';

      var atSign = '@monitor_test';
      Monitor _monitor = Monitor(
        notifCallback,
        errorCallback,
        atSign,
        atClientPreference,
        MonitorPreference(),
        retryCallback,
        monitorConnectivityChecker: monitorConnectivityChecker,
        remoteSecondary: remoteSecondary,
        monitorOutboundConnectionFactory: monitorOutboundConnectionFactory
      );

      when(outboundConnection.write("from:" + atSign + '\n')).thenAnswer((Invocation invocation) async {
        onData("abcde\n".codeUnits);
        onData("success\n".codeUnits);
      });

      Future<void> monitorStartFuture = _monitor!.start(lastNotificationTime: null);

      await untilCalled(outboundConnection.getSocket());
      verify(outboundConnection.getSocket()).called(1);

      await monitorStartFuture;
      print (_monitor.status);
    });

  });
}
