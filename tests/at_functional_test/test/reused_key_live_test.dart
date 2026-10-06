import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:at_functional_test/src/config_util.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

/// One key object reused for several legacy sends: each encryption takes a new
/// IV, so no two values share a keystream.
void main() {
  TestUtils.isolateStorage('reused_key_live_test');
  late String me;
  late String peer;
  final runId = DateTime.now().microsecondsSinceEpoch;
  const first = 'AAAAAAAAAAAAAAAA';
  const second = 'BBBBBBBBBBBBBBBB';

  setUpAll(() async {
    me = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    peer = ConfigUtil.getYaml()['atSign']['secondAtSign'];
    await TestUtils.initAtClient(peer, 'wavi', posture: PqPosture.legacy);
    await TestUtils.initAtClient(me, 'wavi', posture: PqPosture.legacy);
  });

  List<int> xor16(List<int> a, List<int> b) =>
      [for (var i = 0; i < 16; i++) a[i] ^ b[i]];

  test('a reused key notifies with a new IV each time', () async {
    final client = AtClientManager.getInstance().atClient;
    final key =
        (AtKey.shared('reusednotify$runId', namespace: 'wavi', sharedBy: me)
              ..sharedWith(peer))
            .build();

    Future<(String?, List<int>)> send(String value) async {
      final result = await client.notificationService.notify(
          NotificationParams.forUpdate(key, value: value),
          waitForFinalDeliveryStatus: false,
          checkForFinalDeliveryStatus: false);
      expect(result.atClientException, isNull);
      final sent =
          await client.notificationService.fetch(result.notificationID);
      return (key.metadata.ivNonce, base64Decode(sent.value!));
    }

    final (firstIv, firstCiphertext) = await send(first);
    final (secondIv, secondCiphertext) = await send(second);

    expect(firstIv, isNotNull);
    expect(secondIv, isNot(firstIv),
        reason: 'the second send must not reuse the IV the first left on the '
            'key');
    expect(xor16(firstCiphertext, secondCiphertext),
        isNot(xor16(utf8.encode(first), utf8.encode(second))),
        reason: 'two values under one shared key and one IV XOR to the XOR of '
            'their plaintexts');
  });

  test('a reused key puts with a new IV each time', () async {
    final client = AtClientManager.getInstance().atClient;
    final key =
        (AtKey.shared('reusedput$runId', namespace: 'wavi', sharedBy: me)
              ..sharedWith(peer))
            .build();
    final remote = PutRequestOptions()..useRemoteAtServer = true;

    await client.put(key, first, putRequestOptions: remote);
    final firstIv = key.metadata.ivNonce;
    await client.put(key, second, putRequestOptions: remote);
    final secondIv = key.metadata.ivNonce;

    expect(firstIv, isNotNull);
    expect(secondIv, isNot(firstIv),
        reason: 'the second put must not reuse the IV the first left on the '
            'key');
    final read = await client.get(key,
        getRequestOptions: GetRequestOptions()..useRemoteAtServer = true);
    expect(read.value, second,
        reason: 'and the value still reads back under the IV it was sent with');
  });
}
