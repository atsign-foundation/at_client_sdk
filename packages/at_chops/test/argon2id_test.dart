import 'package:at_chops/at_chops.dart';
import 'package:test/test.dart';

void main() {
  group('Argon2idHashingAlgo salting', () {
    // Small costs: these tests are about which bytes go in as the salt, not
    // about how expensive the derivation is.
    ArgonHashParams cheap({List<int>? salt}) => ArgonHashParams()
      ..memory = 64
      ..iterations = 1
      ..parallelism = 1
      ..salt = salt;

    test('a supplied salt is what varies the derived key', () async {
      final a = await Argon2idHashingAlgo()
          .hash('correct horse', hashParams: cheap(salt: List.filled(16, 1)));
      final b = await Argon2idHashingAlgo()
          .hash('correct horse', hashParams: cheap(salt: List.filled(16, 2)));
      final aAgain = await Argon2idHashingAlgo()
          .hash('correct horse', hashParams: cheap(salt: List.filled(16, 1)));

      expect(a, isNot(b),
          reason: 'the whole point of the salt is that two derivations from '
              'one passphrase differ');
      expect(a, aAgain, reason: 'and that the same salt is reproducible');
    });

    test('with no salt the derivation is deterministic in the passphrase alone',
        () async {
      // Pins the legacy behaviour rather than endorsing it. Key files written
      // before the salt field carry no salt, and this fallback is the only
      // thing that keeps them readable — so it has to keep working, and it has
      // to keep being documented as the reason a passphrase alone decided the
      // key.
      final a = await Argon2idHashingAlgo().hash('shared', hashParams: cheap());
      final b = await Argon2idHashingAlgo().hash('shared', hashParams: cheap());
      expect(a, b);
    });

    test('the no-salt fallback salts with UTF-16 code units, not UTF-8',
        () async {
      // The other divergence in the legacy derivation: `password.codeUnits` is
      // UTF-16, while every other hashing arm encodes UTF-8. For a non-ASCII
      // passphrase the two disagree, so an implementation in another language
      // that reasonably reaches for UTF-8 derives a different key and reports
      // it as a wrong passphrase. Pinned so a port can reproduce it.
      const passphrase = 'passwörd-☃';
      final legacy =
          await Argon2idHashingAlgo().hash(passphrase, hashParams: cheap());
      final asUtf8 = await Argon2idHashingAlgo().hash(passphrase,
          hashParams: cheap(salt: [
            0x70, 0x61, 0x73, 0x73, 0x77, 0xc3, 0xb6, 0x72, //
            0x64, 0x2d, 0xe2, 0x98, 0x83
          ]));
      expect(legacy, isNot(asUtf8),
          reason: 'if these ever agree, the fallback has changed encoding and '
              'every legacy key file with a non-ASCII passphrase just became '
              'undecryptable');
    });

    test('owaspMinimum carries OWASP\'s floor', () {
      final p = ArgonHashParams.owaspMinimum(salt: List.filled(16, 0));
      expect(p.memory, 19456);
      expect(p.iterations, 2);
      expect(p.parallelism, 1);
      expect(p.hashLength, 32);
    });

    test('the pinned defaults are the legacy ones', () {
      // Changing any of these makes every key file written to date
      // undecryptable, because none of them records the cost it used.
      final p = ArgonHashParams();
      expect(p.memory, 10000);
      expect(p.iterations, 2);
      expect(p.parallelism, 2);
      expect(p.salt, isNull);
    });
  });
}
