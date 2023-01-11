import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/transformer/response_transformer/get_response_transformer.dart';
import 'package:at_client/src/util/sync_util.dart';
// ignore: depend_on_referenced_packages
import 'package:at_commons/at_builders.dart';
import 'package:test/test.dart';

import 'set_encryption_keys.dart';
import 'test_utils.dart';

void main() {
  test(
    'Verify local changes are synced to server - local ahead',
    () async {
      var atSign = '@alice🛠';
      var preference = TestUtils.getPreference(atSign);
      final atClientManager = await AtClientManager.getInstance()
          .setCurrentAtSign(atSign, 'me', preference);
      var atClient = atClientManager.atClient;
      atClientManager.syncService.sync();
      // To setup encryption keys
      await setEncryptionKeys(atSign, preference);
      // Get server commit id before put operation
      var serverCommitId = await SyncUtil()
          .getLatestServerCommitId(atClient.getRemoteSecondary()!, '');
      print('serverCommitId before put method $serverCommitId');
      expect(serverCommitId != null, true);
      // twitter.me@alice🛠
      var twitterKey = AtKey()
        ..key = 'twitter'
        ..sharedWith = '@bob🛠';
      var value = 'alice.twitter';
      var putResult = await atClient.put(twitterKey, value);
      expect(putResult, true);
      // waiting for 15 seconds for sync to complete.
      await Future.delayed(Duration(seconds: 10));
      // Getting server commit id after put
      var serverCommitIdAfterPut = await SyncUtil()
          .getLatestServerCommitId(atClient.getRemoteSecondary()!, '');
      print('serverCommitId after put method $serverCommitIdAfterPut');
      // After sync successful, the serverCommitId after put should be greater
      // than server commit before put
      expect(serverCommitIdAfterPut! > serverCommitId!, true);
      // Getting value from remote secondary
      var llookupVerbBuilder = LLookupVerbBuilder()
        ..atKey = 'twitter.me'
        ..sharedWith = '@bob🛠'
        ..sharedBy = atSign
        ..operation = 'all';
      var getResponse =
          await atClient.getRemoteSecondary()!.executeVerb(llookupVerbBuilder);
      var transformedValue = await GetResponseTransformer(atClient)
          .transform(Tuple<AtKey, String>()
            ..one = twitterKey
            ..two = (getResponse));
      // Decrypting and verifying the value from the remote secondary
      expect(transformedValue.value, value);
    },
  );

  test('Verify server changes are synced to local - server ahead', () async {
    var atSign = '@alice🛠';
    var preference = TestUtils.getPreference(atSign);
    final atClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(atSign, 'me', preference);
    var atClient = atClientManager.atClient;
    atClientManager.syncService.sync();
    // To setup encryption keys
    await setEncryptionKeys(atSign, preference);
    // Get local commit id before put operation
    var localEntry = await SyncUtil().getLastSyncedEntry('', atSign: atSign);
    print('localCommitId before put method ${localEntry?.commitId}');
    expect(localEntry?.commitId != null, true);
    // twitter.me@alice🛠
    var value = 'alice.linkedin';
    var updateVerbBuilder = UpdateVerbBuilder()
      ..atKey = 'linkedin.me'
      ..sharedBy = atSign
      ..isPublic = true
      ..value = value;
    var updateResponse =
        await atClient.getRemoteSecondary()!.executeVerb(updateVerbBuilder);
    expect(updateResponse.isNotEmpty, true);
    // waiting for 15 seconds for sync to complete.
    await Future.delayed(Duration(seconds: 10));
    // Getting server commit id after put
    var localEntryAfterSync =
        await SyncUtil().getLastSyncedEntry('', atSign: atSign);
    print('localCommitId after put method ${localEntryAfterSync?.commitId}');
    // After sync successful, the localCommitId after put should be greater
    // than localCommitId before put
    expect(localEntryAfterSync!.commitId! > localEntry!.commitId!, true);
    // Getting value from remote secondary
    var atKey = AtKey()
      ..key = 'linkedin.me'
      ..metadata = (Metadata()..isPublic = true)
      ..sharedBy = atSign;
    var getResponse = await atClient.get(atKey);
    expect(getResponse.value, value);
  });

  test('A test to verify sync with regex when local is ahead', () async {
    var atSign = '@alice🛠';
    var sharedWithAtsign = '@bob🛠';
    var preference = TestUtils.getPreference(atSign);
    preference.syncRegex = '.wavi';
    final atClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(atSign, 'wavi', preference);
    var atClient = atClientManager.atClient;
    atClientManager.syncService.sync();
    // To setup encryption keys
    await setEncryptionKeys(atSign, preference);
    // Get server commit id before put operation
    var serverCommitId = await SyncUtil()
        .getLatestServerCommitId(atClient.getRemoteSecondary()!, '');
    print('serverCommitId before put method $serverCommitId');
    expect(serverCommitId != null, true);
    // twitter.me@alice🛠
    var waviKey = AtKey()
      ..key = 'quora'
      ..namespace = 'wavi'
      ..sharedWith = sharedWithAtsign;
    var value = 'alice.quora';
    var atmosphereKey = AtKey()
      ..key = 'medium'
      ..namespace = 'atmosphere'
      ..sharedWith = sharedWithAtsign;
    var valueAtmosphere = 'alice.medium';
    var putResult = await atClient.put(waviKey, value);
    expect(putResult, true);
    putResult = await atClient.put(atmosphereKey, valueAtmosphere);
    expect(putResult, true);
    atClientManager.syncService.sync();
    atClientManager.syncService.sync();
    atClientManager.syncService.sync();
    // waiting for 15 seconds for sync to complete.
    await Future.delayed(Duration(seconds: 15));
    // Getting server commit id after put
    var serverCommitIdAfterPut = await SyncUtil()
        .getLatestServerCommitId(atClient.getRemoteSecondary()!, '');
    var localEntryAfterSync =
        await SyncUtil().getLastSyncedEntry('wavi', atSign: atSign);
    print('last synced entry $localEntryAfterSync');
    // As the regex is set to wavi, .mosphere key should not be synced
    expect(
        (localEntryAfterSync?.atKey!
            .contains('$sharedWithAtsign:medium.atmosphere$atSign')),
        false);
    print('serverCommitId after put method $serverCommitIdAfterPut');
    // After sync successful, the serverCommitId after put should be greater
    // than server commit before put
    expect(serverCommitIdAfterPut! > serverCommitId!, true);
    // Getting value from remote secondary
    var llookupVerbBuilder = LLookupVerbBuilder()
      ..atKey = 'quora.wavi'
      ..sharedWith = sharedWithAtsign
      ..sharedBy = atSign
      ..operation = 'all';
    var getResponse =
        await atClient.getRemoteSecondary()!.executeVerb(llookupVerbBuilder);
    var transformedValue =
        await GetResponseTransformer(atClient).transform(Tuple<AtKey, String>()
          ..one = waviKey
          ..two = (getResponse));
    // Decrypting and verifying the value from the remote secondary
    expect(transformedValue.value, value);
  });

  test(
      'A test to verify sync result in onDone callback on successful completion',
      () async {
    var atSign = '@alice🛠';
    var sharedWithAtsign = '@bob🛠';
    var preference = TestUtils.getPreference(atSign);
    final atClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(atSign, 'wavi', preference);
    var atClient = atClientManager.atClient;
    atClientManager.syncService.sync();
    // To setup encryption keys
    await setEncryptionKeys(atSign, preference);
    var atKey = AtKey()
      ..key = 'discord'
      ..namespace = 'wavi'
      ..sharedWith = sharedWithAtsign;
    var value = 'alice.discord';
    var putResult = await atClient.put(atKey, value);
    expect(putResult, true);
    await Future.delayed(Duration(seconds: 10));
    atClientManager.syncService.sync(onDone: onDoneCallback);
    atClientManager.syncService.sync(onDone: onDoneCallback);
    atClientManager.syncService.sync(onDone: onDoneCallback);
    var llookupVerbBuilder = LLookupVerbBuilder()
      ..atKey = 'discord.wavi'
      ..sharedWith = sharedWithAtsign
      ..sharedBy = atSign
      ..operation = 'all';
    var getResponse =
        await atClient.getRemoteSecondary()!.executeVerb(llookupVerbBuilder);
    var transformedValue =
        await GetResponseTransformer(atClient).transform(Tuple<AtKey, String>()
          ..one = atKey
          ..two = (getResponse));
    // Decrypting and verifying the value from the remote secondary
    expect(transformedValue.value, value);
  });

  test('a test to verify that local key is not synced to the cloud', () async {
    var atSign = '@alice🛠';
    var preference = TestUtils.getPreference(atSign);
    final atClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(atSign, 'wavi', preference);
    var atClient = atClientManager.atClient;
    // To setup encryption keys
    await setEncryptionKeys(atSign, preference);
    atClientManager.syncService.sync();
    var atKey = AtKey()
      ..key = 'localkey'
      ..namespace = 'wavi'
      ..isLocal = true;
    var value = 'alice.localkey';
    var putResult = await atClient.put(atKey, value);
    expect(putResult, true);
    atClientManager.syncService.sync();
    atClientManager.syncService.sync();
    atClientManager.syncService.sync();
    // waiting for 10 seconds for sync to complete.
    await Future.delayed(Duration(seconds: 10));
    var localEntryAfterSync =
        await SyncUtil().getLastSyncedEntry('', atSign: atSign);
    expect(localEntryAfterSync!.atKey, isNot('local:localkey.wavi$atSign'));
    print('local synced entry $localEntryAfterSync');
    var llookupVerbBuilder = LLookupVerbBuilder()
      ..atKey = 'local:localkey.wavi'
      ..sharedBy = atSign
      ..operation = 'all';
    expect(
        () async => await atClient
            .getRemoteSecondary()!
            .executeVerb(llookupVerbBuilder),
        throwsA(predicate((dynamic e) => e is KeyNotFoundException)));
  });

  test('a test to verify multiple updates of a key is synced to the cloud',
      () async {
    var atSign = '@alice🛠';
    var preference = TestUtils.getPreference(atSign);
    final atClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(atSign, 'wavi', preference);
    var atClient = atClientManager.atClient;
    // To setup encryption keys
    await setEncryptionKeys(atSign, preference);
    atClientManager.syncService.sync();
    var atKey = AtKey()
      ..key = 'key1'
      ..namespace = 'wavi';
    var value1 = 'value1.key1';
    var value2 = 'value2.key1';
    var putResult = await atClient.put(atKey, value1);
    expect(putResult, true);
    putResult = await atClient.put(atKey, value2);
    expect(putResult, true);
    // waiting for 10 seconds for sync to complete.
    atClientManager.syncService.sync();
    atClientManager.syncService.sync();
    atClientManager.syncService.sync();
    await Future.delayed(Duration(seconds: 10));
    var llookupVerbBuilder = LLookupVerbBuilder()
      ..atKey = 'key1.wavi'
      ..sharedBy = atSign
      ..operation = 'all';
    var getResponse =
        await atClient.getRemoteSecondary()!.executeVerb(llookupVerbBuilder);
    var transformedValue =
        await GetResponseTransformer(atClient).transform(Tuple<AtKey, String>()
          ..one = atKey
          ..two = (getResponse));
    // Decrypting and verifying the value from the remote secondary
    expect(transformedValue.value, value2);
  });

  test('Update from server for a key that exists in local secondary', () async {
    var atSign = '@alice🛠';
    var preference = TestUtils.getPreference(atSign);
    final atClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(atSign, 'wavi', preference);
    var atClient = atClientManager.atClient;
    // To setup encryption keys
    await setEncryptionKeys(atSign, preference);
    atClientManager.syncService.sync();

    var atKey = AtKey()
      ..key = 'testkey'
      ..namespace = 'wavi';
    var value = 'localvalue';
    var putResult = await atClient.put(atKey, value);
    expect(putResult, true);
    var updateVerbBuilder = UpdateVerbBuilder()
      ..atKey = 'testkey'
      ..sharedBy = atSign
      ..isPublic = true
      ..value = value;
    var updateResponse =
        await atClient.getRemoteSecondary()!.executeVerb(updateVerbBuilder);
    expect(updateResponse.isNotEmpty, true);
    // waiting for 10 seconds for sync to complete.
    atClientManager.syncService.sync();
    atClientManager.syncService.sync();
    atClientManager.syncService.sync();
    await Future.delayed(Duration(seconds: 10));
    var llookupVerbBuilder = LLookupVerbBuilder()
      ..atKey = 'testkey.wavi'
      ..sharedBy = atSign
      ..operation = 'all';
    var getResponse =
        await atClient.getRemoteSecondary()!.executeVerb(llookupVerbBuilder);
    var transformedValue =
        await GetResponseTransformer(atClient).transform(Tuple<AtKey, String>()
          ..one = atKey
          ..two = (getResponse));
    // Decrypting and verifying the value from the remote secondary
    expect(transformedValue.value, value);
    expect(
        transformedValue.metadata!.updatedAt!.isBefore(DateTime.now()), true);
  });
}

void onDoneCallback(syncResult) {
  print('sync result $syncResult');
  //always assert that the sync is successful when this method is triggered
  expect(syncResult.syncStatus, SyncStatus.success);
  //when this method is triggered always switch state to indicate that sync has been successful
}

Future<void> tearDownFunc() async {
  var isExists = await Directory('test/hive').exists();
  if (isExists) {
    Directory('test/hive').deleteSync(recursive: true);
  }
}
