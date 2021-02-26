import 'dart:io';
import 'package:at_client/src/client/BatchVerbBuilder.dart';
import 'package:at_client/src/client/at_client_impl.dart';
import 'package:at_commons/at_commons.dart';
import 'test_util.dart';

void main() async {
  try {
    var atSign = '@murali';
    atSign = atSign.trim();
    await AtClientImpl.createClient(
        atSign, null, TestUtil.getAlicePreference());
    AtClientImpl atClient = await AtClientImpl.getClient(atSign);

    // await atClient.getSyncManager().init('@murali', TestUtil.getAlicePreference(),
    //     atClient.getRemoteSecondary(), atClient.getLocalSecondary());

    var atKey = AtKey()..key = 'location';
    var atKey1 = AtKey()..key = 'firstname';
    var atKey2 = AtKey()..key = 'lastname';
    var batch_verb = atClient.buildBatchCommand()
      ..get(atKey)
      ..get(atKey1)
      ..delete(atKey2);
    print(batch_verb.batch());
    var batch_response = await atClient.runBatch(batch_verb);
    print(batch_response);
  } on Exception catch (e, trace) {
    print(e.toString());
    print(trace);
  }
  exit(1);
}
