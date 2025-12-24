import 'dart:convert' show base64Encode, base64Decode;
import 'dart:typed_data';

/// Wrapper class for handling base64 encoded byte data
class AtBytes {
  final Uint8List bytes;
  const AtBytes(this.bytes);

  factory AtBytes.fromString(String str) {
    return AtBytes(base64Decode(str));
  }

  @override
  String toString() => base64Encode(bytes);

  bool strEquals(String str) => toString() == str;
}
