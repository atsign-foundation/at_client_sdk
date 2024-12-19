import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/transformer/response_transformer/get_response_transformer.dart';
import 'package:at_client/src/util/sync_util.dart';

// ignore: depend_on_referenced_packages
import 'package:at_commons/at_builders.dart';
import 'package:at_functional_test/src/sync_service.dart';
import 'package:test/test.dart';
import 'test_utils.dart';
import 'package:at_functional_test/src/config_util.dart';

void main() {
  late String atSign;
  late String sharedWithAtSign;
  final namespace = 'wavi';
  late AtClientManager atClientManager;

  setUpAll(() async {
    atSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    sharedWithAtSign = ConfigUtil.getYaml()['atSign']['secondAtSign'];
    atClientManager = await TestUtils.initAtClient(atSign, namespace);
    atClientManager.atClient.syncService.sync();
  });

  test('Verify local changes are synced to server - local ahead', () async {
    var atClient = atClientManager.atClient;
    var serverCommitId = await SyncUtil()
        .getLatestServerCommitId(atClient.getRemoteSecondary()!, '');
    expect(serverCommitId != null, true);
    // twitter.me@alice🛠
    var twitterKey = AtKey()
      ..key = 'twitter'
      ..namespace = namespace
      ..sharedWith = sharedWithAtSign;
    var value = 'alice.twitter';
    var putResult = await atClient.put(twitterKey, value);
    expect(putResult, true);
    // Waits until sync twitter key is synced to the server
    await FunctionalTestSyncService.getInstance().syncData(atClient.syncService,
        syncOptions: SyncOptions()..key = twitterKey.toString());
    // Getting server commit id after put
    var serverCommitIdAfterPut = await SyncUtil()
        .getLatestServerCommitId(atClient.getRemoteSecondary()!, '');
    // After sync successful, the serverCommitId after put should be greater
    // than server commit before put
    expect(serverCommitIdAfterPut! > serverCommitId!, true);
    // Getting value from remote secondary
    var llookupVerbBuilder = LLookupVerbBuilder()
      ..atKey = (AtKey.shared('twitter.wavi', sharedBy: atSign)
            ..sharedWith(sharedWithAtSign))
          .build()
      ..operation = 'all';
    var getResponse =
        await atClient.getRemoteSecondary()!.executeVerb(llookupVerbBuilder);
    var transformedValue =
        await GetResponseTransformer(atClient).transform(Tuple<AtKey, String>()
          ..one = twitterKey
          ..two = (getResponse));
    // Decrypting and verifying the value from the remote secondary
    expect(transformedValue.value, value);
  });

  test('Verify server changes are synced to local - server ahead', () async {
    var atClient = atClientManager.atClient;
    var localEntry = await SyncUtil().getLastSyncedEntry('', atSign: atSign);
    print('localCommitId before put method ${localEntry?.commitId}');
    expect(localEntry?.commitId != null, true);
    // twitter.me@alice🛠
    var value = 'alice.linkedin';
    var updateVerbBuilder = UpdateVerbBuilder()
      ..atKey = AtKey.public('linkedin', namespace: namespace, sharedBy: atSign)
          .build()
      ..value = value;
    var updateResponse =
        await atClient.getRemoteSecondary()!.executeVerb(updateVerbBuilder);
    expect(updateResponse.isNotEmpty, true);
    // Waits until key is synced to the remote secondary
    await FunctionalTestSyncService.getInstance().syncData(atClient.syncService,
        syncOptions: SyncOptions()..key = updateVerbBuilder.atKey.toString());
    // Getting server commit id after put
    var localEntryAfterSync =
        await SyncUtil().getLastSyncedEntry('', atSign: atSign);

    // After sync successful, the localCommitId after put should be greater
    // than localCommitId before put
    expect(localEntryAfterSync!.commitId! > localEntry!.commitId!, true);
    // Getting value from remote secondary
    var atKey = AtKey()
      ..key = 'linkedin.wavi'
      ..metadata = (Metadata()..isPublic = true)
      ..sharedBy = atSign;
    var getResponse = await atClient.get(atKey);
    expect(getResponse.value, value);
  });

  test('A test to verify sync with regex when local is ahead', () async {
    // Specifying preference in order to set syncRegex
    TestUtils.getPreference(atSign).syncRegex = namespace;
    var atClient = atClientManager.atClient;
    // Get server commit id before put operation
    var serverCommitId = await SyncUtil()
        .getLatestServerCommitId(atClient.getRemoteSecondary()!, '');
    expect(serverCommitId != null, true);
    // twitter.me@alice🛠
    var waviKey = AtKey()
      ..key = 'quora'
      ..namespace = namespace
      ..sharedWith = sharedWithAtSign;
    var value = 'alice.quora';
    var atmosphereKey = AtKey()
      ..key = 'medium'
      ..namespace = 'atmosphere'
      ..sharedWith = sharedWithAtSign;
    var valueAtmosphere = 'alice.medium';
    var putResult = await atClient.put(waviKey, value);
    expect(putResult, true);
    putResult = await atClient.put(atmosphereKey, valueAtmosphere);
    expect(putResult, true);
    // Sync Data
    await FunctionalTestSyncService.getInstance().syncData(atClient.syncService,
        syncOptions: SyncOptions()..key = atmosphereKey.toString());
    // Getting server commit id after put
    var serverCommitIdAfterPut = await SyncUtil()
        .getLatestServerCommitId(atClient.getRemoteSecondary()!, '');
    var localEntryAfterSync =
        await SyncUtil().getLastSyncedEntry(namespace, atSign: atSign);
    // As the regex is set to wavi, .mosphere key should not be synced
    expect(
        (localEntryAfterSync?.atKey!
            .contains('$sharedWithAtSign:medium.atmosphere$atSign')),
        false);
    // After sync successful, the serverCommitId after put should be greater
    // than server commit before put
    expect(serverCommitIdAfterPut! > serverCommitId!, true);
    // Getting value from remote secondary
    var llookupVerbBuilder = LLookupVerbBuilder()
      ..atKey = (AtKey()
        ..key = 'quora.wavi'
        ..sharedWith = sharedWithAtSign
        ..sharedBy = atSign)
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
    var atClient = atClientManager.atClient;
    var atKey = AtKey()
      ..key = 'discord'
      ..namespace = 'wavi'
      ..sharedWith = sharedWithAtSign
      ..sharedBy = atSign;
    var value = 'alice.discord';
    var putResult = await atClient.put(atKey, value);
    expect(putResult, true);
    await FunctionalTestSyncService.getInstance().syncData(atClient.syncService,
        syncOptions: SyncOptions()..key = atKey.toString());
    var llookupVerbBuilder = LLookupVerbBuilder()
      ..atKey = (AtKey()
        ..key = 'discord.wavi'
        ..sharedWith = sharedWithAtSign
        ..sharedBy = atSign)
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
    var atClient = atClientManager.atClient;
    var atKey = AtKey()
      ..key = 'localkey'
      ..namespace = 'wavi'
      ..isLocal = true
      ..sharedBy = atSign;
    var value = 'alice.localkey';
    var putResult = await atClient.put(atKey, value);
    expect(putResult, true);
    await FunctionalTestSyncService.getInstance()
        .syncData(atClient.syncService);
    var localEntryAfterSync =
        await SyncUtil().getLastSyncedEntry('', atSign: atSign);
    expect(localEntryAfterSync!.atKey, isNot('local:localkey.wavi$atSign'));
    print('local synced entry $localEntryAfterSync');
    var llookupVerbBuilder = LLookupVerbBuilder()
      ..atKey = (AtKey()
        ..key = 'local:localkey.wavi'
        ..sharedBy = atSign)
      ..operation = 'all';
    expect(
        () async => await atClient
            .getRemoteSecondary()!
            .executeVerb(llookupVerbBuilder),
        throwsA(predicate((dynamic e) => e is KeyNotFoundException)));
  });

  test('a test to verify multiple updates of a key is synced to the cloud',
      () async {
    var atClient = atClientManager.atClient;
    var atKey = AtKey()
      ..key = 'key1'
      ..namespace = 'wavi';
    var value1 = 'value1.key1';
    var value2 = 'value2.key1';
    var putResult = await atClient.put(atKey, value1);
    expect(putResult, true);
    putResult = await atClient.put(atKey, value2);
    expect(putResult, true);

    // Waits until atKey is synced to the remote secondary
    await FunctionalTestSyncService.getInstance().syncData(atClient.syncService,
        syncOptions: SyncOptions()..key = atKey.toString());
    var llookupVerbBuilder = LLookupVerbBuilder()
      ..atKey = (AtKey()
        ..key = 'key1.wavi'
        ..sharedBy = atSign)
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
    var atClient = atClientManager.atClient;
    AtKey atKey =
        AtKey.public('testkey', namespace: namespace, sharedBy: atSign).build();
    var value = 'localvalue';
    var putResult = await atClient.put(atKey, value);
    expect(putResult, true);
    var updateVerbBuilder = UpdateVerbBuilder()
      ..atKey = atKey
      ..value = value;
    var updateResponse =
        await atClient.getRemoteSecondary()!.executeVerb(updateVerbBuilder);
    expect(updateResponse.isNotEmpty, true);

    await FunctionalTestSyncService.getInstance().syncData(atClient.syncService,
        syncOptions: SyncOptions()..key = atKey.toString());

    var llookupVerbBuilder = LLookupVerbBuilder()
      ..atKey = (AtKey()
        ..key = 'testkey.wavi'
        ..sharedBy = atSign
        ..metadata = (Metadata()..isPublic = true))
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

  test(
      'Verify delete keys are not synced from server when skipDeletesUntil is set',
      () async {
    var atClient = atClientManager.atClient;
    var serverCommitId = await SyncUtil()
        .getLatestServerCommitId(atClient.getRemoteSecondary()!, '');
    for (int i = 0; i < 10; i++) {
      var value = 'alice.linkedin$i';
      var atKey =
          AtKey.public('linkedin_$i', namespace: namespace, sharedBy: atSign)
              .build();
      var updateVerbBuilder = UpdateVerbBuilder()
        ..atKey = atKey
        ..value = value;
      var updateResponse =
          await atClient.getRemoteSecondary()!.executeVerb(updateVerbBuilder);
      expect(updateResponse.isNotEmpty, true);
      var deleteVerbBuilder = DeleteVerbBuilder()..atKey = atKey;
      await atClient.getRemoteSecondary()!.executeVerb(deleteVerbBuilder);
    }
    var syncVerbBuilder = SyncVerbBuilder()
      ..skipDeletesUntil = (serverCommitId! + 25)
      ..commitId = serverCommitId
      ..isPaginated = true
      ..limit = 15;
    var syncResponse =
        await atClient.getRemoteSecondary()!.executeVerb(syncVerbBuilder);
    final syncJson = jsonDecode(syncResponse.replaceFirst('data:', ''));
    print(syncJson);
    Map<String, String> commitMap = {};
    for (var syncEntry in syncJson) {
      commitMap[syncEntry['atKey']] = syncEntry['operation'];
    }
    for (int i = 0; i < 9; i++) {
      expect(commitMap.containsKey('public:linkedin_$i.wavi$atSign'), false);
    }
    // last delete entry should be present
    expect(commitMap.containsKey('public:linkedin_9.wavi$atSign'), true);
  });

  test('Verify sync response when skip deletes and regex are set', () async {
    var atClient = atClientManager.atClient;
    var serverCommitId = await SyncUtil()
        .getLatestServerCommitId(atClient.getRemoteSecondary()!, '');
    for (int i = 0; i < 3; i++) {
      var value = 'alice.linkedin$i';
      var atKey =
          AtKey.public('linkedin_$i', namespace: namespace, sharedBy: atSign)
              .build();
      var updateVerbBuilder = UpdateVerbBuilder()
        ..atKey = atKey
        ..value = value;
      var updateResponse =
          await atClient.getRemoteSecondary()!.executeVerb(updateVerbBuilder);
      expect(updateResponse.isNotEmpty, true);
    }
    // update/delete keys in wavi namespace
    for (int i = 3; i < 5; i++) {
      var value = 'alice.linkedin$i';
      var atKey =
          AtKey.public('linkedin_$i', namespace: namespace, sharedBy: atSign)
              .build();
      var updateVerbBuilder = UpdateVerbBuilder()
        ..atKey = atKey
        ..value = value;
      var updateResponse =
          await atClient.getRemoteSecondary()!.executeVerb(updateVerbBuilder);
      expect(updateResponse.isNotEmpty, true);
      var deleteVerbBuilder = DeleteVerbBuilder()..atKey = atKey;
      await atClient.getRemoteSecondary()!.executeVerb(deleteVerbBuilder);
    }

    // update the keys in buzz namespace
    for (int i = 5; i < 7; i++) {
      var value = 'alice.linkedin$i';
      var atKey =
          AtKey.public('linkedin_$i', namespace: 'buzz', sharedBy: atSign)
              .build();
      var updateVerbBuilder = UpdateVerbBuilder()
        ..atKey = atKey
        ..value = value;
      var updateResponse =
          await atClient.getRemoteSecondary()!.executeVerb(updateVerbBuilder);
      expect(updateResponse.isNotEmpty, true);
    }

    // update /delete keys in buzz namespace
    for (int i = 7; i < 10; i++) {
      var value = 'alice.linkedin$i';
      var atKey =
          AtKey.public('linkedin_$i', namespace: 'buzz', sharedBy: atSign)
              .build();
      var updateVerbBuilder = UpdateVerbBuilder()
        ..atKey = atKey
        ..value = value;
      var updateResponse =
          await atClient.getRemoteSecondary()!.executeVerb(updateVerbBuilder);
      expect(updateResponse.isNotEmpty, true);
      var deleteVerbBuilder = DeleteVerbBuilder()..atKey = atKey;
      await atClient.getRemoteSecondary()!.executeVerb(deleteVerbBuilder);
    }
    var syncVerbBuilder = SyncVerbBuilder()
      ..skipDeletesUntil = (serverCommitId! + 25)
      ..regex = '.wavi'
      ..commitId = serverCommitId
      ..isPaginated = true
      ..limit = 15;
    var syncResponse =
        await atClient.getRemoteSecondary()!.executeVerb(syncVerbBuilder);
    final syncJson = jsonDecode(syncResponse.replaceFirst('data:', ''));
    print(syncJson);
    Map<String, String> commitMap = {};
    for (var syncEntry in syncJson) {
      commitMap[syncEntry['atKey']] = syncEntry['operation'];
    }
    for (int i = 0; i < 3; i++) {
      expect(commitMap.containsKey('public:linkedin_$i.wavi$atSign'), true);
    }
    for (int i = 3; i < 5; i++) {
      expect(commitMap.containsKey('public:linkedin_$i.wavi$atSign'), false);
    }
    for (int i = 5; i < 7; i++) {
      expect(commitMap.containsKey('public:linkedin_$i.wavi$atSign'), false);
    }
    // last delete entry should NOT be present due to namespace buzz not matching
    expect(commitMap.containsKey('public:linkedin_9.buzz$atSign'), false);
  });
}
