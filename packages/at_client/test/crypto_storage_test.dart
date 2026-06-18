import 'package:at_client/src/crypto/crypto.dart';
import 'package:at_client/src/crypto/crypto_storage.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/atsign.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';

class FakeVerbBuilder extends Fake implements VerbBuilder {}

void main() {
  group('CryptoSecondaryStorage', () {
    late MockAtClientImpl mockAtClient;
    late MockLocalSecondary mockLocalSecondary;
    late MockRemoteSecondary mockRemoteSecondary;
    late CryptoSecondaryStorage storage;

    final storageKey = CryptoStorageKey(
      owner: '@alice'.toAtsign(),
      recipient: '@bob'.toAtsign(),
      namespace: 'chat',
      name: 'session',
    );

    setUpAll(() {
      registerFallbackValue(FakeVerbBuilder());
    });

    setUp(() {
      mockAtClient = MockAtClientImpl();
      mockLocalSecondary = MockLocalSecondary();
      mockRemoteSecondary = MockRemoteSecondary();
      storage = CryptoSecondaryStorage(mockAtClient);

      when(() => mockAtClient.getLocalSecondary())
          .thenReturn(mockLocalSecondary);
      when(() => mockAtClient.getRemoteSecondary())
          .thenReturn(mockRemoteSecondary);
    });

    test('reads local provider storage through the local secondary', () async {
      VerbBuilder? capturedBuilder;
      when(() => mockLocalSecondary.executeVerb(
            any(),
            sync: any(named: 'sync'),
            cameFromServer: any(named: 'cameFromServer'),
          )).thenAnswer((invocation) async {
        capturedBuilder = invocation.positionalArguments.first as VerbBuilder;
        return 'data:local-value';
      });

      final value = await storage.readLocal(storageKey);

      expect(value, 'local-value');
      expect(capturedBuilder, isA<LookupVerbBuilder>());
      final atKey = (capturedBuilder as LookupVerbBuilder).atKey;
      expect(atKey.key, 'session.chat.bob');
      expect(atKey.sharedBy, '@alice');
      expect(atKey.sharedWith, '@bob');
      verifyNever(() => mockRemoteSecondary.executeVerb(
            any(),
            sync: any(named: 'sync'),
            cameFromServer: any(named: 'cameFromServer'),
          ));
    });

    test('writes remote provider storage through the remote secondary',
        () async {
      VerbBuilder? capturedBuilder;
      bool? capturedSync;
      when(() => mockRemoteSecondary.executeVerb(
            any(),
            sync: any(named: 'sync'),
            cameFromServer: any(named: 'cameFromServer'),
          )).thenAnswer((invocation) async {
        capturedBuilder = invocation.positionalArguments.first as VerbBuilder;
        capturedSync = invocation.namedArguments[#sync] as bool?;
        return 'data:ok';
      });

      await storage.write(storageKey, 'remote-value');

      expect(capturedBuilder, isA<UpdateVerbBuilder>());
      final builder = capturedBuilder as UpdateVerbBuilder;
      expect(builder.atKey.key, 'session.chat.bob');
      expect(builder.atKey.sharedBy, '@alice');
      expect(builder.atKey.sharedWith, '@bob');
      expect(builder.value, 'remote-value');
      expect(capturedSync, false);
      verifyNever(() => mockLocalSecondary.executeVerb(
            any(),
            sync: any(named: 'sync'),
            cameFromServer: any(named: 'cameFromServer'),
          ));
    });
  });
}
