import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_functional_test/src/at_demo_credentials.dart' as at_demos;
import 'package:at_functional_test/src/config_util.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

late String atSign;

void main() {
  String namespace = 'wavi';
  late AtClientManager atClientManager;

  setUpAll(() async {
    atSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    atClientManager = await TestUtils.initAtClient(atSign, namespace);
  });

  test(
      'Verify the update and llookup using execute command functionality over a socket connection by passing AtLookupSecureSocketFactory',
      () async {
    final atClient = atClientManager.atClient;
    final atChopsKeys = AtChopsKeys.create(
        null,
        AtPkamKeyPair.create(at_demos.pkamPublicKeyMap[atSign]!,
            at_demos.pkamPrivateKeyMap[atSign]!));
    final atChops = AtChopsImpl(atChopsKeys);
    atClient.atChops = atChops;
    var preference = TestUtils.getPreference(atSign);
    var remoteSecondary = RemoteSecondary(atSign, preference,
        atConnectionFactory: AtLookupSecureSocketFactory());

    remoteSecondary.atLookUp.atChops = atClient.atChops;

    var phoneKey = AtKey()
      ..key = 'mobile'
      ..sharedBy = atSign
      ..metadata = (Metadata()..isPublic = true);
    var value = '+91 990 123 8921';

    var response = await remoteSecondary
        .executeCommand('update:$phoneKey $value\n', auth: true);
    assert((!response!.contains('Invalid syntax')) &&
        (!response.contains('null')));
    response =
        await remoteSecondary.executeCommand('llookup:$phoneKey\n', auth: true);
    expect(response, contains('data:$value'));
  });

   test(
      'Verify the update and llookup using execute command functionality over a socket connection without passing factory should default to a secure socket connection',
      () async {
    final atClient = atClientManager.atClient;
    final atChopsKeys = AtChopsKeys.create(
        null,
        AtPkamKeyPair.create(at_demos.pkamPublicKeyMap[atSign]!,
            at_demos.pkamPrivateKeyMap[atSign]!));
    final atChops = AtChopsImpl(atChopsKeys);
    atClient.atChops = atChops;
    var preference = TestUtils.getPreference(atSign);
    var remoteSecondary = RemoteSecondary(atSign, preference);

    remoteSecondary.atLookUp.atChops = atClient.atChops;

    var phoneKey = AtKey()
      ..key = 'contact-no'
      ..sharedBy = atSign
      ..metadata = (Metadata()..isPublic = true);
    var value = '+1 219 123 8921';

    var response = await remoteSecondary
        .executeCommand('update:$phoneKey $value\n', auth: true);
    assert((!response!.contains('Invalid syntax')) &&
        (!response.contains('null')));
    response =
        await remoteSecondary.executeCommand('llookup:$phoneKey\n', auth: true);
    expect(response, contains('data:$value'));
  });

  test(
      'Verify the update and llookup using executeVerb functionality over a WebSocket connection',
      () async {
    final atClient = atClientManager.atClient;
    final atChopsKeys = AtChopsKeys.create(
        null,
        AtPkamKeyPair.create(at_demos.pkamPublicKeyMap[atSign]!,
            at_demos.pkamPrivateKeyMap[atSign]!));
    final atChops = AtChopsImpl(atChopsKeys);
    atClient.atChops = atChops;
    var preference = TestUtils.getPreference(atSign);
    // create remote secondary Instance with useWebsocket true
    var remoteSecondary = RemoteSecondary(atSign, preference,
        atConnectionFactory: AtLookupWebSocketFactory());

    remoteSecondary.atLookUp.atChops = atClient.atChops;
    String encryptedValue = 'NwrD1d1m8qSNM/5KbGAR4Q==';
    final updateVerbBuilder = UpdateVerbBuilder()
      ..atKey = (AtKey()
        ..key = 'username.wavi'
        ..sharedBy = atSign
        ..metadata = (Metadata()..isEncrypted = true))
      ..value = encryptedValue;

    var response = await remoteSecondary.executeVerb(updateVerbBuilder);
    assert(
        (!response.contains('Invalid syntax')) && (!response.contains('null')));

    final llookupVerbBuilder = LLookupVerbBuilder()
      ..atKey = (AtKey()
        ..key = 'username.wavi'
        ..sharedBy = atSign);
    response = await remoteSecondary.executeVerb(llookupVerbBuilder);
    expect(response, contains('data:$encryptedValue'));
  });

  test(
      'Verify the update and llookup using execute command functionality over a WebSocket connection',
      () async {
    final atClient = atClientManager.atClient;
    final atChopsKeys = AtChopsKeys.create(
        null,
        AtPkamKeyPair.create(at_demos.pkamPublicKeyMap[atSign]!,
            at_demos.pkamPrivateKeyMap[atSign]!));
    final atChops = AtChopsImpl(atChopsKeys);
    atClient.atChops = atChops;
    var preference = TestUtils.getPreference(atSign);
    // create remote secondary Instance with useWebsocket true
    var remoteSecondary = RemoteSecondary(atSign, preference,
        atConnectionFactory: AtLookupWebSocketFactory());

    remoteSecondary.atLookUp.atChops = atClient.atChops;

    var phoneKey = AtKey()
      ..key = 'phone'
      ..sharedBy = atSign
      ..metadata = (Metadata()..isPublic = true);
    var value = '+91 887 888 3435';

    var response = await remoteSecondary
        .executeCommand('update:$phoneKey $value\n', auth: true);
    assert((!response!.contains('Invalid syntax')) &&
        (!response.contains('null')));
    response =
        await remoteSecondary.executeCommand('llookup:$phoneKey\n', auth: true);
    expect(response, contains('data:$value'));
  });

 
}
