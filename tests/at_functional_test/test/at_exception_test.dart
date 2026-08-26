import 'package:at_client/at_client.dart';
// ignore: depend_on_referenced_packages
import 'package:at_functional_test/src/config_util.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  late AtClientManager atClientManager;
  late AtClient atClient;
  late String atSign;
  late String sharedWithAtSign;
  final namespace = 'wavi';

  setUpAll(() async {
    atSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    sharedWithAtSign = ConfigUtil.getYaml()['atSign']['secondAtSign'];
    atClientManager = await TestUtils.initAtClient(atSign, namespace,
        posture: PqPosture.legacy);
    atClientManager.atClient.syncService.sync();
    atClient = atClientManager.atClient;
  });

  test('Verify KeyNotFoundException for local secondary', () async {
    var key = AtKey()
      ..key = 'phone.wavi'
      ..sharedBy = sharedWithAtSign;
    expect(() async => await atClient.get(key),
        throwsA(predicate((dynamic e) => e is AtClientException)));
  });

  test('Verify Key on a non existent atsign', () async {
    var key = AtKey()
      ..key = 'phone.wavi'
      ..sharedBy = '@nonexistentAtSign';
    expect(() async => await atClient.get(key),
        throwsA(predicate((dynamic e) => e is AtClientException)));
  });
}
