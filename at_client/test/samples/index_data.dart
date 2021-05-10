import 'dart:io';
import 'package:at_client/src/client/at_client_impl.dart';
import 'package:at_commons/at_builders.dart';
import 'test_util.dart';

void main() async {
  try {
    var atsign = '@sitaram';
    var preference = TestUtil.getPreferenceRemote();
    await AtClientImpl.createClient(atsign, null, preference);
    var atClient = await AtClientImpl.getClient(atsign);
    atClient.getSyncManager().init(atsign, preference,
        atClient.getRemoteSecondary(), atClient.getLocalSecondary());
    var builder = IndexVerbBuilder()..data = '{"name" : "sita", "location" : "india" }';
    var result = await atClient
        .getRemoteSecondary()
        .executeVerb(builder);
    print('index verb result ${result}');
  } on Exception catch (e, trace) {
    print(e.toString());
    print(trace);
  }
  exit(1);
}