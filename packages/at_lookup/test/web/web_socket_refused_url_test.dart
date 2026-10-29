@TestOn('browser || node')
library;

import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/src/web/web_socket_transport_factory.dart';
import 'package:test/test.dart';

void main() {
  group('Given an atServer address the WebSocket constructor refuses', () {
    test(
        'when a transport is opened to it, then connect fails with '
        'SecondaryConnectException', () async {
      await expectLater(
          const WebSocketTransportFactory().connect('not a host', '1'),
          throwsA(isA<SecondaryConnectException>()
              .having((e) => e.message, 'message', contains('not a host:1'))));
    });
  });
}
