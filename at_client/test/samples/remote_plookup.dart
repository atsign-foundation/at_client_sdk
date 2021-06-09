import 'dart:io';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/client/at_client_impl.dart';
import 'test_util.dart';

void main() async {
  try {
    await AtClientImpl.createClient(
        '@alice', null, TestUtil.getPreferenceRemote());
    var atClient = await (AtClientImpl.getClient('@alice'));
    if(atClient == null) {
      print('unable to create at client instance');
      return;
    }
    var result = await atClient
        .getRemoteSecondary()!
        .executeCommand('plookup:publickey@bob\n', auth: true);
    print(result);
  } on Exception catch (e, trace) {
    print(e.toString());
    print(trace);
  }
  exit(1);
}
