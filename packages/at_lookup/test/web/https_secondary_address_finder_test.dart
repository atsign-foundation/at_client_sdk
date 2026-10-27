@TestOn('browser')
library;

import 'dart:async';

import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup_web.dart';
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

  test('the atSign is URL-encoded into the path', () async {
    await expectLater(
        finder.findSecondary('@a b/c?d'), throwsA(isA<AtException>()));
    expect(paths, ['/@a%20b%2Fc%3Fd']);
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
