import 'dart:collection';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:at_chops/src/algorithm/encryption/aead_output.dart';
import 'package:at_chops/src/algorithm/ffi/openssl_ffi_bindings.dart'
    show aesGcmUpdate;
import 'package:test/test.dart';

/// Catalogue: features/at_chops/aes_gcm_output.feature
void main() {
  test(
      'Pure-Dart encryption joins the ciphertext and tag in one buffer of exactly their length',
      () {
    final Uint8List cipherText =
        Uint8List.fromList(List<int>.generate(1000, (int i) => i & 0xff));
    final Uint8List tag =
        Uint8List.fromList(List<int>.generate(16, (int i) => 0xf0 + i));

    final Uint8List out = cipherTextThenTag(
        _NoConcatList(cipherText, 'ciphertext'), _NoConcatList(tag, 'tag'));

    expect(out, [...cipherText, ...tag],
        reason: 'output is not the ciphertext followed by the tag');
    expect(out.offsetInBytes, 0,
        reason: 'output is a view into a larger buffer');
    expect(out.buffer.lengthInBytes, cipherText.length + tag.length,
        reason: 'output buffer is not exactly the ciphertext and tag length');
  });

  // Both directions: a shorter length misplaces the tag, and a longer one
  // writes or reads past the end of a native buffer.
  for (final (String operation, String input, String output, int reported) in [
    ('EVP_EncryptUpdate', 'plaintext', 'ciphertext', 59),
    ('EVP_EncryptUpdate', 'plaintext', 'ciphertext', 61),
    ('EVP_DecryptUpdate', 'ciphertext', 'plaintext', 59),
    ('EVP_DecryptUpdate', 'ciphertext', 'plaintext', 61),
  ]) {
    test(
        'The AES-256-GCM FFI update step refuses a reported length that differs from its input length ($operation, $reported)',
        () {
      expect(
          () => aesGcmUpdate((Pointer<Int32> outLen) {
                outLen.value = reported;
                return 1;
              }, 60,
                  operation: operation, inputName: input, outputName: output),
          throwsA(isA<StateError>().having(
              (StateError e) => e.message,
              'message',
              '$operation produced a $reported-byte $output, expected 60')),
          reason: 'the update step accepted a reported $reported-byte $output '
              'for a 60-byte $input');
    });
  }
}

/// Bytes that fail the test if anything concatenates them (`+`), iterates
/// them or copies them whole into a new list (`toList`), so a join must copy
/// them straight into its output.
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
