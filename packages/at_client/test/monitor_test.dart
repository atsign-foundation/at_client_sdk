import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/manager/monitor.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:test/test.dart';

import 'package:mocktail/mocktail.dart';

class MockSecondaryAddressFinder extends Mock
    implements SecondaryAddressFinder {}

class MockSecureSocket extends Mock implements SecureSocket {}

class MockStreamSubscription<T> extends Mock implements StreamSubscription<T> {}

class MockOutboundConnection extends Mock implements OutboundConnection {}

class MockMonitorOutboundConnectionFactory extends Mock
    implements MonitorOutboundConnectionFactory {}

class MockAtChops extends Mock implements AtChops {}

class FakeAtSigningInput extends Fake implements AtSigningInput {}

/// Note: The test code here prioritizes brevity over isolation
/// So while, right now, the tests are all passing despite sharing their mock objects, at some point
/// we will add a test where that assumption doesn't hold any more, and the tests will start failing
void main() {
  SecondaryAddressFinder mockSecondaryAddressFinder =
      MockSecondaryAddressFinder();
  MonitorOutboundConnectionFactory mockMonitorOutboundConnectionFactory =
      MockMonitorOutboundConnectionFactory();
  OutboundConnection mockOutboundConnection = MockOutboundConnection();
  SecureSocket mockSocket = MockSecureSocket();
  AtChops mockAtChops = MockAtChops();
  late Function(dynamic data) socketOnDataFn;
  late Function() socketOnDoneFn;
  // ignore: unused_local_variable
  late Function(Exception e) socketOnErrorFn;
  int? lastNotificationTime;
  Future<int?> getLastNotificationTime() async {
    return lastNotificationTime;
  }

  var atSign = '@monitor_test';
  var fakeSecondaryAddress = SecondaryAddress("monitor_test", 12345);
  var fakeCertsLocation = '/home/ubuntu/Desktop/cert.pem';
  var fakeTlsKeysSavePath = '/home/ubuntu/Desktop/cert.pem';
  AtClientPreference atClientPreference = AtClientPreference();
  atClientPreference.decryptPackets = true;
  atClientPreference.tlsKeysSavePath = fakeTlsKeysSavePath;
  atClientPreference.pathToCerts = fakeCertsLocation;
  late AtSigningResult mockSigningResult;

  List<(DateTime, MonitorState)> monitorStateHistory = [];

  late Monitor monitor;
  String allFromMonitor = '';

  late Completer doneCompleter;
  setUp(() {
    reset(mockSecondaryAddressFinder);
    reset(mockSocket);
    reset(mockOutboundConnection);
    reset(mockMonitorOutboundConnectionFactory);
    reset(mockAtChops);

    when(() => mockSecondaryAddressFinder.findSecondary(any()))
        .thenAnswer((_) async => fakeSecondaryAddress);
    when(() => mockOutboundConnection.getSocket())
        .thenAnswer((_) => mockSocket);
    when(() => mockMonitorOutboundConnectionFactory.createConnection(
            fakeSecondaryAddress,
            decryptPackets: true,
            tlsKeysSavePath: fakeTlsKeysSavePath,
            pathToCerts: fakeCertsLocation))
        .thenAnswer((_) async => mockOutboundConnection);
    when(() => mockOutboundConnection.close()).thenAnswer((_) async => {});
    when(() => mockSocket.listen(any(),
        onError: any(named: "onError"),
        onDone: any(named: "onDone"))).thenAnswer((Invocation invocation) {
      socketOnDataFn = invocation.positionalArguments[0];
      socketOnDoneFn = invocation.namedArguments[#onDone];
      socketOnErrorFn = invocation.namedArguments[#onError];

      return MockStreamSubscription<Uint8List>();
    });
    doneCompleter = Completer();
    when(() => mockSocket.done).thenAnswer((_) => doneCompleter.future);

    when(() => mockOutboundConnection.write('from:$atSign\n'))
        .thenAnswer((Invocation invocation) async {
      socketOnDataFn("@data:server challenge\n"
          .codeUnits); // actual challenge is different, of course, but not important for unit tests
    });
    when(() => mockOutboundConnection.write(any(that: startsWith('pkam:'))))
        .thenAnswer((Invocation invocation) async {
      socketOnDataFn("success\n".codeUnits);
    });
    when(() => mockOutboundConnection.write(any(that: startsWith('monitor'))))
        .thenAnswer((Invocation invocation) async {});
    mockSigningResult = AtSigningResult()..result = 'mock_signing_result';
    registerFallbackValue(FakeAtSigningInput());
    when(() => mockAtChops.sign(any())).thenAnswer((_) => mockSigningResult);

    const List<Duration> testConnectDelays = [
      Duration(milliseconds: 100),
      Duration(milliseconds: 200),
      Duration(milliseconds: 300),
      Duration(milliseconds: 500),
      Duration(milliseconds: 800),
      Duration(milliseconds: 1300),
      Duration(milliseconds: 2100),
      Duration(milliseconds: 3400),
    ];
    allFromMonitor = '';
    monitor = Monitor(
      atSign: atSign,
      atClientPreference: atClientPreference,
      atChops: mockAtChops,
      enrollmentId: null,
      secondaryAddressFinder: mockSecondaryAddressFinder,
      handleNotification: (String received) async {
        allFromMonitor += '$received\n';
      },
      getLastNotificationTime: getLastNotificationTime,
      connectDelays: testConnectDelays,
      monitorOutboundConnectionFactory: mockMonitorOutboundConnectionFactory,
    );
    monitor.logger.level = 'warning';
    lastNotificationTime = null;
    monitorStateHistory.clear();
    monitor.currentStateStream.listen((s) {
      final d = DateTime.now().toUtc();
      print('*** $d : state updated: $s');
      monitorStateHistory.add((d, s));
    });
  });

  tearDown(() {
    print('*** Tearing down');
    monitor.stop();
    monitorStateHistory.clear();
  });

  group('Monitor socket response handling', () {
    test('Multiple response lines in single call to socket messageHandler',
        () async {
      List<String> fromServerList = [
        'notification:{"id":"1"}\ndata:ok\nnotification:{"id":',
        '"2"}\nnotification:{"id:"3"}\ndata:',
        'ok\nnoti',
        'fication:{"id":"4"}\n'
      ];

      await monitor.start();
      expect(await monitor.currentStateStream.first, MonitorState.connected);

      String allFromServer = '';
      for (String fromServer in fromServerList) {
        socketOnDataFn(utf8.encode(fromServer));
        allFromServer += fromServer;
      }
      // The Monitor response handler should filter out data:ok\n responses (heartbeat responses)
      // and send only notifications to the Monitor's owner's response handler.
      allFromServer = allFromServer.replaceAll('data:ok\n', '');
      expect(allFromMonitor, allFromServer);
    });
  });

  group('Monitor constructor and start tests', () {
    /// Create a Monitor with our mock connectivity checker, remote secondary and outbound connection factory.
    /// Start the monitor with a NULL last notification time
    /// Check that the monitor has started and has written the correct things to the socket
    test('Monitor start, secondary OK, NULL lastNotificationTime', () async {
      await monitor.start();
      expect(await monitor.currentStateStream.first, MonitorState.connected);
      final writesToSocket =
          verify(() => mockOutboundConnection.write(captureAny())).captured;
      expect(writesToSocket.length, 3);
      // We've created a monitor with a null lastNotificationTime - expect the command sent to the server to be simply 'monitor\n'
      expect(writesToSocket.last, 'monitor:selfNotifications\n');
    });

    /// Create a Monitor with our mock connectivity checker, remote secondary and outbound connection factory.
    /// Start the monitor with a REAL last notification time
    /// Check that the monitor has started and has written the correct things to the socket
    test('Monitor start, secondary OK, with a real lastNotificationTime',
        () async {
      lastNotificationTime =
          DateTime.now().subtract(Duration(days: 1)).millisecondsSinceEpoch;
      await monitor.start();
      expect(await monitor.currentStateStream.first, MonitorState.connected);
      final writesToSocket =
          verify(() => mockOutboundConnection.write(captureAny())).captured;
      expect(writesToSocket.length, 3);
      // We've created a monitor with a real lastNotificationTime
      expect(writesToSocket.last,
          'monitor:selfNotifications:$lastNotificationTime\n');
    });

    test('Monitor start, secondary not available', () async {
      when(() => mockMonitorOutboundConnectionFactory.createConnection(
          fakeSecondaryAddress,
          decryptPackets: true,
          tlsKeysSavePath: fakeTlsKeysSavePath,
          pathToCerts: fakeCertsLocation)).thenAnswer((_) async {
        throw AtConnectException('Mock - connection failed');
      });

      await monitor.start();

      expect(await monitor.currentStateStream.first, MonitorState.notConnected);
    });

    test('Monitor start, secondary reachable but rejecting commands', () async {
      when(() => mockOutboundConnection.write(any()))
          .thenAnswer((Invocation invocation) async {
        throw Exception('mockOutboundConnection.write() throwing exception');
      });

      await monitor.start();

      expect(await monitor.currentStateStream.first, MonitorState.notConnected);
    });

    test('start, secondary reachable but rejecting commands', () async {
      when(() => mockOutboundConnection.write(any()))
          .thenAnswer((Invocation invocation) async {
        throw Exception('mockOutboundConnection.write() throwing exception');
      });

      await monitor.start();

      expect(await monitor.currentStateStream.first, MonitorState.notConnected);
    });

    test('start, secondary reachable but pkam failure', () async {
      when(() => mockOutboundConnection.write(any(that: startsWith('pkam:'))))
          .thenAnswer((Invocation invocation) async {
        throw Exception('mockOutboundConnection.write() throwing exception');
      });

      await monitor.start();

      expect(await monitor.currentStateStream.first, MonitorState.notConnected);
    });

    test(
        'start, secondary OK, socket OK, socket closed, reconnects immediately',
        () async {
      await monitor.start();

      expect(await monitor.currentStateStream.first, MonitorState.connected);

      socketOnDoneFn();

      expect(await monitor.currentStateStream.first, MonitorState.notConnected);

      // should reconnect after the initial reconnectDelay
      expect(await monitor.currentStateStream.first, MonitorState.connected);
    });

    test(
        'start, secondary OK, socket OK, socket closed, reconnects on third attempt',
        () async {
      await monitor.start();

      expect(await monitor.currentStateStream.first, MonitorState.connected);

      print('*** calling socket onDone');
      socketOnDoneFn();

      expect(await monitor.currentStateStream.first, MonitorState.notConnected);

      print('*** ${DateTime.now().toUtc()} : making connections fail');

      // make connections fail
      when(() => mockMonitorOutboundConnectionFactory.createConnection(
          fakeSecondaryAddress,
          decryptPackets: true,
          tlsKeysSavePath: fakeTlsKeysSavePath,
          pathToCerts: fakeCertsLocation)).thenAnswer((_) async {
        throw AtConnectException('Mock - connection failed');
      });

      print(
          '*** ${DateTime.now().toUtc()} : Sleeping for ${monitor.connectDelays[0]}');
      await Future.delayed(monitor.connectDelays[0]);
      print(
          '*** ${DateTime.now().toUtc()} : Sleeping for ${monitor.connectDelays[1]}');
      await Future.delayed(monitor.connectDelays[1]);

      await Future.delayed(Duration(milliseconds: 50)); // fudge factor

      // make connections succeed again
      print('*** ${DateTime.now().toUtc()} : making connections succeed');
      when(() => mockMonitorOutboundConnectionFactory.createConnection(
              fakeSecondaryAddress,
              decryptPackets: true,
              tlsKeysSavePath: fakeTlsKeysSavePath,
              pathToCerts: fakeCertsLocation))
          .thenAnswer((_) async => mockOutboundConnection);

      expect(await monitor.currentStateStream.first, MonitorState.connected);
    });

    test('Monitor heartbeat sending regularly', () async {
      atClientPreference.monitorHeartbeatInterval = Duration(milliseconds: 20);
      Duration waitTime = Duration(milliseconds: 21);

      int numHeartbeatsSent = 0;
      when(() => mockOutboundConnection.write("noop:0\n"))
          .thenAnswer((Invocation invocation) async {
        numHeartbeatsSent++;
        sleep(Duration(milliseconds: 1));
        socketOnDataFn("@ok\n".codeUnits);
      });

      await monitor.start();
      expect(await monitor.currentStateStream.first, MonitorState.connected);

      // We expect the first heartbeat to be sent heartbeatIntervalMillis from now
      await Future.delayed(waitTime);

      // we should have sent one heartbeat so far
      expect(numHeartbeatsSent, 1);
      // and the monitor status is still 'started'
      expect(monitor.currentState, MonitorState.connected);

      // Now let's wait long enough for some heartbeats to be sent, check they have all been sent,
      // and check that the monitor status is still 'started'
      int additionalHeartbeatsToSend = 3;
      int expectedHeartbeatCount =
          numHeartbeatsSent + additionalHeartbeatsToSend;
      await Future.delayed(waitTime);
      await Future.delayed(waitTime);
      await Future.delayed(waitTime);
      // We're expecting three more to have been sent
      expect(numHeartbeatsSent, expectedHeartbeatCount);
      expect(monitor.currentState, MonitorState.connected);

      // Now let's simulate the socket is calling 'onDone'
      // The monitor's status should go to `notConnected`
      socketOnDoneFn();
      expect(await monitor.currentStateStream.first, MonitorState.notConnected);
      expect(monitor.currentState, MonitorState.notConnected);
      expect(monitor.heartbeatTimer, null);
      expect(numHeartbeatsSent, expectedHeartbeatCount);
    });

    test('Test that heartbeat exceptions are caught gracefully', () async {
      atClientPreference.monitorHeartbeatInterval = Duration(milliseconds: 100);

      int numHeartbeatAttempts = 0;
      when(() => mockOutboundConnection.write("noop:0\n"))
          .thenAnswer((Invocation invocation) async {
        numHeartbeatAttempts++;
        throw Exception('mockOutboundConnection.write() throwing exception');
      });

      await monitor.start();

      await Future.delayed(atClientPreference.monitorHeartbeatInterval +
          Duration(milliseconds: 10));

      // If there's an unhandled exception, this next assertion will not be made
      expect(numHeartbeatAttempts, 1);
    });

    test('Test when monitor heartbeat response not received', () async {
      // Do one successful heartbeat
      // Then fake a timeout on the next one
      // When the timeout occurs, socket as marked done
      // When the socket is marked done, monitor state changes
      // There is then a brief delay before the next connect attempt
      // We will make the first reconnect attempt fail
      // We will make the second reconnect attempt succeed
      // So we need to verify (1) monitor state changes to "notConnected"
      // and then (2) monitor state changes back to "connected" after the
      // reconnect, and then (3) we get another heartbeat
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

      atClientPreference.monitorHeartbeatResponseTimeout =
          Duration(milliseconds: 20);
      atClientPreference.monitorHeartbeatInterval = Duration(milliseconds: 60);

      monitor.logger.level = 'info';
      await monitor.start();
      expect(await monitor.currentStateStream.first, MonitorState.connected);
      expect(monitor.currentState, MonitorState.connected);

      print('*** Waiting for two heartbeat successes');
      // Wait for two heartbeat successes
      await Future.delayed(atClientPreference.monitorHeartbeatInterval * 2.2);
      expect(numHeartbeatsSent, 2);
      print('*** Got two heartbeat successes');

      // Let's make reconnects fail, then stop heartbeat responses
      print('*** Make reconnects fail');
      when(() => mockMonitorOutboundConnectionFactory.createConnection(
          fakeSecondaryAddress,
          decryptPackets: true,
          tlsKeysSavePath: fakeTlsKeysSavePath,
          pathToCerts: fakeCertsLocation)).thenAnswer((_) async {
        throw AtConnectException('Mock - connection failed');
      });

      // Let's NOT send a response to the next heartbeat(s).
      print('*** Stopping heartbeat responses');
      sendHeartbeatResponse = false;

      // Wait for the heartbeat timeout
      print('*** Waiting for heartbeat to timeout');
      await Future.delayed((atClientPreference.monitorHeartbeatResponseTimeout +
              atClientPreference.monitorHeartbeatInterval) *
          1.2);

      // Status should be "notConnected"
      print('*** State should be "notConnected"');
      expect(monitor.currentState, MonitorState.notConnected);

      // Wait for the first delay timeout
      print('*** Wait for the reconnect delay timeout');
      await Future.delayed(monitor.connectDelays[0] * 1.1);

      print('*** Expect notConnected');
      expect(monitor.currentState, MonitorState.notConnected);

      // let's start sending responses to heartbeats again
      print('*** Start sending heartbeat responses again');
      sendHeartbeatResponse = true;

      // and let's make creating new connections succeed again
      print('*** Make connections succeed again');
      when(() => mockMonitorOutboundConnectionFactory.createConnection(
              fakeSecondaryAddress,
              decryptPackets: true,
              tlsKeysSavePath: fakeTlsKeysSavePath,
              pathToCerts: fakeCertsLocation))
          .thenAnswer((_) async => mockOutboundConnection);

      // Wait for the second delay timeout
      print('*** Wait for the second reconnect delay timeout');
      await Future.delayed(monitor.connectDelays[1] * 1.1);

      // Now the monitor state should be 'connected' again
      print('*** Expect connected');
      expect(monitor.currentState, MonitorState.connected);

      // Finally, let's make sure that heartbeats are happening again, and the monitor is still happy
      print('*** Ensure that heartbeats are happening again');
      int lastHeartbeatCount = numHeartbeatsSent;
      int additionalHeartbeatsToSend = 3;
      await Future.delayed(atClientPreference.monitorHeartbeatInterval * 3.5);
      int expectedHeartbeatCount =
          lastHeartbeatCount + additionalHeartbeatsToSend;
      expect(numHeartbeatsSent >= expectedHeartbeatCount, true);
      expect(monitor.currentState, MonitorState.connected);
    });
  });
}
