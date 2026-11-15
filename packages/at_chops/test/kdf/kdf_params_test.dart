import 'package:at_chops/at_chops.dart';
import 'package:test/test.dart';

void main() {
  group('KdfParams JSON', () {
    test('Argon2idParams round-trips', () {
      const params =
          Argon2idParams(memoryKiB: 1024, iterations: 2, parallelism: 4);
      expect(params.toJson(), {'alg': 'argon2id', 'm': 1024, 't': 2, 'p': 4});
      expect(KdfParams.fromJson(params.toJson()), params);
    });

    test('Pbkdf2Sha256Params round-trips', () {
      const params = Pbkdf2Sha256Params(iterations: 10000);
      expect(params.toJson(), {'alg': 'pbkdf2-sha256', 'iterations': 10000});
      expect(KdfParams.fromJson(params.toJson()), params);
    });

    for (final json in <Map<String, Object?>>[
      {'alg': 'scrypt', 'N': 1024},
      {'alg': 'argon2id', 'm': 1024, 't': 2},
      {'alg': 'pbkdf2-sha256'},
      {'alg': 'pbkdf2-sha256', 'iterations': '10000'},
      {'m': 1024, 't': 2, 'p': 4},
    ]) {
      test('$json throws UnsupportedKdfException', () {
        expect(() => KdfParams.fromJson(json),
            throwsA(isA<UnsupportedKdfException>()));
      });
    }
  });
}
