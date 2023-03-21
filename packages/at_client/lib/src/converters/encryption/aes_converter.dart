import 'dart:convert';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart';

class AESEncrypter extends Converter<List<int>, List<int>> {
  final String encryptionKey;
  final String? ivBase64;

  const AESEncrypter(this.encryptionKey, {this.ivBase64});

  @override
  List<int> convert(List<int> input) {
    var aesKey = AES(Key.fromBase64(encryptionKey), padding: null);

    var aesEncrypter = Encrypter(aesKey);
    var encryptedValue = aesEncrypter.encryptBytes(input, iv: getIV(ivBase64));
    return encryptedValue.bytes;
  }

  @override
  AESEncryptionSink startChunkedConversion(sink) {
    return AESEncryptionSink(encryptionKey, sink, ivBase64: ivBase64);
  }
}

class AESDecrypter extends Converter<List<int>, List<int>> {
  final String encryptionKey;
  final String? ivBase64;

  const AESDecrypter(this.encryptionKey, {this.ivBase64});

  @override
  List<int> convert(List<int> input) {
    var aesKey = AES(Key.fromBase64(encryptionKey), padding: null);
    var decrypter = Encrypter(aesKey);
    return decrypter.decryptBytes(Encrypted(input as Uint8List),
        iv: getIV(ivBase64));
  }

  @override
  AESDecryptionSink startChunkedConversion(sink) {
    return AESDecryptionSink(encryptionKey, sink, ivBase64: ivBase64);
  }
}

class AESCodec extends Codec<List<int>, List<int>> {
  final String encryptionKey;
  final String? ivBase64;

  const AESCodec(this.encryptionKey, {this.ivBase64});

  @override
  List<int> encode(List<int> input) {
    return AESEncrypter(encryptionKey, ivBase64: ivBase64).convert(input);
  }

  @override
  List<int> decode(List<int> encoded) {
    return AESDecrypter(encryptionKey, ivBase64: ivBase64).convert(encoded);
  }

  @override
  AESEncrypter get encoder => AESEncrypter(encryptionKey, ivBase64: ivBase64);

  @override
  AESDecrypter get decoder => AESDecrypter(encryptionKey, ivBase64: ivBase64);
}

class AESEncryptionSink extends ByteConversionSink {
  final Converter _converter;
  final Sink<List<int>> _outSink;

  AESEncryptionSink(String encryptionKey, this._outSink, {String? ivBase64})
      : _converter = AESEncrypter(encryptionKey, ivBase64: ivBase64);

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

  AESDecryptionSink(String encryptionKey, this._outSink, {String? ivBase64})
      : _converter = AESDecrypter(encryptionKey, ivBase64: ivBase64);

  @override
  void add(List<int> chunk) {
    _outSink.add(_converter.convert(chunk));
  }

  @override
  void close() {
    _outSink.close();
  }
}

IV getIV(String? ivBase64) {
  if (ivBase64 == null) {
    return IV.fromLength(16);
  } else {
    return IV.fromBase64(ivBase64);
  }
}
