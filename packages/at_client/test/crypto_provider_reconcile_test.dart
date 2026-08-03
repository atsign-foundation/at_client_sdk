import 'package:at_client/at_client.dart';
import 'package:test/test.dart';

/// Minimal provider — registration is all this test exercises; encrypt/decrypt
/// are never invoked here.
class _StubProvider extends CryptoProvider {
  @override
  final String id;

  _StubProvider(this.id);

  @override
  Future<String> encrypt(
      CryptoContext context, AtKey atKey, String value) async {
    atKey.metadata.appMetadata = AppMetadata(providerId: id);
    return 'x';
  }

  @override
  Future<String> decrypt(
          CryptoContext context, AtKey atKey, String value) async =>
      'x';
}

void main() {
  // Regression for the pluggable-crypto e2e flake (xl-pluggable / PR #1930):
  // setCurrentAtSign's idempotency short-circuit (same atSign, no atChops/
  // atLookUp/enrollmentId override) returns the cached AtClient WITHOUT going
  // through AtClientImpl.create(), which is the only place the new preference's
  // crypto config gets adopted onto a re-used client. A same-atSign re-set
  // carrying a NEW provider config therefore silently dropped it, surfacing
  // intermittently in CI as `CryptoProviderNotRegistered` on the next put. The
  // fix adopts the new crypto config in the short-circuit path too.
  group('setCurrentAtSign crypto-config adoption', () {
    AtClientPreference prefWith(String providerId) => AtClientPreference()
      ..hiveStoragePath = 'test/hive'
      ..commitLogPath = 'test/hive/path'
      ..crypto = CryptoConfig(
          defaultProviderId: 'legacy', providers: [_StubProvider(providerId)]);

    test(
        're-setting the same atSign with a new provider config adopts it via '
        'the short-circuit (does not drop it)', () async {
      final atSign = '@cryptoreconcile';
      final manager = AtClientManager(atSign);

      // First set: create() configures providerA during _init.
      await manager.setCurrentAtSign(atSign, 'wavi', prefWith('providerA'));
      final firstClient = manager.atClient as AtClientImpl;
      expect(CryptoConfig.forClient(firstClient).lookup('providerA'), isNotNull,
          reason: 'first create() must adopt the preference provider');

      // Second set: SAME atSign, no override -> idempotency short-circuit.
      await manager.setCurrentAtSign(atSign, 'wavi', prefWith('providerB'));

      // The short-circuit must reuse the same client (no stop/recreate) AND
      // adopt the new crypto config onto it.
      expect(identical(manager.atClient, firstClient), isTrue,
          reason: 'short-circuit should reuse the cached client');
      expect(CryptoConfig.forClient(firstClient).lookup('providerB'), isNotNull,
          reason: 'short-circuit must adopt the new preference crypto config');
    });
  });
}
