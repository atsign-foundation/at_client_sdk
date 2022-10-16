import 'dart:convert';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart';

class AESEncrypter extends Converter<List<int>, List<int>> {
  final String _encryptionKey;
  const AESEncrypter(this._encryptionKey);

  @override
  List<int> convert(List<int> input) {
    var aesKey = AES(Key.fromBase64(_encryptionKey), padding: null);

    var initializationVector = IV.fromLength(16);
    var aesEncrypter = Encrypter(aesKey);
    var encryptedValue =
        aesEncrypter.encryptBytes(input, iv: initializationVector);
    return encryptedValue.bytes;
  }

  @override
  AESEncryptionSink startChunkedConversion(sink) {
    return AESEncryptionSink(_encryptionKey, sink);
  }
}

class AESDecrypter extends Converter<List<int>, List<int>> {
  final String _encryptionKey;
  const AESDecrypter(this._encryptionKey);

  @override
  List<int> convert(List<int> input) {
    var aesKey = AES(Key.fromBase64(_encryptionKey), padding: null);
    var decrypter = Encrypter(aesKey);
    var iv2 = IV.fromLength(16);
    return decrypter.decryptBytes(Encrypted(input as Uint8List), iv: iv2);
  }

  @override
  AESDecryptionSink startChunkedConversion(sink) {
    return AESDecryptionSink(_encryptionKey, sink);
  }
}

class AESCodec extends Codec<List<int>, List<int>> {
  final String _key;
  const AESCodec(this._key);

  @override
  List<int> encode(List<int> input) {
    return AESEncrypter(_key).convert(input);
  }

  @override
  List<int> decode(List<int> encoded) {
    return AESDecrypter(_key).convert(encoded);
  }

  @override
  AESEncrypter get encoder => AESEncrypter(_key);
  @override
  AESDecrypter get decoder => AESDecrypter(_key);
}

class AESEncryptionSink extends ByteConversionSink {
  final Converter _converter;
  final Sink<List<int>> _outSink;
  AESEncryptionSink(key, this._outSink) : _converter = AESEncrypter(key);

  @override
  void add(List<int> chunk) {
    _outSink.add(_converter.convert(chunk));
  }

  @override
  void close() {
    _outSink.close();
  }

  @override
  void addSlice(List<int> chunk, int start, int end, bool isLast) {
    add(chunk.sublist(start, end));
    if (isLast) close();
  }
}

class AESDecryptionSink extends ChunkedConversionSink<List<int>> {
  final Converter _converter;
  final Sink<List<int>> _outSink;
  AESDecryptionSink(key, this._outSink) : _converter = AESDecrypter(key);

  @override
  void add(List<int> chunk) {
    _outSink.add(_converter.convert(chunk));
  }

  @override
  void close() {
    _outSink.close();
  }
}
