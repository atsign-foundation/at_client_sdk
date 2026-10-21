import 'dart:typed_data';

/// Lowercase hex encoding of [bytes], two characters per byte.
///
/// Internal: the string form the hashing algorithms report. Digest APIs hand
/// back raw bytes, and the Atsign Protocol carries hashes as lowercase hex
/// (checksums, `md5CheckSum`), so there is one encoder rather than one per algo.
String hexEncode(List<int> bytes) {
  final buffer = StringBuffer();
  for (final byte in bytes) {
    buffer.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

/// Bytes of the hex string [hex], either letter case.
///
/// Throws [FormatException] on an odd length or any character outside
/// `0-9a-fA-F`.
Uint8List hexDecode(String hex) {
  if (hex.length.isOdd) {
    throw FormatException('Hex string has an odd length', hex);
  }
  final bytes = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < bytes.length; i++) {
    bytes[i] = (_nibble(hex, i * 2) << 4) | _nibble(hex, i * 2 + 1);
  }
  return bytes;
}

int _nibble(String hex, int index) {
  final unit = hex.codeUnitAt(index);
  if (unit >= 0x30 && unit <= 0x39) return unit - 0x30;
  if (unit >= 0x61 && unit <= 0x66) return unit - 0x61 + 10;
  if (unit >= 0x41 && unit <= 0x46) return unit - 0x41 + 10;
  throw FormatException('Not a hex digit', hex, index);
}
