@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

/// A string literal holding `HKDF` in any case: the algorithm name WebCrypto's
/// `importKey`, `deriveBits` and `deriveKey` are given to run HKDF.
final _hkdfAlgorithmName = RegExp(r'''(['"])hkdf\1''', caseSensitive: false);

/// `deriveBits` or `deriveKey`, as a name or in a string, other than at_chops'
/// `HkdfSha256.deriveKey` and `HkdfSha384.deriveKey`.
final _webCryptoDerivation =
    RegExp(r'(?<!HkdfSha(?:256|384)\s*\.\s*)\bderive(?:Bits|Key)\b');

/// The lines of [source] that ask WebCrypto for HKDF or for any derivation,
/// as `<line>: <text>`. Matches run over the whole source, so a call wrapped
/// at its dot is still found.
List<String> _webCryptoDerivations(String source) {
  final lines = source.split('\n');
  final hits = <int>{
    for (final pattern in [_hkdfAlgorithmName, _webCryptoDerivation])
      for (final match in pattern.allMatches(source))
        '\n'.allMatches(source.substring(0, match.start)).length
  };
  return [
    for (final i in hits.toList()..sort()) '${i + 1}: ${lines[i].trim()}'
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
        for (final line in _webCryptoDerivations(file.readAsStringSync()))
          '${file.path}:$line'
    ];
    expect(requests, isEmpty,
        reason: 'no at_client_wasm library source may ask WebCrypto for HKDF '
            'or call deriveBits or deriveKey');
  });

  test('the scan matches WebCrypto derivations and not at_chops HKDF', () {
    const webCryptoRequests = [
      "        'name': 'HKDF'.toJS,",
      "          .importKey('raw', jsPrf, 'HKDF'.toJS, false,",
      "              _usages(['deriveBits', 'deriveKey']))",
      '        .deriveBits(_hkdf(label, canonical), master, _hkdfBits)',
      '          .deriveKey(',
    ];
    for (final line in webCryptoRequests) {
      final matched = _webCryptoDerivations(line);
      print('positive control matched: $matched');
      expect(matched, hasLength(1),
          reason: 'the scan must catch a WebCrypto derivation: $line');
    }

    final deriver =
        File('lib/src/keys/web_crypto_passkey.dart').readAsStringSync();
    final atChopsLines = [
      ...deriver.split('\n').where((line) => line.contains('HkdfSha256')),
      '    Uint8List expand(String label) => HkdfSha256.deriveKey(prf.output,',
    ];
    final matched = _webCryptoDerivations(atChopsLines.join('\n'));
    print('negative control lines: $atChopsLines');
    print('negative control matched: $matched');
    expect(atChopsLines, hasLength(greaterThan(1)),
        reason: "the deriver must name at_chops' HkdfSha256");
    expect(matched, isEmpty,
        reason: "naming at_chops' HKDF is not a WebCrypto derivation");
  });
}
