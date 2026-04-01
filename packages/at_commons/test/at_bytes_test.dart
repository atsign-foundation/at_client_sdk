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
      AtBytes a = AtBytes.fromString('bone');
      AtBytes b = AtBytes.fromString('bone');
      AtBytes c = AtBytes.fromString('stringss');
      AtBytes? d;
      AtBytes? e;
      // Verify toString() matches
      expect(a.strEquals(b.toString()), isTrue);
      expect(a == b, isTrue);
      expect(a == c, isFalse);
      // Verify null cases
      expect(a == d, isFalse);
      expect(d == e, isTrue);
    });

    test('equal AtBytes instances should have the same hashCode', () {
      final a = AtBytes(Uint8List.fromList([72, 101, 108, 108, 111]));
      final b = AtBytes(Uint8List.fromList([72, 101, 108, 108, 111]));
      final c = AtBytes(Uint8List.fromList([72, 101, 108, 108, 112]));

      expect(a == b, isTrue);
      expect(a.hashCode, b.hashCode);
      expect(a.hashCode == c.hashCode, isFalse);
    });
  });
}
