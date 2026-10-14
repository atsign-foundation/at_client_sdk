import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:at_functional_test/src/config_util.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

/// A get, against a live atServer, of a record written the way at_client
/// 3.2.0 wrote it: legacy ciphertext with no isEncrypted and no
/// ivNonce.
///
/// Catalogue: features/at_client/get_legacy_ciphertext_flagged_unencrypted.feature
void main() {
  TestUtils.isolateStorage('legacy_ciphertext_flagged_unencrypted_live_test');
  late AtClient client;
  late String atSign;
  final runId = DateTime.now().microsecondsSinceEpoch;
  final namespace = 'legacyflag$runId';
  const group = '{"name":"admins","userAtSigns":["@bob"],"daemonAtSigns":[]}';

  setUpAll(() async {
    atSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    client = (await TestUtils.initAtClient(atSign, namespace,
            posture: PqPosture.legacy))
        .atClient;
  });

  test('Legacy ciphertext flagged isEncrypted false is decrypted', () async {
    final key = '2.groups.$namespace$atSign';
    final selfKey = await client.getLocalSecondary()!.getEncryptionSelfKey();
    final stored = EncryptionUtil.encryptValue(group, selfKey!);
    final remote = client.getRemoteSecondary()!;
    await remote.executeCommand('update:$key $stored\n', auth: true);
    final meta = jsonDecode((await remote.executeCommand('llookup:meta:$key\n',
            auth: true))!
        .replaceFirst('data:', '')) as Map<String, dynamic>;
    expect(meta['isEncrypted'], isFalse,
        reason: 'the control: the atServer serves a missing flag as false');
    expect(meta['ivNonce'], isNull);

    final got = await client.get(AtKey.fromString(key),
        getRequestOptions: GetRequestOptions()..useRemoteAtServer = true);

    expect(got.value, group);
  });
}
