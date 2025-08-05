import 'package:at_chops/src/key/at_key_pair.dart';
import 'package:encrypt/encrypt.dart';
import 'dart:convert';

/// Represents an AES key for symmetric encryption.
class AESKey extends SymmetricKey {
  final String _aesKey;
  @override
  String get key => _aesKey;
  AESKey(this._aesKey) : super(_aesKey);

  /// Generates an AES key for symmetric encryption with a given length.
  /// Key is created with a list of [length] with non negative values randomly generated from >=0 and < 256 and converted to base64 string
  static AESKey generate(int length) {
    var aesKey = AES(Key.fromSecureRandom(length));
    return AESKey(aesKey.key.base64);
  }

  /// Returns the key length in bytes.
  /// e.g for 128 bit key length will be 16
  /// for 192 bit key length will be 24
  /// for 256 bit key length will be 32
  int getLength() {
    return base64.decode(_aesKey).length;
  }

  @override
  String toString() {
    return _aesKey;
  }
}
