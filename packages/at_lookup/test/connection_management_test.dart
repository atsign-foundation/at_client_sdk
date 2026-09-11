import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_lookup/src/connection/outbound_message_listener.dart';
import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';

import 'at_lookup_test_utils.dart';
import 'fake_at_server_transport.dart';

void main() {
  group('test connection close and socket cleanup', () {
    late SecondaryAddressFinder finder;
    late FakeAtServerTransportFactory transportFactory;

    setUp(() {
      finder = MockSecondaryAddressFinder();
      when(() => finder.findSecondary(any())).thenAnswer((invocation) =>
          Future<SecondaryAddress>.value(
              SecondaryAddress('test.test.test', 12345)));

      transportFactory = FakeAtServerTransportFactory();
    });

    test(
        'test AtLookupImpl closes invalid connections before creating new ones',
        () async {
      AtLookupImpl atLookup = AtLookupImpl('@alice', 'test.test.test', 64,
          secondaryAddressFinder: finder, transportFactory: transportFactory);
      expect(atLookup.transportFactory.runtimeType.toString(),
          "FakeAtServerTransportFactory");

      await atLookup.createConnection();

      // let's get a handle to the first transport & connection
      OutboundConnection firstConnection = atLookup.connection!;
      FakeAtServerTransport firstTransport = transportFactory.created.single;

      expect(firstTransport.destroyed, false);
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

      // has the first connection been closed, and its transport destroyed?
      expect(firstTransport.destroyed, true);
      expect(firstConnection.metaData!.isClosed, true);

      // has a new connection been created, over a new transport?
      OutboundConnection secondConnection = atLookup.connection!;
      expect(transportFactory.created, hasLength(2));
      FakeAtServerTransport secondTransport = transportFactory.last;
      expect(firstConnection.hashCode == secondConnection.hashCode, false);
      expect(secondTransport.destroyed, false);
      expect(secondConnection.metaData!.isClosed, false);
      expect(secondConnection.isInValid(), false);
    });

    test(
        'test message listener closes connection'
        ' when socket listener onDone is called', () async {
      FakeAtServerTransport transport = FakeAtServerTransport();
      OutboundConnection oc = OutboundConnectionImpl(transport);
      OutboundMessageListener oml = OutboundMessageListener(oc);
      expect(transport.destroyed, false);
      expect(oc.metaData?.isClosed, false);
      oml.onSocketDone();
      expect(transport.destroyed, true);
      expect(oc.metaData?.isClosed, true);
    });

    test(
        'test message listener closes connection'
        ' when socket listener onError is called', () async {
      FakeAtServerTransport transport = FakeAtServerTransport();
      OutboundConnection oc = OutboundConnectionImpl(transport);
      OutboundMessageListener oml = OutboundMessageListener(oc);
      expect(transport.destroyed, false);
      expect(oc.metaData?.isClosed, false);
      oml.onSocketError('test');
      expect(transport.destroyed, true);
      expect(oc.metaData?.isClosed, true);
    });

    test('test can safely call connection.close() repeatedly', () async {
      FakeAtServerTransport transport = FakeAtServerTransport();
      OutboundConnection oc = OutboundConnectionImpl(transport);
      OutboundMessageListener oml = OutboundMessageListener(oc);
      expect(transport.destroyed, false);
      expect(oc.metaData?.isClosed, false);
      await oml.closeConnection();
      expect(transport.destroyed, true);
      expect(oc.metaData?.isClosed, true);

      transport.destroyed = false;
      await oml.closeConnection();
      // Since the connection was already closed above,
      // we don't expect destroy to be called on the socket again
      expect(transport.destroyed, false);
      expect(oc.metaData?.isClosed, true);
    });

    test(
        'test that OutboundMessageListener.closeConnection will call'
        ' connection.close if the connection is idle', () async {
      FakeAtServerTransport transport = FakeAtServerTransport();
      OutboundConnection oc = OutboundConnectionImpl(transport);
      OutboundMessageListener oml = OutboundMessageListener(oc);
      expect(transport.destroyed, false);
      expect(oc.metaData?.isClosed, false);

      expect(oc.isInValid(), false);
      // Make the connection appear 'idle'
      oc.setIdleTime(1);
      await Future.delayed(Duration(milliseconds: 2));
      expect(oc.isInValid(), true);

      await oml.closeConnection();

      expect(transport.destroyed, true);
      expect(oc.metaData?.isClosed, true);
    });

    test(
        'test that OutboundMessageListener.closeConnection will not call'
        ' connection.close if already marked closed', () async {
      FakeAtServerTransport transport = FakeAtServerTransport();
      OutboundConnection oc = OutboundConnectionImpl(transport);
      OutboundMessageListener oml = OutboundMessageListener(oc);
      expect(transport.destroyed, false);
      oc.metaData!.isClosed = true;

      await oml.closeConnection();

      // socketDestroyed will be set in these tests only if socket.destroy() is called
      expect(transport.destroyed, false);
    });

    test(
        'test that OutboundMessageListener.closeConnection will call'
        ' connection.close even if the connection is marked stale', () async {
      FakeAtServerTransport transport = FakeAtServerTransport();
      OutboundConnection oc = OutboundConnectionImpl(transport);
      OutboundMessageListener oml = OutboundMessageListener(oc);
      expect(transport.destroyed, false);
      expect(oc.metaData?.isClosed, false);
      oc.metaData!.isStale = true;

      await oml.closeConnection();

      expect(transport.destroyed, true);
      expect(oc.metaData?.isClosed, true);
    });
  });

  // In order to reduce duplicated test code, creating test functions which will be used in two ways. See test groups below.
  testOne(Duration? delayBeforeClose) async {
    OutboundConnection connection =
        OutboundConnectionImpl(FakeAtServerTransport());
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
    OutboundConnection connection =
        OutboundConnectionImpl(FakeAtServerTransport());
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
    OutboundConnection connection =
        OutboundConnectionImpl(FakeAtServerTransport());
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
