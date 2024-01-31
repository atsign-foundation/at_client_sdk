import 'package:at_client/at_client.dart';
import 'package:at_client/src/client/verb_builder_manager.dart';
import 'package:at_client/src/decryption_service/shared_key_decryption.dart';
import 'package:at_client/src/transformer/request_transformer/get_request_transformer.dart';
import 'package:at_client/src/decryption_service/decryption_manager.dart';
import 'package:at_client/src/decryption_service/local_key_decryption.dart';
import 'package:at_client/src/decryption_service/self_key_decryption.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:at_chops/at_chops.dart';

class MockRemoteSecondary extends Mock implements RemoteSecondary {}

class MockAtLookup extends Mock implements AtLookupImpl {}

class MockLocalSecondary extends Mock implements LocalSecondary {}

class MockAtChops extends Mock implements AtChops {}

class MockAtClientImpl extends Mock implements AtClientImpl {}

class MockGetRequestTransformer extends Mock implements GetRequestTransformer {}

class MockSecondaryManager extends Mock implements SecondaryManager {}

class FakeLocalLookUpVerbBuilder extends Fake implements LLookupVerbBuilder {}

void main() {
  AtLookupImpl mockAtLookup = MockAtLookup();
  AtClientImpl mockAtClientImpl = MockAtClientImpl();
  AtChops mockAtChops = MockAtChops();
  LocalSecondary mockLocalSecondary = MockLocalSecondary();
  var atClientPreferenceWithAtChops = AtClientPreference();
  var lookupVerbBuilder = LookupVerbBuilder()
    ..atKey = (AtKey()
      ..key = 'phone.wavi'
      ..sharedBy = '@alice');

  setUp(() {
    reset(mockAtLookup);
    registerFallbackValue(FakeLocalLookUpVerbBuilder());
    when(() => mockAtLookup.executeVerb(lookupVerbBuilder)).thenAnswer(
        (_) async =>
            throw AtExceptionUtils.get('AT0015', 'Connection timeout'));
    when(() => mockAtClientImpl.getLocalSecondary())
        .thenAnswer((_) => mockLocalSecondary);
    when(() => mockAtClientImpl.getCurrentAtSign()).thenAnswer((_) => '@xyz');
    when(() => mockLocalSecondary.getEncryptionPublicKey('@xyz'))
        .thenAnswer((_) => Future.value('dummy_encryption_public_key'));
    when(() => mockLocalSecondary.executeVerb(any<LLookupVerbBuilder>()))
        .thenAnswer((_) async => 'dummy_shared_key');
    when(() => mockAtClientImpl.atChops).thenAnswer((_) => mockAtChops);
  });

  group('A group of positive test mock test to verify decryption service', () {
    test('A test to verify decryption is successful when all keys are found',
        () async {
      var encryptionPrivateKey =
          'MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQCrGPCsZtFf1xhALzrtnfjRlr9p6RdKMNPd2Z5RkOvUsvZuK56aR2Sc7Yl6HqPFi5rr1Xd4SwNXTfZIgVxpU4QoTyNjyFUWrWHoo2NQ0lUX75HAWYIzQf706HfkGmmDBOGoUEVJPLvQv9vPMpIofZYj9WTiWo9zBTRT8EbPNTF1RJHWQNfgs3xYkX16FfutBvS/B5TYZWDXpwVFwuGh0FF2gL3/wZvp6Qq5PXnV/iiF3mrF46kXXE04WAeizsF1u2nP8OuwdLkSk0I1zka81Xrpey/yRcbOEwK9zG5c6XsgqwCILEhLIBvYX/LRacllkxBci5ivZaSBsx41Jsc+Hw69AgMBAAECggEAOO8jpzrPkUTSHQmaYlee5J91MpkN1vJIjhpMRHglAbJLrn11WYFISbABf1GSzbmW48M07iKIChU3Twk85w+TepZbAGk5Z0Jqwi8cbViQWFav+YHPgZ8EaBqzSoQ/eAm3zXpok+ZR2TT+wAPj/vVLcMvHtkrMUUn6D7R0256nxo1u+fdJ5vsBefhSKR23zNfp+ynU54s20Gc4ejqDujbIow+aiJZv9y/asPG5UdSWN6ykhoPlOCv+VqAlGT7OWFKAMTUfIZb1UsqCIYKN+BNbwFBkFcuzr8AM5Xxd1DoNcBVdLOY6j+6k2kd4U0XxvLAhE0FZDVt5J82jGtmDJQyRQQKBgQDjFixG3XnXArYnM8667+LrdIK2UGbxu94pMjRR16g7v+miShASdcxzmBr/oDAHJrSwYg4t6QIyarj0nIfUqUNefQS28qjDBuQRMHwAcYcZZ5QwynJZsyHu5KP/Hqm2V4C7mU84jpKygiDQl9GSXIsIldQ+5ADrAvpFVkyNOwGFpwKBgQDA4dCHpFFmW2BcFIHXn3fpg2JPNSnXBmVl64QRVKUj30As5KMpgULiP5qP9KfogYArm+S+p6uK5s6kqdLDNOMwqCGLD21n8EOzOjtd1bbzxuC/OUu1SCmmqMd64Y+StNj5lxx1FmkbGT96kAM20QnvUdz1U1KeCODprL5z4L9c+wKBgQCztaBklHEPjr3IWF+J4L2byCCJVyegtiQiRfDRs/EXF9E09ZeyhDbAY+c51PMtNZxY2cCO5I8whvTH3/g+e5Us+ZL5lR+o95MVZ2E6mJ1ppWbJFe1Yv0JjY93Ez+dOvgDKdZEUGQBO9Fwzt3HKeiItMSU+gAGZ+klFBf6e5ctWkQKBgFckbpspwOD2vaU8WqE5Weq1QjA4+6s7J4qRijxuOqHnVk4yCglRbg9b3w/U4BtqjqalKwZ8KEN8HbZFR4SMG2y7OVRjZvGDmoKZ94JgcOTYYGfkkfDYJoE2VdGNoNkOPc0d2WyI8HmewZA1Ck60yMFIAgUQXQ4rQrowImemDa8LAoGAYc8Tp8LUNj4fYzTA0zE7YwBga0eTB8F9eHYhimAhBRScG5FYQHlGgNvwfAATclJfX2ikBRHidWUYGM/4+z10ZX+98uwGEwPgUWJCy8mLJ6CJb88a0j7LQjOYd5ZT+Qi96X5Y4RRYj7/2CHaq1KvoywqsGoaVaiTK1opj33c7F64=';
      var encryptedValue = 'xTdYWFLRc2Gv2ACnMZbP4A==';
      var sharedKeyEnc =
          'T3VaG/MMd7ZFnKMCCQUqIOM4dDiLiZXeIZkXJ3p13jn4EXU6FWgygCbG/8aUrMr3riPO+Il4CwIvGrulGXsKzx9sjBxsFAhTDczzvOt0a52UJFxIjJGkC7mAuprLa23dRI/zUfvxEd6fgXVDT5k8itOO0ykOcb9syEtvzg+vZhniVODz7yu9gh0R1iQDxebM5mCPbGKNlEkdGJq6wGBvn26p2fq5CaPyIBHRU2B+DIaBEKnVmK2WomJnrCbLtYFlGGmtsMkCVfllBJSW3i6SZ1m080Yt07qtjnsWobK1FT+2i07Q+uGEaSjIr5eUyPeN4V5L1ZmsnXk92w+vhD0k0w==';
      var atKey = (AtKey.shared('phone', namespace: 'wavi', sharedBy: '@bob')
            ..sharedWith('@alice'))
          .build();
      atKey.metadata = Metadata()
        ..sharedKeyEnc = sharedKeyEnc
        ..pubKeyCS = 'd4f6d9483907286a0563b9fdeb01aa61';

      when(() => mockLocalSecondary.getEncryptionPrivateKey())
          .thenAnswer((_) => Future.value(encryptionPrivateKey));

      when(() => mockAtClientImpl.getPreferences())
          .thenAnswer((_) => atClientPreferenceWithAtChops);
      final atChopsKeys = AtChopsKeys.create(
          AtEncryptionKeyPair.create('', encryptionPrivateKey), null);
      when(() => mockAtClientImpl.atChops)
          .thenAnswer((_) => AtChopsImpl(atChopsKeys));
      var sharedKeyDecryption = SharedKeyDecryption(mockAtClientImpl);
      var result = await sharedKeyDecryption.decrypt(atKey, encryptedValue);
      expect(result, 'hello');
      when(() => mockAtClientImpl.getPreferences())
          .thenAnswer((_) => atClientPreferenceWithAtChops);

      expect(await sharedKeyDecryption.decrypt(atKey, encryptedValue), 'hello');
    });
  });

  group('A group of tests to verify exceptions in decryption service', () {
    test(
        'A test to verify exception is thrown when current atsign public key is not found',
        () {
      var atKey = (AtKey.shared('phone', namespace: 'wavi', sharedBy: '@alice')
            ..sharedWith('@bob'))
          .build();
      atKey.metadata = Metadata()
        ..pubKeyCS = 'd4f6d9483907286a0563b9fdeb01aa61';

      when(() => mockLocalSecondary.getEncryptionPublicKey('@xyz')).thenAnswer(
          (_) => throw KeyNotFoundException(
              'public:publickey@xyz is not found in keystore'));

      var sharedKeyDecryption = SharedKeyDecryption(mockAtClientImpl);
      expect(
          () => sharedKeyDecryption.decrypt(atKey, '123'),
          throwsA(predicate((dynamic e) =>
              e is AtPublicKeyNotFoundException &&
              e.message ==
                  'Failed to fetch the current atSign public key - public:publickey${mockAtClientImpl.getCurrentAtSign()!}')));
    });

    test(
        'A test to verify exception is thrown when private encryption key is not found using at_chops',
        () {
      var atKey = (AtKey.shared('phone', namespace: 'wavi', sharedBy: '@murali')
            ..sharedWith('@sitaram'))
          .build();
      atKey.metadata = Metadata()
        ..sharedKeyEnc = 'dummy_shared_key'
        ..pubKeyCS = 'd4f6d9483907286a0563b9fdeb01aa61';

      when(() => mockAtClientImpl.getPreferences())
          .thenAnswer((_) => atClientPreferenceWithAtChops);
      var sharedKeyDecryptionWithAtChops =
          SharedKeyDecryption(mockAtClientImpl);
      final atChopsKeys =
          AtChopsKeys.create(AtEncryptionKeyPair.create('', ''), null);
      when(() => mockAtClientImpl.atChops)
          .thenAnswer((_) => AtChopsImpl(atChopsKeys));
      expect(
          () async =>
              await sharedKeyDecryptionWithAtChops.decrypt(atKey, '123'),
          throwsA(predicate((dynamic e) => e is Exception)));
    });

    // The AtLookup verb throws exception is stacked by the executeVerb in remote secondary
    test(
        'Test to verify exception gets stacked in remote secondary executeVerb',
        () async {
      RemoteSecondary remoteSecondary =
          RemoteSecondary('@alice', AtClientPreference());
      remoteSecondary.atLookUp = mockAtLookup;
      try {
        await remoteSecondary.executeVerb(lookupVerbBuilder);
      } on AtException catch (e) {
        expect(e.getTraceMessage(),
            'Failed to fetchData caused by\nConnection timeout');
      }
    });
  });

  group('A group of test to validate the decryption service manager', () {
    test(
        'Test to verify the SharedKeyDecryption instance is returned for shared key',
        () {
      var currentAtSign = '@bob';
      var atKey = AtKey()
        ..key = 'phone.wavi'
        ..sharedBy = '@alice';

      var decryptionService =
          AtKeyDecryptionManager(mockAtClientImpl).get(atKey, currentAtSign);
      expect(decryptionService, isA<SharedKeyDecryption>());
    });

    test(
        'Test to verify the LocalKeyDecryption instance is returned for local key',
        () {
      var currentAtSign = '@bob';
      var atKey = AtKey()
        ..key = 'phone.wavi'
        ..sharedWith = '@alice'
        ..sharedBy = '@bob'
        ..metadata = Metadata();

      var decryptionService =
          AtKeyDecryptionManager(mockAtClientImpl).get(atKey, currentAtSign);
      expect(decryptionService, isA<LocalKeyDecryption>());
    });

    test(
        'Test to verify SelfKeyDecryption instance is returned for '
        'self key when sharedWith is populated', () {
      var currentAtSign = '@alice';
      var atKey = AtKey()
        ..key = '_phone.wavi'
        ..sharedWith = '@alice'
        ..sharedBy = '@alice'
        ..metadata = Metadata();

      var decryptionService =
          AtKeyDecryptionManager(mockAtClientImpl).get(atKey, currentAtSign);
      expect(decryptionService, isA<SelfKeyDecryption>());
    });

    test(
        'Test to verify SelfKeyDecryption instance is returned for '
        'self key when sharedWith is not populated', () {
      var currentAtSign = '@alice';
      var atKey = AtKey()
        ..key = 'phone.wavi'
        ..sharedBy = '@alice'
        ..metadata = Metadata();

      var decryptionService =
          AtKeyDecryptionManager(mockAtClientImpl).get(atKey, currentAtSign);
      expect(decryptionService, isA<SelfKeyDecryption>());
    });
  });

  group(
      'A group of tests to validate errors when empty value is passed as decrypted value',
      () {
    test(
        'Test to verify IllegalArgumentException is thrown when encrypted value is null - SharedKeyDecryption',
        () {
      expect(
          () => SharedKeyDecryption(mockAtClientImpl).decrypt(AtKey(), ''),
          throwsA(predicate((dynamic e) =>
              e is AtDecryptionException &&
              e.message == 'Decryption failed. Encrypted value is null')));
    });

    test(
        'Test to verify IllegalArgumentException is thrown when encrypted value is null - SelfKeyDecryption',
        () {
      expect(
          () => SelfKeyDecryption(mockAtClientImpl).decrypt(AtKey(), ''),
          throwsA(predicate((dynamic e) =>
              e is AtDecryptionException &&
              e.message == 'Decryption failed. Encrypted value is null')));
    });

    test(
        'Test to verify IllegalArgumentException is thrown when encrypted value is null - LocalKeyDecryption',
        () {
      expect(
          () => LocalKeyDecryption(mockAtClientImpl).decrypt(AtKey(), ''),
          throwsA(predicate((dynamic e) =>
              e is AtDecryptionException &&
              e.message == 'Decryption failed. Encrypted value is null')));
    });
  });
}
