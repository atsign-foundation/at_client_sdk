import 'dart:io';

import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/crypto/legacy/legacy_decryption.dart';
import 'package:at_client/src/crypto/legacy/legacy_encryption.dart';
import 'package:at_commons/at_builders.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'test_utils/mocks.dart';

void main() {
  String currentAtSign = '@alice';
  String namespace = 'unit.test';

  MockRemoteSecondary mockRemoteSecondary = MockRemoteSecondary();

  late AtChops atChops;
  late AtClient atClient;

  setUp(() async {
    AtClientPreference atClientPreference = AtClientPreference()
      ..hiveStoragePath = 'test/unit_test_storage/hive'
      ..commitLogPath = 'test/unit_test_storage/commit';

    AtEncryptionKeyPair atEncryptionKeyPair =
        AtChopsUtil.generateAtEncryptionKeyPair();
    AtPkamKeyPair atPkamKeyPair = AtChopsUtil.generateAtPkamKeyPair();
    AtChopsKeys atChopsKeys =
        AtChopsKeys.create(atEncryptionKeyPair, atPkamKeyPair);
    atChopsKeys.selfEncryptionKey =
        AtChopsUtil.generateSymmetricKey(EncryptionKeyType.aes256);
    atChops = AtChopsImpl(atChopsKeys);

    atClient = await AtClientImpl.create(
        currentAtSign, namespace, atClientPreference,
        remoteSecondary: mockRemoteSecondary, atChops: atChops);

    // During decryption, fetches the encryption public key from local keystore.
    // So, store the encryption public key into local secondary keystore.
    await atClient.getLocalSecondary()?.putValue(
        'public:publickey$currentAtSign',
        atEncryptionKeyPair.atPublicKey.publicKey);
  });

  tearDownAll(() {
    Directory('test/unit_test_storage').deleteSync(recursive: true);
  });

  group('A group of tests related to encryption and decryption of shared keys',
      () {
    test(
        'A test to verify encryption and decryption of shared key is successful - with publicKeyHash',
        () async {
      registerFallbackValue(LLookupVerbBuilder());
      AtKey sharedKey =
          (AtKey.shared('email', namespace: namespace, sharedBy: currentAtSign)
                ..sharedWith('@bob'))
              .build();
      String value = 'alice@atsign.com';

      when(() => mockRemoteSecondary
              .executeVerb(any(that: EncryptedSharedKeyMatcher())))
          .thenAnswer((_) => Future.value('data:null'));

      // Returns encryption public key of sharedWith atSign.
      // For unit test, reusing the current AtSign encryptionPublicKey.
      when(() => mockRemoteSecondary
              .executeVerb(any(that: EncryptionPublicKeyMatcher())))
          .thenAnswer((_) => Future.value(
              atChops.atChopsKeys.atEncryptionKeyPair?.atPublicKey.publicKey));

      // Encryption
      SharedKeyEncryption sharedKeyEncryption = SharedKeyEncryption(atClient);
      String encryptedValue =
          await sharedKeyEncryption.encrypt(sharedKey, value);
      expect(sharedKey.metadata.pubKeyHash?.hash.isNotEmpty, true);
      expect(sharedKey.metadata.pubKeyHash?.hashingAlgo, 'sha512');
      expect(sharedKey.metadata.sharedKeyEnc?.isNotEmpty, true);
      expect(sharedKey.metadata.pubKeyCS?.isNotEmpty, true);

      // Explicitly setting pubKeyCS to null, so that pubKeyHash will only be used
      // during decryption.
      sharedKey.metadata.pubKeyCS = null;
      expect(sharedKey.metadata.pubKeyCS, null);

      // Decryption
      SharedWithMeDecryption sharedKeyDecryption =
          SharedWithMeDecryption(atClient);
      String decryptedValue =
          await sharedKeyDecryption.decrypt(sharedKey, encryptedValue);
      expect(decryptedValue, value);
    });

    test('A test to verify exception is thrown when publicKeyHash mismatch',
        () async {
      registerFallbackValue(LLookupVerbBuilder());
      AtKey sharedKey =
          (AtKey.shared('email', namespace: namespace, sharedBy: currentAtSign)
                ..sharedWith('@bob'))
              .build();
      String value = 'alice@atsign.com';

      when(() => mockRemoteSecondary
              .executeVerb(any(that: EncryptedSharedKeyMatcher())))
          .thenAnswer((_) => Future.value('data:null'));

      // Returns encryption public key of sharedWith atSign.
      // For unit test, reusing the current AtSign encryptionPublicKey.
      when(() => mockRemoteSecondary
              .executeVerb(any(that: EncryptionPublicKeyMatcher())))
          .thenAnswer((_) => Future.value(
              atChops.atChopsKeys.atEncryptionKeyPair?.atPublicKey.publicKey));

      // Encryption
      SharedKeyEncryption sharedKeyEncryption = SharedKeyEncryption(atClient);
      String encryptedValue =
          await sharedKeyEncryption.encrypt(sharedKey, value);
      expect(sharedKey.metadata.pubKeyHash?.hash.isNotEmpty, true);
      expect(sharedKey.metadata.pubKeyHash?.hashingAlgo, 'sha512');
      expect(sharedKey.metadata.sharedKeyEnc?.isNotEmpty, true);
      expect(sharedKey.metadata.pubKeyCS?.isNotEmpty, true);

      // Explicitly setting pubKeyCS to null, so that pubKeyHash will only be used
      // during decryption.
      sharedKey.metadata.pubKeyCS = null;
      expect(sharedKey.metadata.pubKeyCS, null);
      // Explicitly changing the publicKeyHash value to mimic change in publicKeyHash
      // value.
      sharedKey.metadata.pubKeyHash =
          PublicKeyHash('dummy_hash_value', HashingAlgoType.sha512.name);

      // Decryption
      SharedWithMeDecryption sharedKeyDecryption =
          SharedWithMeDecryption(atClient);
      expect(
          () async =>
              await sharedKeyDecryption.decrypt(sharedKey, encryptedValue),
          throwsA(predicate((dynamic e) =>
              e is AtPublicKeyChangeException &&
              e.message ==
                  'Public key has changed. Cannot decrypt shared key ${sharedKey.toString()}')));
    });
  });
}

class EncryptedSharedKeyMatcher extends Matcher {
  @override
  Description describe(Description description) {
    return description;
  }

  @override
  bool matches(item, Map matchState) {
    return item.atKey.key.startsWith(AtConstants.atEncryptionSharedKey);
  }
}

class EncryptionPublicKeyMatcher extends Matcher {
  @override
  Description describe(Description description) {
    // TODO: implement describe
    throw UnimplementedError();
  }

  @override
  bool matches(item, Map matchState) {
    return item.atKey.key.startsWith('publickey');
  }
}
