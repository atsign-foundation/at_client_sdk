@TestOn('browser')
library;

import 'dart:async';

import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup_web.dart';
import 'package:at_lookup/src/util/abandonment.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

import 'answered_paths.dart';

/// Catalogue: features/at_lookup/transports.feature
void main() {
  late StreamChannel channel;
  late int port;
  late HttpsSecondaryAddressFinder finder;

  Future<List<String>> answered() => answeredPaths(port);

  /// The paths the atDirectory has taken, once it has taken any, waiting at
  /// most 5 seconds.
  Future<List<String>> firstTaken() async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    var paths = await answered();
    while (paths.isEmpty && DateTime.now().isBefore(deadline)) {
      paths = await answered();
    }
    return paths;
  }

  setUpAll(() async {
    channel = spawnHybridUri('https_fake_directory.dart');
    final ready = Completer<int>();
    channel.stream.listen((event) => ready.complete((event as num).toInt()));
    port = await ready.future;
    finder =
        HttpsSecondaryAddressFinder('127.0.0.1', port: port, scheme: 'http');
  });

  tearDownAll(() => channel.sink.close());

  tearDown(() async => expect(await answered(), isEmpty,
      reason: 'each test names every request it makes'));

  test('a 200 host:port answer is the atServer address', () async {
    final address = await finder.findSecondary('@alice');
    expect(address.host, 'vip.example.org');
    expect(address.port, 1234);
    expect(await answered(), ['/@alice']);
  });

  test('an atSign given without its @ is asked for with one', () async {
    expect((await finder.findSecondary('alice')).port, 1234);
    expect(await answered(), ['/@alice']);
  });

  test('a 404 is SecondaryNotFoundException', () async {
    await expectLater(finder.findSecondary('@nobody'),
        throwsA(isA<SecondaryNotFoundException>()));
    expect(await answered(), ['/@nobody'],
        reason: 'the 404 is the atDirectory\'s answer');
  });

  test('the atSign is asked for in its canonical form', () async {
    expect((await finder.findSecondary('@Alice')).port, 1234);
    expect(await answered(), ['/@alice']);
  });

  test('an atSign that is not one is refused before anything is asked',
      () async {
    await expectLater(finder.findSecondary('@a b/c?d'),
        throwsA(isA<InvalidAtSignException>()));
    expect(await answered(), isEmpty,
        reason: 'the atDirectory took no request before one made after the '
            'refusal');
  });

  test('an answer naming a host behind an @ is refused', () async {
    await expectLater(
        finder.findSecondary('@elsewhere'),
        throwsA(isA<AtException>()
            .having((e) => e.message, 'message', contains('not host:port'))));
    expect(await answered(), ['/@elsewhere'],
        reason: 'the refusal is of the atDirectory\'s answer');
  });

  test('An oversized atDirectory answer is refused', () async {
    await expectLater(
        finder.findSecondary('@huge'),
        throwsA(isA<AtException>().having(
            (e) => e.message,
            'message',
            allOf(contains('longer than 512 bytes'),
                isNot(contains('aaaaaaaa'))))),
        reason: 'refused at the bound, without echoing what was read');
    expect(await answered(), ['/@huge'],
        reason: 'the refusal is of the atDirectory\'s answer');
  });

  test('An oversized atDirectory answer fails without reading the rest',
      () async {
    final sw = Stopwatch()..start();
    await expectLater(
        finder.findSecondary('@endless', timeout: const Duration(seconds: 15)),
        throwsA(isA<AtException>().having(
            (e) => e.message, 'message', contains('longer than 512 bytes'))),
        reason: 'the body never ends, so only a reader that stops at the '
            'bound can refuse it before the timeout');
    expect(sw.elapsed, lessThan(const Duration(seconds: 5)));
    expect(await answered(), ['/@endless'],
        reason: 'the refusal is of the atDirectory\'s answer');
  });

  test('a close of the lookup it asks for ends the request at once', () async {
    final abandonment = Abandonment();
    final asked = abandonment.run(() => finder.findSecondary('@slow'));
    expect(await firstTaken(), ['/@slow'],
        reason: 'the request is in flight when the lookup closes');
    final closedAt = DateTime.now();
    abandonment.abandon();

    await expectLater(
        asked,
        throwsA(isA<RootServerConnectivityException>()
            .having((e) => e.message, 'message', contains('abandoned'))));
    expect(DateTime.now().difference(closedAt),
        lessThan(const Duration(seconds: 1)),
        reason: 'the atDirectory takes 2 seconds to answer @slow');
  });

  for (final atSign in ['@malformed', '@badport']) {
    test('a 200 body that is not host:port is refused ($atSign)', () async {
      await expectLater(
          finder.findSecondary(atSign),
          throwsA(allOf(
              isA<AtException>(), isNot(isA<SecondaryNotFoundException>()))));
      expect(await answered(), ['/$atSign'],
          reason: 'the refusal is of the atDirectory\'s answer');
    });
  }

  test('any other status is RootServerConnectivityException', () async {
    await expectLater(finder.findSecondary('@broken'),
        throwsA(isA<RootServerConnectivityException>()));
    expect(await answered(), ['/@broken'],
        reason: 'the status is the atDirectory\'s answer');
  });

  test('an unreachable atDirectory is RootServerConnectivityException',
      () async {
    await expectLater(
        HttpsSecondaryAddressFinder('127.0.0.1', port: 1, scheme: 'http')
            .findSecondary('@alice'),
        throwsA(isA<RootServerConnectivityException>()));
  });

  test('an answer slower than timeout is AtTimeoutException', () async {
    final asked =
        finder.findSecondary('@slow', timeout: const Duration(seconds: 1));
    var settled = false;
    unawaited(asked.then((_) {}, onError: (_) {}).whenComplete(() {
      settled = true;
    }));
    expect(await firstTaken(), ['/@slow'],
        reason: 'the request reaches the atDirectory');
    expect(settled, isFalse,
        reason: 'the request is in flight before the timeout runs out');
    await expectLater(asked, throwsA(isA<AtTimeoutException>()));
  });
}
