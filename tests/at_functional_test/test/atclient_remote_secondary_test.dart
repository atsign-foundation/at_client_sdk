import 'package:at_client/at_client.dart';
import 'package:at_commons/src/verb/llookup_verb_builder.dart';
import 'package:at_commons/src/verb/update_verb_builder.dart';
import 'package:at_functional_test/src/config_util.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  TestUtils.isolateStorage('atclient_remote_secondary_test');
  late AtClientManager atClientManager;
  late String atSign;
  final namespace = 'wavi';

  setUpAll(() async {
    atSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    atClientManager = await TestUtils.initAtClient(atSign, namespace,
        posture: PqPosture.legacy);
  });

  test('sequence of put and get results', () async {
    var value = '+1 1111';
    final phoneUpdateBuilder = UpdateVerbBuilder()
      ..atKey = (AtKey()
        ..key = 'phone'
        ..sharedBy = atSign
        ..metadata = (Metadata()..isPublic = true))
      ..value = value;
    await atClientManager.atClient
        .getRemoteSecondary()!
        .executeVerb(phoneUpdateBuilder);
    final phoneLookupVerbBuilder = LLookupVerbBuilder()
      ..atKey = (AtKey()
        ..key = 'phone'
        ..sharedBy = atSign
        ..metadata = (Metadata()..isPublic = true));

    final emailUpdateBuilder = UpdateVerbBuilder()
      ..atKey = (AtKey()
        ..key = 'email'
        ..sharedBy = atSign
        ..metadata = (Metadata()..isPublic = true))
      ..value = 'alice@gmail.com';
    await atClientManager.atClient
        .getRemoteSecondary()!
        .executeVerb(emailUpdateBuilder);
    final emailLookupVerbBuilder = LLookupVerbBuilder()
      ..atKey = (AtKey()
        ..key = 'email'
        ..sharedBy = atSign
        ..metadata = (Metadata()..isPublic = true));

    final locationUpdateBuilder = UpdateVerbBuilder()
      ..atKey = (AtKey()
        ..key = 'location'
        ..sharedBy = atSign
        ..metadata = (Metadata()..isPublic = true))
      ..value = 'newyork';
    await atClientManager.atClient
        .getRemoteSecondary()!
        .executeVerb(locationUpdateBuilder);
    final locationLookupVerbBuilder = LLookupVerbBuilder()
      ..atKey = (AtKey()
        ..key = 'location'
        ..sharedBy = atSign
        ..metadata = (Metadata()..isPublic = true));
    final phoneFuture = atClientManager.atClient
        .getRemoteSecondary()!
        .executeVerb(phoneLookupVerbBuilder);
    final emailFuture = atClientManager.atClient
        .getRemoteSecondary()!
        .executeVerb(emailLookupVerbBuilder);
    final locationFuture = atClientManager.atClient
        .getRemoteSecondary()!
        .executeVerb(locationLookupVerbBuilder);
    expect(await phoneFuture, 'data:+1 1111');
    expect(await emailFuture, 'data:alice@gmail.com');
    expect(await locationFuture, 'data:newyork');
  });
}
