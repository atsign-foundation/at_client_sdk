import 'dart:convert';
import 'dart:typed_data';

import 'package:at_client/at_client.dart';
import 'package:crypton/crypton.dart';
import 'package:test/test.dart';
import 'package:at_chops/at_chops.dart';

import 'package:at_functional_test/src/at_demo_credentials.dart' as at_demos;
import 'test_utils.dart';

String atSign = '@alice🛠';
String namespace = 'wavi';

void main() {
  late AtClientManager atClientManager;

  setUpAll(() async {
    atClientManager = await TestUtils.initAtClient(atSign, namespace);
  });

  test('Verify pkam auth', () async {
    final atClient = atClientManager.atClient;
    var fromResponse = await atClient
        .getRemoteSecondary()!
        .executeCommand('from:$atSign\n', auth: true);
    expect(fromResponse!.isNotEmpty, true);
    fromResponse = fromResponse.replaceAll('data:', '');
    var pkamDigest = generatePKAMDigest(atSign, fromResponse);
    var pkamResult = await atClient
        .getRemoteSecondary()!
        .executeCommand('pkam:$pkamDigest\n', auth: true);
    expect(pkamResult, 'data:success');
  });

  test('Verify pkam auth with atchops', () async {
    final atClient = atClientManager.atClient;
    final atChopsKeys = AtChopsKeys.create(
        null,
        AtPkamKeyPair.create(at_demos.pkamPublicKeyMap[atSign]!,
            at_demos.pkamPrivateKeyMap[atSign]!));
    final atChops = AtChopsImpl(atChopsKeys);
    atClient.atChops = atChops;
    atClient.getRemoteSecondary()!.atLookUp.atChops = atClient.atChops;
    var fromResponse = await atClient
        .getRemoteSecondary()!
        .executeCommand('from:$atSign\n', auth: true);
    expect(fromResponse!.isNotEmpty, true);
    fromResponse = fromResponse.replaceAll('data:', '');
    var pkamDigest = generatePKAMDigest(atSign, fromResponse);
    var pkamResult = await atClient
        .getRemoteSecondary()!
        .executeCommand('pkam:$pkamDigest\n', auth: true);
    expect(pkamResult, 'data:success');
  });
}

String generatePKAMDigest(String atsign, String challenge) {
  var privateKey = at_demos.pkamPrivateKeyMap[atSign]!;
  privateKey = privateKey.trim();
  var key = RSAPrivateKey.fromString(privateKey);
  challenge = challenge.trim();
  var sign =
      key.createSHA256Signature(Uint8List.fromList(utf8.encode(challenge)));
  return base64Encode(sign);
}
