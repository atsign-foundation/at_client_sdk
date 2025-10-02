import 'dart:async' show StreamSubscription;
import 'dart:convert' show utf8;
import 'dart:io';
import 'dart:typed_data' show Uint8List;

import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:test/expect.dart';
import 'package:test/scaffolding.dart';
import 'package:mocktail/mocktail.dart';

import 'at_lookup_test_utils.dart';

void main() async {
  group('this should be moved to functional tests', () {
    test('look up @cicd1 from root.atsign.wtf:64', () async {
      var secondaryAddress = await CacheableSecondaryAddressFinder(
        'root.atsign.wtf',
        64,
        proxies: null,
      ).findSecondary('@cicd1');
      expect(secondaryAddress.port, isNotNull);
      expect(secondaryAddress.host, isNotNull);
      print(secondaryAddress.toString());
    });
  });

  group('some cache tests with a MockSecondaryFinder', () {
    String rootDomain = 'root.atsign.unit.tests';
    int rootPort = 64;

    SecondaryUrlFinder mockSecondaryFinder = MockSecondaryUrlFinder();

    String addressFromAtSign(String atSign) {
      if (atSign.startsWith('@')) {
        atSign = atSign.replaceFirst('@', '');
      }
      return '$atSign.secondaries.unit.tests:1001';
    }

    late CacheableSecondaryAddressFinder cache;

    setUp(() {
      reset(mockSecondaryFinder);
      when(() => mockSecondaryFinder
              .findSecondaryUrl(any(that: startsWith('registered'))))
          .thenAnswer((invocation) async =>
              addressFromAtSign(invocation.positionalArguments.first));
      when(() => mockSecondaryFinder
              .findSecondaryUrl(any(that: startsWith('notCached'))))
          .thenAnswer((invocation) async =>
              addressFromAtSign(invocation.positionalArguments.first));
      when(() => mockSecondaryFinder
              .findSecondaryUrl(any(that: startsWith('notRegistered'))))
          .thenAnswer((invocation) async {
        throw SecondaryNotFoundException(
            CacheableSecondaryAddressFinder.getNotFoundExceptionMessage(
                invocation.positionalArguments.first));
      });

      cache = CacheableSecondaryAddressFinder(
        rootDomain,
        rootPort,
        secondaryFinder: mockSecondaryFinder,
        proxies: null,
      );
    });

    test('test lookup of @alice on non-existent atDirectory', () async {
      CacheableSecondaryAddressFinder cache = CacheableSecondaryAddressFinder(
        'root.no.no.no',
        64,
        proxies: null,
      );
      expect(() async => await cache.findSecondary('@alice'),
          throwsA(predicate((e) => e is RootServerConnectivityException)));
    });

    test('test simple lookup for @registeredAtSign1', () async {
      var atSign = '@registeredAtSign1';
      var secondaryAddress = await cache.findSecondary(atSign);
      expect(secondaryAddress.port, isNotNull);
      expect(secondaryAddress.host, isNotNull);
      expect(secondaryAddress.toString(), addressFromAtSign(atSign));
    });

    test('test simple lookup for registeredAtSign1', () async {
      var atSign = 'registeredAtSign1';
      var secondaryAddress = await cache.findSecondary(atSign);
      expect(secondaryAddress.port, isNotNull);
      expect(secondaryAddress.host, isNotNull);
      expect(secondaryAddress.toString(), addressFromAtSign(atSign));
    });

    test('test simple lookup for notRegisteredAtSign1', () async {
      var atSign = 'notRegisteredAtSign1';
      expect(
          () async => await cache.findSecondary(atSign),
          throwsA(predicate((e) =>
              e is SecondaryNotFoundException &&
              e.message ==
                  CacheableSecondaryAddressFinder.getNotFoundExceptionMessage(
                      atSign))));
    });
    test('test isCached for registeredAtSign1', () async {
      var atSign = 'registeredAtSign1';
      await cache.findSecondary(atSign);
      expect(cache.cacheContains(atSign), true);
    });
    test('test isCached for notRegisteredAtSign1', () async {
      var atSign = 'notRegisteredAtSign1';
      expect(cache.cacheContains(atSign), false);
    });

    test('test expiry time - default cache expiry for registeredAtSign1',
        () async {
      var atSign = 'registeredAtSign1';
      await cache.findSecondary(atSign);
      final approxExpiry =
          DateTime.now().add(Duration(hours: 1)).millisecondsSinceEpoch;
      expect(cache.getCacheExpiryTime(atSign), isNotNull);
      expect((approxExpiry - cache.getCacheExpiryTime(atSign)!) < 100, true);
    });

    // TODO Why are these tests commented out?
//    test('test expiry time  - custom cache expiry for registeredAtSign1',
//        () async {
//      var atSign = 'registeredAtSign1';
//      await cache.findSecondary(atSign, cacheFor: Duration(seconds: 30));
//      final approxExpiry =
//          DateTime.now().add(Duration(seconds: 30)).millisecondsSinceEpoch;
//      expect(cache.getCacheExpiryTime(atSign), isNotNull);
//      expect((approxExpiry - cache.getCacheExpiryTime(atSign)!) < 100, true);
//    });

//    test('test update cache for atsign which is not yet cached', () async {
//      var atSign = 'notCachedAtSign1';
//      expect(cache.cacheContains(atSign), false);
//      await cache.findSecondary(atSign, refreshCacheNow: true);
//      expect(cache.cacheContains(atSign), true);
//    });
  });

  group(
      'some cache tests with a real SecondaryUrlFinder on a mocked root server',
      () {
    registerFallbackValue(SecureSocketConfig());
    String atSign = '@alice';
    String noAtAtSign = atSign.replaceFirst('@', '');
    String mockAtDirectoryHost = '127.0.0.5';
    String mockedAtServerAddress = 'guid.swarm.zone.test:12345';

    late Function socketOnDataFn;

    late SecureSocket mockSocket;
    late MockSecureSocketFactory mockSocketFactory;

    late CacheableSecondaryAddressFinder cachingAtServerFinder;

    late int numSocketCreateCalls;
    late int requiredFailures;

    SecureSocket createMockAtDirectorySocket(String address, int port) {
      SecureSocket mss = MockSecureSocket();
      when(() => mss.flush()).thenAnswer((invocation) => Future<void>.value());
      when(() => mss.destroy()).thenAnswer((invocation) {
        (mss as MockSecureSocket).destroyed = true;
      });
      when(() => mss.setOption(SocketOption.tcpNoDelay, true)).thenReturn(true);
      when(() => mss.remoteAddress).thenReturn(InternetAddress(address));
      when(() => mss.remotePort).thenReturn(port);
      return mss;
    }

    setUp(() {
      mockSocket = createMockAtDirectorySocket(mockAtDirectoryHost, 64);
      mockSocketFactory = MockSecureSocketFactory();

      cachingAtServerFinder = CacheableSecondaryAddressFinder(
        mockAtDirectoryHost,
        64,
        secondaryFinder: SecondaryUrlFinder(mockAtDirectoryHost, 64,
            socketFactory: mockSocketFactory),
        proxies: null,
      );

      numSocketCreateCalls = 0;
      when(() =>
              mockSocketFactory.createSocket(mockAtDirectoryHost, '64', any()))
          .thenAnswer((invocation) {
        print(
            'mock create socket: numFailures $numSocketCreateCalls requiredFailures $requiredFailures');
        if (numSocketCreateCalls++ < requiredFailures) {
          throw SocketException('Simulating socket connection failure');
        } else {
          return Future<SecureSocket>.value(mockSocket);
        }
      });

      when(() => mockSocket.listen(any(),
          onError: any(named: "onError"),
          onDone: any(named: "onDone"))).thenAnswer((Invocation invocation) {
        socketOnDataFn = invocation.positionalArguments[0];
        // socketOnErrorFn = invocation.namedArguments[#onError];
        // socketOnDoneFn = invocation.namedArguments[#onDone];

        socketOnDataFn('@'.codeUnits);
        return MockStreamSubscription();
      });

      when(() => mockSocket.write('$noAtAtSign\n'))
          .thenAnswer((Invocation invocation) async {
        socketOnDataFn("@$mockedAtServerAddress\n".codeUnits);
      });
    });

    test('test lookup of @alice with mocked atDirectory and zero failures',
        () async {
      requiredFailures = 0;
      SecondaryAddress sa = await cachingAtServerFinder.findSecondary(atSign);
      expect(sa.toString(), mockedAtServerAddress);
      expect(numSocketCreateCalls - 1, requiredFailures);
    });

    test('test lookup of @alice with mocked atDirectory and 1 failure',
        () async {
      requiredFailures = 1;
      SecondaryAddress sa = await cachingAtServerFinder.findSecondary(atSign);
      expect(sa.toString(), mockedAtServerAddress);
      expect(numSocketCreateCalls - 1, requiredFailures);
    });

    test('test lookup of @alice with mocked atDirectory and 2 failures',
        () async {
      requiredFailures = 2;
      SecondaryAddress sa = await cachingAtServerFinder.findSecondary(atSign);
      expect(sa.toString(), mockedAtServerAddress);
      expect(numSocketCreateCalls - 1, requiredFailures);
    });

    test('test lookup of @alice with mocked atDirectory and 3 failures',
        () async {
      requiredFailures = 3;
      SecondaryAddress sa = await cachingAtServerFinder.findSecondary(atSign);
      expect(sa.toString(), mockedAtServerAddress);
      expect(numSocketCreateCalls - 1, requiredFailures);
    });

    test('test lookup of @alice with mocked atDirectory and 4 failures',
        () async {
      requiredFailures = 4;
      SecondaryAddress sa = await cachingAtServerFinder.findSecondary(atSign);
      expect(sa.toString(), mockedAtServerAddress);
      expect(numSocketCreateCalls - 1, requiredFailures);
    });

    test('test lookup of @alice with mocked atDirectory and 5 failures',
        () async {
      requiredFailures = 5;
      expect(() async => await cachingAtServerFinder.findSecondary(atSign),
          throwsA(predicate((e) {
        print('${e.runtimeType} : $e');
        expect(numSocketCreateCalls, requiredFailures);
        return e is RootServerConnectivityException;
      })));
    });
  });

  group('some tests using fallbacks', () {
    registerFallbackValue(SecureSocketConfig());
    String atSign = '@alice';
    String noAtAtSign = atSign.replaceFirst('@', '');
    String mockAtDirectoryHost = '127.0.0.5';
    String timeoutAtDirectoryHost = 'no.no.no.no';
    String mockedAtServerAddress = 'guid.swarm.zone.test:12345';

    late Function socketOnDataFn;

    late SecureSocket mockSocket;
    late MockSecureSocketFactory mockSocketFactory;

    late int numSocketCreateCalls;
    late int requiredFailures;

    late Proxies proxies;

    SecureSocket createMockAtDirectorySocket(String address, int port) {
      SecureSocket mss = MockSecureSocket();
      when(() => mss.flush()).thenAnswer((invocation) => Future<void>.value());
      when(() => mss.destroy()).thenAnswer((invocation) {
        (mss as MockSecureSocket).destroyed = true;
      });
      when(() => mss.setOption(SocketOption.tcpNoDelay, true)).thenReturn(true);
      when(() => mss.remoteAddress).thenReturn(InternetAddress(address));
      when(() => mss.remotePort).thenReturn(port);
      return mss;
    }

    setUp(() {
      mockSocket = createMockAtDirectorySocket(mockAtDirectoryHost, 64);
      mockSocketFactory = MockSecureSocketFactory();

      proxies = Proxies([
        SecondaryAddress('proxy0001.test.test', 443),
        SecondaryAddress('proxy0002.test.test', 443),
        SecondaryAddress('proxy0003.test.test', 443)
      ]);

      numSocketCreateCalls = 0;
      when(() => mockSocketFactory.createSocket(
              mockAtDirectoryHost, '64', any(),
              createSocketTimeout: any(named: 'createSocketTimeout')))
          .thenAnswer((invocation) {
        print(
            'mock create socket: numFailures $numSocketCreateCalls requiredFailures $requiredFailures');
        if (numSocketCreateCalls++ < requiredFailures) {
          throw SocketException('Simulating socket connection failure');
        } else {
          return Future<SecureSocket>.value(mockSocket);
        }
      });
      when(() => mockSocketFactory.createSocket(
              timeoutAtDirectoryHost, '64', any(),
              createSocketTimeout: any(named: 'createSocketTimeout')))
          .thenAnswer((invocation) async {
        await Future.delayed(invocation.namedArguments[#createSocketTimeout]);
        throw SocketException('Simulating socket timeout',
            osError: OSError(
                'Simulated timeout',
                (Platform.isWindows
                    ? 10060 // WSAETIMEDOUT
                    : 110)));
      });

      when(() => mockSocket.listen(any(),
          onError: any(named: "onError"),
          onDone: any(named: "onDone"))).thenAnswer((Invocation invocation) {
        socketOnDataFn = invocation.positionalArguments[0];
        // socketOnErrorFn = invocation.namedArguments[#onError];
        // socketOnDoneFn = invocation.namedArguments[#onDone];

        socketOnDataFn('@'.codeUnits);
        return MockStreamSubscription();
      });

      when(() => mockSocket.write('$noAtAtSign\n'))
          .thenAnswer((Invocation invocation) async {
        socketOnDataFn("@$mockedAtServerAddress\n".codeUnits);
      });
    });

    test('test Proxies constructor', () {
      expect(() => Proxies([]), throwsA(isA<ArgumentError>()));
    });

    test('test Proxies next function', () {
      for (int i = 0; i < proxies.addresses.length * 3 + 1; i++) {
        final p = proxies.next();
        expect(p, proxies.addresses[i % proxies.addresses.length]);
      }
    });

    test('test lookup of @alice with mocked atDirectory and zero failures',
        () async {
      CacheableSecondaryAddressFinder cachingAtServerFinder =
          CacheableSecondaryAddressFinder(mockAtDirectoryHost, 64,
              socketFactory: mockSocketFactory,
              proxies: proxies,
              createSocketTimeout: Duration(milliseconds: 25));

      requiredFailures = 0;
      SecondaryAddress sa = await cachingAtServerFinder.findSecondary(atSign);
      expect(sa.toString(), mockedAtServerAddress);
      expect(numSocketCreateCalls - 1, requiredFailures);
    });

    test('test fallback to proxy after 5 failures', () async {
      CacheableSecondaryAddressFinder cachingAtServerFinder =
          CacheableSecondaryAddressFinder(mockAtDirectoryHost, 64,
              socketFactory: mockSocketFactory,
              proxies: proxies,
              createSocketTimeout: Duration(milliseconds: 25));
      requiredFailures = 5;
      SecondaryAddress sa = await cachingAtServerFinder.findSecondary(atSign);
      expect(numSocketCreateCalls, requiredFailures);
      expect(sa, isIn(proxies.addresses));
    });

    test('test fallback continues to be used', () async {
      CacheableSecondaryAddressFinder cachingAtServerFinder =
          CacheableSecondaryAddressFinder(mockAtDirectoryHost, 64,
              socketFactory: mockSocketFactory,
              proxies: proxies,
              createSocketTimeout: Duration(milliseconds: 25));
      requiredFailures = 5;
      SecondaryAddress sa = await cachingAtServerFinder.findSecondary(atSign);
      expect(numSocketCreateCalls, requiredFailures);
      expect(sa, equals(proxies.addresses[0]));

      // Clear the cache, try again, same fallback should be used
      cachingAtServerFinder.clear();
      numSocketCreateCalls = 0;
      SecondaryAddress sa1 = await cachingAtServerFinder.findSecondary(atSign);
      expect(numSocketCreateCalls, 0); // should just return proxy straight away
      expect(
          sa1, equals(proxies.addresses[0])); // And it should be the same proxy

      // Clear the cache, unset the fallback, try again - expect socket create calls
      cachingAtServerFinder.clear();
      cachingAtServerFinder.secondaryFinder.fallback = null;
      numSocketCreateCalls = 0;
      SecondaryAddress sa2 = await cachingAtServerFinder.findSecondary(atSign);
      expect(numSocketCreateCalls, requiredFailures);
      expect(sa2, equals(proxies.addresses[1]));
    });

    test('test fallback to proxy after timeout', () async {
      CacheableSecondaryAddressFinder cachingAtServerFinder =
          CacheableSecondaryAddressFinder(timeoutAtDirectoryHost, 64,
              socketFactory: mockSocketFactory,
              proxies: proxies,
              createSocketTimeout: Duration(milliseconds: 25));
      SecondaryAddress sa = await cachingAtServerFinder.findSecondary(atSign);
      expect(sa, isIn(proxies.addresses));
    });
  });

  group(
      'some cache tests with a real SecondaryUrlFinder but with rootDomain set to proxy:<something>',
      () {
    String proxyHost = 'vip.ve.atsign.zone';
    String rootDomain = 'proxy:$proxyHost';
    int rootPort = 8443;

    String addressFromAtSign(String atSign) {
      return '$proxyHost:$rootPort';
    }

    late CacheableSecondaryAddressFinder csaf;

    setUp(() {
      csaf = CacheableSecondaryAddressFinder(
        rootDomain,
        rootPort,
        proxies: null,
      );
    });

    test('test simple lookup for @registeredAtSign1', () async {
      var atSign = '@registeredAtSign1';
      var secondaryAddress = await csaf.findSecondary(atSign);
      expect(secondaryAddress.port, isNotNull);
      expect(secondaryAddress.host, isNotNull);
      expect(secondaryAddress.toString(), addressFromAtSign(atSign));
    });
    test('test simple lookup for registeredAtSign1', () async {
      var atSign = 'registeredAtSign1';
      var secondaryAddress = await csaf.findSecondary(atSign);
      expect(secondaryAddress.port, isNotNull);
      expect(secondaryAddress.host, isNotNull);
      expect(secondaryAddress.toString(), addressFromAtSign(atSign));
    });
    test('test isCached for registeredAtSign1', () async {
      var atSign = 'registeredAtSign1';
      await csaf.findSecondary(atSign);
      expect(csaf.cacheContains(atSign), true);
    });

    test('test expiry time - default cache expiry for registeredAtSign1',
        () async {
      var atSign = 'registeredAtSign1';
      await csaf.findSecondary(atSign);
      final approxExpiry =
          DateTime.now().add(Duration(hours: 1)).millisecondsSinceEpoch;
      expect(csaf.getCacheExpiryTime(atSign), isNotNull);
      expect((approxExpiry - csaf.getCacheExpiryTime(atSign)!) < 100, true);
    });
  });

  test(
      'regression test - secureSocketConfig is used to create socket for findSecondary',
      () async {
    final rootDomain = 'root.atsign.unit.tests';
    final rootPort = 64;
    String atSign = "bob";

    AtLookupSecureSocketFactory mockSocketFactory = MockSecureSocketFactory();
    SecureSocket mockSecureSocket = MockSecureSocket();
    StreamSubscription<Uint8List> mockStreamSubscription =
        MockStreamSubscription();

    SecureSocketConfig config = SecureSocketConfig();

    late Future<void> Function(List<int>) callback;
    late SecureSocketConfig configPassedToFactory;

    when(
      () => mockSocketFactory.createSocket(
        rootDomain,
        rootPort.toString(),
        any(),
      ),
    ).thenAnswer((invocation) async {
      configPassedToFactory = invocation.positionalArguments[2];
      return mockSecureSocket;
    });

    when(() => mockSecureSocket.listen(any())).thenAnswer((invocation) {
      callback = invocation.positionalArguments.first;
      callback(utf8.encode("@"));
      return mockStreamSubscription;
    });

    when(() => mockSecureSocket.write("$atSign\n")).thenAnswer((invocation) {
      callback(utf8.encode("null\n"));
    });

    when(() => mockSecureSocket.write("@exit\n")).thenReturn(null);

    when(() => mockSecureSocket.destroy()).thenReturn(null);
    when(() => mockSecureSocket.flush()).thenAnswer((_) async => null);

    SecondaryUrlFinder finder = SecondaryUrlFinder(rootDomain, rootPort,
        socketFactory: mockSocketFactory, socketConfig: config);

    await finder.findSecondaryUrl(
      atSign,
    );

    expect(
      configPassedToFactory.hashCode,
      config.hashCode,
      reason: "SecureSocketConfig was not passed through to socket factory",
    );
  });
}
