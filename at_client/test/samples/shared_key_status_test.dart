import 'package:at_client/src/client/at_client_impl.dart';
import 'package:at_commons/at_commons.dart';
import 'test_util.dart';

void main() async {
  var atsign = '@alice';
  var preference = TestUtil.getAlicePreference();
  await AtClientImpl.createClient(atsign, null, preference);
  var atClient = await AtClientImpl.getClient(atsign);
  await atClient!.getSyncManager()!.sync(_onSyncDone);
  var key = AtKey()..key = 'k1'
    ..sharedBy = '@alice'
    ..sharedWith = '@bob';
  var put_resullt = await atClient.put(key, 'v1');
  print(put_resullt);
  var getmeta_result =  await atClient.getMeta(key);
  print(getmeta_result);
  print(getmeta_result!.sharedKeyStatus);
}

void _onSyncDone(var syncManager){
  print('sync done');
}