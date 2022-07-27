import 'dart:convert';
import 'package:at_client/src/converters/encoder/at_encoder.dart';

/// An abstract class for encode of data
abstract class AbstractAtDecoder<T, V> {
  V decode(T value);
}

/// Class implementing base64 decoding of data
class AtBase64Decoder extends AbstractAtDecoder<String, String> {
  @override
  String decode(String value) {
    return utf8.decode(base64Decode(value));
  }
}

class AtDecoderFactory {
  AbstractAtDecoder get(EncodingType encodingType) {
    if (encodingType == EncodingType.base64) {
      return AtBase64Decoder();
    }
    return AtBase64Decoder();
  }
}

class AtDecoderImpl {
  String decodeData(String value, EncodingType encodingType) {
    return AtDecoderFactory().get(encodingType).decode(value);
  }
}
