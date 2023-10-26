import 'package:at_client/src/manager/at_client_manager.dart';
import 'package:at_client/src/client/at_client_spec.dart';

import 'package:test/test.dart';
import 'package:at_commons/at_commons.dart';
import 'test_utils.dart';

void main() {
  late AtClientManager atClientManager;
  late AtClient atClient;
  var sharedWithAtSign = '@bob🛠';
  var currentAtSign = '@alice🛠';
  var namespace = 'wavi';

  setUpAll(() async {
    atClientManager = await TestUtils.initAtClient(currentAtSign, namespace);
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
