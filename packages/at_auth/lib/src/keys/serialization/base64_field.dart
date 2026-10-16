import 'dart:convert';
import 'dart:typed_data';

/// [value], the base64 held in the keyfile field [fieldName], decoded.
///
/// A value that does not decode is refused with the exception [refuse] makes
/// of a message naming the field, the decoder's reason and the offset of the
/// first character it rejected, and holding nothing of [value].
Uint8List decodeBase64Field(String value, String fieldName,
    [Exception Function(String message) refuse = FormatException.new]) {
  try {
    return base64Decode(value);
  } on FormatException catch (e) {
    throw refuse('$fieldName is not valid base64: ${e.message} '
        '(at offset ${e.offset})');
  }
}
