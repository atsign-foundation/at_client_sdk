import 'dart:io';

import 'package:at_client/src/lifecycle/transport_error_io.dart' as io;
import 'package:at_client/src/lifecycle/transport_error_web.dart' as web;
import 'package:test/test.dart';

void main() {
  group('isTransportError', () {
    test('io branch', () {
      expect(io.isTransportError(SocketException('x')), isTrue);
      expect(io.isTransportError(HandshakeException('x')), isTrue);
      expect(io.isTransportError(StateError('x')), isFalse);
    });

    test('web branch', () {
      expect(web.isTransportError(SocketException('x')), isFalse);
      expect(web.isTransportError(HandshakeException('x')), isFalse);
      expect(web.isTransportError(StateError('x')), isFalse);
    });
  });
}
