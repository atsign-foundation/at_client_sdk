import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:at_chops/src/algorithm/encryption/aead_output.dart';
import 'package:at_chops/src/algorithm/ffi/openssl_ffi_bindings.dart'
    show aesGcmUpdate;
import 'package:cryptography/cryptography.dart';
import 'package:test/test.dart';

import 'no_concat_cipher.dart';

/// Catalogue: features/at_chops/aes_gcm_output.feature
void main() {
  for (final (String name, Cipher cipher) in [
    ('AES-256-GCM', AesGcm.with256bits()),
    ('ChaCha20-Poly1305', Chacha20.poly1305Aead()),
  ]) {
    test(
        'The pure-Dart encrypt step copies the ciphertext and tag into one buffer of exactly their length ($name)',
        () async {
      final Uint8List key =
          Uint8List.fromList(List<int>.generate(32, (int i) => i));
      final Uint8List nonce =
          Uint8List.fromList(List<int>.generate(12, (int i) => 0xa0 + i));
      final Uint8List plain =
          Uint8List.fromList(List<int>.generate(1000, (int i) => i & 0xff));
      final Uint8List aad =
          Uint8List.fromList(List<int>.generate(7, (int i) => 0x50 + i));

      final SecretBox box = await cipher.encrypt(plain,
          secretKey: SecretKey(key), nonce: nonce, aad: aad);
      final Uint8List out = await aeadEncrypt(NoConcatCipher(cipher), plain,
          key: key, nonce: nonce, aad: aad);

      expectExactLengthOutput(out, [...box.cipherText, ...box.mac.bytes]);
    });
  }

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

  for (final (String method, String update) in [
    ('encrypt', '_encryptUpdate'),
    ('decrypt', '_decryptUpdate'),
  ]) {
    test(
        "The source of AesGcm256FfiAlgo's encrypt and decrypt calls the AES-256-GCM FFI update step ($method)",
        () async {
      final Uri? library = await Isolate.resolvePackageUri(Uri.parse(
          'package:at_chops/src/algorithm/encryption/aes_gcm_ffi_algo.dart'));
      final String body = _methodBody(File.fromUri(library!).readAsStringSync(),
          'Future<Uint8List>', method);

      expect(body, contains('$update('),
          reason: 'the body read is not the one that runs $update');
      expect(RegExp(r'\baesGcmUpdate\s*\(').hasMatch(body), isTrue,
          reason: 'AesGcm256FfiAlgo.$method does not call aesGcmUpdate '
              '(a source check: it pins the call, not its arguments)');
    });
  }
}

/// The block body of the one method in [source] declared as
/// `[returnType] [name](`, with its comments and string literals blanked.
String _methodBody(String source, String returnType, String name) {
  final String code = _codeOnly(source);
  final List<RegExpMatch> headers =
      RegExp('${RegExp.escape(returnType)}\\s+${RegExp.escape(name)}\\s*\\(')
          .allMatches(code)
          .toList();
  expect(headers, hasLength(1),
      reason: 'expected one declaration of $returnType $name(');
  final int paramsEnd = _closing(code, headers.single.end - 1, '(', ')');
  final Match? open =
      RegExp(r'\s*(async\s*)?\{').matchAsPrefix(code, paramsEnd + 1);
  expect(open, isNotNull, reason: '$name has no block body');
  final int bodyStart = open!.end - 1;
  return code.substring(bodyStart, _closing(code, bodyStart, '{', '}') + 1);
}

/// The index of the [close] that matches the [open] at [start] in [code].
int _closing(String code, int start, String open, String close) {
  int depth = 0;
  for (int i = start; i < code.length; i++) {
    if (code[i] == open) depth++;
    if (code[i] == close && --depth == 0) return i;
  }
  fail('no $close matches the $open at offset $start');
}

/// [source] with every comment and string literal replaced by spaces, so
/// offsets still line up and only code is left to match.
String _codeOnly(String source) {
  final List<String> out = source.split('');
  void blank(int from, int to) {
    for (int k = from; k < to; k++) {
      if (out[k] != '\n') out[k] = ' ';
    }
  }

  late int Function(int, bool) code;

  int string(int i) {
    final bool raw = i > 0 && source[i - 1] == 'r';
    final String quote =
        source.startsWith("'''", i) || source.startsWith('"""', i)
            ? source.substring(i, i + 3)
            : source[i];
    i += quote.length;
    while (i < source.length) {
      if (source.startsWith(quote, i)) return i + quote.length;
      if (!raw && source[i] == r'\') {
        i += 2;
      } else if (!raw && source.startsWith(r'${', i)) {
        i = code(i + 2, true);
      } else {
        i++;
      }
    }
    return i;
  }

  int blockComment(int i) {
    int depth = 0;
    while (i < source.length) {
      if (source.startsWith('/*', i)) {
        depth++;
        i += 2;
      } else if (source.startsWith('*/', i)) {
        i += 2;
        if (--depth == 0) return i;
      } else {
        i++;
      }
    }
    return i;
  }

  code = (int i, bool interpolation) {
    int depth = 0;
    while (i < source.length) {
      final int from = i;
      if (source.startsWith('//', i)) {
        final int newline = source.indexOf('\n', i);
        i = newline < 0 ? source.length : newline;
        blank(from, i);
      } else if (source.startsWith('/*', i)) {
        i = blockComment(i);
        blank(from, i);
      } else if (source[i] == "'" || source[i] == '"') {
        i = string(i);
        blank(from, i);
      } else {
        if (source[i] == '{') depth++;
        if (source[i] == '}' && interpolation && depth-- == 0) return i + 1;
        i++;
      }
    }
    return i;
  };

  code(0, false);
  return out.join();
}
