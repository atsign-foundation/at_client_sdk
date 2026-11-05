import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Decodes a hex string to bytes.
Uint8List acvpHex(String s) {
  final out = Uint8List(s.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(s.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

/// The cases of group [name] in `test/vectors/ml_dsa_65_acvp.json`.
List<Map<String, dynamic>> mlDsa65AcvpGroup(String name) {
  final vectors =
      jsonDecode(File('test/vectors/ml_dsa_65_acvp.json').readAsStringSync())
          as Map;
  return (vectors[name] as List).cast<Map<String, dynamic>>();
}

/// The ML-DSA-65 keyGen cases, decoded to bytes.
List<({int tcId, Uint8List seed, Uint8List pk, Uint8List sk})>
    mlDsa65KeyGenVectors() => [
          for (final c in mlDsa65AcvpGroup('keyGen'))
            (
              tcId: c['tcId'] as int,
              seed: acvpHex(c['seed'] as String),
              pk: acvpHex(c['pk'] as String),
              sk: acvpHex(c['sk'] as String),
            )
        ];
