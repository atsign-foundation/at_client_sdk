import 'dart:convert';

/// An abstract class for encode of data
abstract class AbstractAtEncoder<T, V> {
  V encode(T value);
}

/// Class implementing base64 encoding of data
class AtBase64Encoder extends AbstractAtEncoder<String, String> {
  @override
  String encode(String value) {
    return base64Encode(utf8.encode(value));
  }
}

class AtEncoderFactory {
  AbstractAtEncoder get(EncodingType encodingType) {
    if (encodingType == EncodingType.base64) {
      return AtBase64Encoder();
    }
    return AtBase64Encoder();
  }
}

class AtEncoderImpl {
  String encodeData(String value, EncodingType encodingType) {
    return AtEncoderFactory().get(encodingType).encode(value);
  }
}

enum EncodingType { base64 }
