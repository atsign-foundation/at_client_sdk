import 'dart:convert' show base64Encode;

import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/secret_sharing/key_package.dart' show PackageKey;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart' hide MockAtClient;
import 'test_utils/mocks.dart' as mocks show MockAtClient;

/// A verifier that accepts whatever is served as [advertisement]: an entry
/// whose kid matches a generation's while its public half is another key's
/// passes the real verifier only by a kid collision, which this stands in for.
class _Accepting implements AdvertisedKeyVerifier {
  final NskeyAdvertisement advertisement;

  _Accepting(this.advertisement);

  @override
  Future<NskeyAdvertisement> verify(String owner, String payload) async =>
      advertisement;
}

/// What a client seals a content key to when the key is its own atSign's.
void main() {
  const alice = '@alice';
  const namespace = 'app_1.my_apps';

  setUpAll(() {
    registerFallbackValue(AtKey());
    registerFallbackValue(FakeUpdateVerbBuilder());
  });

  group(
      'Given this enrollment holds the private of its own generation G, and '
      'the atServer serves G\'s kid with a public half that is not G\'s', () {
    test(
        'when it writes in that namespace, then the content key is sealed to '
        'the public half its private derives, and opens under that private',
        () async {
      final g = await XWingKeyPair.generate();
      final gKid = nskeyKidOf(g.publicKeyBytes);
      final io = InMemoryAtKeysIo();
      await io.write(alice, AtKeys());
      final filing = NskeyPrivateFiling(keysIo: io, atSign: alice);
      await filing.store(
          namespace: namespace,
          nskeyKid: gKid,
          seed: NskeySeed(g.privateKeyBytes));

      final other = await XWingKeyPair.generate();
      final served = NskeyAdvertisement(
        v: nskeyAdvertisementVersion,
        createdAt: DateTime.utc(2026),
        keys: [
          PackageKey(
              use: SecretSharingAlgos.useEnc,
              alg: SecretSharingAlgos.xWing,
              pub: base64Encode(other.publicKeyBytes),
              kid: gKid),
        ],
      );

      final atClient = mocks.MockAtClient();
      when(() => atClient.getCurrentAtSign()).thenReturn(alice);
      when(() => atClient.get(any()))
          .thenAnswer((_) async => AtValue()..value = 'served');
      final context = CryptoContext(atClient: atClient);
      final ring = PublishedNskeyKeyRing(atClient,
          verifier: _Accepting(served), privateFiling: filing);
      final cache = ContentKeyCache();
      final provider = NskeyProvider(keyRing: ring, cache: cache);
      final conveyed = <AtKey, String>{};
      when(() => atClient.put(any(), any(),
              putRequestOptions: any(named: 'putRequestOptions')))
          .thenAnswer((inv) async {
        final key = inv.positionalArguments[0] as AtKey;
        conveyed[key] = await provider.encrypt(
            context, key, inv.positionalArguments[1] as String);
        return true;
      });
      expect(
          (await ring.currentPublic(alice, namespace))!.keys.single.kid, gKid,
          reason: 'the control: the ring is served G\'s kid with the other '
              'public half');

      await CkManager(cache: cache, keyRing: ring, pointer: null).ensureCurrent(
          context,
          AtKey()
            ..key = 'treaty'
            ..namespace = namespace
            ..sharedBy = alice
            ..metadata = Metadata());

      final MapEntry(key: record, value: envelope) = conveyed.entries.single;
      expect(record.metadata.appMetadata!.additional!['nskeyKid'], gKid);
      final String opened;
      try {
        opened = await provider.decrypt(context, record, envelope);
      } on AtDecryptionException catch (e) {
        fail('G\'s private does not open the content key, so it was sealed '
            'to a public half G\'s private does not derive: $e');
      }
      expect(opened, cache.current(alice, namespace)!.toBase64());
    });
  });
}
