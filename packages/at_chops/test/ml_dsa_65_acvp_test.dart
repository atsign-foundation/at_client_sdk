/// NIST ACVP conformance for ML-DSA-65 (FIPS 204).
///
/// Until this existed, `ml_dsa_65_algo_test.dart` asserted key and signature
/// LENGTHS and that a signature round-trips — which two wrong implementations
/// agreeing with each other would also satisfy. ML-DSA-65 authenticates every
/// PQ enrollment, so it was the algorithm on the critical path with the least
/// evidence behind it.
///
/// The vectors in `test/vectors/ml_dsa_65_acvp.json` are NIST's, unmodified,
/// filtered to the parameter set and interface this package implements. See
/// the `_provenance` object in that file for exactly what was excluded and
/// why — nothing was dropped for size.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:pqcrypto/pqcrypto.dart';
import 'package:test/test.dart';

Uint8List _hex(String s) {
  final out = Uint8List(s.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(s.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

String _toHex(Uint8List b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

/// NIST publishes its vectors in uppercase hex; [_toHex] emits lowercase.
/// Normalising here keeps a genuine mismatch reading as a byte difference.
String _expectHex(Object? nistHex) => (nistHex as String).toLowerCase();

void main() {
  final vectors =
      jsonDecode(File('test/vectors/ml_dsa_65_acvp.json').readAsStringSync())
          as Map;

  List<Map<String, dynamic>> vectorsFor(String name) =>
      (vectors[name] as List).cast<Map<String, dynamic>>();

  const params = DilithiumParams.mlDsa65;

  group('ML-DSA-65 ACVP keyGen', () {
    final cases = vectorsFor('keyGen');

    test('the fixture carries every published ML-DSA-65 keyGen vector', () {
      expect(cases, hasLength(25));
    });

    for (final c in cases) {
      test('tcId ${c['tcId']}: the seed derives the published keypair', () {
        final (pk, sk) =
            MlDsa.generateKeyPairSeeded(params, _hex(c['seed'] as String));
        expect(_toHex(pk), _expectHex(c['pk']));
        expect(_toHex(sk), _expectHex(c['sk']));
      });
    }
  });

  group('ML-DSA-65 ACVP sigGen (deterministic)', () {
    final cases = vectorsFor('sigGenDeterministic');

    test('the fixture carries every published deterministic vector', () {
      expect(cases, hasLength(15));
    });

    for (final c in cases) {
      // The sharpest assertion available: with rnd fixed at zero the signature
      // is a pure function of (sk, message, context), so this reproduces
      // NIST's bytes exactly rather than merely producing something verifiable.
      test('tcId ${c['tcId']}: signing reproduces the published signature', () {
        final sig = MlDsa.signDeterministic(
          _hex(c['sk'] as String),
          _hex(c['message'] as String),
          params,
          ctx: _hex(c['context'] as String),
        );
        expect(_toHex(sig), _expectHex(c['signature']));
      });
    }
  });

  group('ML-DSA-65 ACVP sigGen (hedged)', () {
    final cases = vectorsFor('sigGenHedged');

    // Hedged signing mixes in fresh randomness, and `MlDsa.sign` draws it
    // internally, so these signatures cannot be reproduced. Verifying them is
    // what they can prove.
    for (final c in cases) {
      test('tcId ${c['tcId']}: the published signature verifies', () {
        expect(
          MlDsa.verify(
            _hex(c['pk'] as String),
            _hex(c['message'] as String),
            _hex(c['signature'] as String),
            params,
            ctx: _hex(c['context'] as String),
          ),
          isTrue,
        );
      });
    }
  });

  group('ML-DSA-65 ACVP sigVer', () {
    final cases = vectorsFor('sigVer');

    test('the fixture carries both arms', () {
      // NIST publishes negative cases with a `reason` naming what was
      // corrupted. Without some of each, a verifier hard-wired to one answer
      // would pass the whole group.
      expect(cases.where((c) => c['testPassed'] == true), isNotEmpty);
      expect(cases.where((c) => c['testPassed'] == false), isNotEmpty);
    });

    for (final c in cases) {
      final expected = c['testPassed'] as bool;
      final reason = (c['reason'] as String).isEmpty ? 'valid' : c['reason'];
      test('tcId ${c['tcId']} ($reason): verify returns $expected', () {
        expect(
          MlDsa.verify(
            _hex(c['pk'] as String),
            _hex(c['message'] as String),
            _hex(c['signature'] as String),
            params,
            ctx: _hex(c['context'] as String),
          ),
          expected,
        );
      });
    }
  });

  group('at_chops uses the empty context RFC 9964 requires', () {
    // The vectors above drive the primitive. These drive the wrapper, because
    // the context string is the one parameter at_chops fixes rather than
    // passes through, and RFC 9964's ML-DSA JOSE algorithms are defined over
    // pure ML-DSA with an EMPTY context. Getting it wrong would produce
    // signatures no RFC 9964 verifier accepts, while every round-trip test in
    // this package stayed green.

    test('a signature from at_chops verifies under an empty context', () async {
      final kp = await MlDsa65PureDartAlgo().generateKeyPair();
      final msg = Uint8List.fromList(utf8.encode('envelope payload'));
      final sig =
          MlDsa65PureDartAlgo.signBytesSync(msg, secretKey: kp.secretKey);

      expect(MlDsa.verify(kp.publicKey, msg, sig, params, ctx: Uint8List(0)),
          isTrue);
    });

    test('and not under a non-empty one', () async {
      // The control. Without it the test above would pass on a build that
      // ignored the context entirely.
      final kp = await MlDsa65PureDartAlgo().generateKeyPair();
      final msg = Uint8List.fromList(utf8.encode('envelope payload'));
      final sig =
          MlDsa65PureDartAlgo.signBytesSync(msg, secretKey: kp.secretKey);

      expect(
          MlDsa.verify(kp.publicKey, msg, sig, params,
              ctx: Uint8List.fromList([1, 2, 3])),
          isFalse);
    });

    test('the published empty-context vector verifies through at_chops', () {
      // The one ACVP row whose context at_chops can express and whose
      // signature is valid, run through the public API rather than the
      // primitive. It comes from sigGen rather than sigVer because sigVer's
      // only empty-context row is a negative case.
      final c = vectorsFor('sigGenDeterministic')
          .firstWhere((c) => c['context'] == '');
      expect(
        MlDsa65PureDartAlgo.verifyBytesSync(
          _hex(c['message'] as String),
          signature: _hex(c['signature'] as String),
          publicKey: _hex(c['pk'] as String),
        ),
        isTrue,
      );
    });
  });
}
