@TestOn('browser')
library;

import 'dart:async';

import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup_web.dart';
import 'package:at_lookup/src/util/abandonment.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

void main() {
  late StreamChannel channel;
  late HttpsSecondaryAddressFinder finder;
  final paths = <String>[];

  setUpAll(() async {
    channel = spawnHybridUri('https_fake_directory.dart');
    final port = Completer<int>();
    channel.stream.listen((event) => port.isCompleted
        ? paths.add(event as String)
        : port.complete((event as num).toInt()));
    finder = HttpsSecondaryAddressFinder('127.0.0.1',
        port: await port.future, scheme: 'http');
  });

  tearDownAll(() => channel.sink.close());

  setUp(paths.clear);

  test('a 200 host:port answer is the atServer address', () async {
    final address = await finder.findSecondary('@alice');
    expect(address.host, 'vip.example.org');
    expect(address.port, 1234);
    expect(paths, ['/@alice']);
  });

  test('an atSign given without its @ is asked for with one', () async {
    expect((await finder.findSecondary('alice')).port, 1234);
    expect(paths, ['/@alice']);
  });

  test('a 404 is SecondaryNotFoundException', () async {
    await expectLater(finder.findSecondary('@nobody'),
        throwsA(isA<SecondaryNotFoundException>()));
  });

  test('the atSign is asked for in its canonical form', () async {
    expect((await finder.findSecondary('@Alice')).port, 1234);
    expect(paths, ['/@alice']);
  });

  test('an atSign that is not one is refused before anything is asked',
      () async {
    await expectLater(finder.findSecondary('@a b/c?d'),
        throwsA(isA<InvalidAtSignException>()));
    expect(paths, isEmpty);
  });

  test('an answer naming a host behind an @ is refused', () async {
    await expectLater(
        finder.findSecondary('@elsewhere'),
        throwsA(isA<AtException>().having(
            (e) => e.message, 'message', contains('not host:port'))));
  });

  test('an answer longer than 512 bytes is refused', () async {
    await expectLater(
        finder.findSecondary('@huge'),
        throwsA(isA<AtException>().having((e) => e.message, 'message',
            contains('longer than 512 bytes'))));
  });

  test('a close of the lookup it asks for ends the request at once', () async {
    final abandonment = Abandonment();
    final asked = abandonment.run(() => finder.findSecondary('@slow'));
    await Future<void>.delayed(const Duration(milliseconds: 100));
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
    });
  }

  test('any other status is RootServerConnectivityException', () async {
    await expectLater(finder.findSecondary('@broken'),
        throwsA(isA<RootServerConnectivityException>()));
  });

  test('an unreachable atDirectory is RootServerConnectivityException',
      () async {
    await expectLater(
        HttpsSecondaryAddressFinder('127.0.0.1', port: 1, scheme: 'http')
            .findSecondary('@alice'),
        throwsA(isA<RootServerConnectivityException>()));
  });

  test('an answer slower than timeout is AtTimeoutException', () async {
    await expectLater(
        finder.findSecondary('@slow',
            timeout: const Duration(milliseconds: 200)),
        throwsA(isA<AtTimeoutException>()));
  });
}
