import 'dart:typed_data';

import 'package:at_client/at_client.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';

/// What the data path says when the conveyance read comes back badly.
///
/// Two answers, and a caller acts on them differently. "The record is not here
/// yet" is advice to wait for sync; "the record is here and this client cannot
/// open it" is advice to fix the client. Collapsing the second into the first
/// sends an app away to poll for a record that already arrived.
void main() {
  const owner = '@alice';
  const namespace = 'app_1.my_apps';

  late MockAtClient mockAtClient;
  late CryptoContext context;

  /// The value as it reaches a reader: the writer's ciphertext plus the
  /// `appMetadata` the writer stamped, which is what cites the content key.
  late AtKey arrivedValue;
  late String ciphertext;
  late String ckKid;

  setUpAll(() {
    registerFallbackValue(AtKey());
  });

  setUp(() async {
    mockAtClient = MockAtClient();
    context = CryptoContext(atClient: mockAtClient);

    // The client registers the data provider but not the one a conveyance
    // record is written under. Both tests get this, so the only thing that
    // varies between them is what the conveyance read does.
    mockAtClient.getPreferences().crypto = CryptoConfig(
      defaultProviderId: legacyCryptoProviderId,
      providers: [SymmetricAesGcmProvider(cache: ContentKeyCache())],
    );

    // The writer: a cache already holding the content key, so `encrypt`
    // produces a value citing it. Fixed key material — nothing here reaches
    // the AEAD, so its value carries no weight.
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
    // Mutation, stated rather than applied: delete the
    // `on CryptoProviderNotRegistered { rethrow; }` clause from
    // `SymmetricAesGcmProvider._resolveFromConveyance`'s inner `read` helper
    // and the broad catch swallows the refusal again — this test then sees a
    // ContentKeyUnavailableException blaming sync, and the control below stays
    // green, which is what makes the pair a differential.
    test(
        'a conveyance whose crypto provider is unregistered refuses out of the '
        'data read', () async {
      // The read is routed through the real crypto runtime against the real
      // config, so both the refusal and the message it carries are the ones
      // production composes rather than a string this test invented.
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

    // The control. It has to be able to stay green while the assertion above
    // goes red, or a change that made every conveyance read throw would look
    // like a pass. Nothing about it depends on the refusal clause: the record
    // is nowhere, which is the case the caller is told to wait out, and that
    // answer is unchanged.
    test(
        'a conveyance that is nowhere still reports the content key as '
        'unavailable', () async {
      // A read that finds nothing, modelled as the client refusing with a
      // not-found exception. That is another AtClientException, so it also
      // pins that the rethrow discriminates within the family rather than
      // widening to all of it.
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
