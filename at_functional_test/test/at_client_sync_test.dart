import 'package:at_client/at_client.dart';
import 'package:at_client/src/transformer/response_transformer/get_response_transformer.dart';
import 'package:at_client/src/util/sync_util.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

import 'set_encryption_keys.dart';
import 'test_utils.dart';

void main() {
  test('Verify local changes are synced to server - local ahead', () async {
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
    var transformedValue =
        await GetResponseTransformer(atClient).transform(Tuple<AtKey, String>()
          ..one = twitterKey
          ..two = (getResponse));
    // Decrypting and verifying the value from the remote secondary
    expect(transformedValue.value, value);
  });

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
}
