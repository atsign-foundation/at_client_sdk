import 'dart:convert';
import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockLocalKeyStore extends Mock implements SecondaryKeyStore {}

void main() {
  var storageDir = '${Directory.current.path}/test/hive';
  final String atSign = '@alice';

  group(
      'A group of authorization test on update/delete verbs in local secondary',
      () {
    setUp(() async => await setupLocalStorage(storageDir, atSign));
    tearDown(() async => await tearDownLocalStorage(storageDir));

    test(
        'update/delete on different namespaces by enrollment with * namespace access',
        () async {
      final testEnrollmentId = 'aaa111';
      var atClient = await AtClientImpl.create(
          '@alice',
          'all',
          AtClientPreference()
            ..isLocalStoreRequired = true
            ..hiveStoragePath = 'test/hive'
            ..commitLogPath = 'test/hive/commit');
      atClient.enrollmentId = testEnrollmentId;
      // Insert the enrollment info into the local secondary.
      var localEnrollmentKey = AtKey()
        ..isLocal = true
        ..key = testEnrollmentId
        ..sharedBy = '@alice';
      await atClient.getLocalSecondary()?.keyStore?.put(
          localEnrollmentKey.toString(),
          AtData()
            ..data = jsonEncode(
                Enrollment()..namespace = {"__manage": "rw", "*": "rw"}));
      //1. create a self key in wavi namespace
      var waviKey = AtKey()
        ..key = 'phone'
        ..sharedBy = atSign
        ..sharedWith = atSign
        ..namespace = 'wavi';
      var verbBuilder = UpdateVerbBuilder()
        ..atKey = waviKey
        ..value = '1234';
      var updateWaviKeyResult = await atClient
          .getLocalSecondary()!
          .executeVerb(verbBuilder, sync: false);
      expect(updateWaviKeyResult, isNotNull);
      expect(updateWaviKeyResult!.startsWith('data:'), true);
      //1.1 delete self key in wavi namespace
      var deleteBuilder = DeleteVerbBuilder()..atKey = waviKey;
      var deleteWaviKeyResult = await atClient
          .getLocalSecondary()!
          .executeVerb(deleteBuilder, sync: false);
      expect(deleteWaviKeyResult, isNotNull);
      expect(deleteWaviKeyResult!.startsWith('data:'), true);
      //2. create a public key in buzz namespace
      var buzzKey = AtKey()
        ..key = 'email'
        ..sharedBy = atSign
        ..namespace = 'buzz'
        ..metadata = (Metadata()..isPublic = true);
      verbBuilder = UpdateVerbBuilder()
        ..atKey = buzzKey
        ..value = 'alice@gmail.com';
      var updateBuzzKeyResult =
          await atClient.getLocalSecondary()!.executeVerb(verbBuilder);
      expect(updateBuzzKeyResult, isNotNull);
      expect(updateBuzzKeyResult!.startsWith('data:'), true);
      //2.1 delete public key in buzz namespace
      deleteBuilder = DeleteVerbBuilder()..atKey = buzzKey;
      var deleteBuzzKeyResult = await atClient
          .getLocalSecondary()!
          .executeVerb(deleteBuilder, sync: false);
      expect(deleteBuzzKeyResult, isNotNull);
      expect(deleteBuzzKeyResult!.startsWith('data:'), true);
      //3. create a key with no namespace
      var noNamespaceKey = AtKey()
        ..key = 'location'
        ..sharedBy = atSign
        ..sharedWith = atSign;
      verbBuilder = UpdateVerbBuilder()
        ..atKey = noNamespaceKey
        ..value = 'india';
      var noNamespaceKeyUpdateResult =
          await atClient.getLocalSecondary()!.executeVerb(verbBuilder);
      expect(noNamespaceKeyUpdateResult, isNotNull);
      expect(noNamespaceKeyUpdateResult!.startsWith('data:'), true);
      //3.1 delete the key with no namespace
      deleteBuilder = DeleteVerbBuilder()..atKey = noNamespaceKey;
      var deleteNoNamespaceKeyResult = await atClient
          .getLocalSecondary()!
          .executeVerb(deleteBuilder, sync: false);
      expect(deleteNoNamespaceKeyResult, isNotNull);
      expect(deleteNoNamespaceKeyResult!.startsWith('data:'), true);
      //4. create a reserved key
      var reservedKey = AtKey()
        ..key = 'shared_key'
        ..sharedBy = atSign
        ..sharedWith = '@bob';
      verbBuilder = UpdateVerbBuilder()
        ..atKey = reservedKey
        ..value = 'randomsharedkey';
      var reservedKeyUpdateResult = await atClient
          .getLocalSecondary()!
          .executeVerb(verbBuilder, sync: false);
      expect(reservedKeyUpdateResult, isNotNull);
      expect(reservedKeyUpdateResult!.startsWith('data:'), true);
      //4.1 delete the reserved key
      deleteBuilder = DeleteVerbBuilder()..atKey = reservedKey;
      var deleteReservedKeyResult = await atClient
          .getLocalSecondary()!
          .executeVerb(deleteBuilder, sync: false);
      expect(deleteReservedKeyResult, isNotNull);
      expect(deleteReservedKeyResult!.startsWith('data:'), true);
    });

    test(
        'update on different namespaces by enrollment with specific namespace access',
        () async {
      final testEnrollmentId = 'aaa111';
      var atClient = await AtClientImpl.create(
          '@alice',
          'all',
          AtClientPreference()
            ..isLocalStoreRequired = true
            ..hiveStoragePath = 'test/hive'
            ..commitLogPath = 'test/hive/commit');
      atClient.enrollmentId = testEnrollmentId;
      // Insert the enrollment info into the local secondary.
      var localEnrollmentKey = AtKey()
        ..isLocal = true
        ..key = testEnrollmentId
        ..sharedBy = '@alice';
      await atClient.getLocalSecondary()?.keyStore?.put(
          localEnrollmentKey.toString(),
          AtData()
            ..data = jsonEncode(Enrollment()..namespace = {"wavi": "rw"}));
      //1. create a self key in wavi namespace should pass
      var waviKey = AtKey()
        ..key = 'phone'
        ..sharedBy = atSign
        ..sharedWith = atSign
        ..namespace = 'wavi';
      var verbBuilder = UpdateVerbBuilder()
        ..atKey = waviKey
        ..value = '1234';
      var updateWaviKeyResult = await atClient
          .getLocalSecondary()!
          .executeVerb(verbBuilder, sync: false);
      expect(updateWaviKeyResult, isNotNull);
      expect(updateWaviKeyResult!.startsWith('data:'), true);

      //2. create a public key in buzz namespace should fail
      var buzzKey = AtKey()
        ..key = 'email'
        ..sharedBy = atSign
        ..namespace = 'buzz'
        ..metadata = (Metadata()..isPublic = true);
      verbBuilder = UpdateVerbBuilder()
        ..atKey = buzzKey
        ..value = 'alice@gmail.com';
      expect(
          () async =>
              await atClient.getLocalSecondary()!.executeVerb(verbBuilder),
          throwsA(predicate((dynamic e) =>
              e is UnAuthorizedException &&
              e.message ==
                  'Cannot perform update on public:email.buzz@alice due to insufficient privilege')));

      //3. create a key with no namespace should fail
      var noNamespaceKey = AtKey()
        ..key = 'location'
        ..sharedBy = atSign
        ..sharedWith = atSign;
      verbBuilder = UpdateVerbBuilder()
        ..atKey = noNamespaceKey
        ..value = 'india';
      expect(
          () async =>
              await atClient.getLocalSecondary()!.executeVerb(verbBuilder),
          throwsA(predicate((dynamic e) =>
              e is UnAuthorizedException &&
              e.message ==
                  'Cannot perform update on @alice:location@alice due to insufficient privilege')));

      //4. create a reserved key should pass
      var reservedKey = AtKey()
        ..key = 'shared_key'
        ..sharedBy = atSign
        ..sharedWith = '@bob';
      verbBuilder = UpdateVerbBuilder()
        ..atKey = reservedKey
        ..value = 'randomsharedkey';
      var reservedKeyUpdateResult = await atClient
          .getLocalSecondary()!
          .executeVerb(verbBuilder, sync: false);
      expect(reservedKeyUpdateResult, isNotNull);
      expect(reservedKeyUpdateResult!.startsWith('data:'), true);
    });
    test(
        'delete on different namespaces by enrollment with specific namespace access',
        () async {
      final testEnrollmentId = 'aaa111';
      var atClient = await AtClientImpl.create(
          '@alice',
          'all',
          AtClientPreference()
            ..isLocalStoreRequired = true
            ..hiveStoragePath = 'test/hive'
            ..commitLogPath = 'test/hive/commit');
      atClient.enrollmentId = testEnrollmentId;
      // Insert the enrollment info into the local secondary.
      var localEnrollmentKey = AtKey()
        ..isLocal = true
        ..key = testEnrollmentId
        ..sharedBy = '@alice';
      await atClient.getLocalSecondary()?.keyStore?.put(
          localEnrollmentKey.toString(),
          AtData()
            ..data = jsonEncode(
                Enrollment()..namespace = {"__manage": "rw", "*": "rw"}));
      //1. create a self key in wavi namespace
      var waviKey = AtKey()
        ..key = 'phone'
        ..sharedBy = atSign
        ..sharedWith = atSign
        ..namespace = 'wavi';
      var verbBuilder = UpdateVerbBuilder()
        ..atKey = waviKey
        ..value = '1234';
      var updateWaviKeyResult = await atClient
          .getLocalSecondary()!
          .executeVerb(verbBuilder, sync: false);
      expect(updateWaviKeyResult, isNotNull);
      expect(updateWaviKeyResult!.startsWith('data:'), true);

      //2. create a public key in buzz namespace
      var buzzKey = AtKey()
        ..key = 'email'
        ..sharedBy = atSign
        ..namespace = 'buzz'
        ..metadata = (Metadata()..isPublic = true);
      verbBuilder = UpdateVerbBuilder()
        ..atKey = buzzKey
        ..value = 'alice@gmail.com';
      var updateBuzzKeyResult =
          await atClient.getLocalSecondary()!.executeVerb(verbBuilder);
      expect(updateBuzzKeyResult, isNotNull);
      expect(updateBuzzKeyResult!.startsWith('data:'), true);

      //3. create a key with no namespace
      var noNamespaceKey = AtKey()
        ..key = 'location'
        ..sharedBy = atSign
        ..sharedWith = atSign;
      verbBuilder = UpdateVerbBuilder()
        ..atKey = noNamespaceKey
        ..value = 'india';
      var noNamespaceKeyUpdateResult =
          await atClient.getLocalSecondary()!.executeVerb(verbBuilder);
      expect(noNamespaceKeyUpdateResult, isNotNull);
      expect(noNamespaceKeyUpdateResult!.startsWith('data:'), true);

      //4. create a reserved key
      var reservedKey = AtKey()
        ..key = 'shared_key'
        ..sharedBy = atSign
        ..sharedWith = '@bob';
      verbBuilder = UpdateVerbBuilder()
        ..atKey = reservedKey
        ..value = 'randomsharedkey';
      var reservedKeyUpdateResult = await atClient
          .getLocalSecondary()!
          .executeVerb(verbBuilder, sync: false);
      expect(reservedKeyUpdateResult, isNotNull);
      expect(reservedKeyUpdateResult!.startsWith('data:'), true);
      AtClientImpl.atClientInstanceMap.remove(atSign);
      // create an atClient for new enrollment
      var newEnrollmentId = 'abc123';
      var enrolledAtClient = await AtClientImpl.create(
          '@alice',
          'wavi',
          AtClientPreference()
            ..isLocalStoreRequired = true
            ..hiveStoragePath = 'test/hive'
            ..commitLogPath = 'test/hive/commit');
      enrolledAtClient.enrollmentId = newEnrollmentId;
      // Insert the enrollment info into the local secondary.
      var localEnrollmentKey_2 = AtKey()
        ..isLocal = true
        ..key = newEnrollmentId
        ..sharedBy = '@alice';
      await atClient.getLocalSecondary()?.keyStore?.put(
          localEnrollmentKey_2.toString(),
          AtData()
            ..data = jsonEncode(Enrollment()..namespace = {"wavi": "rw"}));
      // delete self key in wavi namespace should pass
      var deleteBuilder = DeleteVerbBuilder()..atKey = waviKey;
      var deleteWaviKeyResult = await enrolledAtClient
          .getLocalSecondary()!
          .executeVerb(deleteBuilder, sync: false);
      expect(deleteWaviKeyResult, isNotNull);
      expect(deleteWaviKeyResult!.startsWith('data:'), true);
      // delete public key in buzz namespace should fail
      deleteBuilder = DeleteVerbBuilder()..atKey = buzzKey;
      expect(
          () async => await enrolledAtClient
              .getLocalSecondary()!
              .executeVerb(deleteBuilder),
          throwsA(predicate((dynamic e) =>
              e is UnAuthorizedException &&
              e.message ==
                  'Cannot perform delete on public:email.buzz@alice due to insufficient privilege')));
      // delete the key with no namespace should fail
      deleteBuilder = DeleteVerbBuilder()..atKey = noNamespaceKey;
      expect(
          () async => await enrolledAtClient
              .getLocalSecondary()!
              .executeVerb(deleteBuilder),
          throwsA(predicate((dynamic e) =>
              e is UnAuthorizedException &&
              e.message ==
                  'Cannot perform delete on @alice:location@alice due to insufficient privilege')));
      // delete the reserved key should pass
      deleteBuilder = DeleteVerbBuilder()..atKey = reservedKey;
      var deleteReservedKeyResult = await enrolledAtClient
          .getLocalSecondary()!
          .executeVerb(deleteBuilder, sync: false);
      expect(deleteReservedKeyResult, isNotNull);
      expect(deleteReservedKeyResult!.startsWith('data:'), true);
    });
  });
  group('A group of authorization tests on llookup verb in local secondary',
      () {
    setUp(() async => await setupLocalStorage(storageDir, atSign));
    tearDown(() async => await tearDownLocalStorage(storageDir));
    test(
        'get method on different namespaces can be accessed by enrollment with * namespace access',
        () async {
      final testEnrollmentId = 'aaa111';
      var atClient = await AtClientImpl.create(
          '@alice',
          'all',
          AtClientPreference()
            ..isLocalStoreRequired = true
            ..hiveStoragePath = 'test/hive'
            ..commitLogPath = 'test/hive/commit');
      atClient.enrollmentId = testEnrollmentId;
      // Insert the enrollment info into the local secondary.
      var localEnrollmentKey = AtKey()
        ..isLocal = true
        ..key = testEnrollmentId
        ..sharedBy = '@alice';
      await atClient.getLocalSecondary()?.keyStore?.put(
          localEnrollmentKey.toString(),
          AtData()
            ..data = jsonEncode(
                Enrollment()..namespace = {"__manage": "rw", "*": "rw"}));

      //1. create a key in wavi namespace
      var waviKey = AtKey()
        ..key = 'phone'
        ..sharedBy = atSign
        ..sharedWith = atSign
        ..namespace = 'wavi';
      var verbBuilder = UpdateVerbBuilder()
        ..atKey = waviKey
        ..value = '1234';
      var updateWaviKeyResult = await atClient
          .getLocalSecondary()!
          .executeVerb(verbBuilder, sync: false);
      expect(updateWaviKeyResult, isNotNull);
      expect(updateWaviKeyResult!.startsWith('data:'), true);
      //2. create a key in buzz namespace
      var buzzKey = AtKey()
        ..key = 'email'
        ..sharedBy = atSign
        ..sharedWith = atSign
        ..namespace = 'buzz';
      verbBuilder = UpdateVerbBuilder()
        ..atKey = buzzKey
        ..value = 'alice@gmail.com';
      var updateBuzzKeyResult =
          await atClient.getLocalSecondary()!.executeVerb(verbBuilder);
      expect(updateBuzzKeyResult, isNotNull);
      expect(updateBuzzKeyResult!.startsWith('data:'), true);
      //3. create a key with no namespace
      var noNamespaceKey = AtKey()
        ..key = 'location'
        ..sharedBy = atSign
        ..sharedWith = atSign;
      verbBuilder = UpdateVerbBuilder()
        ..atKey = noNamespaceKey
        ..value = 'india';
      var noNamespaceKeyUpdateResult =
          await atClient.getLocalSecondary()!.executeVerb(verbBuilder);
      expect(noNamespaceKeyUpdateResult, isNotNull);
      expect(noNamespaceKeyUpdateResult!.startsWith('data:'), true);
      //4. create a reserved key
      var reservedKey = AtKey()
        ..key = 'shared_key'
        ..sharedBy = atSign
        ..sharedWith = '@bob';
      verbBuilder = UpdateVerbBuilder()
        ..atKey = reservedKey
        ..value = 'randomsharedkey';
      var updateReservedKeyResult =
          await atClient.getLocalSecondary()!.executeVerb(verbBuilder);
      expect(updateReservedKeyResult, isNotNull);
      expect(updateReservedKeyResult!.startsWith('data:'), true);

      // llookup on wavi namespace should be allowed
      var waviLookupBuilder = LLookupVerbBuilder()..atKey = waviKey;
      var waviResult =
          await atClient.getLocalSecondary()!.executeVerb(waviLookupBuilder);
      expect(waviResult, 'data:1234');
      //llookup on buzz namespace should be allowed
      var buzzLookupBuilder = LLookupVerbBuilder()..atKey = buzzKey;
      var buzzResult =
          await atClient.getLocalSecondary()!.executeVerb(buzzLookupBuilder);
      expect(buzzResult, 'data:alice@gmail.com');
      // llookup on NO namespace should be allowed
      var noNamespaceLookupBuilder = LLookupVerbBuilder()
        ..atKey = noNamespaceKey;
      var noNamespaceResult = await atClient
          .getLocalSecondary()!
          .executeVerb(noNamespaceLookupBuilder);
      expect(noNamespaceResult, 'data:india');
      // llookup on reserved key should be allowed
      var reservedKeyLookupBuilder = LLookupVerbBuilder()..atKey = reservedKey;
      var reservedKeyResult = await atClient
          .getLocalSecondary()!
          .executeVerb(reservedKeyLookupBuilder);
      expect(reservedKeyResult, 'data:randomsharedkey');
    });
    test(
        'get method checks on enrollment with specific namespace(e.g wavi) access',
        () async {
      final privilegedEnrollment = 'aaa111';
      var atClient = await AtClientImpl.create(
          '@alice',
          'all',
          AtClientPreference()
            ..isLocalStoreRequired = true
            ..hiveStoragePath = 'test/hive'
            ..commitLogPath = 'test/hive/commit');
      atClient.enrollmentId = privilegedEnrollment;
      // Insert the enrollment info into the local secondary.
      var localEnrollmentKey = AtKey()
        ..isLocal = true
        ..key = privilegedEnrollment
        ..sharedBy = '@alice';
      await atClient.getLocalSecondary()?.keyStore?.put(
          localEnrollmentKey.toString(),
          AtData()..data = jsonEncode(Enrollment()..namespace = {"*": "rw"}));
      //1. create a key in wavi namespace
      var waviKey = AtKey()
        ..key = 'phone'
        ..sharedBy = atSign
        ..sharedWith = atSign
        ..namespace = 'wavi';
      var verbBuilder = UpdateVerbBuilder()
        ..atKey = waviKey
        ..value = '1234';
      var updateWaviKeyResult = await atClient
          .getLocalSecondary()!
          .executeVerb(verbBuilder, sync: false);
      expect(updateWaviKeyResult, isNotNull);
      expect(updateWaviKeyResult!.startsWith('data:'), true);
      //2. create a key in buzz namespace
      var buzzKey = AtKey()
        ..key = 'email'
        ..sharedBy = atSign
        ..sharedWith = atSign
        ..namespace = 'buzz';
      verbBuilder = UpdateVerbBuilder()
        ..atKey = buzzKey
        ..value = 'alice@gmail.com';
      var updateBuzzKeyResult =
          await atClient.getLocalSecondary()!.executeVerb(verbBuilder);
      expect(updateBuzzKeyResult, isNotNull);
      expect(updateBuzzKeyResult!.startsWith('data:'), true);
      //3. create a key with no namespace
      var noNamespaceKey = AtKey()
        ..key = 'location'
        ..sharedBy = atSign
        ..sharedWith = atSign;
      verbBuilder = UpdateVerbBuilder()
        ..atKey = noNamespaceKey
        ..value = 'india';
      var noNamespaceKeyUpdateResult =
          await atClient.getLocalSecondary()!.executeVerb(verbBuilder);
      expect(noNamespaceKeyUpdateResult, isNotNull);
      expect(noNamespaceKeyUpdateResult!.startsWith('data:'), true);
      //4. create a reserved key
      var reservedKey = AtKey()
        ..key = 'shared_key'
        ..sharedBy = atSign
        ..sharedWith = '@bob';
      verbBuilder = UpdateVerbBuilder()
        ..atKey = reservedKey
        ..value = 'randomsharedkey';
      var updateReservedKeyResult =
          await atClient.getLocalSecondary()!.executeVerb(verbBuilder);
      expect(updateReservedKeyResult, isNotNull);
      expect(updateReservedKeyResult!.startsWith('data:'), true);
      AtClientImpl.atClientInstanceMap.remove(atSign);
      // create an atClient for new enrollment
      var newEnrollmentId = 'abc123';
      var enrolledAtClient = await AtClientImpl.create(
          '@alice',
          'wavi',
          AtClientPreference()
            ..isLocalStoreRequired = true
            ..hiveStoragePath = 'test/hive'
            ..commitLogPath = 'test/hive/commit');
      enrolledAtClient.enrollmentId = newEnrollmentId;
      // Insert the enrollment info into the local secondary.
      var localEnrollmentKey_2 = AtKey()
        ..isLocal = true
        ..key = newEnrollmentId
        ..sharedBy = '@alice';
      await atClient.getLocalSecondary()?.keyStore?.put(
          localEnrollmentKey_2.toString(),
          AtData()
            ..data = jsonEncode(Enrollment()..namespace = {"wavi": "rw"}));
      // llookup on wavi namespace should be allowed
      var waviLookupBuilder = LLookupVerbBuilder()..atKey = waviKey;
      var waviResult = await enrolledAtClient
          .getLocalSecondary()!
          .executeVerb(waviLookupBuilder);
      expect(waviResult, 'data:1234');
      //llookup on buzz namespace should be DENIED
      var buzzLookupBuilder = LLookupVerbBuilder()..atKey = buzzKey;
      expect(
          () async => await enrolledAtClient
              .getLocalSecondary()!
              .executeVerb(buzzLookupBuilder),
          throwsA(predicate((dynamic e) =>
              e is UnAuthorizedException &&
              e.message ==
                  'Cannot perform llookup on @alice:email.buzz@alice due to insufficient privilege')));
      //llookup on NO namespace should be DENIED
      var noNamespaceLookupBuilder = LLookupVerbBuilder()
        ..atKey = noNamespaceKey;
      expect(
          () async => await enrolledAtClient
              .getLocalSecondary()!
              .executeVerb(noNamespaceLookupBuilder),
          throwsA(predicate((dynamic e) =>
              e is UnAuthorizedException &&
              e.message ==
                  'Cannot perform llookup on @alice:location@alice due to insufficient privilege')));
      // llookup on reserved key should be allowed
      var reservedKeyLookupBuilder = LLookupVerbBuilder()..atKey = reservedKey;
      var reservedKeyResult = await atClient
          .getLocalSecondary()!
          .executeVerb(reservedKeyLookupBuilder);
      expect(reservedKeyResult, 'data:randomsharedkey');
    });
  });
  group('A group of authorization tests on scan verb in local secondary', () {
    setUp(() async => await setupLocalStorage(storageDir, atSign));
    tearDown(() async => await tearDownLocalStorage(storageDir));
    test('scan method return all keys on an enrollment with * namespace access',
        () async {
      final testEnrollmentId = 'aaa111';
      var atClient = await AtClientImpl.create(
          '@alice',
          'all',
          AtClientPreference()
            ..isLocalStoreRequired = true
            ..hiveStoragePath = 'test/hive'
            ..commitLogPath = 'test/hive/commit');
      atClient.enrollmentId = testEnrollmentId;
      // Insert the enrollment info into the local secondary.
      var localEnrollmentKey = AtKey()
        ..isLocal = true
        ..key = testEnrollmentId
        ..sharedBy = '@alice';
      await atClient.getLocalSecondary()?.keyStore?.put(
          localEnrollmentKey.toString(),
          AtData()
            ..data = jsonEncode(
                Enrollment()..namespace = {"__manage": "rw", "*": "rw"}));
      //1. create a key in wavi namespace
      var waviKey = AtKey()
        ..key = 'phone'
        ..sharedBy = atSign
        ..sharedWith = atSign
        ..namespace = 'wavi';
      var verbBuilder = UpdateVerbBuilder()
        ..atKey = waviKey
        ..value = '1234';
      var updateWaviKeyResult = await atClient
          .getLocalSecondary()!
          .executeVerb(verbBuilder, sync: false);
      expect(updateWaviKeyResult, isNotNull);
      expect(updateWaviKeyResult!.startsWith('data:'), true);
      //2. create a key in buzz namespace
      var buzzKey = AtKey()
        ..key = 'email'
        ..sharedBy = atSign
        ..sharedWith = atSign
        ..namespace = 'buzz';
      verbBuilder = UpdateVerbBuilder()
        ..atKey = buzzKey
        ..value = 'alice@gmail.com';
      var updateBuzzKeyResult =
          await atClient.getLocalSecondary()!.executeVerb(verbBuilder);
      expect(updateBuzzKeyResult, isNotNull);
      expect(updateBuzzKeyResult!.startsWith('data:'), true);
      //3. create a key with no namespace
      var noNamespaceKey = AtKey()
        ..key = 'location'
        ..sharedBy = atSign
        ..sharedWith = atSign;
      verbBuilder = UpdateVerbBuilder()
        ..atKey = noNamespaceKey
        ..value = 'india';
      var noNamespaceKeyUpdateResult =
          await atClient.getLocalSecondary()!.executeVerb(verbBuilder);
      expect(noNamespaceKeyUpdateResult, isNotNull);
      expect(noNamespaceKeyUpdateResult!.startsWith('data:'), true);
      //4. create a reserved key
      var reservedKey = AtKey()
        ..key = 'shared_key'
        ..sharedBy = atSign
        ..sharedWith = '@bob';
      verbBuilder = UpdateVerbBuilder()
        ..atKey = reservedKey
        ..value = 'randomsharedkey';
      var updateReservedKeyResult =
          await atClient.getLocalSecondary()!.executeVerb(verbBuilder);
      expect(updateReservedKeyResult, isNotNull);
      expect(updateReservedKeyResult!.startsWith('data:'), true);

      // scan keys
      var scanVerbBuilder = ScanVerbBuilder();
      var scanResult =
          await atClient.getLocalSecondary()!.executeVerb(scanVerbBuilder);
      expect(scanResult, isNotEmpty);
      var scanJson = jsonDecode(scanResult!);
      print(scanJson);
      expect(scanJson.contains('@alice:email.buzz@alice'), true);
      expect(scanJson.contains('@alice:location@alice'), true);
      expect(scanJson.contains('@alice:phone.wavi@alice'), true);
      expect(scanJson.contains('@bob:shared_key@alice'), true);
      AtClientImpl.atClientInstanceMap.remove(atSign);
      // create an atClient for new enrollment
      var newEnrollmentId = 'abc123';
      var enrolledAtClient = await AtClientImpl.create(
          '@alice',
          'wavi',
          AtClientPreference()
            ..isLocalStoreRequired = true
            ..hiveStoragePath = 'test/hive'
            ..commitLogPath = 'test/hive/commit');
      enrolledAtClient.enrollmentId = newEnrollmentId;
      // Insert the enrollment info into the local secondary.
      var localEnrollmentKey_2 = AtKey()
        ..isLocal = true
        ..key = newEnrollmentId
        ..sharedBy = '@alice';
      await atClient.getLocalSecondary()?.keyStore?.put(
          localEnrollmentKey_2.toString(),
          AtData()
            ..data = jsonEncode(Enrollment()..namespace = {"wavi": "rw"}));
      // enrolled client should be able to see wavi key and reserved key in scan. Buzz key and no namespace keys should not be returned
      enrolledAtClient.enrollmentId = newEnrollmentId;
      var enrolledClientScanResult = await enrolledAtClient
          .getLocalSecondary()!
          .executeVerb(scanVerbBuilder);
      expect(enrolledClientScanResult, isNotEmpty);
      var enrolledScanJson = jsonDecode(enrolledClientScanResult!);
      expect(enrolledScanJson.contains('@alice:phone.wavi@alice'), true);
      expect(enrolledScanJson.contains('@bob:shared_key@alice'), true);
      expect(enrolledScanJson.contains('@alice:email.buzz@alice'), false);
      expect(enrolledScanJson.contains('@alice:location@alice'), false);
    });
  });
}

Future<void> setupLocalStorage(String storageDir, String atSign) async {
  var commitLogInstance = await AtCommitLogManagerImpl.getInstance()
      .getCommitLog(atSign, commitLogPath: storageDir);
  var persistenceManager = SecondaryPersistenceStoreFactory.getInstance()
      .getSecondaryPersistenceStore(atSign)!;
  await persistenceManager.getHivePersistenceManager()!.init(storageDir);
  persistenceManager.getSecondaryKeyStore()!.commitLog = commitLogInstance;
}

Future<void> tearDownLocalStorage(storageDir) async {
  try {
    var isExists = await Directory(storageDir).exists();
    if (isExists) {
      Directory(storageDir).deleteSync(recursive: true);
    }
    AtClientImpl.atClientInstanceMap.clear();
  } catch (e, st) {
    print('local_secondary_test.dart: exception / error in tearDown: $e, $st');
  }
}
