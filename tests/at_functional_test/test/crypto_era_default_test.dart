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
  TestUtils.isolateStorage('crypto_era_default_test');
  late String atSign;
  const namespace = 'wavi';

  setUpAll(() async {
    atSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
  });

  test('a client that named no CryptoConfig gets the default posture\'s providers',
      () async {
    // The SDK's default, read rather than named: this test's subject IS the
    // default, so a named constant would leave it passing while measuring a
    // posture the SDK had moved on from.
    final manager = await TestUtils.initAtClient(atSign, namespace,
        atKeysIo: InMemoryAtKeysIo(),
        posture: TestUtils.sdkDefaultPosture);
    final client = manager.atClient;

    // Checked, not assumed: if the harness had named a config the assertions
    // below would be about the app's choice, not the SDK's default.
    expect(client.getPreferences()?.crypto,
        same(const CryptoConfig.eraDefault()),
        reason: 'this test is about what the SDK supplies when the app names '
            'nothing');

    final resolved = CryptoConfig.forClient(client);

    // ⚠️ **These two asserted `isNotNull` until 2026-09-08**, when the shipped
    // default was `pqReady`. It is `legacy` again, which configures no
    // post-quantum providers at all — so an inbound record naming one has
    // nothing to resolve to and the read throws naming the id, exactly as a
    // build predating those providers does. That is the point of the stage,
    // not a gap in it.
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

    // The control, and it is what stops the three rows above passing for a
    // build that dropped the providers everywhere. A stage that DOES configure
    // them still resolves both, over the same client construction.
    final ready = await TestUtils.initAtClient(atSign, namespace,
        atKeysIo: InMemoryAtKeysIo(), posture: PqPosture.pqReady);
    final readyConfig = CryptoConfig.forClient(ready.atClient);
    expect(readyConfig.lookup(symmetricAesGcmCryptoProviderId), isNotNull,
        reason: 'an inbound PQ record names this provider, and a client at a '
            'stage that reads post-quantum data must resolve it');
    expect(readyConfig.lookup(nskeyCryptoProviderId), isNotNull);
  });
}
