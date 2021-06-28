import 'package:at_client/at_client.dart';

import 'test_util.dart';

void main() async {
  try {
    var preference = TestUtil.getBobPreference();
    var atsign = '@bob🛠';
    //1.
    await AtClientImpl.createClient(atsign, 'me', preference);
    var atClient = await (AtClientImpl.getClient(atsign));
    if (atClient == null) {
      print('unable to create at client instance');
      return;
    }
    await atClient.downloadFile(
        'file_transfer_33e44ad9-cf6f-4433-9345-078a7732c9ed', '@alice🛠',
        downloadPath: 'test/samples/output');
  } on Exception catch (e, trace) {
    print(e.toString());
    print(trace);
  }
}
