import 'dart:convert';
import 'dart:typed_data';

import 'package:at_lookup/src/web/ws_frame.dart';
import 'package:test/test.dart';

void main() {
  group('ws_frame_test', () {
    test('String encodes to utf8', () {
      final input = 'hello';
      final bytes = frameBytes(input);
      expect(bytes, utf8.encode(input));
    });

    test('multi-byte UTF-8 string round-trips byte-exact', () {
      final input = 'hello 🌍';
      final bytes = frameBytes(input);
      expect(utf8.decode(bytes), input);
    });

    test('ByteBuffer encodes to Uint8List.view', () {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final buffer = bytes.buffer;
      final result = frameBytes(buffer);
      expect(result, bytes);
      expect(result, isA<Uint8List>());
    });

    test('Uint8List returns as is', () {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final result = frameBytes(bytes);
      expect(result, same(bytes));
    });

    test('List<int> returns as is', () {
      final bytes = <int>[1, 2, 3];
      final result = frameBytes(bytes);
      expect(result, same(bytes));
    });

    test('unsupported type throws ArgumentError', () {
      expect(() => frameBytes(123), throwsA(isA<ArgumentError>()));
      expect(() => frameBytes(null), throwsA(isA<ArgumentError>()));
    });
  });
}
