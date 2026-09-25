@TestOn('browser')
library;

import 'dart:convert';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/src/web/web_socket_transport.dart';
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

    test('connect to unused port fails', () async {
      final factory = WebSocketTransportFactory(scheme: 'ws');
      await expectLater(
        factory.connect('127.0.0.1', '32567', timeout: Duration(seconds: 2)),
        throwsA(isA<SecondaryConnectException>()),
      );
    });
  });
}
