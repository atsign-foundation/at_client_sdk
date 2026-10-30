import 'dart:convert';

import 'package:at_chops/src/key/keys.dart';
import 'package:encrypt/encrypt.dart';

/// Represents an ED25519 key for symmetric encryption.
class Ed25519Key extends SymmetricKey {
  final String _key;
  @override
  String get key => _key;
  Ed25519Key(this._key) : super(_key);

  /// Generates an AES key for symmetric encryption with a given length.
  /// Key is created with a list of [length] with non negative values randomly generated from >=0 and < 256 and converted to base64 string
  static Ed25519Key generate(int length) {
    var aesKey = AES(Key.fromSecureRandom(length));
    return Ed25519Key(aesKey.key.base64);
  }

  /// Returns the key length in bytes.
  /// e.g for 128 bit key length will be 16
  /// for 192 bit key length will be 24
  /// for 256 bit key length will be 32
  int getLength() {
    return base64.decode(_key).length;
  }

  @override
  String toString() {
    return _key;
  }
}
