import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:mocktail/mocktail.dart';

class MockAtLookup extends Mock implements AtLookUp {}

class MockAtLookUpImpl extends Mock implements AtLookupImpl {}

class MockAtChops extends Mock implements AtChops {}

class MockAtChopsKeys extends Mock implements AtChopsKeys {}

class MockSecondaryAddressFinder extends Mock
    implements SecondaryAddressFinder {}

class MockRemoteSecondary extends Mock implements RemoteSecondary {}

class MockLocalSecondary extends Mock implements LocalSecondary {}

class MockCryptoProvider extends Mock implements CryptoProvider {}

class FakeCryptoProvider extends Fake implements CryptoProvider {}

class MockAtClientManager extends Mock implements AtClientManager {}

class MockAtClient extends Mock implements AtClient {
  // A stable, mutable preference (matching the real getPreferences(), which
  // returns the live instance) so tests can set `.crypto` to inject a
  // CryptoConfig that CryptoRuntime resolves against.
  final AtClientPreference _preference = AtClientPreference()
    ..namespace = 'wavi';

  @override
  AtClientPreference getPreferences() => _preference;
}

/// A client that refuses to encrypt new data with the legacy provider.
///
/// Its own class rather than a cascade on [MockAtClient] because
/// `disallowLegacyEncryption` is final — a flag governing what a client may
/// write must not be flippable mid-run.
class StrictMockAtClient extends Mock implements AtClient {
  final AtClientPreference _preference =
      AtClientPreference(disallowLegacyEncryption: true);

  @override
  AtClientPreference getPreferences() => _preference;
}

class MockAtClientImpl extends Mock implements AtClientImpl {
  // AtClientImpl keeps a concrete resolved getter (the AtClient interface
  // carries none); `implements` erases its body, and an unstubbed mocktail
  // getter returns null into a non-nullable type. Restore the default.
  @override
  SigningAlgoType get signingAlgoType => SigningAlgoType.rsa2048;
}

/// `AtKeysIo` is `sealed`, but that only restricts direct subtyping of the
/// base — `WrittenAtKeysIo` is an ordinary `abstract class`, so extending it
/// outside at_auth is legal. Both methods throw so any accidental key IO in
/// the S-2 seam fails loudly (the stub doubles as the behaviour-neutrality
/// proof). Deliberately does NOT override `flush` (not present on the
/// at_auth version this branch compiles against).
class StubAtKeysIo extends WrittenAtKeysIo {
  @override
  Future<AtKeys> read(String atSign) => throw UnimplementedError();

  @override
  Future<void> write(String atSign, AtKeys atKeys) =>
      throw UnimplementedError();
}

class FakeLookupVerbBuilder extends Fake implements LookupVerbBuilder {}
