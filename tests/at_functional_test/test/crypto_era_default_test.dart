// The nskey surface is @experimental; exercising it from another package is
// the point of this file.
// ignore_for_file: experimental_member_use

@Tags(['pq'])
library;

import 'package:at_auth/at_auth.dart';
import 'package:at_client/at_client.dart';
import 'package:at_functional_test/src/config_util.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

/// The era default, on a real constructed client rather than a mock.
///
/// A mock never runs `AtClientImpl._init`, so the unit tests pin the resolution
/// rule but stay green for an era default that construction never adopts.
void main() {
  TestUtils.isolateStorage('crypto_era_default_test');
  late String atSign;
  const namespace = 'wavi';

  setUpAll(() async {
    atSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
  });

  test('a client that named no CryptoConfig gets the default posture\'s providers',
      () async {
    // NOTE: read the SDK's default rather than naming a posture — a named
    // constant keeps passing while measuring a default the SDK has moved off.
    final manager = await TestUtils.initAtClient(atSign, namespace,
        atKeysIo: InMemoryAtKeysIo(),
        posture: TestUtils.sdkDefaultPosture);
    final client = manager.atClient;

    expect(client.getPreferences()?.crypto,
        same(const CryptoConfig.eraDefault()),
        reason: 'this test is about what the SDK supplies when the app names '
            'nothing');

    final resolved = CryptoConfig.forClient(client);

    expect(resolved.lookup(symmetricAesGcmCryptoProviderId), isNull,
        reason: 'the shipped default stands in for a build from before these '
            'schemes, so a record stamped with one does not open here');
    expect(resolved.lookup(nskeyCryptoProviderId), isNull,
        reason: 'and the content key it cites is unreachable for the same '
            'reason');
    expect(resolved.defaultProviderId, legacyCryptoProviderId,
        reason: 'the shipped default writes legacy whichever stage it is — '
            'legacy and pqReady both carry writesPqByDefault false, and it is '
            'pqActive that moves it, which is why this reads the default '
            'rather than naming one');

    // NOTE: control — without a stage that does configure the providers, the
    // assertions above also pass for a build that dropped them everywhere.
    final ready = await TestUtils.initAtClient(atSign, namespace,
        atKeysIo: InMemoryAtKeysIo(), posture: PqPosture.pqReady);
    final readyConfig = CryptoConfig.forClient(ready.atClient);
    expect(readyConfig.lookup(symmetricAesGcmCryptoProviderId), isNotNull,
        reason: 'an inbound PQ record names this provider, and a client at a '
            'stage that reads post-quantum data must resolve it');
    expect(readyConfig.lookup(nskeyCryptoProviderId), isNotNull);
  });
}
