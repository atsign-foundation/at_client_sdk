import 'package:at_client/at_client.dart';

import 'test_util.dart';

void main() async {
  try {
    var preference = TestUtil.getBobPreference();
    var atsign = '@bob🛠';
    //1.
    var atClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(atsign, 'wavi', preference);
    var atClient = atClientManager.atClient;
    // ignore: deprecated_member_use_from_same_package
    await atClient.downloadFile(
        'file_transfer_33e44ad9-cf6f-4433-9345-078a7732c9ed', '@alice🛠',
        downloadPath: 'test/samples/output');
  } on Exception catch (e, trace) {
    print(e.toString());
    print(trace);
  }
}
