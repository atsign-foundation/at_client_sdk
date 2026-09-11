import 'dart:typed_data';

import 'package:at_client/at_client.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';

/// What the data path says when the conveyance read comes back badly.
///
/// "The record is not here yet" is advice to wait for sync; "the record is here
/// and this client cannot open it" is advice to fix the client.
void main() {
  const owner = '@alice';
  const namespace = 'app_1.my_apps';

  late MockAtClient mockAtClient;
  late CryptoContext context;

  /// The value as it reaches a reader: the writer's ciphertext plus the
  /// `appMetadata` that cites the content key.
  late AtKey arrivedValue;
  late String ciphertext;
  late String ckKid;

  setUpAll(() {
    registerFallbackValue(AtKey());
  });

  setUp(() async {
    mockAtClient = MockAtClient();
    context = CryptoContext(atClient: mockAtClient);

    // NOTE: the provider a conveyance record is written under is deliberately
    // left unregistered.
    mockAtClient.getPreferences().crypto = CryptoConfig(
      defaultProviderId: legacyCryptoProviderId,
      providers: [SymmetricAesGcmProvider(cache: ContentKeyCache())],
    );

    final writerCache = ContentKeyCache();
    final ck = ContentKey(Uint8List.fromList(List<int>.filled(32, 7)));
    ckKid = ck.ckKid;
    writerCache.putAsCurrent(owner, namespace, ck, 'the-writers-nskey-kid');

    final valueKey = AtKey()
      ..key = 'treaty'
      ..namespace = namespace
      ..sharedBy = owner
      ..metadata = Metadata();
    ciphertext = await SymmetricAesGcmProvider(cache: writerCache)
        .encrypt(context, valueKey, 'the treaty text');

    arrivedValue = AtKey()
      ..key = valueKey.key
      ..namespace = valueKey.namespace
      ..sharedBy = valueKey.sharedBy
      ..metadata = (Metadata()..appMetadata = valueKey.metadata.appMetadata);
  });

  /// The reading client: its own empty cache, so the content key has to come
  /// from the conveyance record.
  SymmetricAesGcmProvider reader() =>
      SymmetricAesGcmProvider(cache: ContentKeyCache());

  group('a conveyance read that fails is not automatically an absent record',
      () {
    // NOTE: this guards the `on CryptoProviderNotRegistered { rethrow; }`
    // clause in `SymmetricAesGcmProvider._resolveFromConveyance` — without it
    // the broad catch swallows the refusal and blames sync instead.
    test(
        'a conveyance whose crypto provider is unregistered refuses out of the '
        'data read', () async {
      when(() => mockAtClient.get(any(),
              getRequestOptions: any(named: 'getRequestOptions')))
          .thenAnswer((invocation) async {
        final requested = invocation.positionalArguments.first as AtKey;
        requested.metadata.appMetadata =
            AppMetadata(providerId: nskeyCryptoProviderId);
        await CryptoRuntime(mockAtClient).decryptForGet(requested, 'sealed-ck');
        return AtValue();
      });

      await expectLater(
        reader().decrypt(context, arrivedValue, ciphertext),
        throwsA(isA<CryptoProviderNotRegistered>().having(
          (e) => e.message,
          'message names the provider the conveyance was written under',
          contains(nskeyCryptoProviderId),
        )),
      );
    });

    // The control: it stays green while the test above goes red.
    test(
        'a conveyance that is nowhere still reports the content key as '
        'unavailable', () async {
      // A not-found is also an AtClientException, so this pins that the
      // rethrow discriminates within the family rather than widening to all
      // of it.
      when(() => mockAtClient.get(any(),
              getRequestOptions: any(named: 'getRequestOptions')))
          .thenThrow(AtKeyNotFoundException('key not found'));

      await expectLater(
        reader().decrypt(context, arrivedValue, ciphertext),
        throwsA(isA<ContentKeyUnavailableException>()
            .having((e) => e.ckKid, 'ckKid', ckKid)),
      );
    });
  });
}
