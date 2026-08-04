import 'dart:async';
import 'dart:io';

import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
// AtLookupImpl is deliberately not exported from the barrel; these tests drive
// its connection internals directly.
import 'package:at_lookup/src/at_lookup_impl.dart';
import 'package:at_lookup/src/connection/outbound_message_listener.dart';
import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';

import 'at_lookup_test_utils.dart';

class MockOutboundConnectionImpl extends Mock
    implements OutboundConnectionImpl {}

void main() {
  group('test connection close and socket cleanup', () {
    late SecondaryAddressFinder finder;
    late MockSecureSocketFactory mockSocketFactory;

    setUp(() {
      mockSocketNumber = 1;

      finder = MockSecondaryAddressFinder();
      when(() => finder.findSecondary(any())).thenAnswer((invocation) =>
          Future<SecondaryAddress>.value(
              SecondaryAddress('test.test.test', 12345)));

      mockSocketFactory = MockSecureSocketFactory();
      registerFallbackValue(SecureSocketConfig());
      when(() =>
              mockSocketFactory.createSocket('test.test.test', '12345', any()))
          .thenAnswer((invocation) {
        return Future<SecureSocket>.value(
            createMockAtServerSocket('test.test.test', 12345));
      });
    });

    test(
        'test AtLookupImpl will use its default SecureSocketFactory if none is provided to it',
        () async {
      AtLookupImpl atLookup = AtLookupImpl('@alice', 'test.test.test', 64,
          secondaryAddressFinder: finder, secureSocketFactory: null);

      expect(atLookup.socketFactory.runtimeType.toString(),
          "AtLookupSecureSocketFactory");
      expect(() async => await atLookup.createConnection(),
          throwsA(predicate((dynamic e) => e is SecondaryConnectException)));
    });

    test(
        'test AtLookupImpl closes invalid connections before creating new ones',
        () async {
      AtLookupImpl atLookup = AtLookupImpl('@alice', 'test.test.test', 64,
          secondaryAddressFinder: finder,
          secureSocketFactory: mockSocketFactory);
      expect(atLookup.socketFactory.runtimeType.toString(),
          "MockSecureSocketFactory");

      await atLookup.createConnection();

      // let's get a handle to the first socket & connection
      OutboundConnection firstConnection = atLookup.connection!;
      MockSecureSocket firstSocket =
          firstConnection.getSocket() as MockSecureSocket;

      expect(firstSocket.mockNumber, 1);
      expect(firstSocket.destroyed, false);
      expect(firstConnection.metaData!.isClosed, false);
      expect(firstConnection.isInValid(), false);

      // Make the connection appear 'idle'
      firstConnection.setIdleTime(1);
      await Future.delayed(Duration(milliseconds: 2));
      expect(firstConnection.isInValid(), true);

      // When we now call AtLookupImpl's createConnection again, it should:
      // - notice that its current connection is 'idle', and close it
      // - create a new connection
      await atLookup.createConnection();

      // has the first connection been closed, and its socket destroyed?
      expect(firstSocket.destroyed, true);
      expect(firstConnection.metaData!.isClosed, true);

      // has a new connection been created, with a new socket?
      OutboundConnection secondConnection = atLookup.connection!;
      MockSecureSocket secondSocket =
          secondConnection.getSocket() as MockSecureSocket;
      expect(firstConnection.hashCode == secondConnection.hashCode, false);
      expect(secondSocket.mockNumber, 2);
      expect(secondSocket.destroyed, false);
      expect(secondConnection.metaData!.isClosed, false);
      expect(secondConnection.isInValid(), false);
    });

    test(
        'test message listener closes connection'
        ' when socket listener onDone is called', () async {
      OutboundConnection oc = OutboundConnectionImpl(
          createMockAtServerSocket('test.test.test', 12345));
      OutboundMessageListener oml = OutboundMessageListener(oc);
      expect((oc.getSocket() as MockSecureSocket).destroyed, false);
      expect(oc.metaData?.isClosed, false);
      oml.onSocketDone();
      expect((oc.getSocket() as MockSecureSocket).destroyed, true);
      expect(oc.metaData?.isClosed, true);
    });

    test(
        'test message listener closes connection'
        ' when socket listener onError is called', () async {
      OutboundConnection oc = OutboundConnectionImpl(
          createMockAtServerSocket('test.test.test', 12345));
      OutboundMessageListener oml = OutboundMessageListener(oc);
      expect((oc.getSocket() as MockSecureSocket).destroyed, false);
      expect(oc.metaData?.isClosed, false);
      oml.onSocketError('test');
      expect((oc.getSocket() as MockSecureSocket).destroyed, true);
      expect(oc.metaData?.isClosed, true);
    });

    test('test can safely call connection.close() repeatedly', () async {
      OutboundConnection oc = OutboundConnectionImpl(
          createMockAtServerSocket('test.test.test', 12345));
      OutboundMessageListener oml = OutboundMessageListener(oc);
      expect((oc.getSocket() as MockSecureSocket).destroyed, false);
      expect(oc.metaData?.isClosed, false);
      await oml.closeConnection();
      expect((oc.getSocket() as MockSecureSocket).destroyed, true);
      expect(oc.metaData?.isClosed, true);

      (oc.getSocket() as MockSecureSocket).destroyed = false;
      await oml.closeConnection();
      // Since the connection was already closed above,
      // we don't expect destroy to be called on the socket again
      expect((oc.getSocket() as MockSecureSocket).destroyed, false);
      expect(oc.metaData?.isClosed, true);
    });

    test(
        'test that OutboundMessageListener.closeConnection will call'
        ' connection.close if the connection is idle', () async {
      OutboundConnection oc = OutboundConnectionImpl(
          createMockAtServerSocket('test.test.test', 12345));
      OutboundMessageListener oml = OutboundMessageListener(oc);
      expect((oc.getSocket() as MockSecureSocket).destroyed, false);
      expect(oc.metaData?.isClosed, false);

      expect(oc.isInValid(), false);
      // Make the connection appear 'idle'
      oc.setIdleTime(1);
      await Future.delayed(Duration(milliseconds: 2));
      expect(oc.isInValid(), true);

      await oml.closeConnection();

      expect((oc.getSocket() as MockSecureSocket).destroyed, true);
      expect(oc.metaData?.isClosed, true);
    });

    test(
        'test that OutboundMessageListener.closeConnection will not call'
        ' connection.close if already marked closed', () async {
      OutboundConnection oc = OutboundConnectionImpl(
          createMockAtServerSocket('test.test.test', 12345));
      OutboundMessageListener oml = OutboundMessageListener(oc);
      expect((oc.getSocket() as MockSecureSocket).destroyed, false);
      oc.metaData!.isClosed = true;

      await oml.closeConnection();

      // socketDestroyed will be set in these tests only if socket.destroy() is called
      expect((oc.getSocket() as MockSecureSocket).destroyed, false);
    });

    test(
        'test that OutboundMessageListener.closeConnection will call'
        ' connection.close even if the connection is marked stale', () async {
      OutboundConnection oc = OutboundConnectionImpl(
          createMockAtServerSocket('test.test.test', 12345));
      OutboundMessageListener oml = OutboundMessageListener(oc);
      expect((oc.getSocket() as MockSecureSocket).destroyed, false);
      expect(oc.metaData?.isClosed, false);
      oc.metaData!.isStale = true;

      await oml.closeConnection();

      expect((oc.getSocket() as MockSecureSocket).destroyed, true);
      expect(oc.metaData?.isClosed, true);
    });
  });

  // In order to reduce duplicated test code, creating test functions which will be used in two ways. See test groups below.
  testOne(Duration? delayBeforeClose) async {
    Socket mockSocket = MockSecureSocket();
    when(() => mockSocket.setOption(SocketOption.tcpNoDelay, true))
        .thenAnswer((_) => true);
    OutboundConnection connection = OutboundConnectionImpl(mockSocket);
    OutboundMessageListener outboundMessageListener =
        OutboundMessageListener(connection);

    // We want to set up a connection, then call read() and have it time out.
    // When read() times out, the connection should be closed BEFORE the exception is thrown
    // This test is to guard against race conditions if we're not using `await` somewhere that we should be

    // This variable enables us to introduce a delay before closing the connection
    // The introduction of this delay enables the race condition (if it exists) to occur in this test
    if (delayBeforeClose != null) {
      outboundMessageListener.delayBeforeClose = delayBeforeClose;
    }
    int transientWaitTimeMillis = 50;
    try {
      await outboundMessageListener.read(
          transientWaitTimeMillis: transientWaitTimeMillis);
    } on AtTimeoutException catch (expected) {
      expect(
          expected.message,
          startsWith(
              'Waited for $transientWaitTimeMillis millis. No response after'));
      expect(connection.isInValid(), true);
    }
  }

  testTwo(Duration? delayBeforeClose) async {
    Socket mockSocket = MockSecureSocket();
    when(() => mockSocket.setOption(SocketOption.tcpNoDelay, true))
        .thenAnswer((_) => true);
    OutboundConnection connection = OutboundConnectionImpl(mockSocket);
    OutboundMessageListener outboundMessageListener =
        OutboundMessageListener(connection);

    // We want to set up a connection, then call read() and have it time out.
    // When read() times out, the connection should be closed BEFORE the exception is thrown
    // This test is to guard against race conditions if we're not using `await` somewhere that we should be

    // This variable enables us to introduce a delay before closing the connection
    // The introduction of this delay enables the race condition (if it exists) to occur in this test
    if (delayBeforeClose != null) {
      outboundMessageListener.delayBeforeClose = delayBeforeClose;
    }
    int maxWaitMilliSeconds = 50;
    try {
      await outboundMessageListener.read(
          maxWaitMilliSeconds: maxWaitMilliSeconds);
      expect(false, true, reason: 'Test should not have reached this point');
    } on AtTimeoutException catch (expected) {
      expect(expected.message,
          'Full response not received after $maxWaitMilliSeconds millis from remote atServer');
      expect(connection.isInValid(), true);
    }
  }

  testThree(Duration? delayBeforeClose) async {
    Socket mockSocket = MockSecureSocket();
    when(() => mockSocket.setOption(SocketOption.tcpNoDelay, true))
        .thenAnswer((_) => true);
    OutboundConnection connection = OutboundConnectionImpl(mockSocket);
    OutboundMessageListener outboundMessageListener =
        OutboundMessageListener(connection);

    // We want to set up a connection, then call read() and have it time out.
    // When read() times out, the connection should be closed BEFORE the exception is thrown
    // This test is to guard against race conditions if we're not using `await` somewhere that we should be

    // This variable enables us to introduce a delay before closing the connection
    // The introduction of this delay enables the race condition (if it exists) to occur in this test
    if (delayBeforeClose != null) {
      outboundMessageListener.delayBeforeClose = delayBeforeClose;
    }
    int maxWaitMilliSeconds = 50;
    try {
      await outboundMessageListener.read(
          maxWaitMilliSeconds: maxWaitMilliSeconds);
      expect(false, true, reason: 'Test should not have reached this point');
    } on AtTimeoutException catch (expected) {
      expect(expected.message,
          'Full response not received after $maxWaitMilliSeconds millis from remote atServer');
      expect(() async => await connection.write("hello\n"),
          throwsA(predicate((dynamic e) => e is ConnectionInvalidException)));
    }
  }

  group('A group of tests to detect race condition in connection management',
      () {
    test(
        'Test that isInvalid is set on the OutboundConnection after transientWaitTime timeout BEFORE the OutboundMessageListener.read() returns',
        () async {
      await testOne(Duration(milliseconds: 100));
    });

    test(
        'Test that isInvalid is set on the OutboundConnection after maxWaitTime timeout BEFORE the OutboundMessageListener.read() returns',
        () async {
      await testTwo(Duration(milliseconds: 100));
    });

    test(
        'Test that an attempt to write to an outbound connection which has had a timeout will throw a ConnectionInvalidException',
        () async {
      await testThree(Duration(milliseconds: 100));
    });
  });

  /// These tests will pass even when the race condition exists because of complications in the event loop from testing
  /// The tests are here to verify that we haven't caused another problem from the introduction
  /// of `@visibleForTesting Duration? delayBeforeClose` into OutboundMessageListener
  group('Same race condition tests without the artificial delay', () {
    test(
        'Test that isInvalid is set on the OutboundConnection after transientWaitTime timeout BEFORE the OutboundMessageListener.read() returns',
        () async {
      await testOne(null);
    });

    test(
        'Test that isInvalid is set on the OutboundConnection after maxWaitTime timeout BEFORE the OutboundMessageListener.read() returns',
        () async {
      await testTwo(null);
    });

    test(
        'Test that an attempt to write to an outbound connection which has had a timeout will throw a ConnectionInvalidException',
        () async {
      await testThree(null);
    });
  });
}
