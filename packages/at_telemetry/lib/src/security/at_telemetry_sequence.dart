import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

// Where a batch sits in its producer's stream: a boot id, random at each
// atServer start, and a number counting up from 0 within that boot. It
// travels as the at-telemetry-sequence header, under the signature.
final class AtTelemetrySequence {
  static const int bootIdLength = 16;
  // 2^53 - 1, so the number survives a JavaScript reader
  static const int maxNumber = 9007199254740991;
  static final RegExp _bootIdPattern = RegExp(r'^[A-Za-z0-9_-]{22}$');
  static final RegExp _headerPattern =
      RegExp(r'^boot=([A-Za-z0-9_-]{22});seq=(0|[1-9][0-9]{0,15})$');

  final String bootId;
  final int number;

  AtTelemetrySequence({required this.bootId, required this.number}) {
    if (!_bootIdPattern.hasMatch(bootId) ||
        base64Url.decode('$bootId==').length != bootIdLength) {
      throw ArgumentError.value(bootId, 'bootId', 'must be 16 base64url bytes');
    }
    if (number < 0 || number > maxNumber) {
      throw RangeError.range(number, 0, maxNumber, 'number');
    }
  }

  factory AtTelemetrySequence.parse(String header) {
    final RegExpMatch? match = _headerPattern.firstMatch(header);
    final int? number = match == null ? null : int.tryParse(match[2]!);
    if (match == null || number == null || number > maxNumber) {
      throw const FormatException('Invalid at-telemetry-sequence header');
    }
    try {
      return AtTelemetrySequence(bootId: match[1]!, number: number);
    } on ArgumentError {
      throw const FormatException('Invalid at-telemetry-sequence header');
    }
  }

  // 16 random bytes as unpadded base64url
  static String newBootId({Random? random}) {
    final Random source = random ?? Random.secure();
    final Uint8List bytes = Uint8List.fromList(
      List<int>.generate(bootIdLength, (int _) => source.nextInt(256)),
    );
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  String get header => 'boot=$bootId;seq=$number';

  @override
  bool operator ==(Object other) =>
      other is AtTelemetrySequence &&
      other.bootId == bootId &&
      other.number == number;

  @override
  int get hashCode => Object.hash(bootId, number);

  @override
  String toString() => header;
}
