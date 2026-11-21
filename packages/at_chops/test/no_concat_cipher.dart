import 'dart:collection';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart' show DartCipher;
import 'package:test/test.dart';

/// Encrypts with [fallback], but hands back a [SecretBox] whose ciphertext
/// and tag fail the test if anything concatenates them (`+`) or copies them
/// whole into a new list (`toList`), so encryption must copy them straight
/// into its output.
class NoConcatCipher extends Cipher {
  final Cipher _fallback;

  NoConcatCipher(this._fallback);

  @override
  MacAlgorithm get macAlgorithm => _fallback.macAlgorithm;

  @override
  int get nonceLength => _fallback.nonceLength;

  @override
  int get secretKeyLength => _fallback.secretKeyLength;

  @override
  Future<SecretBox> encrypt(
    List<int> clearText, {
    required SecretKey secretKey,
    List<int>? nonce,
    List<int> aad = const <int>[],
    Uint8List? possibleBuffer,
  }) async {
    final SecretBox box = await _fallback.encrypt(clearText,
        secretKey: secretKey, nonce: nonce, aad: aad);
    return SecretBox(_NoConcatList(box.cipherText, 'ciphertext'),
        nonce: box.nonce, mac: Mac(_NoConcatList(box.mac.bytes, 'tag')));
  }

  @override
  Future<List<int>> decrypt(
    SecretBox secretBox, {
    required SecretKey secretKey,
    List<int> aad = const <int>[],
    Uint8List? possibleBuffer,
  }) =>
      _fallback.decrypt(secretBox, secretKey: secretKey, aad: aad);

  @override
  DartCipher toSync() => _fallback.toSync();
}

/// Expects [out] to be [expected] in a Uint8List that owns a buffer of
/// exactly its length.
void expectExactLengthOutput(Uint8List out, List<int> expected) {
  expect(out, expected, reason: 'output is not the ciphertext and tag');
  expect(out.offsetInBytes, 0, reason: 'output is a view into a larger buffer');
  expect(out.buffer.lengthInBytes, expected.length,
      reason: 'output buffer is not exactly the ciphertext and tag length');
}

class _NoConcatList extends ListBase<int> {
  final List<int> _bytes;
  final String _name;

  _NoConcatList(this._bytes, this._name);

  @override
  int get length => _bytes.length;

  @override
  set length(int newLength) => fail('the $_name was resized');

  @override
  int operator [](int index) => _bytes[index];

  @override
  void operator []=(int index, int value) => fail('the $_name was modified');

  @override
  List<int> operator +(List<int> other) =>
      fail('the $_name was concatenated into a new list');

  @override
  Iterator<int> get iterator => fail('the $_name was iterated');

  @override
  List<int> toList({bool growable = true}) =>
      fail('the $_name was copied into a new list');
}
