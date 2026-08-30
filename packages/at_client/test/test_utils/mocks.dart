/// The shared mocks and fakes. A test file declaring its own copy of one of
/// these shadows the shared version silently — a local declaration wins over
/// an import with no analyzer complaint — so the two drift apart unnoticed.
///
/// Four families are deliberately NOT here, because their per-file versions
/// carry behaviour rather than duplicating it, and moving them would change
/// what their tests exercise:
///
/// - `MockAtClient` in most files is bare, while the version below bakes in a
///   preference. A concrete override cannot be intercepted by `when(...)`, so
///   adopting it would silently disable the `getPreferences` stubs that a
///   dozen files rely on.
/// - `MockAtClientImpl` and `MockLocalSecondary` in `notification_service_test`
///   carry a keystore and several overrides the shared versions do not.
/// - `MockSecondaryKeyStore` in `local_secondary_test` carries its own fixture
///   keys.
///
/// Before adding a family here, check that every copy is genuinely identical:
/// a copy that grew a method is an intentional difference, not a duplicate.
library;

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:mocktail/mocktail.dart';

class MockAtLookUp extends Mock implements AtLookUp {}

class MockAtLookupImpl extends Mock implements AtLookupImpl {}

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
  /// [keyEstablishmentAlgorithms] is a constructor argument rather than
  /// something a test sets afterwards because the field is final — and
  /// `getPreferences()` is a concrete override here, so `when(() =>
  /// client.getPreferences())` does not reach `noSuchMethod` and silently
  /// stubs nothing. Both routes a test would reach for are closed; this is
  /// the one that works.
  /// [posture] is a constructor argument for the same reason: it is final on
  /// the preference, and the preference itself is unreachable through
  /// `when(...)`. A test needing a client that configures no post-quantum
  /// providers names `PqPosture.legacy` here; the default stays `pqReady`,
  /// which is `AtClientPreference`'s own.
  MockAtClient({List<String>? keyEstablishmentAlgorithms, PqPosture? posture})
      : _preference = AtClientPreference(
            posture: posture ?? PqPosture.pqReady,
            keyEstablishmentAlgorithms: keyEstablishmentAlgorithms)
          ..namespace = 'wavi';

  // A stable, mutable preference (matching the real getPreferences(), which
  // returns the live instance) so tests can set `.crypto` to inject a
  // CryptoConfig that CryptoRuntime resolves against.
  final AtClientPreference _preference;

  @override
  AtClientPreference getPreferences() => _preference;
}

/// A client that refuses to encrypt new data with the legacy provider.
///
/// Its own class rather than a cascade on [MockAtClient] because
/// `disallowLegacyEncryption` is final and posture-only — a flag governing
/// what a client may write must not be flippable mid-run.
class StrictMockAtClient extends Mock implements AtClient {
  final AtClientPreference _preference =
      AtClientPreference(posture: PqPosture.pqActive);

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

class MockSyncService extends Mock implements SyncService {}

class MockNotificationService extends Mock implements NotificationService {}

class MockEnrollmentService extends Mock implements EnrollmentService {}

class FakeLookupVerbBuilder extends Fake implements LookupVerbBuilder {}

class FakeLocalLookUpVerbBuilder extends Fake implements LLookupVerbBuilder {}

class FakeUpdateVerbBuilder extends Fake implements UpdateVerbBuilder {}

class FakeDeleteVerbBuilder extends Fake implements DeleteVerbBuilder {}

class FakeAtKey extends Fake implements AtKey {}

class FakeAtSigningInput extends Fake implements AtSigningInput {}
