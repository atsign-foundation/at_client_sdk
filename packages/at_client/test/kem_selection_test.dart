import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:test/test.dart';

Uint8List _bytes(String s) => Uint8List.fromList(utf8.encode(s));

/// Resolving an advertised algorithm id to the KEM, suite and seal version
/// that open what was sealed under it, and the preference knob that decides
/// which ids an enrollment advertises.
void main() {
  group('an algorithm id resolves to the KEM that realises it', () {
    test('each id names a distinct implementation', () {
      expect(SecretSharingAlgos.kemFor(SecretSharingAlgos.xWing),
          same(XWingPureDartAlgo.instance));
      expect(SecretSharingAlgos.kemFor(SecretSharingAlgos.mlKem1024),
          same(MlKem1024PureDartAlgo.instance));
    });

    test('an id this build does not implement is null, not a guess', () {
      // NOTE: falling back to a default here would seal under a KEM the
      // recipient never advertised.
      expect(SecretSharingAlgos.kemFor('kyber-1024-v9'), isNull);
      expect(SecretSharingAlgos.kemForSuite('x-wing-hpke-v9'), isNull);
    });

    test('each live suite maps to its own KEM, and the retired one to none',
        () {
      // NOTE: the retired suite id is spelled out because no constant names
      // it, and a holder can still advertise the string.
      expect(SecretSharingAlgos.kemForSuite('x-wing-hpke-v1'), isNull,
          reason: 'a retired suite must resolve to no KEM, so an envelope '
              'claiming it is refused rather than decapsulated');
      expect(SecretSharingAlgos.kemForSuite(SecretSharingAlgos.xWingRfc9180),
          same(XWingPureDartAlgo.instance));
      expect(
          SecretSharingAlgos.kemForSuite(SecretSharingAlgos.mlKem1024Rfc9180),
          same(MlKem1024PureDartAlgo.instance));
    });
  });

  group('the id → KEM → suite → version chain seals and opens', () {
    for (final keyAlgo in SecretSharingAlgos.keyAlgos) {
      test('$keyAlgo round-trips end to end', () async {
        final kem = SecretSharingAlgos.kemFor(keyAlgo)!;
        final suite = SecretSharingAlgos.suiteForKeyAlgo(keyAlgo)!;
        final version = SecretSharingAlgos.sealVersionFor(suite)!;

        final pair = await kem.keyPairFromSeed(kem.newSeed());
        final info = _bytes('at_client/test/$keyAlgo');
        final plaintext = _bytes('the quick brown fox 🦊');

        final sealed = await pqSeal(kem, pair.publicKey, plaintext,
            info: info, version: version);
        expect(sealed.first, version,
            reason:
                'the version byte on the wire is the one the suite maps to');

        expect(
            await pqOpen(kem, pair.secretKey, sealed, info: info), plaintext);
      });
    }

    test('the two KEMs are not interchangeable', () async {
      final xWing = SecretSharingAlgos.kemFor(SecretSharingAlgos.xWing)!;
      final mlKem = SecretSharingAlgos.kemFor(SecretSharingAlgos.mlKem1024)!;

      final xWingPair = await xWing.keyPairFromSeed(xWing.newSeed());
      final mlKemPair = await mlKem.keyPairFromSeed(mlKem.newSeed());

      expect(xWingPair.publicKey.length, isNot(mlKemPair.publicKey.length),
          reason: '1216 bytes against 1568 — they are not even the same shape');

      // NOTE: info is held empty on both ends, so the refusal below has the
      // KEM mismatch as its only possible cause.
      final sealed = await pqSeal(mlKem, mlKemPair.publicKey, _bytes('secret'),
          info: Uint8List(0),
          version: SecretSharingAlgos.sealVersionFor(
              SecretSharingAlgos.mlKem1024Rfc9180)!);
      expect(
          () => pqOpen(xWing, xWingPair.secretKey, sealed, info: Uint8List(0)),
          throwsA(isA<PqOpenException>()));
    });
  });

  group('the deployment knob', () {
    test('defaults to the hybrid, and to exactly one algorithm', () {
      expect(AtClientPreference().keyEstablishmentAlgorithms,
          [SecretSharingAlgos.xWing],
          reason: 'a second entry costs a keypair minted, filed and carried '
              'for the life of the enrollment, and buys nothing until a '
              'deployment is actually migrating between KEMs');
    });

    test('takes the no-hybrid option, and it resolves', () {
      final preference = AtClientPreference(
          keyEstablishmentAlgorithms: const [SecretSharingAlgos.mlKem1024]);

      expect(
          SecretSharingAlgos.kemFor(
              preference.keyEstablishmentAlgorithms.first),
          same(MlKem1024PureDartAlgo.instance));
    });

    test('takes both, which is what a migration between KEMs looks like', () {
      final preference = AtClientPreference(keyEstablishmentAlgorithms: const [
        SecretSharingAlgos.mlKem1024,
        SecretSharingAlgos.xWing,
      ]);

      // NOTE: the first entry is what anything minting a single key uses; the
      // rest are advertised by the key package so peers can still reach it.
      expect(preference.keyEstablishmentAlgorithms.first,
          SecretSharingAlgos.mlKem1024);
      expect(preference.keyEstablishmentAlgorithms, hasLength(2));
    });

    test('refuses an empty list, where the sender-side list permits one', () {
      // NOTE: sealing to nothing writes to nobody, but advertising nothing
      // can receive nothing while looking healthy.
      expect(
          () => AtClientPreference(keyEstablishmentAlgorithms: const []),
          throwsA(isA<ArgumentError>().having((e) => e.message.toString(),
              'message', contains('can receive nothing'))));
      expect(
          AtClientPreference(sealsToKeyAlgorithms: const [])
              .sealsToKeyAlgorithms,
          isEmpty);
    });

    test('refuses an algorithm this build cannot mint', () {
      expect(
          () => AtClientPreference(
              keyEstablishmentAlgorithms: const ['ml-kem-768']),
          throwsA(isA<ArgumentError>().having((e) => e.message.toString(),
              'message', contains('this build mints'))));
    });

    test('every advertised option resolves to an implementation', () {
      for (final keyAlgo in SecretSharingAlgos.keyAlgos) {
        expect(SecretSharingAlgos.kemFor(keyAlgo), isNotNull,
            reason: '$keyAlgo is offered but has no implementation');
        expect(SecretSharingAlgos.suiteForKeyAlgo(keyAlgo), isNotNull,
            reason: '$keyAlgo is offered but maps to no sealing suite');
      }
    });
  });
}
