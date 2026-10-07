import 'dart:convert';
import 'dart:math';

import 'package:at_telemetry/at_telemetry.dart';
import 'package:test/test.dart';

void main() {
  group('AtTelemetrySequence', () {
    test('round trips through its header', () {
      final AtTelemetrySequence sequence = AtTelemetrySequence(
        bootId: AtTelemetrySequence.newBootId(random: Random(1)),
        number: 7,
      );

      expect(AtTelemetrySequence.parse(sequence.header), sequence);
      expect(sequence.header, matches(r'^boot=[A-Za-z0-9_-]{22};seq=7$'));
    });

    test('a new boot id is 16 random bytes', () {
      final String bootId = AtTelemetrySequence.newBootId();

      expect(base64Url.decode('$bootId=='), hasLength(16));
      expect(bootId, isNot(AtTelemetrySequence.newBootId()));
    });

    test('rejects a negative or oversized number', () {
      expect(
        () => AtTelemetrySequence(
          bootId: 'AAECAwQFBgcICQoLDA0ODw',
          number: -1,
        ),
        throwsRangeError,
      );
      expect(
        () => AtTelemetrySequence.parse(
          'boot=AAECAwQFBgcICQoLDA0ODw;seq=9007199254740992',
        ),
        throwsFormatException,
      );
    });

    test('rejects a malformed boot id', () {
      expect(
        () => AtTelemetrySequence.parse('boot=short;seq=1'),
        throwsFormatException,
      );
    });
  });
}
