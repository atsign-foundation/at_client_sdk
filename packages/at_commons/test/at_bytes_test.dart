import 'package:test/test.dart';
import 'package:at_commons/src/key/atbytes.dart';
import 'dart:typed_data';

void main() {
  group('AtBytes', () {
    test('strEquals should compare AtBytes with String by value', () {
      // Create test data
      final testData =
      Uint8List.fromList([72, 101, 108, 108, 111]); // "Hello" in ASCII
      final atBytes = AtBytes(testData);

      // The base64 encoded string of "Hello" is "SGVsbG8="
      final expectedBase64String = "SGVsbG8=";

      // Test strEquals with string
      expect(atBytes.strEquals(expectedBase64String), true);
      expect(atBytes.strEquals("WrongString"), false);

      // Verify that a different AtBytes instance with same content equals the same string
      final atBytes2 = AtBytes(Uint8List.fromList([72, 101, 108, 108, 111]));
      expect(atBytes2.strEquals(expectedBase64String), true);

      // Verify toString() matches the expected base64 string
      expect(atBytes.toString(), expectedBase64String);
    });

    test('AtBytes.equals should work regardless of nullity', () {
      AtBytes a = AtBytes.fromString('str');
      AtBytes b = AtBytes.fromString('str');
      AtBytes c = AtBytes.fromString('string');
      AtBytes? d;
      AtBytes? e;
      // Verify toString() matches
      expect(a.strEquals(b.toString()), isTrue);
      expect(AtBytes.equals(a, b), isTrue);
      expect(AtBytes.equals(a, c), isFalse);
      // Verify null cases
      expect(AtBytes.equals(a, d), isFalse);
      expect(AtBytes.equals(d, e), isTrue);
    });
  });
}
