@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

/// A string literal holding `HKDF` in any case: the algorithm name WebCrypto's
/// `importKey`, `deriveBits` and `deriveKey` are given to run HKDF.
final _hkdfAlgorithmName = RegExp(r'''(['"])hkdf\1''', caseSensitive: false);

/// The lines of [source] that ask WebCrypto for HKDF, as `<line>: <text>`.
List<String> _hkdfRequests(String source) {
  final lines = source.split('\n');
  return [
    for (var i = 0; i < lines.length; i++)
      if (_hkdfAlgorithmName.hasMatch(lines[i])) '${i + 1}: ${lines[i].trim()}'
  ];
}

/// Every .dart file under lib/ (tests run from the package root), by path.
List<File> _librarySources() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .toList()
  ..sort((a, b) => a.path.compareTo(b.path));

/// Catalogue: features/at_client_wasm/passkey_derivation.feature
void main() {
  test('at_client_wasm has no HKDF of its own', () {
    final sources = _librarySources();
    print('scanned ${sources.length} library sources: '
        '${sources.map((f) => f.path).join(', ')}');
    expect(sources.map((f) => f.path),
        contains('lib/src/keys/web_crypto_passkey.dart'),
        reason: 'the passkey deriver must be among the scanned sources');

    final requests = [
      for (final file in sources)
        for (final line in _hkdfRequests(file.readAsStringSync()))
          '${file.path}:$line'
    ];
    expect(requests, isEmpty,
        reason: 'no at_client_wasm library source may ask WebCrypto for HKDF');
  });

  test('the scan matches a WebCrypto HKDF request and not at_chops HKDF', () {
    const webCryptoRequests = [
      "          .importKey('raw', jsPrf, 'HKDF'.toJS, false,",
      "        'name': 'HKDF'.toJS,",
    ];
    for (final line in webCryptoRequests) {
      final matched = _hkdfRequests(line);
      print('positive control matched: $matched');
      expect(matched, hasLength(1),
          reason: 'the scan must catch a WebCrypto HKDF request: $line');
    }

    final deriver =
        File('lib/src/keys/web_crypto_passkey.dart').readAsStringSync();
    final atChopsLines = deriver
        .split('\n')
        .where((line) => line.contains('HkdfSha256'))
        .toList();
    print('negative control lines: $atChopsLines');
    expect(atChopsLines, isNotEmpty,
        reason: "the deriver must name at_chops' HkdfSha256");
    expect(_hkdfRequests(atChopsLines.join('\n')), isEmpty,
        reason: "naming at_chops' HkdfSha256 is not a WebCrypto HKDF request");
  });
}
