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
/// The unit tests pin the resolution rule; what they cannot show is that the
/// wiring actually runs during `AtClientImpl` construction — a mock never goes
/// through `_init`, so an era default that was never adopted would still pass
/// every one of them. That gap is exactly the kind this branch has been bitten
/// by twice: a code path that looks wired, is unit-green, and never executes.
void main() {
  late String atSign;
  const namespace = 'wavi';

  setUpAll(() async {
    atSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
  });

  test('a client that named no CryptoConfig still resolves the nskey providers',
      () async {
    final manager = await TestUtils.initAtClient(atSign, namespace,
        atKeysIo: InMemoryAtKeysIo(), posture: PqPosture.legacy);
    final client = manager.atClient;

    // Checked, not assumed: if the harness had named a config the assertions
    // below would be about the app's choice, not the SDK's default.
    expect(client.getPreferences()?.crypto,
        same(const CryptoConfig.eraDefault()),
        reason: 'this test is about what the SDK supplies when the app names '
            'nothing');

    final resolved = CryptoConfig.forClient(client);

    expect(resolved.lookup(symmetricAesGcmCryptoProviderId), isNotNull,
        reason: 'an inbound PQ record names this provider — a client that '
            'cannot resolve it fails on data already sent to it');
    expect(resolved.lookup(nskeyCryptoProviderId), isNotNull,
        reason: 'and the content key it cites is conveyed under this one');
    expect(resolved.defaultProviderId, legacyCryptoProviderId,
        reason: 'final 3.x reads PQ and still writes legacy; moving this is '
            'the 4.x step and a fleet-wide commitment');
  });
}
