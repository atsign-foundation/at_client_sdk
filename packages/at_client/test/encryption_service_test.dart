import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/encryption_service/encryption_manager.dart';
import 'package:at_client/src/encryption_service/self_key_encryption.dart';
import 'package:at_client/src/encryption_service/shared_key_encryption.dart';
import 'package:at_client/src/transformer/request_transformer/put_request_transformer.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockAtClientManager extends Mock implements AtClientManager {}

class MockLocalSecondary extends Mock implements LocalSecondary {}

class MockRemoteSecondary extends Mock implements RemoteSecondary {}

class MockAtClient extends Mock implements AtClient {
  @override
  AtClientPreference? getPreferences() {
    return AtClientPreference()..namespace = 'wavi';
  }
}

class FakeLocalLookUpVerbBuilder extends Fake implements LLookupVerbBuilder {}

void main() {
  LocalSecondary mockLocalSecondary = MockLocalSecondary();

  RemoteSecondary mockRemoteSecondary = MockRemoteSecondary();

  AtClient mockAtClient = MockAtClient();

  AtClientManager mockAtClientManager = MockAtClientManager();

  group('A group of test to validate self key encryption exceptions', () {
    test(
        'A test to verify SelfKeyNotFoundException is thrown when self key is not found',
        () {
      when(() => mockLocalSecondary.getEncryptionSelfKey())
          .thenAnswer((_) => Future.value(''));

      var selfKeyEncryption =
          SelfKeyEncryption(localSecondary: mockLocalSecondary);

      expect(
          () => selfKeyEncryption.encrypt(
              AtKey.self('phone', namespace: 'wavi').build(), 'self_key_value'),
          throwsA(predicate((dynamic e) =>
              e is SelfKeyNotFoundException &&
              e.message ==
                  'Self encryption key is not set for current atSign')));
    });
  });

  group('A group of tests related positive scenario of encryption', () {
    test(
        'A test to verify value gets encrypted when self encryption key is available',
        () async {
      var selfEncryptionKey = 'REqkIcl9HPekt0T7+rZhkrBvpysaPOeC2QL1PVuWlus=';
      var value = 'self_key_value';
      when(() => mockLocalSecondary.getEncryptionSelfKey())
          .thenAnswer((_) => Future.value(selfEncryptionKey));
      var selfKeyEncryption =
          SelfKeyEncryption(localSecondary: mockLocalSecondary);
      var encryptedData = await selfKeyEncryption.encrypt(
          AtKey.self('phone', namespace: 'wavi').build(), value);
      var response =
          EncryptionUtil.decryptValue(encryptedData, selfEncryptionKey);
      expect(response, value);
    });
  });

  group('A group of test to sign the public data', () {
    test('A test to verify the sign the public data', () async {
      String encryptionPrivateKey =
          'MIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQCTauOYbRGwtdJUdIhUyRCXZggjPw2T2y8l6oo+DRb7qaeWqTruvcqmCj9lL+yCauu7VHYdzN9Gn6wQogMutl7LaNcBaDrfmyclpRGFJBuvJHazM4DAA1WZntQYkFVErihAdB+tzui+MzE7Io5av8OsfPH/mKBz7AQi8pAEOW1IoRIOKAcdX0wzuL8lXbn6dYZPejyQhT3344xElWmr6jzuxZC4sVnjIBOGiUY3Y3Nj6g4byJ1LYbyOuaYTll3lD4id0YgAoNS4M9SG8Hnyu7BH9QLLJKJTLmko2vLg/FywbHBRJhhfiwaVi4gp+G4UNHAdEhswciJHmqrQY9xoEaj5AgMBAAECggEAerzDE/SzhuJLZV/E5nqlYrhjzBzCTDlwruvw/6rcWNovG2R5Ga9RWx8rGy9khk1JSaYP1c3ulBl7JDoP1kOm90qpwJUsd2HxnQkrZiPjHNaKMbeO2c+s5IN16aG6LL2n68oDWi3sX/e1ZJvn1CzXWPSKdBl6dimqZAJ639mEYLPfEbfo2jqZpJktmpdaVvI8cgi+TSnOdLdSF+uAZzEOuG1SK7hg05SjOb4WuWT7ZmE/jipL/u7LLI77bOHkSWU8Eg2hxkAjy0x+TkYc/Gimf2SqDVsdutA3egpAX/sVHNJT8pE0u9WtFiiKlTx84ebtBmAV8K4/Kx5dBCO5G7vdtQKBgQDFa9LH9WSJJGiPJ/ngGZ4fM4FF1GbGpfvaHl2DB32LFTbNECjs/9+QQWkijJPSSUhdbNBIzm0qR8XM65vtGEUn8bIxX8OtFuRDVlTYPBjFJN0eLtPQyfguBsimQdnRdghJBdBENuwVJJHh9Hac0uiKRd+yN6i3p2XfeGcmjOBXswKBgQC/KMW7J+gzzwUJHtxJP1CEFDYtzRtirc0vK9rdLQxLtwlLGfhEXuv5jKrFUNrNFPYHEaVDeaARzdKeC/Lo5A3Sl/y7y4aF8vQei7aR56DayCKw7C5PnXYVQGF+ENvCrd6WgqiUJUTkVWdy/viTnnbWDnWZA/O4yq1g5t4x2FXmowKBgCo337CRQrmtRoruspoBAHaNriR/wqbSkiRYAAloTamzlK+PuCDOq0GPK2uPAoGi2E3aWkRnmKLFDIDBFexDF27uWfwDDbZzQcdArA4989IdCwhMXVG2D1PQcZJUXL9VbXooOxyLXjs7QdM/UypAVChVvvu+uV7k9n0uo2h0EfnPAoGBAIPiPmE8TDCKUIAVYYfLfeJSC3sX+h/fpyM3T32u2b/XHTtKRIXvM0DtcthFS1+YaZFA9FMUM4J1DS1rMwDIblzv7TcnWL1LfG8ilygctVacI4sKt3zINzK8Q0b1nJi42kvfAy2KdPhPj9q/3IIEHxrZyPpzxo+kjW/AeGXNSp6fAoGBAIs0AWG/LR1VsSw4D9/Zareo0lUr72A4awoPVRqzD70RvwT1+hC3jOxjt6tSi9fY2oSYUPx++mBd+G+CYIqBESRBLhvJLoSTKGZuQyWnJfslkZDg6ojWCXxKAv90J3QRikh/1XRtTqVqIOBBVvF72faC3Dn/jPOB/N0ggvUL1URJ';
      var putRequestTransformer = PutRequestTransformer(mockAtClient);
      var atKey = (AtKey.public('location', namespace: 'wavi')
            ..sharedBy('@alice'))
          .build();
      var value = '+91-8087656456';
      var updateVerbBuilder = await putRequestTransformer.transform(
          Tuple()
            ..one = atKey
            ..two = value,
          encryptionPrivateKey: encryptionPrivateKey);
      assert(updateVerbBuilder.dataSignature != null);
    });
  });
  group('A group of test to validate the encryption service manager', () {
    test('Test to verify the encryption of shared key', () async {
      var currentAtSign = '@sitaram';
      var atKey = AtKey()
        ..key = 'phone.wavi'
        ..sharedWith = '@bob'
        ..sharedBy = '@alice';

      when(() => mockAtClientManager.atClient).thenAnswer((_) => mockAtClient);
      when(() => mockAtClient.getCurrentAtSign()).thenAnswer((_) => '@sitaram');

      var encryptionService = AtKeyEncryptionManager(mockAtClient)
          .get(atKey, currentAtSign);
      expect(encryptionService, isA<SharedKeyEncryption>());
    });

    test('Test to verify the encryption of self key', () async {
      var currentAtSign = '@alice';
      var atKey = AtKey()
        ..key = 'phone.wavi'
        ..sharedWith = '@alice'
        ..sharedBy = '@alice'
        ..metadata = Metadata();

      var encryptionService = AtKeyEncryptionManager(mockAtClient)
          .get(atKey, currentAtSign);
      expect(encryptionService, isA<SelfKeyEncryption>());
    });
  });

  group(
      'A group of test to validate the incorrect data type sent for encryption value',
      () {
    test('Throws error when encrypted value is of type Integer', () {
      var currentAtSign = '@alice';
      var atKey = AtKey()
        ..key = 'phone.wavi'
        ..sharedWith = '@bob'
        ..metadata = (Metadata()..isPublic = false);
      var value = 918078908676;

      var encryptionService = AtKeyEncryptionManager(mockAtClient)
          .get(atKey, currentAtSign);

      expect(
          () => encryptionService.encrypt(atKey, value),
          throwsA(predicate((dynamic e) =>
              e is AtClientException &&
              e.message ==
                  'Invalid value type found: ${value.runtimeType}. Valid value type is String')));
    });
  });

  group(
      'A group of tests to related to fetch and decrypt the encrypted shared key',
      () {
    test(
        'A test to verify encrypted shared key is fetched from local secondary and decrypted successfully',
        () async {
      registerFallbackValue(FakeLocalLookUpVerbBuilder());
      var sharedKeyEncryption = SharedKeyEncryption(mockAtClient);

      var originalSharedKey = 'WwOn34SJaEQUHvmaY5haGtVAfHp1eBzLk8239uRGnhw=';
      var encryptedSharedKey =
          'T3VaG/MMd7ZFnKMCCQUqIOM4dDiLiZXeIZkXJ3p13jn4EXU6FWgygCbG/8aUrMr3riPO+Il4CwIvGrulGXsKzx9sjBxsFAhTDczzvOt0a52UJFxIjJGkC7mAuprLa23dRI/zUfvxEd6fgXVDT5k8itOO0ykOcb9syEtvzg+vZhniVODz7yu9gh0R1iQDxebM5mCPbGKNlEkdGJq6wGBvn26p2fq5CaPyIBHRU2B+DIaBEKnVmK2WomJnrCbLtYFlGGmtsMkCVfllBJSW3i6SZ1m080Yt07qtjnsWobK1FT+2i07Q+uGEaSjIr5eUyPeN4V5L1ZmsnXk92w+vhD0k0w==';
      var encryptionPrivateKey =
          'MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQCrGPCsZtFf1xhALzrtnfjRlr9p6RdKMNPd2Z5RkOvUsvZuK56aR2Sc7Yl6HqPFi5rr1Xd4SwNXTfZIgVxpU4QoTyNjyFUWrWHoo2NQ0lUX75HAWYIzQf706HfkGmmDBOGoUEVJPLvQv9vPMpIofZYj9WTiWo9zBTRT8EbPNTF1RJHWQNfgs3xYkX16FfutBvS/B5TYZWDXpwVFwuGh0FF2gL3/wZvp6Qq5PXnV/iiF3mrF46kXXE04WAeizsF1u2nP8OuwdLkSk0I1zka81Xrpey/yRcbOEwK9zG5c6XsgqwCILEhLIBvYX/LRacllkxBci5ivZaSBsx41Jsc+Hw69AgMBAAECggEAOO8jpzrPkUTSHQmaYlee5J91MpkN1vJIjhpMRHglAbJLrn11WYFISbABf1GSzbmW48M07iKIChU3Twk85w+TepZbAGk5Z0Jqwi8cbViQWFav+YHPgZ8EaBqzSoQ/eAm3zXpok+ZR2TT+wAPj/vVLcMvHtkrMUUn6D7R0256nxo1u+fdJ5vsBefhSKR23zNfp+ynU54s20Gc4ejqDujbIow+aiJZv9y/asPG5UdSWN6ykhoPlOCv+VqAlGT7OWFKAMTUfIZb1UsqCIYKN+BNbwFBkFcuzr8AM5Xxd1DoNcBVdLOY6j+6k2kd4U0XxvLAhE0FZDVt5J82jGtmDJQyRQQKBgQDjFixG3XnXArYnM8667+LrdIK2UGbxu94pMjRR16g7v+miShASdcxzmBr/oDAHJrSwYg4t6QIyarj0nIfUqUNefQS28qjDBuQRMHwAcYcZZ5QwynJZsyHu5KP/Hqm2V4C7mU84jpKygiDQl9GSXIsIldQ+5ADrAvpFVkyNOwGFpwKBgQDA4dCHpFFmW2BcFIHXn3fpg2JPNSnXBmVl64QRVKUj30As5KMpgULiP5qP9KfogYArm+S+p6uK5s6kqdLDNOMwqCGLD21n8EOzOjtd1bbzxuC/OUu1SCmmqMd64Y+StNj5lxx1FmkbGT96kAM20QnvUdz1U1KeCODprL5z4L9c+wKBgQCztaBklHEPjr3IWF+J4L2byCCJVyegtiQiRfDRs/EXF9E09ZeyhDbAY+c51PMtNZxY2cCO5I8whvTH3/g+e5Us+ZL5lR+o95MVZ2E6mJ1ppWbJFe1Yv0JjY93Ez+dOvgDKdZEUGQBO9Fwzt3HKeiItMSU+gAGZ+klFBf6e5ctWkQKBgFckbpspwOD2vaU8WqE5Weq1QjA4+6s7J4qRijxuOqHnVk4yCglRbg9b3w/U4BtqjqalKwZ8KEN8HbZFR4SMG2y7OVRjZvGDmoKZ94JgcOTYYGfkkfDYJoE2VdGNoNkOPc0d2WyI8HmewZA1Ck60yMFIAgUQXQ4rQrowImemDa8LAoGAYc8Tp8LUNj4fYzTA0zE7YwBga0eTB8F9eHYhimAhBRScG5FYQHlGgNvwfAATclJfX2ikBRHidWUYGM/4+z10ZX+98uwGEwPgUWJCy8mLJ6CJb88a0j7LQjOYd5ZT+Qi96X5Y4RRYj7/2CHaq1KvoywqsGoaVaiTK1opj33c7F64=';

      when(() => mockAtClient.getLocalSecondary())
          .thenAnswer((_) => mockLocalSecondary);

      when(() => mockLocalSecondary
              .executeVerb(any(that: EncryptedSharedKeyMatcher())))
          .thenAnswer((_) => Future.value(encryptedSharedKey));
      when(() => mockLocalSecondary.getEncryptionPrivateKey())
          .thenAnswer((_) => Future.value(encryptionPrivateKey));

      var atKey = AtKey()
        ..sharedBy = '@alice'
        ..sharedWith = '@bob'
        ..key = 'phone';
      expect(await sharedKeyEncryption.getSharedKey(atKey), originalSharedKey);
    });

    test(
        'A test to verify encrypted shared key is fetched from remote secondary and decrypted successfully',
        () async {
      registerFallbackValue(FakeLocalLookUpVerbBuilder());
      var sharedKeyEncryption = SharedKeyEncryption(mockAtClient);

      var originalSharedKey = 'WwOn34SJaEQUHvmaY5haGtVAfHp1eBzLk8239uRGnhw=';
      var encryptedSharedKey =
          'T3VaG/MMd7ZFnKMCCQUqIOM4dDiLiZXeIZkXJ3p13jn4EXU6FWgygCbG/8aUrMr3riPO+Il4CwIvGrulGXsKzx9sjBxsFAhTDczzvOt0a52UJFxIjJGkC7mAuprLa23dRI/zUfvxEd6fgXVDT5k8itOO0ykOcb9syEtvzg+vZhniVODz7yu9gh0R1iQDxebM5mCPbGKNlEkdGJq6wGBvn26p2fq5CaPyIBHRU2B+DIaBEKnVmK2WomJnrCbLtYFlGGmtsMkCVfllBJSW3i6SZ1m080Yt07qtjnsWobK1FT+2i07Q+uGEaSjIr5eUyPeN4V5L1ZmsnXk92w+vhD0k0w==';
      var encryptionPrivateKey =
          'MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQCrGPCsZtFf1xhALzrtnfjRlr9p6RdKMNPd2Z5RkOvUsvZuK56aR2Sc7Yl6HqPFi5rr1Xd4SwNXTfZIgVxpU4QoTyNjyFUWrWHoo2NQ0lUX75HAWYIzQf706HfkGmmDBOGoUEVJPLvQv9vPMpIofZYj9WTiWo9zBTRT8EbPNTF1RJHWQNfgs3xYkX16FfutBvS/B5TYZWDXpwVFwuGh0FF2gL3/wZvp6Qq5PXnV/iiF3mrF46kXXE04WAeizsF1u2nP8OuwdLkSk0I1zka81Xrpey/yRcbOEwK9zG5c6XsgqwCILEhLIBvYX/LRacllkxBci5ivZaSBsx41Jsc+Hw69AgMBAAECggEAOO8jpzrPkUTSHQmaYlee5J91MpkN1vJIjhpMRHglAbJLrn11WYFISbABf1GSzbmW48M07iKIChU3Twk85w+TepZbAGk5Z0Jqwi8cbViQWFav+YHPgZ8EaBqzSoQ/eAm3zXpok+ZR2TT+wAPj/vVLcMvHtkrMUUn6D7R0256nxo1u+fdJ5vsBefhSKR23zNfp+ynU54s20Gc4ejqDujbIow+aiJZv9y/asPG5UdSWN6ykhoPlOCv+VqAlGT7OWFKAMTUfIZb1UsqCIYKN+BNbwFBkFcuzr8AM5Xxd1DoNcBVdLOY6j+6k2kd4U0XxvLAhE0FZDVt5J82jGtmDJQyRQQKBgQDjFixG3XnXArYnM8667+LrdIK2UGbxu94pMjRR16g7v+miShASdcxzmBr/oDAHJrSwYg4t6QIyarj0nIfUqUNefQS28qjDBuQRMHwAcYcZZ5QwynJZsyHu5KP/Hqm2V4C7mU84jpKygiDQl9GSXIsIldQ+5ADrAvpFVkyNOwGFpwKBgQDA4dCHpFFmW2BcFIHXn3fpg2JPNSnXBmVl64QRVKUj30As5KMpgULiP5qP9KfogYArm+S+p6uK5s6kqdLDNOMwqCGLD21n8EOzOjtd1bbzxuC/OUu1SCmmqMd64Y+StNj5lxx1FmkbGT96kAM20QnvUdz1U1KeCODprL5z4L9c+wKBgQCztaBklHEPjr3IWF+J4L2byCCJVyegtiQiRfDRs/EXF9E09ZeyhDbAY+c51PMtNZxY2cCO5I8whvTH3/g+e5Us+ZL5lR+o95MVZ2E6mJ1ppWbJFe1Yv0JjY93Ez+dOvgDKdZEUGQBO9Fwzt3HKeiItMSU+gAGZ+klFBf6e5ctWkQKBgFckbpspwOD2vaU8WqE5Weq1QjA4+6s7J4qRijxuOqHnVk4yCglRbg9b3w/U4BtqjqalKwZ8KEN8HbZFR4SMG2y7OVRjZvGDmoKZ94JgcOTYYGfkkfDYJoE2VdGNoNkOPc0d2WyI8HmewZA1Ck60yMFIAgUQXQ4rQrowImemDa8LAoGAYc8Tp8LUNj4fYzTA0zE7YwBga0eTB8F9eHYhimAhBRScG5FYQHlGgNvwfAATclJfX2ikBRHidWUYGM/4+z10ZX+98uwGEwPgUWJCy8mLJ6CJb88a0j7LQjOYd5ZT+Qi96X5Y4RRYj7/2CHaq1KvoywqsGoaVaiTK1opj33c7F64=';

      when(() => mockAtClient.getLocalSecondary())
          .thenAnswer((_) => mockLocalSecondary);
      when(() => mockAtClient.getRemoteSecondary())
          .thenAnswer((_) => mockRemoteSecondary);

      when(() => mockLocalSecondary
              .executeVerb(any(that: EncryptedSharedKeyMatcher())))
          .thenAnswer((_) => Future.value('data:null'));
      when(() => mockRemoteSecondary
              .executeVerb(any(that: EncryptedSharedKeyMatcher())))
          .thenAnswer((_) => Future.value(encryptedSharedKey));
      when(() => mockLocalSecondary.getEncryptionPrivateKey())
          .thenAnswer((_) => Future.value(encryptionPrivateKey));

      var atKey = AtKey()
        ..sharedBy = '@alice'
        ..sharedWith = '@bob'
        ..key = 'phone';
      expect(await sharedKeyEncryption.getSharedKey(atKey), originalSharedKey);
    });

    test(
        'A test to verify empty string is returned when shared key is not found in local and remote secondary',
        () async {
      registerFallbackValue(FakeLocalLookUpVerbBuilder());
      var sharedKeyEncryption = SharedKeyEncryption(mockAtClient);

      when(() => mockAtClient.getLocalSecondary())
          .thenAnswer((_) => mockLocalSecondary);
      when(() => mockAtClient.getRemoteSecondary())
          .thenAnswer((_) => mockRemoteSecondary);

      when(() => mockLocalSecondary
              .executeVerb(any(that: EncryptedSharedKeyMatcher())))
          .thenAnswer((_) => Future.value('data:null'));
      when(() => mockRemoteSecondary
              .executeVerb(any(that: EncryptedSharedKeyMatcher())))
          .thenAnswer((_) => Future.value('data:null'));

      var atKey = AtKey()
        ..sharedBy = '@alice'
        ..sharedWith = '@bob'
        ..key = 'phone';
      expect(await sharedKeyEncryption.getSharedKey(atKey), '');
    });
  });

  group('A group of test related to shared_key is synced to cloud secondary',
      () {
    String storageDir = '${Directory.current.path}/test/hive';
    AtCommitLog? atCommitLog;

    test(
        'A test to verify isEncryptedSharedKeyInSync method returns false when commit id null',
        () async {
      atCommitLog = await AtCommitLogManagerImpl.getInstance().getCommitLog(
          '@alice',
          commitLogPath: storageDir,
          enableCommitId: false);
      await atCommitLog?.commit('@bob:shared_key@alice', CommitOp.UPDATE);

      var sharedKeyEncryption = SharedKeyEncryption(mockAtClient);
      sharedKeyEncryption.atCommitLog = atCommitLog;

      var atKey = AtKey()
        ..key = AT_ENCRYPTION_SHARED_KEY
        ..sharedBy = '@alice'
        ..sharedWith = '@bob';
      expect(
          await sharedKeyEncryption.isEncryptedSharedKeyInSync(atKey), false);
    });

    test(
        'A test to verify isEncryptedSharedKeyInSync method returns true when commit is not null',
        () async {
      var commitLogInstance = await AtCommitLogManagerImpl.getInstance()
          .getCommitLog('@alice', commitLogPath: storageDir);
      await commitLogInstance?.commit('@bob:shared_key@alice', CommitOp.UPDATE);

      var sharedKeyEncryption = SharedKeyEncryption(mockAtClient);
      sharedKeyEncryption.atCommitLog = commitLogInstance;

      var atKey = AtKey()
        ..key = AT_ENCRYPTION_SHARED_KEY
        ..sharedBy = '@alice'
        ..sharedWith = '@bob';
      expect(await sharedKeyEncryption.isEncryptedSharedKeyInSync(atKey), true);
    });

    test(
        'A test to verify isEncryptedSharedKeyInSync method returns false when two commit entries exist with commit id null and not null',
        () async {
      var commitLogInstance = await AtCommitLogManagerImpl.getInstance()
          .getCommitLog('@alice',
              commitLogPath: storageDir, enableCommitId: false);
      // Null commit id
      await commitLogInstance?.commitLogKeyStore.add(CommitEntry(
          '@bob:shared_key@alice', CommitOp.UPDATE, DateTime.now()));
      // Populated commit id to mock commit entry is synced from server
      await commitLogInstance?.commitLogKeyStore.add(
          CommitEntry('@bob:shared_key@alice', CommitOp.UPDATE, DateTime.now())
            ..commitId = 1);

      var sharedKeyEncryption = SharedKeyEncryption(mockAtClient);
      sharedKeyEncryption.atCommitLog = commitLogInstance;

      var atKey = AtKey()
        ..key = AT_ENCRYPTION_SHARED_KEY
        ..sharedBy = '@alice'
        ..sharedWith = '@bob';
      expect(
          await sharedKeyEncryption.isEncryptedSharedKeyInSync(atKey), false);
    });

    tearDown(() async {
      await AtCommitLogManagerImpl.getInstance().close();
      var isExists = await Directory(storageDir).exists();
      if (isExists) {
        Directory(storageDir).deleteSync(recursive: true);
      }
    });
  });

  group('A group of test related shared key encryption', () {
    String storageDir = '${Directory.current.path}/test/hive';
    SharedKeyEncryption sharedKeyEncryption;
    AtCommitLog? atCommitLog;

    var encryptionPrivateKey =
        'MIIEvAIBADANBgkqhkiG9w0BAQEFAASCBKYwggSiAgEAAoIBAQCJ+42pSjfJ5DSe7jCh7RWSH9MlTiG3PPrYdEGHDoSNhtPflSiL6BhpEpodNMLSaYpWsoV9ad2vRgXqgN0qM3LufflkgAigpAU8ukzCUWs+7sHQZBPfiz/clO1GuajF7iV0CaOe7tJA7Hyod9StALDi/56kwhGqLi84rimLeNKxv7qCfOJowePJCrs5++KXQozQXWYoeeBrj1HGEWMCbuoaw3ihvwJPBo76GkR7seYcq9AlrFivf2HcvDaPx0fSMXejTS5aL0Kogz7hBrNNGi1WyjD51hZEvMssh1OYy6TKtYsj3veMO1zd9fBZT+9yXXNCZ3cXXnZqOHAetWEPsjoNAgMBAAECggEAQ7Bp4ECOebY/si+7H9SEnniKRmS72X5KuGDfvHd8w0j/K1Gq4Gdtgi4j+Gvnnv0zZjCRl+KVY+SABnhNBuTSXvjhnVHJ6bRM9WuXOERkziymW6qcrS9MltNgSy/NAbxAF1qbL96MuljJFoQiivQp0lH/62dg7xFVDQMzUj5lbdid0CIV9r9Jp6SxXCG8OTjhU8RupXyqWiIgg3xVr/Y2ayYnO2O8cnm9V8C0zTvX5290IijTfHXkbarGg0vY7sg2Krs1uk1sQ+70yHJSppTOfa+cfYLuoj4k+emqJWWn7TZKkTlfnc6ON566XN5eiH+t2AmKttW9MxWQhaWv50I7KQKBgQDH4yh3u8f+Pbj3L3SJMN0aQ/ZHMApJ96C+iAJRgYp0aYuVpHscQPRxS7p3JwT758cKdrUTHSji/t7PrtsLDlp9rLw8WHEng7rfA/hlL9Ghoks/3gxaX90+dCXMo1odKbCxTEEBGxUC0aFIOOQGJ8Ot47fNE15IuaoPDO/On1X36wKBgQCwt6H02nLxKY0ILdu8HRVGXcqOOcBQiMIrjjhmt7llAfB5cJKuwq29apyJdRglqWSHXuK3B42reiF3I0fm3+QfihqFUfchU+2N8LcCciNR1BM0l1t/Xkw/FW18lTld0WoTAI/EOE+VEOzzdO542f2m7EBjQZy9hVg4XtlKi1pP5wKBgCXrqVS1siZAbWOvhAs20utVs1Yj/f+0U7FxugbebXbSQyHbd2OPyw/nTvOl2mMzwGXyyT1cDdKqiXia8oExcudeqsNEAAuACSaf6TLBFKL2WBJAvNU0VJOxky40WzcnHpc0ISzlh2HmhRNff5rPVmcZyVfFceCYIHQEf0YSokuLAoGAFqnmXnWpqh4vFS50cOK1+MlMkgL8FBgF9voNZ7cGUtr10U1LspgLGjDTFJns19+qoeXcY6bXV3eZVSM0NHrgUd8vWYvSivatj7egcPLcbsEpGWST+njIhIql+QVWTx7tYLSAu6SRKEf8a5jCgMNMUZ0ZAOHITVINp2UarwHCOl8CgYBenz32mGQapDgw7fyw3aWe5e4i2rC3jHOxJOHSHTAcLzBZ7JrKOIoNtiHU9XWIjRB0kng4a0rDffywxM4YHI+ZMXgvYzHE1Ob2ei3Q/Q52bxkLEwEGrqwXl1kdmCb69imp1T92JBZ3ls2dX7+uJtJiy5KlZilGN61AwMgOxyg7Mg==';
    var encryptionPublicKey =
        'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAifuNqUo3yeQ0nu4woe0Vkh/TJU4htzz62HRBhw6EjYbT35Uoi+gYaRKaHTTC0mmKVrKFfWndr0YF6oDdKjNy7n35ZIAIoKQFPLpMwlFrPu7B0GQT34s/3JTtRrmoxe4ldAmjnu7SQOx8qHfUrQCw4v+epMIRqi4vOK4pi3jSsb+6gnziaMHjyQq7Ofvil0KM0F1mKHnga49RxhFjAm7qGsN4ob8CTwaO+hpEe7HmHKvQJaxYr39h3Lw2j8dH0jF3o00uWi9CqIM+4QazTRotVsow+dYWRLzLLIdTmMukyrWLI973jDtc3fXwWU/vcl1zQmd3F152ajhwHrVhD7I6DQIDAQAB';
    var sharedKey = 'Q58MkV2KwLNZAVS6SxKEzw1okYHtf/9k9EegctSyCqo=';
    var encryptedSharedKey =
        'JZ3fjGxobojMytMhslfcBsJ5R0f5oVFwV7Qyyko1PMB3DhWMWRhlCQFUIZlyGyX0gIBrDBkYGRHDkj00DYAoF1VVJ3jaHL1d45VPpYpPG0QxhA7A8BriU8PnX+3wbUk8LMD7GscW3sOJPJ2mduCM2UKs1TUO3D4AKR7vrEZXRi11ddgQZet6JgTcKG+/uG7ftdMxs1Y+jHvwfHCYlW+w/IfERzoyfPlAyyGAuY/ucZea/9JvSXtgp5Oxk7MKn3IMBa3N6vCb0zYpg+6SUdee0t47zeTaMcPJ9wCOJQ6p5b5ltK7kJxX2ILGHDFUeMUISKG2eMrEeR9HlVKQ3e3eLRw==';
    var publicKeyCheckSum = '745a800133171a170121e8040e3ebfe7';

    setUp(() async {
      registerFallbackValue(FakeLocalLookUpVerbBuilder());
      when(() => mockAtClient.getLocalSecondary())
          .thenAnswer((_) => mockLocalSecondary);
      when(() => mockAtClient.getRemoteSecondary())
          .thenAnswer((_) => mockRemoteSecondary);
      when(() => mockLocalSecondary.getEncryptionPrivateKey())
          .thenAnswer((_) => Future.value(encryptionPrivateKey));

      atCommitLog = await AtCommitLogManagerImpl.getInstance().getCommitLog(
          '@alice',
          commitLogPath: storageDir,
          enableCommitId: false);
    });

    test('test to verify encryption when shared key is available', () async {
      sharedKeyEncryption = SharedKeyEncryption(mockAtClient);
      await atCommitLog?.commitLogKeyStore.add(
          // Adding commit id to mock commit entry is synced from server
          CommitEntry('@bob:shared_key@alice', CommitOp.UPDATE, DateTime.now())
            ..commitId = 0);
      sharedKeyEncryption.atCommitLog = atCommitLog;
      var atKey = (AtKey.shared('phone', namespace: 'wavi', sharedBy: '@alice')
            ..sharedWith('@bob'))
          .build();
      var value = 'hello';

      when(() => mockLocalSecondary
          .executeVerb(any(that: EncryptedSharedKeyMatcher())))
          .thenAnswer((_) => Future.value(encryptedSharedKey));
      when(() => mockLocalSecondary
          .executeVerb(any(that: EncryptionPublicKeyMatcher())))
          .thenAnswer((_) => Future.value(encryptionPublicKey));

      var encryptedValue = await sharedKeyEncryption.encrypt(atKey, value);
      var decryptedSharedKey =
          EncryptionUtil.decryptKey(encryptedSharedKey, encryptionPrivateKey);
      expect(decryptedSharedKey, sharedKey);
      var decryptedValue =
          EncryptionUtil.decryptValue(encryptedValue, decryptedSharedKey);
      expect(decryptedValue, value);
      expect(atKey.metadata?.sharedKeyEnc.isNotNull, true);
      expect(atKey.metadata?.pubKeyCS.isNotNull, true);
    });

    test('test to verify encryption when a new shared key is generated',
        () async {
      sharedKeyEncryption = SharedKeyEncryption(mockAtClient);
      // Adding commit id to mock that commit entry is synced from server
      await atCommitLog?.commitLogKeyStore.add(
          CommitEntry('@bob:shared_key@alice', CommitOp.UPDATE, DateTime.now())
            ..commitId = 0);
      sharedKeyEncryption.atCommitLog = atCommitLog;

      when(() => mockLocalSecondary
              .executeVerb(any(that: EncryptedSharedKeyMatcher())))
          .thenAnswer((_) => Future.value('data:null'));
      when(() => mockRemoteSecondary
              .executeVerb(any(that: EncryptedSharedKeyMatcher())))
          .thenAnswer((_) => Future.value('data:null'));
      when(() => mockLocalSecondary
              .executeVerb(any(that: EncryptionPublicKeyMatcher())))
          .thenAnswer((_) => Future.value(encryptionPublicKey));
      when(() => mockLocalSecondary.executeVerb(
          any(that: UpdatedSharedKeyMatcher()),
          sync: true)).thenAnswer((_) => Future.value('data:1'));
      when(() => mockLocalSecondary.getEncryptionPublicKey('@alice'))
          .thenAnswer((_) => Future.value(encryptionPublicKey));

      var atKey = (AtKey.shared('phone', namespace: 'wavi', sharedBy: '@alice')
            ..sharedWith('@bob'))
          .build();
      var originalValue = 'hello';

      var encryptedValue =
          await sharedKeyEncryption.encrypt(atKey, originalValue);
      expect(
          EncryptionUtil.decryptValue(
              encryptedValue, sharedKeyEncryption.sharedKey),
          originalValue);
      expect(atKey.metadata?.sharedKeyEnc.isNotNull, true);
      expect(atKey.metadata?.pubKeyCS.isNotNull, true);
    });

    test(
        'test to verify exception is thrown when update command fails to store shared_key to remote secondary',
        () async {
      atCommitLog!.commitLogKeyStore.add(CommitEntry(
          '@bob:shared_key@alice', CommitOp.UPDATE, DateTime.now()));

      sharedKeyEncryption = SharedKeyEncryption(mockAtClient);
      sharedKeyEncryption.atCommitLog = atCommitLog;

      when(() => mockLocalSecondary
              .executeVerb(any(that: EncryptedSharedKeyMatcher())))
          .thenAnswer((_) => Future.value('data:null'));
      when(() => mockRemoteSecondary
              .executeVerb(any(that: EncryptedSharedKeyMatcher())))
          .thenAnswer((_) => Future.value('data:null'));
      when(() => mockLocalSecondary
              .executeVerb(any(that: EncryptionPublicKeyMatcher())))
          .thenAnswer((_) => Future.value(encryptionPublicKey));
      when(() => mockLocalSecondary.executeVerb(
          any(that: UpdatedSharedKeyMatcher()),
          sync: true)).thenAnswer((_) => Future.value('data:1'));
      when(() => mockRemoteSecondary
              .executeVerb(any(that: UpdatedSharedKeyMatcher()), sync: true))
          .thenAnswer((_) => throw SecondaryConnectException(
              'unable to connect to remote secondary'));
      when(() => mockLocalSecondary.getEncryptionPublicKey('@alice'))
          .thenAnswer((_) => Future.value(encryptionPublicKey));

      var atKey = (AtKey.shared('phone', namespace: 'wavi', sharedBy: '@alice')
            ..sharedWith('@bob'))
          .build();
      var originalValue = 'hello';
      expect(
          () async => await sharedKeyEncryption.encrypt(atKey, originalValue),
          throwsA(predicate((dynamic e) =>
              e is SecondaryConnectException &&
              e.message == 'unable to connect to remote secondary')));
    });

    tearDown(() async {
      await AtCommitLogManagerImpl.getInstance().close();
      var isExists = await Directory(storageDir).exists();
      if (isExists) {
        Directory(storageDir).deleteSync(recursive: true);
      }
    });
  });
}

class EncryptedSharedKeyMatcher extends Matcher {
  @override
  Description describe(Description description) =>
      description.add('A custom matcher to match the encrypted shared key');

  @override
  bool matches(item, Map matchState) {
    if (item is LLookupVerbBuilder && item.atKey!.contains('shared_key')) {
      return true;
    }
    return false;
  }
}

class EncryptionPublicKeyMatcher extends Matcher {
  @override
  Description describe(Description description) =>
      description.add('A custom matcher to match the encrypted public key');

  @override
  bool matches(item, Map matchState) {
    if (item is LLookupVerbBuilder && item.atKey!.contains('publickey')) {
      return true;
    }
    return false;
  }
}

class UpdatedSharedKeyMatcher extends Matcher {
  @override
  Description describe(Description description) => description.add(
      'A custom matcher to match the encrypted shared key for update verb builder');

  @override
  bool matches(item, Map matchState) {
    if (item is UpdateVerbBuilder) {
      return true;
    }
    return false;
  }
}
