import 'dart:typed_data';
import 'package:pq_demo_6/openssl.dart' show HmacSha256;
import 'mls_crypto.dart';

class MessageKey {
  final Uint8List key; // 32 B AES-256 key
  final Uint8List nonce; // 12 B AES-GCM nonce
  MessageKey(this.key, this.nonce);
}

class SenderRatchet {
  Uint8List _currentSecret;
  int _generation;
  final Map<int, MessageKey> _skippedKeys;
  final HmacSha256 _hmac;

  SenderRatchet(this._hmac, Uint8List leafSecret)
      : _currentSecret = leafSecret,
        _generation = 0,
        _skippedKeys = {};

  int get generation => _generation;

  MessageKey deriveMessageKey(int targetGeneration) {
    if (targetGeneration < _generation) {
      final skipped = _skippedKeys.remove(targetGeneration);
      if (skipped == null) {
        throw StateError('Key for generation $targetGeneration already consumed');
      }
      return skipped;
    }
    while (_generation < targetGeneration) {
      _skippedKeys[_generation] = MessageKey(
        expandWithLabel(_hmac, _currentSecret, 'key', _u32(this._generation), 32),
        expandWithLabel(_hmac, _currentSecret, 'nonce', _u32(this._generation), 12),
      );
      _currentSecret =
          expandWithLabel(_hmac, _currentSecret, 'secret', _u32(this._generation), 32);
      _generation++;
    }
    final key = MessageKey(
      expandWithLabel(_hmac, _currentSecret, 'key', _u32(_generation), 32),
      expandWithLabel(_hmac, _currentSecret, 'nonce', _u32(_generation), 12),
    );
    _currentSecret =
        expandWithLabel(_hmac, _currentSecret, 'secret', _u32(_generation), 32);
    _generation++;
    return key;
  }

  static Uint8List _u32(int n) => Uint8List(4)
    ..[0] = (n >> 24) & 0xff
    ..[1] = (n >> 16) & 0xff
    ..[2] = (n >> 8) & 0xff
    ..[3] = n & 0xff;
}

class SecretTree {
  final HmacSha256 _hmac;
  final Map<int, SenderRatchet> _ratchets;
  final Uint8List _encryptionSecret;
  final int _numLeaves;

  SecretTree(this._hmac, this._encryptionSecret, this._numLeaves)
      : _ratchets = {};

  SenderRatchet getRatchet(int leafIndex) {
    return _ratchets.putIfAbsent(leafIndex, () {
      final leafSecret = expandWithLabel(
          _hmac, _encryptionSecret, 'leaf', _leafBytes(leafIndex), 32);
      return SenderRatchet(_hmac, leafSecret);
    });
  }

  static Uint8List _leafBytes(int i) => Uint8List(4)
    ..[0] = (i >> 24) & 0xff
    ..[1] = (i >> 16) & 0xff
    ..[2] = (i >> 8) & 0xff
    ..[3] = i & 0xff;
}
