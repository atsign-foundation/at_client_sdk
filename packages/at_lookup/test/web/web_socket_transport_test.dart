@TestOn('browser')
library;

import 'dart:async';
import 'dart:convert';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/src/web/web_socket_transport_factory.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

void main() {
  group('web_socket_transport_test', () {
    late StreamChannel channel;
    late int port;

    setUpAll(() async {
      channel = spawnHybridUri('ws_fake_server.dart');
      port = (await channel.stream.first as num).toInt();
    });

    tearDownAll(() {
      channel.sink.close();
    });

    test('connect, add, inbound', () async {
      final factory = WebSocketTransportFactory(scheme: 'ws');
      final transport = await factory.connect('127.0.0.1', port.toString());

      transport.add(utf8.encode('from:@a\n'));

      final event = await transport.inbound.first;
      expect(utf8.decode(event), 'data:from:@a\n');

      transport.destroy();
    });

    test('a binary frame arrives as its bytes', () async {
      final transport = await WebSocketTransportFactory(scheme: 'ws')
          .connect('127.0.0.1', port.toString());

      transport.add(utf8.encode('@binary:from:@a\n'));

      final event = await transport.inbound.first
          .timeout(const Duration(seconds: 5));
      expect(utf8.decode(event), 'data:from:@a\n',
          reason: 'a browser hands a binary frame over as a Blob unless the '
              'socket asks for an ArrayBuffer');

      transport.destroy();
    });

    test('server-side close completes inbound', () async {
      final factory = WebSocketTransportFactory(scheme: 'ws');
      final transport = await factory.connect('127.0.0.1', port.toString());

      transport.add(utf8.encode('@exit'));

      await expectLater(transport.inbound.toList(), completion(isEmpty));
      transport.destroy();
    });

    test('destroy() twice does not throw, inbound completes', () async {
      final factory = WebSocketTransportFactory(scheme: 'ws');
      final transport = await factory.connect('127.0.0.1', port.toString());

      transport.destroy();
      transport.destroy();

      await expectLater(transport.inbound.toList(), completion(isEmpty));
    });

    test('a small command\'s flush does not wait for the socket to drain',
        () async {
      final transport = await WebSocketTransportFactory(scheme: 'ws')
          .connect('127.0.0.1', port.toString());
      final replies = StreamIterator(transport.inbound);
      final flushes = <int>[];

      for (var i = 0; i < 100; i++) {
        transport.add(utf8.encode('noop:$i\n'));
        final watch = Stopwatch()..start();
        await transport.flush();
        flushes.add(watch.elapsedMicroseconds);
        expect(await replies.moveNext(), isTrue);
      }
      flushes.sort();
      final median = flushes[flushes.length ~/ 2];

      expect(median, lessThan(5000),
          reason: 'a command within the high-water mark returns from flush '
              'without a 10 ms poll; median ${median}us over 100 commands');
      transport.destroy();
    });

    test('connect to unused port fails', () async {
      final factory = WebSocketTransportFactory(scheme: 'ws');
      await expectLater(
        factory.connect('127.0.0.1', '32567', timeout: Duration(seconds: 2)),
        throwsA(isA<SecondaryConnectException>()),
      );
    });
  });
}
