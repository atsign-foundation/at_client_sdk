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

  @override
  bool operator ==(Object other) {
    if (other is! AtBytes) return false;
    if (identical(this, other)) return true;
    if (bytes.length != other.bytes.length) return false;
    for (int i = 0; i < bytes.length; i++) {
      if (bytes[i] != other.bytes[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(bytes);
}
