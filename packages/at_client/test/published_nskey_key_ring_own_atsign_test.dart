import 'dart:convert';
import 'dart:typed_data';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/secret_sharing/key_package.dart' show PackageKey;
import 'package:at_client/src/secret_sharing/secret_store.dart' show Secret;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';

/// The ring compares atSigns in canonical form, so the client's own atSign is
/// recognised, and its cache shared, however a caller spells it.
void main() {
  const alice = '@alice';
  const namespace = 'app_1.my_apps';

  setUpAll(() => registerFallbackValue(AtKey()));

  late MockAtClient atClient;
  setUp(() {
    atClient = MockAtClient();
    when(() => atClient.getCurrentAtSign()).thenReturn(alice);
    when(() => atClient.get(any(),
            getRequestOptions: any(named: 'getRequestOptions')))
        .thenThrow(AtKeyNotFoundException('not served'));
  });

  Future<({String kid, Uint8List seed, PackageKey key})> generation() async {
    final kem = SecretSharingAlgos.kemFor(SecretSharingAlgos.xWing)!;
    final seed = kem.newSeed();
    final key = PackageKey.fromBytes(
        use: SecretSharingAlgos.useEnc,
        alg: SecretSharingAlgos.xWing,
        pub: (await kem.keyPairFromSeed(seed)).publicKey);
    return (kid: key.kid, seed: seed, key: key);
  }

  test(
      'an own advertisement cached under one spelling serves another, with '
      'no lookup', () async {
    final g = await generation();
    final ring = PublishedNskeyKeyRing(atClient)
      ..rememberOwn(
          alice,
          namespace,
          NskeyAdvertisement(
              v: nskeyAdvertisementVersion,
              createdAt: DateTime.utc(2026),
              keys: [g.key]));

    final served = await ring.currentPublic('@ALICE', namespace);

    expect(served?.nskeyKid, g.kid,
        reason: 'one cache entry per atSign, whatever the spelling');
    verifyNever(() => atClient.get(any(),
        getRequestOptions: any(named: 'getRequestOptions')));
  });

  test('a private filed for the own atSign is held under another spelling',
      () async {
    final g = await generation();
    final io = InMemoryAtKeysIo();
    await io.write(alice, AtKeys());
    final privates = NskeyPrivateFiling(keysIo: io, atSign: alice);
    await privates.file(Secret(
        namespace: namespace,
        name: '${NskeyPrivateFiling.secretNamePrefix}${g.kid}',
        value: base64Encode(g.seed)));
    final ring = PublishedNskeyKeyRing(atClient,
        privateFiling: privates, askOnReadMiss: false);

    expect(await ring.heldPrivateHalf('@ALICE', namespace, g.kid), isNotNull,
        reason: 'the own atSign, so the filed private is read');
    expect((await ring.heldPublic('@ALICE', namespace, g.kid))?.kid, g.kid,
        reason: 'the own atSign, so the public is re-derived from the filing');
  });
}
