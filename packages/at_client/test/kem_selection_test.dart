import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:test/test.dart';

Uint8List _bytes(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  group('an algorithm id resolves to the KEM that realises it', () {
    test('each id names a distinct implementation', () {
      expect(SecretSharingAlgos.kemFor(SecretSharingAlgos.xWing),
          same(XWingPureDartAlgo.instance));
      expect(SecretSharingAlgos.kemFor(SecretSharingAlgos.mlKem1024),
          same(MlKem1024PureDartAlgo.instance));
    });

    test('an id this build does not implement is null, not a guess', () {
      // Falling back to a default here would seal under a KEM the recipient
      // never advertised, producing a record only they could discover was
      // broken.
      expect(SecretSharingAlgos.kemFor('kyber-1024-v9'), isNull);
      expect(SecretSharingAlgos.kemForSuite('x-wing-hpke-v9'), isNull);
    });

    test('each live suite maps to its own KEM, and the retired one to none',
        () {
      // 'x-wing-hpke-v1' is spelled out rather than named: the constant is
      // gone, and a holder can still put the string in its advertisement.
      expect(SecretSharingAlgos.kemForSuite('x-wing-hpke-v1'), isNull,
          reason: 'a retired suite must resolve to no KEM, so an envelope '
              'claiming it is refused rather than decapsulated');
      expect(SecretSharingAlgos.kemForSuite(SecretSharingAlgos.xWingRfc9180),
          same(XWingPureDartAlgo.instance));
      expect(SecretSharingAlgos.kemForSuite(SecretSharingAlgos.mlKem1024Rfc9180),
          same(MlKem1024PureDartAlgo.instance));
    });
  });

  group('the id → KEM → suite → version chain seals and opens', () {
    // This is the whole contract the wiring rests on: given only a recipient's
    // advertised algorithm id, a sender can pick a KEM and an envelope version
    // that the recipient's key actually opens.
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
            reason: 'the version byte on the wire is the one the suite maps to');

        expect(await pqOpen(kem, pair.secretKey, sealed, info: info),
            plaintext);
      });
    }

    test('the two KEMs are not interchangeable', () async {
      // The arms must genuinely differ or the round-trips above prove nothing:
      // an envelope sealed under one KEM must not open under the other, which
      // is exactly why the advertised id has to be followed rather than
      // assumed.
      final xWing = SecretSharingAlgos.kemFor(SecretSharingAlgos.xWing)!;
      final mlKem = SecretSharingAlgos.kemFor(SecretSharingAlgos.mlKem1024)!;

      final xWingPair = await xWing.keyPairFromSeed(xWing.newSeed());
      final mlKemPair = await mlKem.keyPairFromSeed(mlKem.newSeed());

      expect(xWingPair.publicKey.length, isNot(mlKemPair.publicKey.length),
          reason: '1216 bytes against 1568 — they are not even the same shape');

      // The subject is the KEM mismatch, so the binding is held constant at
      // empty on both ends — a differing info would give the refusal below a
      // second possible cause.
      final sealed = await pqSeal(
          mlKem, mlKemPair.publicKey, _bytes('secret'),
          info: Uint8List(0),
          version: SecretSharingAlgos.sealVersionFor(
              SecretSharingAlgos.mlKem1024Rfc9180)!);
      expect(() => pqOpen(xWing, xWingPair.secretKey, sealed,
              info: Uint8List(0)),
          throwsA(isA<PqOpenException>()));
    });
  });

  group('the deployment knob', () {
    test('defaults to the hybrid', () {
      expect(AtClientPreference().keyEstablishmentAlgo,
          SecretSharingAlgos.xWing);
    });

    test('takes the no-hybrid option, and it resolves', () {
      final preference = AtClientPreference()
        ..keyEstablishmentAlgo = SecretSharingAlgos.mlKem1024;

      expect(SecretSharingAlgos.kemFor(preference.keyEstablishmentAlgo),
          same(MlKem1024PureDartAlgo.instance));
    });

    test('every advertised option resolves to an implementation', () {
      // Guards the case where an id is added to `keyAlgos` and the mapping is
      // not swept — the id would then be advertised and unusable.
      for (final keyAlgo in SecretSharingAlgos.keyAlgos) {
        expect(SecretSharingAlgos.kemFor(keyAlgo), isNotNull,
            reason: '$keyAlgo is offered but has no implementation');
        expect(SecretSharingAlgos.suiteForKeyAlgo(keyAlgo), isNotNull,
            reason: '$keyAlgo is offered but maps to no sealing suite');
      }
    });
  });
}
