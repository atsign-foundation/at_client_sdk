import 'dart:convert';
import 'dart:math';

import 'package:at_telemetry/at_telemetry.dart';
import 'package:test/test.dart';

const String _bootId = 'AAECAwQFBgcICQoLDA0ODw';

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

    test('the constructor rejects a malformed boot id', () {
      for (final String bootId in <String>[
        '',
        'short',
        'AAECAwQFBgcICQoLDA0ODw==',
        'AAECAwQFBgcICQoLDA0OD+',
      ]) {
        expect(
          () => AtTelemetrySequence(bootId: bootId, number: 0),
          throwsArgumentError,
          reason: bootId,
        );
      }
    });

    test('parse rejects a boot id with nonzero trailing bits', () {
      // AAECAwQFBgcICQoLDA0ODx is AAECAwQFBgcICQoLDA0ODw with spare bits set,
      // so accepting it would give two headers for one boot id
      expect(
        () => AtTelemetrySequence.parse('boot=AAECAwQFBgcICQoLDA0ODx;seq=0'),
        throwsFormatException,
      );
    });

    test('accepts 0 and the largest number JavaScript can hold', () {
      for (final int number in <int>[0, AtTelemetrySequence.maxNumber]) {
        final AtTelemetrySequence sequence =
            AtTelemetrySequence(bootId: _bootId, number: number);

        expect(AtTelemetrySequence.parse(sequence.header), sequence);
      }
      expect(
        () => AtTelemetrySequence(
          bootId: _bootId,
          number: AtTelemetrySequence.maxNumber + 1,
        ),
        throwsRangeError,
      );
    });

    test('parse rejects headers that are not exactly the canonical form', () {
      for (final String header in <String>[
        '',
        'boot=$_bootId;seq=',
        'boot=$_bootId;seq=-1',
        'boot=$_bootId;seq=1 ',
        ' boot=$_bootId;seq=1',
        'boot=$_bootId; seq=1',
        'seq=1;boot=$_bootId',
        'boot=$_bootId;seq=1;x=2',
        'boot=$_bootId;seq=12345678901234567',
      ]) {
        expect(
          () => AtTelemetrySequence.parse(header),
          throwsFormatException,
          reason: header,
        );
      }
    });

    test('a seeded Random gives a repeatable boot id', () {
      expect(
        AtTelemetrySequence.newBootId(random: Random(7)),
        AtTelemetrySequence.newBootId(random: Random(7)),
      );
      expect(
        AtTelemetrySequence.newBootId(random: Random(7)),
        matches(r'^[A-Za-z0-9_-]{22}$'),
      );
    });

    test('is equal by boot id and number', () {
      final AtTelemetrySequence sequence =
          AtTelemetrySequence(bootId: _bootId, number: 1);
      final AtTelemetrySequence same =
          AtTelemetrySequence(bootId: _bootId, number: 1);

      expect(sequence, same);
      expect(sequence.hashCode, same.hashCode);
      expect(sequence, isNot(AtTelemetrySequence(bootId: _bootId, number: 2)));
      expect(
        sequence,
        isNot(AtTelemetrySequence(
          bootId: 'AQECAwQFBgcICQoLDA0ODw',
          number: 1,
        )),
      );
      expect(sequence, isNot(sequence.header));
    });

    test('toString is the header', () {
      final AtTelemetrySequence sequence =
          AtTelemetrySequence(bootId: _bootId, number: 3);

      expect(sequence.toString(), 'boot=$_bootId;seq=3');
    });
  });
}
